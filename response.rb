module Szn
  class Response

    attr_reader :response

    def initialize(response)
      @response = response
    end
    def headers
      @headers = {}
      response.each_header do |key, value|
        @headers[key] = value
      end
    end
  end
end