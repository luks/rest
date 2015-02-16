require "pry"

require_relative "request.rb"
require_relative "payload.rb"
require_relative "response.rb"


module Szn
  class Rest

    def self.get(url, headers={}, &block)
      Request.exec(:method => :get, :url => url, :headers => headers, &block)
    end

    def self.post(url, payload, headers={}, &block)
      Request.exec(:method => :post, :url => url, :payload => payload, :headers => headers, &block)
    end

    def self.patch(url, payload, headers={}, &block)
      Request.exec(:method => :patch, :url => url, :payload => payload, :headers => headers, &block)
    end

    def self.put(url, payload, headers={}, &block)
      Request.exec(:method => :put, :url => url, :payload => payload, :headers => headers, &block)
    end

    def self.delete(url, headers={}, &block)
      Request.exec(:method => :delete, :url => url, :headers => headers, &block)
    end

    def self.head(url, headers={}, &block)
      Request.exec(:method => :head, :url => url, :headers => headers, &block)
    end

    def self.options(url, headers={}, &block)
      Request.exec(:method => :options, :url => url, :headers => headers, &block)
    end

  end
end


binding.pry