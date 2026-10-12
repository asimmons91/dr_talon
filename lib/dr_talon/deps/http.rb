# frozen_string_literal: true

require "net/http"
require "uri"

module DrTalon
  module Deps
    # Minimal HTTPS GET with redirects, for downloading dependencies.
    class HTTP
      MAX_REDIRECTS = 5

      # @param url [String]
      # @return [String] the response body
      # @raise [FetchError] on network errors and non-2xx responses
      def get(url)
        uri = URI(url)

        (MAX_REDIRECTS + 1).times do
          response = request(uri)
          case response
          when Net::HTTPSuccess then return response.body
          when Net::HTTPRedirection then uri = URI.join(uri, response["location"])
          else raise FetchError, "GET #{uri} returned #{response.code} #{response.message}"
          end
        end

        raise FetchError, "GET #{url} redirected more than #{MAX_REDIRECTS} times"
      end

      private

      def request(uri)
        raise FetchError, "Only http(s) URLs are supported: #{uri}" unless uri.is_a?(URI::HTTP)

        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 60) do |http|
          http.request(Net::HTTP::Get.new(uri, "User-Agent" => "dr_talon/#{VERSION}"))
        end
      rescue SocketError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, Net::ProtocolError => e
        raise FetchError, "GET #{uri} failed: #{e.message}"
      end
    end
  end
end
