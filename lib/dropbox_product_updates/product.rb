module DropboxProductUpdates
  class Product

    def self.all_products_array
      # binding.pry
      # limit = 250
      # params = {}
      # find_params = { limit: limit }.merge(params)
      p_arr = []
      pages.times do |p|
        p_arr << ShopifyAPI::Product.find(:all)
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
