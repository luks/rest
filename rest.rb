require "pry"

require_relative "request.rb"
require_relative "content.rb"
require_relative "response.rb"


module Szn
  class Rest

    def self.get(url, headers={}, &block)
      Request.run(:method => :get, :url => url, :headers => headers, &block)
    end

    def self.post(url, content, headers={}, &block)
      Request.run(:method => :post, :url => url, :content => content, :headers => headers, &block)
    end

    def self.patch(url, content, headers={}, &block)
      Request.run(:method => :patch, :url => url, :content => content, :headers => headers, &block)
    end

    def self.put(url, content, headers={}, &block)
      Request.run(:method => :put, :url => url, :content => content, :headers => headers, &block)
    end

    def self.delete(url, headers={}, &block)
      Request.run(:method => :delete, :url => url, :headers => headers, &block)
    end

    def self.head(url, headers={}, &block)
      Request.run(:method => :head, :url => url, :headers => headers, &block)
    end

    def self.options(url, headers={}, &block)
      Request.run(:method => :options, :url => url, :headers => headers, &block)
    end

  end
end


binding.pry