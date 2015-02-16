require "net/http"
require "uri"
require "openssl"
require "cgi"

module Szn
  class Request

    attr_reader :args, :uri, :method, :headers, :cookies, :content, :processed_headers, :max_redirects, :user, :password

    def self.run(args, &block)
      new(args).run(&block)
    end

    def initialize args
      @args     = args
      @method   = args[:method]
      @uri      = URI.parse(process_url_params(args[:url],args[:headers]))
      @headers  = args[:headers] || {}
      @cookies  = @headers.delete(:cookies) || args[:cookies] || {}
      @content  = Szn::Content.generate(args[:content])
      @processed_headers = make_headers args[:headers]
      @max_redirects = args[:max_redirects] || 10
      @user     = args[:user]
      @password = args[:password]
    end

    def run &block
      dispatch net_http_request_class(method).new(uri.request_uri,processed_headers), &block
    ensure
      content.close if content
    end

    private

    def dispatch req, &block

      net = net_http_class.new(uri.host, uri.port)

      if uri.is_a?(URI::HTTPS)
        net.use_ssl = true
        net.verify_mode = OpenSSL::SSL::VERIFY_NONE
      end

      if user && passsword
        req.basic_auth user, password
      end

      net.start do |http|
        established_connection = true
        if @block_response
          net_http_do_request(http, req, content ? content.to_s : nil, &@block_response)
        else
          res = net_http_do_request(http, req, content ? content.to_s : nil) \
            { |http_response| http_response }
          process_result res, &block
        end
      end
    end

    def process_result res, & block
      response = Szn::Response.new(res, args, self)
      if block_given?
        block.call(response, self, res, &block)
      else
        response.return!(self, res, &block)
      end
    end

    def valid_cookie_key?(string)
      return false if string.empty?
      ! Regexp.new('[\x0-\x1f\x7f=;, ]').match(string)
    end

    # Validate cookie values. Rather than following RFC 6265, allow anything
    # but control characters, comma, and semicolon.
    def valid_cookie_value?(value)
      ! Regexp.new('[\x0-\x1f\x7f,;]').match(value)
    end

    def net_http_class
      Net::HTTP
    end

    def net_http_request_class(method)
      Net::HTTP.const_get(method.to_s.capitalize)
    end

    def net_http_do_request(http, req, body=nil, &block)
      if body != nil && body.respond_to?(:read)
        req.body_stream = body
      end
      return http.request(req, body, &block)
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
        #:accept_encoding => 'gzip, deflate',
        #:content_encoding => 'gzip',
        :cache_control => 'no-cache'
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
      headers.merge!(@content.headers) if @content
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