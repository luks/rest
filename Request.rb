require "pry"
require "net/http"
require "uri"
require "openssl"
require "cgi"

#f30454af68aa70369ab46f2cf3b742ffc0b928b1
#x-oauth-basic
headers = { "Authentication" => "f30454af68aa70369ab46f2cf3b742ffc0b928b1" }
require 'tempfile'
require 'stringio'
require 'mime/types'



module Szn

  module Payload
    extend self

    def generate(params)
      if params.is_a?(String)
        Base.new(params)
      elsif params.is_a?(Hash)
        if params.delete(:multipart) == true || has_file?(params)
          Multipart.new(params)
        else
          UrlEncoded.new(params)
        end
      elsif params.respond_to?(:read)
        Streamed.new(params)
      else
        nil
      end
    end

    def has_file?(params)
      params.any? do |_, v|
        case v
        when Hash
          has_file?(v)
        when Array
          has_file_array?(v)
        else
          v.respond_to?(:path) && v.respond_to?(:read)
        end
      end
    end

    def has_file_array?(params)
      params.any? do |v|
        case v
        when Hash
          has_file?(v)
        when Array
          has_file_array?(v)
        else
          v.respond_to?(:path) && v.respond_to?(:read)
        end
      end
    end

    class Base
      def initialize(params)
        build_stream(params)
      end

      def build_stream(params)
        @stream = StringIO.new(params)
        @stream.seek(0)
      end

      def read(bytes=nil)
        @stream.read(bytes)
      end

      alias :to_s :read

      # Flatten parameters by converting hashes of hashes to flat hashes
      # {keys1 => {keys2 => value}} will be transformed into [keys1[key2], value]
      def flatten_params(params, parent_key = nil)
        result = []
        params.each do |key, value|
          calculated_key = parent_key ? "#{parent_key}[#{handle_key(key)}]" : handle_key(key)
          if value.is_a? Hash
            result += flatten_params(value, calculated_key)
          elsif value.is_a? Array
            result += flatten_params_array(value, calculated_key)
          else
            result << [calculated_key, value]
          end
        end
        result
      end

      def flatten_params_array value, calculated_key
        result = []
        value.each do |elem|
          if elem.is_a? Hash
            result += flatten_params(elem, calculated_key)
          elsif elem.is_a? Array
            result += flatten_params_array(elem, calculated_key)
          else
            result << ["#{calculated_key}[]", elem]
          end
        end
        result
      end

      def headers
        {'Content-Length' => size.to_s}
      end

      def size
        @stream.size
      end

      alias :length :size

      def close
        @stream.close unless @stream.closed?
      end

      def inspect
        result = to_s.inspect
        @stream.seek(0)
        result
      end

      def short_inspect
        (size > 500 ? "#{size} byte(s) length" : inspect)
      end

    end

    class Streamed < Base
      def build_stream(params = nil)
        @stream = params
      end

      def size
        if @stream.respond_to?(:size)
          @stream.size
        elsif @stream.is_a?(IO)
          @stream.stat.size
        end
      end

      alias :length :size
    end

    class UrlEncoded < Base
      def build_stream(params = nil)
        @stream = StringIO.new(flatten_params(params).collect do |entry|
          "#{entry[0]}=#{handle_key(entry[1])}"
        end.join("&"))
        @stream.seek(0)
      end

      # for UrlEncoded escape the keys
      def handle_key key
        Parser.escape(key.to_s, Escape)
      end

      def headers
        super.merge({'Content-Type' => 'application/x-www-form-urlencoded'})
      end

      Parser = URI.const_defined?(:Parser) ? URI::Parser.new : URI
      Escape = Regexp.new("[^#{URI::PATTERN::UNRESERVED}]")
    end

    class Multipart < Base
      EOL = "\r\n"

      def build_stream(params)
        b = "--#{boundary}"

        @stream = Tempfile.new("RESTClient.Stream.#{rand(1000)}")
        @stream.binmode
        @stream.write(b + EOL)

        if params.is_a? Hash
          x = flatten_params(params)
        else
          x = params
        end

        last_index = x.length - 1
        x.each_with_index do |a, index|
          k, v = * a
          if v.respond_to?(:read) && v.respond_to?(:path)
            create_file_field(@stream, k, v)
          else
            create_regular_field(@stream, k, v)
          end
          @stream.write(EOL + b)
          @stream.write(EOL) unless last_index == index
        end
        @stream.write('--')
        @stream.write(EOL)
        @stream.seek(0)
      end

      def create_regular_field(s, k, v)
        s.write("Content-Disposition: form-data; name=\"#{k}\"")
        s.write(EOL)
        s.write(EOL)
        s.write(v)
      end

      def create_file_field(s, k, v)
        begin
          s.write("Content-Disposition: form-data;")
          s.write(" name=\"#{k}\";") unless (k.nil? || k=='')
          s.write(" filename=\"#{v.respond_to?(:original_filename) ? v.original_filename : File.basename(v.path)}\"#{EOL}")
          s.write("Content-Type: #{v.respond_to?(:content_type) ? v.content_type : mime_for(v.path)}#{EOL}")
          s.write(EOL)
          while (data = v.read(8124))
            s.write(data)
          end
        ensure
          v.close if v.respond_to?(:close)
        end
      end

      def mime_for(path)
        mime = MIME::Types.type_for path
        mime.empty? ? 'text/plain' : mime[0].content_type
      end

      def boundary
        @boundary ||= rand(1_000_000).to_s
      end

      # for Multipart do not escape the keys
      def handle_key key
        key
      end

      def headers
        super.merge({'Content-Type' => %Q{multipart/form-data; boundary=#{boundary}}})
      end

      def close
        @stream.close!
      end
    end
  end





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
      @method   = args[:method]
      @headers  = args[:headers] || {}
      @url      = process_url_params(args[:url], headers)
      @user     = args[:user]
      @password = args[:password]
      @payload  = Payload.generate(args[:payload])
      @uri      = URI.parse(args[:url])
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
      request.set_form_data payload

      response = http.request(request)
      binding.pry
    end

    private

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

  end


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



# class Resource
#   attr_reader :url, :options, :block

#   def initialize(url, options={}, &block)
#     @url = url
#     @block = block
#     @options = options
#   end

#   def get(additional_headers={}, &block)
#     headers = (options[:headers] || {}).merge(additional_headers)
#     Request.execute(options.merge(
#             :method => :get,
#             :url => url,
#             :headers => headers), &(block || @block))
#   end

#   def head(additional_headers={}, &block)
#     headers = (options[:headers] || {}).merge(additional_headers)
#     Request.execute(options.merge(
#             :method => :head,
#             :url => url,
#             :headers => headers), &(block || @block))
#   end

#   def post(payload, additional_headers={}, &block)
#     headers = (options[:headers] || {}).merge(additional_headers)
#     Request.execute(options.merge(
#             :method => :post,
#             :url => url,
#             :payload => payload,
#             :headers => headers), &(block || @block))
#   end

#   def put(payload, additional_headers={}, &block)
#     headers = (options[:headers] || {}).merge(additional_headers)
#     Request.execute(options.merge(
#             :method => :put,
#             :url => url,
#             :payload => payload,
#             :headers => headers), &(block || @block))
#   end

#   def patch(payload, additional_headers={}, &block)
#     headers = (options[:headers] || {}).merge(additional_headers)
#     Request.execute(options.merge(
#             :method => :patch,
#             :url => url,
#             :payload => payload,
#             :headers => headers), &(block || @block))
#   end

#   def delete(additional_headers={}, &block)
#     headers = (options[:headers] || {}).merge(additional_headers)
#     Request.execute(options.merge(
#             :method => :delete,
#             :url => url,
#             :headers => headers), &(block || @block))
#   end
# end

binding.pry