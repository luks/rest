require "net/http"
require "uri"
require "openssl"
require "cgi"

module Szn

  class Request

    attr_reader :method, :url, :headers, :cookies,
                :payload, :user, :password, :read_timeout, :max_redirects,
                :open_timeout, :raw_response, :processed_headers, :args,
                :ssl_opts,
                :uri


    def self.execute(args, & block)
      new(args).execute(& block)
    end

    def initialize args
      @args     = args
      @method   = args[:method]
      @headers  = stringify_headers(args[:headers]) || {}
      @cookies  = @headers.delete(:cookies) || args[:cookies] || {}
      @payload  = Szn::Payload.generate(args[:payload])
      @url      = process_url_params(args[:url], headers)
      @uri      = URI.parse(args[:url])

      @user     = args[:user]
      @password = args[:password]
      @processed_headers = make_headers headers

    end

    def execute & block
      net_http_request_class(method)
      http = Net::HTTP.new(uri.host, uri.port)
      if uri.is_a?(URI::HTTPS)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      request = net_http_request_class(method).new(uri.request_uri, headers)
      request.basic_auth "lukapiske@gmail.com/token", "f30454af68aa70369ab46f2cf3b742ffc0b928b1"

      response = net_http_do_request http, request, payload ? payload.to_s : nil, &block

    end

    private

    def net_http_do_request(http, req, body=nil, &block)
      if body != nil && body.respond_to?(:read)
        req.body_stream = body
        return http.request(req, nil, &block)
      else
        return http.request(req, body, &block)
      end
    end


    def net_http_request_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
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
      }
    end

    def make_headers user_headers
      unless @cookies.empty?

        # Validate that the cookie names and values look sane. If you really
        # want to pass scary characters, just set the Cookie header directly.
        # RFC6265 is actually much more restrictive than we are.
        @cookies.each do |key, val|
          unless valid_cookie_key?(key)
            raise ArgumentError.new("Invalid cookie name: #{key.inspect}")
          end
          unless valid_cookie_value?(val)
            raise ArgumentError.new("Invalid cookie value: #{val.inspect}")
          end
        end

        user_headers[:cookie] = @cookies.map { |key, val| "#{key}=#{val}" }.sort.join('; ')
      end
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