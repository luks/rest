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
        UrlEncoded.new(params)
      else
        nil
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

  end
end
