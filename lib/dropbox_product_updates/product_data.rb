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

      # DropboxProductImports::Product.all_products_array.each do |page|
      #   page.each do |product|
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
    begin
      ## this does not belong here
      process_products
    rescue
      delete_datum
    end
    delete_datum
  end

  def delete_datum
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

  def process_products
    DropboxProductUpdates::Product.all_products_array.each do |page|
      page.each do |shopify_product|
        shopify_product.variants.each do |v|
          matches = RawDatum.where(status: 9).where("data->>'*ItemCode' = ?", v.sku)
          if matches.any?
            match = matches.first
            ## should be its own class
            # binding.pry 
            ProductData.update_product_descriptions(v, match)
          end
        end
      end
    end
  end

  def self.update_product_descriptions(variant, match)
    product = ShopifyAPI::Product.find(variant.product_id)

    if match.data["OverwriteShopifyDescOnImport"] == 'Yes'
      desc = match.data["SalesDescription"]
      product.body_html = desc
    end

    product.title = product.title.gsub('  ',' ').titleize

    tags = %w{  
       Country
       Category
       SubCategory1
       SC1Singular
       SubCategory2
       SpecialFeatures
       Condition
       OuterConditionDetail
       InnerConditionDetail
       SoleConditionDetail
       SourceCountrySize
       AustralianSize
       ShoeHeelHeight
       BagW
       BagH
       BagD
       ClothingLength
       SimpleColour
       DetailColour
       SimplePattern
       SimpleMaterial
       DetailMaterial
       LiningMaterial
       SoleMaterial
       Weight(grams)
       Season
       HasTag
       HasOriginalBox
       HasDustbag
       WeLove
       Vintage
       Partywear
       Workwear
       CasualWear
       OnSale
       Gender
       CommunityLoves
       LocationTracking
       IsConsigned
       ProvidedBy
       Authentication
       PhotoDone
    }

    product.tags = tags.map { |tag| !(match.data[tag].nil? or (match.data[tag].to_s.downcase == 'n/a') or (match.data[tag].blank?)) ? "#{tag.underscore.humanize.titleize}: #{match.data[tag]}" : nil  }.join(',')
    puts "#{product.title} :: UPDATED!!!"
    #binding.pry
    #
    product.save!

    ##metafields

  end
end
