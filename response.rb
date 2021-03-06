
#res.response.is_a?(Net::HTTPSuccess)

module Szn
  class Response

    attr_reader :response, :args, :request

    def initialize(response, args, request)
      @args     = args
      @response = response
      @request  = request
    end

    def headers
      @headers ||= Szn::Response.beautify_headers(response.to_hash)
    end

    def cookies
      @cookies ||= (self.headers[:set_cookie] || {}).inject({}) do |out, cookie_content|
        out.merge parse_cookie(cookie_content)
      end
    end

    def body
      response.body
    end

    def msg
      response.msg
    end

    def code
      @code ||= response.code.to_i
    end

    def return! request = nil, result = nil, &block

      # when Net::HTTPSuccess then
      #   response
      # when Net::HTTPRedirection then
      if (200..207).include? code
        self
      elsif [301, 302, 307].include? code
        unless [:get, :head].include? args[:method]
          #raise Exceptions::EXCEPTIONS_MAP[code].new(self, code)
        else
          follow_redirection(request, result, &block)
        end
      elsif code == 303
        args[:method] = :get
        args.delete :content
        follow_redirection(request, result, &block)
      #elsif Exceptions::EXCEPTIONS_MAP[code]
        #raise Exceptions::EXCEPTIONS_MAP[code].new(self, code)
      else
        #raise RequestFailed.new(self, code)
      end
    end

        # Follow a redirection
    def follow_redirection request = nil, result = nil, & block
      url = headers[:location]
      if url !~ /^http/
        url = URI.parse(args[:url]).merge(url).to_s
      end
      args[:url] = url
      if request
        if request.max_redirects == 0
          #raise MaxRedirectsReached
          raise ArgumentError, 'too many HTTP redirects'
        end
        args[:password]      = request.password
        args[:user]          = request.user
        args[:headers]       = request.headers
        args[:max_redirects] = request.max_redirects - 1
        # pass any cookie set in the result
        if result && result['set-cookie']
          args[:headers][:cookies] = (args[:headers][:cookies] || {}).merge(parse_cookie(result['set-cookie']))
        end
      end
      Request.run args, &block
    end

    def self.beautify_headers(headers)
      headers.inject({}) do |out, (key, value)|
        out[key.gsub(/-/, '_').downcase.to_sym] = %w{ set-cookie }.include?(key.downcase) ? value : value.first
        out
      end
    end

    private

    # Parse a cookie value and return its content in an Hash
    def parse_cookie cookie_content
      out = {}
      CGI::Cookie::parse(cookie_content).each do |key, cookie|
        unless ['expires', 'path'].include? key
          out[CGI::escape(key)] = cookie.value[0] ? (CGI::escape(cookie.value[0]) || '') : ''
        end
      end
      out
    end

  end
end