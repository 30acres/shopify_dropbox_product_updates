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
      RawDatum.create(data: product.to_hash.to_json, client_id: 0, status: 9)
    end
    begin
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
            binding.pry
            match = matches.first
            product = match.product
          end
        end
      end
    end
  end

  def has_dropbox_description
    # if dropbox_images.any?
    #   puts "Found match (#{@product.title})"
    #   match = true
    # else
    #   puts "No match (#{@product.title})"
    #   match = false
    # end
    # match
  end

  def update_descriptions
    # if has_dropbox_images
    #   upload_images
    # end
  end

  def dropbox_images
    # if @product.variants.any? and @product.variants.first.sku.length >= 5 ## Just to make sure its not an accident
    #   connect_to_source.metadata(@path)['contents'].select { |image| image['path'].include?(@product.variants.first.sku + '-')   }
    # else
    #   []
    # end
  end

  def upload_images
    # remove_all_images if dropbox_images.any?
    # dropbox_images.each do |di|
    #   url = connect_to_source.media(di['path'])['url']
    #   if url
    #     image = ShopifyAPI::Image.new(product_id: @product.id, src: url)
    #     image.save!
    #   end
    # end
  end

end
