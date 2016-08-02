require 'net/http'
require 'dropbox_sdk'
require "product/product"
require 'csv'
require 'slack-notifier'


module ImportProductData
  def self.update_all_products(path, token)
    if path and token
      ## Clear the Decks
      ProductData.delete_datum

      ## get the csv
      ProductData.new(path,token).get_csv

      ## parse the rows
      ## update the descriptions
      ProductData.process_products

      ## Clear the decks again
      ProductData.delete_datum

    end
  end
end

class ProductData
  def initialize(path,token)
    @path = path
    @token = token
    @notifier = Slack::Notifier.new ENV['SLACK_IMAGE_WEBHOOK'], channel: '#product_data_feed',
      username: 'Import Notifier', icon: 'https://cdn.shopify.com/s/files/1/1290/9713/t/4/assets/favicon.png?3454692878987139175'

  end

  def get_csv
    CSV.parse(file, { headers: true }) do |product|
      # encoded = CSV.parse(product).to_hash.to_json
      encoded = product.to_hash.inject({}) { |h, (k, v)| h[k] = v.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').valid_encoding? ? v.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') : '' ; h }
      encoded_more = encoded.to_json
      puts encoded_more
      RawDatum.create(data: encoded_more, client_id: 0, status: 9)
      # puts product
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
    @notifier = Slack::Notifier.new ENV['SLACK_IMAGE_WEBHOOK'], channel: '#product_data_feed',
      username: 'Data Notifier', icon: 'https://cdn.shopify.com/s/files/1/1290/9713/t/4/assets/favicon.png?3454692878987139175'

    RawDatum.where(status: 9).each do |data|
      code = data.data["*ItemCode"]
      shopify_variants = []
      [1,2,3].each do |page|
        shopify_variants << ShopifyAPI::Variant.find(:all, params: { limit: 250, fields: 'sku', page: page } )
      end
      shopify_variants = shopify_variants.flatten
      if shopify_variants.any?
        ## if SKU matches
        # binding.pry
        matches = shopify_variants.select { |sv| sv.sku == code }
        if matches.any?
          v = matches.first
          ProductData.update_product_descriptions(v, data)
        else
          v = nil
          ProductData.update_product_descriptions(v, data)
        end
      end
    end

    ## first update all then do new perhaps?
    # DropboxProductUpdates::Product.all_products_array.each do |page|
    #   page.each do |shopify_product|
    #     shopify_product.variants.each do |v|
    #       matches = RawDatum.where(status: 9).where("data->>'*ItemCode' = ?", v.sku)
    #       if matches.any?
    #         sleep(1)
    #         match = matches.first
    #         ProductData.update_product_descriptions(v, match)
    #         match.delete
    #       else
    #         ProductData.update_product_descriptions(v, match, 'new')
    #       end
    #     end
    #   end
    # end
    # ### any with no match - create 
    # new_matches = RawDatum.where(status: 9) ##.where("data->>'*ItemCode' = ?", v.sku)
    # if new_matches.any?
    #   new_matches.each do |new_match|
    #     match = new_match
    #     ProductData.update_product_descriptions(match.data['*ItemCode'], match, 'new')
    #   end
    # end
    #
  end

  def self.update_product_descriptions(variant, match)
    if variant.nil?
      puts 'NO MATCH'
      product = ShopifyAPI::Product.new
    else
      puts 'MATCH'
      product = ShopifyAPI::Product.find(variant.product_id)
    end

    desc = match.data["Product Description"]
    product.body_html = desc
    product.product_type = match.data['Sub-category 1']
    product.vendor = match.data["Designer"]
    product.title = match.data["Product Title"].gsub('  ',' ').split.map(&:capitalize).join(' ')

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
    Designer
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

    product.tags = tags.map { |tag| !(match.data[tag].nil? or (match.data[tag].to_s.downcase == 'n/a') or (match.data[tag].blank?)) ? "#{tag.underscore.humanize.titleize}: #{match.data[tag].gsub(',','')}" : nil  }.join(',')
    product.tags = product.tags + ', ImportChecked'

    product.options = [
      ShopifyAPI::Option.new(name: 'Size'), 
      ShopifyAPI::Option.new(name: 'Colour'),
      ShopifyAPI::Option.new(name: 'Material')
    ]

    puts "#{product.title} :: UPDATED!!!"
    if match.data["Publish on Website"] == 'Yes'
      product.published_at = Time.now
    else
      product.published_at = nil
    end
    puts product.inspect

    puts '====================================='
    puts '====================================='
    puts product
    puts '=== P R O D U C T S A V E D ============================='

    # binding.pry
    if product.id
      v = product.variants.first
    else
      v = ShopifyAPI::Variant.new
    end
    v.product_id = product.id
    v.price = match.data["Price"].gsub('$','').gsub(',','').to_s.strip.to_f
    v.sku = match.data["*ItemCode"]
    v.grams = match.data["Weight (grams)"].to_i
    v.compare_at_price = match.data["Price (before Sale)"]
    v.option1 = [match.data["Source Country Size"],match.data["Source Country Size"]].join('/')
    v.option2 = match.data["Colour"].to_s.blank? ? 'N/A' : match.data["Colour"].to_s
    v.option3 = match.data["Material"].to_s.blank? ? 'N/A' : match.data["Material"]
    v.inventory_quantity = match.data["NumStockAvailable"]
    v.old_inventory_quantity = match.data["NumStockAvailable"]
    v.requires_shipping = true
    v.barcode = nil
    v.taxable = true
    v.position = 1
    v.inventory_policy = 'deny'
    v.fulfillment_service = "manual"
    v.inventory_management = "shopify"
    # weight: match.data["Weight (grams)"].to_i/100,
    v.weight_unit = "g"
    puts v.inspect
    # binding.pry
    product.variants = [v]
    sleep(1)
    product.save!
    # v.save!
    puts '====================================='

    # if variant.nil? 
    #   updates << "Product Data: New Product: #{product.title}"
    # else
    #   updates << "Product Data: Updated Product #{product.title}"
    # end

    puts '=== V A R I A N T S A V E D ============================='
    puts '====================================='

  end
end
