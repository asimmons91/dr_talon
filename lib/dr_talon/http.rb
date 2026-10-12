# frozen_string_literal: true

require "net/http"
require "uri"

module DrTalon
  # Minimal HTTP(S) GETs with redirects, for dependencies and engine
  # downloads. Basic auth is only sent to the host it was given for.
  class HTTP
    MAX_REDIRECTS = 5

    # A request failed or returned a non-2xx status.
    class Error < DrTalon::Error; end

    # The server answered 401.
    class Unauthorized < Error; end

    Auth = Data.define(:username, :password)

    # @param url [String]
    # @param auth [Auth, nil]
    # @return [String] the response body
    # @raise [Error]
    def get(url, auth: nil)
      follow(url, auth) { |response| return response.body.to_s }
    end

    # Streams a response body to +path+.
    #
    # @param url [String]
    # @param path [String]
    # @param auth [Auth, nil]
    # @yieldparam received [Integer] bytes so far
    # @yieldparam total [Integer, nil] Content-Length, if sent
    # @return [String] +path+
    # @raise [Error]
    def download(url, path, auth: nil)
      follow(url, auth) do |response|
        total = response.content_length
        received = 0
        File.open(path, "wb") do |file|
          response.read_body do |chunk|
            file.write(chunk)
            received += chunk.bytesize
            yield received, total if block_given?
          end
        end
        return path
      end
    end

    private

    # Yields the first successful response; the caller reads its body.
    def follow(url, auth)
      uri = URI(url)
      origin = uri.host

      (MAX_REDIRECTS + 1).times do
        redirect = nil
        request(uri, (auth if uri.host == origin)) do |response|
          case response
          when Net::HTTPSuccess then yield response
          when Net::HTTPRedirection then redirect = URI.join(uri, response["location"])
          when Net::HTTPUnauthorized then raise Unauthorized, "#{uri.host} rejected the username or password (401)"
          else raise Error, "GET #{uri} returned #{response.code} #{response.message}"
          end
        end
        uri = redirect
      end

      raise Error, "GET #{url} redirected more than #{MAX_REDIRECTS} times"
    end

    def request(uri, auth, &block)
      raise Error, "Only http(s) URLs are supported: #{uri}" unless uri.is_a?(URI::HTTP)

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 120) do |http|
        request = Net::HTTP::Get.new(uri, "User-Agent" => "dr_talon/#{VERSION}")
        request.basic_auth(auth.username, auth.password) if auth
        http.request(request, &block)
      end
    rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError => e
      raise Error, "GET #{uri} failed: #{e.message}"
    end
  end
end
