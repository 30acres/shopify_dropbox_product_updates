require 'net/http'
require 'dropbox_sdk'
require "product/product"
require 'csv'
require 'slack-notifier'

module ImportProductData

  def self.update_all_products(path, token)
    @notifier = Slack::Notifier.new ENV['SLACK_IMAGE_WEBHOOK'], channel: '#product_data_feed',
      username: 'Data Notifier', icon: 'https://cdn.shopify.com/s/files/1/1290/9713/t/4/assets/favicon.png?3454692878987139175'

    @notifier.ping "[Product Data] Started Import"
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
      @notifier.ping "[Product Data] Finished Import"
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

    already_imported = Import.where(path: path, modified: modified).any?

    unless already_imported
      @notifier.ping "[Product Data] Files Changed"
      CSV.parse(file, { headers: true }) do |product|
        # encoded = CSV.parse(product).to_hash.to_json
        encoded = product.to_hash.inject({}) { |h, (k, v)| h[k] = v.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '').valid_encoding? ? v.to_s.encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '') : '' ; h }
        encoded_more = encoded.to_json
        puts encoded_more
        RawDatum.create(data: encoded_more, client_id: 0, status: 9)

      end
      Import.new(path: path, modified: modified).save!
    else
      @notifier.ping "[Product Data] No Changes"
    end
  end

  def self.delete_datum
    ## so cheap and dirty
    RawDatum.where(status: 9).destroy_all
  end

  def path
    connect_to_source.metadata(@path)['contents'][0]['path']
  end

  def modified
    # "modified"=>"Wed, 03 Aug 2016 00:53:28 +0000",
    connect_to_source.metadata(@path)['contents'][0]['modified']
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
      username: 'Data Notifier', icon_url: 'https://cdn.shopify.com/s/files/1/1290/9713/t/4/assets/favicon.png?3454692878987139175'

    shopify_variants = []
    [1,2,3].each do |page|
      shopify_variants << ShopifyAPI::Variant.find(:all, params: { limit: 250, fields: 'sku, product_id', page: page } )
    end
    shopify_variants = shopify_variants.flatten
    # binding.pry

    RawDatum.where(status: 9).each do |data|
      code = data.data["*ItemCode"]
      if shopify_variants.any?
        matches = shopify_variants.select { |sv| sv.sku == code }
        # binding.pry
        if matches.any?
          # binding.pry
          v = matches.first
          ProductData.update_product_descriptions(v, data)
        else
          v = nil
          ProductData.update_product_descriptions(v, data)
        end
      else
        v = nil
        ProductData.update_product_descriptions(v, data)
      end
    end

  end

  def self.update_product_descriptions(variant, match)
    puts '==== C R E D I T ===='
    puts ShopifyAPI.credit_used
    if ShopifyAPI.credit_used >= 38
      puts 'Chilling out...too much credit used!'
      sleep(20)
    end
    puts '---=============-----'
    sleep(1)
    oldtags = ''


    if variant.nil?
      puts 'NO MATCH'
      product = ShopifyAPI::Product.new
    else
      puts 'MATCH FOUND'
      product = ShopifyAPI::Product.find(variant.product_id)
      oldtags = product.tags
    end

    desc = match.data["Product Description"]
    product.body_html = desc
    product.product_type = match.data['Category']
    product.vendor = match.data["Designer"]
    product.title = match.data["Product Title"].gsub('  ',' ').split.map(&:capitalize).join(' ')

    product.metafields_global_title_tag = product.title
    product.metafields_global_description_tag = desc

    tags = Array.new([
    'Category',
    'Sub-category 1',
    'Sub-category 2',
    'Condition',
    'Outer Condition Detail',
    'Inner Condition Detail',
    'Sole Condition Detail',
    'Country',
    'Source Country Size',
    'Australian Size',
    'Designer',
    'Width',
    'Height',
    'Depth',
    'Heel Height',
    'Colour',
    'Detailed Colour',
    'Detailed Material',
    'Lining Material',
    'Pattern',
    'Gender',
    'Season',
    'Has Tag',
    'Has Original Box',
    'Has Dustbag',
    'Vintage',
    'Price',	
    'Price (before Sale)',	
    'IsConsigned',
    'NumStockAvailable',
    'Publish on Website',
    'Vintage',
    'Partywear',
    'Workwear',
    'Casual Wear',
    'We Love',
    'Community Loves',
    'On Sale',
    'Recommended Retail Price',
    'LocationTracking',
    'IsConsigned',
    'NumStockAvailable',
    'IsDataValid',
    'PhotoDone',
    'OverwriteShopifyDescOnImport',
    'Sold by',
    'Published'
    ])

    product.tags = tags.map { |tag| !(match.data[tag].nil? or (match.data[tag].to_s.downcase == 'n/a') or (match.data[tag].blank?)) ? "#{tag.underscore.humanize.titleize}: #{match.data[tag].gsub(',','')}" : nil  }.join(',')
    product.tags = product.tags + ", #{match.data['Designer']}"
    product.tags = product.tags

    product_options = [] 
    ['Australian Size','Colour','Material'].each_with_index do |opt,index|
      # binding.pry
      # if !(match.data[opt].to_s.downcase.include?('n/a') or match.data[opt].nil? or match.data[opt].blank?)
        product_options << ShopifyAPI::Option.new(name: opt)
      # end
    end
    product.options = product_options

    puts "#{product.title} :: UPDATED!!!"
    if match.data["Publish on Website"] == 'Yes'
      unless product.id
        product.published_at = DateTime.now - 10.hours
      end
    else
      product.published_at = nil
    end
    puts product.inspect

    puts '====================================='
    puts '====================================='
    puts product
    puts '=== P R O D U C T S A V E D ==========================='

    # binding.pry
    if product.id
      v = product.variants.first
    else
      v = ShopifyAPI::Variant.new
    end

    ['Australian Size','Colour','Material'].each_with_index do |opt,index|
      # binding.pry
        if index == 0
          d = match.data[opt].to_s.strip
          v.option1 = d.blank? ? 'n/a' : d
        end
        if index == 1
          d = match.data[opt].to_s.strip
          v.option2 = d.blank? ? 'n/a' : d
        end
        if index == 2
          d = match.data[opt].to_s.strip
          v.option3 = d.blank? ? 'n/a' : d
        end
    end

    v.product_id = product.id
    v.price = match.data["Price"].gsub('$','').gsub(',','').to_s.strip.to_f
    v.sku = match.data["*ItemCode"]
    v.grams = match.data["Weight (grams)"].to_i
    v.compare_at_price = match.data["Price (before Sale)"]
    
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
