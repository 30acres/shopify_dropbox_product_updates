require 'net/http'
require 'dropbox_sdk'
require "product/product"
require 'csv'

module ImportProductData
  def self.update_all_products(path, token)
    if path and token
      ## get the csv
      ProductData.new(path,token).get_csv
      ## parse the rows
      ## update the descriptions

      ProductData.process_products

      ProductData.delete_datum
     
      # DropboxProductUpdates::Product.all_products_array.each do |page|
      #   page.each do |product|
      #     binding.pry
      #     ProductData.new(product,data,token).update_descriptions
      #   end
      # end
    end
  end
end

class ProductData
  def initialize(path,token)
    @path = path
    @token = token
  end

  def get_csv
    CSV.parse(file, { headers: true }) do |product|
      # encoded = CSV.parse(product).to_hash.to_json
      encoded = product.to_hash.inject({}) { |h, (k, v)| h[k] = v.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').valid_encoding? ? v.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') : '' ; h }
      encoded_more = encoded.to_json
      puts encoded
      RawDatum.create(data: encoded_more, client_id: 0, status: 9)
      puts product
    end
  end

  def self.delete_datum
    ## so cheap and dirty
    RawDatum.where(status: 9).destroy_all
  end

  def path
    connect_to_source.metadata(@path)['contents'][0]['path']
  end

  def file
    connect_to_source.get_file(path)
  end


  def connect_to_source
    # w = DropboxOAuth2FlowNoRedirect.new(APP_KEY, APP_SECRET)
    # authorize_url = flow.start()
    DropboxClient.new(@token)
  end

  def self.process_products
    DropboxProductUpdates::Product.all_products_array.each do |page|
      page.each do |shopify_product|
        shopify_product.variants.each do |v|
          matches = RawDatum.where(status: 9).where("data->>'*ItemCode' = ?", v.sku)
          if matches.any?
            sleep(1)
            match = matches.first
            ProductData.update_product_descriptions(v, match)
          end
        end
      end
    end
  end

  def self.update_product_descriptions(variant, match)
    product = ShopifyAPI::Product.find(variant.product_id)

      desc = match.data["Product Description"]
      product.body_html = desc
      product.title = product.title.gsub('  ',' ').split.map(&:capitalize).join(' ')
      
      product.metafields_global_title_tag = product.title
      product.metafields_global_description_tag = desc

    tags = %w{  
    Category
    Sub-category 1
    Sub-category 2
    Condition
    Outer Condition Detail
    Inner Condition Detail
    Sole Condition Detail
    Country
    Source Country Size
    Australian Size
    Width
    Height
    Depth
    Heel Height
    Colour
    Detailed Colour
    Detailed Material
    Lining Material
    Pattern
    Gender
    Season
    Has Tag
    Has Original Box
    Has Dustbag
    Vintage
    Price	
    Price (before Sale)	
    IsConsigned
    NumStockAvailable
    Publish on Website
    Vintage
    Partywear
    Workwear
    Casual Wear
    We Love
    Community Loves
    On Sale
    Recommended Retail Price
    LocationTracking
    IsConsigned
    NumStockAvailable
    IsDataValid
    PhotoDone
    OverwriteShopifyDescOnImport
    Sold by
    Published
    }

    product.tags = tags.map { |tag| !(match.data[tag].nil? or (match.data[tag].to_s.downcase == 'n/a') or (match.data[tag].blank?)) ? "#{tag.underscore.humanize.titleize}: #{match.data[tag]}" : nil  }.join(',')
    product.tags = product.tags + ', ImportCheck'

    product.options = [
      ShopifyAPI::Option.new(name: 'Size'), 
      ShopifyAPI::Option.new(name: 'Colour'),
      ShopifyAPI::Option.new(name: 'Material')
    ]
    # binding.pry
    product.variants = [
      ShopifyAPI::Variant.new(
        price: match.data["Price"].gsub('$','').gsub(',','').to_s.strip,
        sku: match.data["*ItemCode"],
        grams: match.data["Weight (grams)"].to_i,
        compare_at_price: match.data["Price (before Sale)"],
        option1: [match.data["Source Country Size"],match.data["Source Country Size"]].join('/'),
        option2: match.data["Colour"],
        option3: match.data["Material"],
        inventory_quantity: match.data["NumStockAvailable"],
        weight: match.data["Weight (grams)"].to_i/100,
        weight_unit: "g"
      )
    ]

    # binding.pry
    
    puts "#{product.title} :: UPDATED!!!"
    if match.data["Publish on Website"] == 'Yes'
      product.published_at = Time.now
    else
      product.published_at = nil
    end

    puts '====================================='
    puts product
    product.save!
    puts '=== S A V E D ============================='

  end
end
