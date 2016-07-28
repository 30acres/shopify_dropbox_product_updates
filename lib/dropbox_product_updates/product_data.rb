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
          # binding.pry
          matches = RawDatum.where(status: 9).where("data->>'*ItemCode' = ?", v.sku)
          if matches.any?
            match = matches.first
            ProductData.update_product_descriptions(v, match)
          end
        end
      end
    end
  end

  def self.update_product_descriptions(variant, match)
    product = ShopifyAPI::Product.find(variant.product_id)

    # if match.data["OverwriteShopifyDescOnImport"] == 'Yes'
      desc = match.data["SalesDescription"]
      product.body_html = desc
    # end

    product.title = product.title.gsub('  ',' ').split.map(&:capitalize).join(' ')
    tags = %w{  
    Category
    Sub-category 1
    Condition
    Country
    Source Country Size
    Australian Size
    Heel Height
    Colour
    Pattern
    Material
    Gender
    Season
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
    puts "#{product.title} :: UPDATED!!!"
    unless match.data["Published"] == 'TRUE'
      product.published_at = nil
    end
    #binding.pry
    puts '====================================='
    product.save!
    puts '=== S A V E D ============================='

    ##metafields

  end
end
