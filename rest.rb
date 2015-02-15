require "pry"

require_relative "request.rb"
require_relative "payload.rb"


module Szn

  class Rest

    def self.get(url, headers={}, &block)
      Request.execute(:method => :get, :url => url, :headers => headers, &block)
    end

    def self.post(url, payload, headers={}, &block)
      Request.execute(:method => :post, :url => url, :payload => payload, :headers => headers, &block)
    end

    def self.patch(url, payload, headers={}, &block)
      Request.execute(:method => :patch, :url => url, :payload => payload, :headers => headers, &block)
    end

    def self.put(url, payload, headers={}, &block)
      Request.execute(:method => :put, :url => url, :payload => payload, :headers => headers, &block)
    end

    def self.delete(url, headers={}, &block)
      Request.execute(:method => :delete, :url => url, :headers => headers, &block)
    end

    def self.head(url, headers={}, &block)
      Request.execute(:method => :head, :url => url, :headers => headers, &block)
    end

    def self.options(url, headers={}, &block)
      Request.execute(:method => :options, :url => url, :headers => headers, &block)
    end

  end

end


binding.pry