module DropboxProductUpdates
  module Product
    def self.all_products_array(params={})
      p_arr = []
      find_params = { limit: limit }.merge(params)
      pages.times do |p|
        p_arr << ShopifyAPI::Product.find(:all, params: find_params.merge({ page: p}) ) 
      end
      p_arr
    end

    def self.recent_products_array
      params = { updated_at_min: 15.minutes.ago }
      all_products_array(params)
    end

    def self.pages
      count/limit
    end

    def self.limit
      50
    end

    def self.count
      ShopifyAPI::Product.count
    end
  end
end

