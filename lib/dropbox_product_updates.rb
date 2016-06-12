require "dropbox_product_updates/version"

module DropboxProductUpdates
  require "dropbox_product_updates/product"
  require "dropbox_product_updates/product_data"

  def self.update_all_products(path=nil, token=nil)
    payload = ''
    ImportProductData.update_all_products(path,token)
    payload = 'Successful Import (More info soon...)'
    payload
  end

end
