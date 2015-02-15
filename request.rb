#       #request.basic_auth "{email}/token", "{token}"
require "net/http"
require "uri"
require "openssl"
require "cgi"

module Szn
  class Request

    attr_reader :args, :method, :uri, :headers,
                :payload, :processed_headers

    def self.execute(args, &block)
      new(args).execute(&block)
    end

    def initialize args
      @args     = args
      @method   = args[:method]
      @uri      = URI.parse(process_url_params(args[:url],args[:headers]))
      @headers  = stringify_headers(args[:headers]) || {}
      @payload  = Szn::Payload.generate(args[:payload])
      @processed_headers = make_headers args[:headers]
    end

    def execute &block
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.is_a?(URI::HTTPS)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end
      request   = net_http_request_class(method).new(uri.request_uri,processed_headers)
      response  = net_http_do_request http, request, payload ? payload.to_s : nil, &block
    ensure
      payload.close if payload
    end

    private

    def net_http_request_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
    end

    def net_http_do_request(http, req, body=nil, &block)
      if body != nil && body.respond_to?(:read)
        req.body_stream = body
        return http.request(req, nil, &block)
      else
        return http.request(req, body, &block)
      end
    end

    def process_url_params url, headers
      url_params = {}
      headers.delete_if do |key, value|
        if 'params' == key.to_s.downcase && value.is_a?(Hash)
          url_params.merge! value
          true
        else
          false
        end
      end
      unless url_params.empty?
        query_string = url_params.collect { |k, v| "#{k.to_s}=#{CGI::escape(v.to_s)}" }.join('&')
        url + "?#{query_string}"
      else
        url
      end
    end

    def default_headers
      {
        :accept => '*/*',
        :accept_encoding => 'gzip, deflate',
        :content_encoding => 'gzip',
        :cache_control => 'no-cache'
      }
    end

    def make_headers user_headers
      headers = stringify_headers(default_headers).merge(stringify_headers(user_headers))
      headers.merge!(@payload.headers) if @payload
      headers
    end

    def stringify_headers headers
      headers.inject({}) do |result, (key, value)|
        if key.is_a? Symbol
          key = key.to_s.split(/_/).map(&:capitalize).join('-')
        end
        if 'CONTENT-TYPE' == key.upcase
          result[key] = maybe_convert_extension(value.to_s)
        elsif 'ACCEPT' == key.upcase
          # Accept can be composed of several comma-separated values
          if value.is_a? Array
            target_values = value
          else
            target_values = value.to_s.split ','
          end
          result[key] = target_values.map { |ext|
            maybe_convert_extension(ext.to_s.strip)
          }.join(', ')
        else
          result[key] = value.to_s
        end
        result
      end
    end

    def maybe_convert_extension(ext)
      unless ext =~ /\A[a-zA-Z0-9_@-]+\z/
        return ext
      end
      types = MIME::Types.type_for(ext)
      if types.empty?
        ext
      else
        types.first.content_type
      end
    end
  end
end