require "ipaddr"
require "net/http"

module Fenix
  module Web
    class Fetch
      ValidationError = Class.new(StandardError)
      TransportError = Class.new(StandardError)
      Response = Struct.new(:status, :headers, :body, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(url:, transport: nil, resolver: nil, max_redirects: 3, output_limit_bytes: 20_000)
        @url = url
        @transport = transport || method(:default_transport)
        @resolver = resolver || method(:default_resolver)
        @max_redirects = max_redirects
        @output_limit_bytes = output_limit_bytes
      end

      def call
        uri = parse_uri(@url)
        redirects = 0

        loop do
          validate_remote!(uri)
          response = @transport.call(uri)
          status = response.status.to_i

          case status
          when 200...300
            return {
              "url" => uri.to_s,
              "content" => extracted_content(response).byteslice(0, @output_limit_bytes),
              "content_type" => normalized_content_type(response),
              "redirects" => redirects,
            }
          when 300...400
            raise ValidationError, "web_fetch exceeded #{@max_redirects} redirects" if redirects >= @max_redirects

            uri = redirect_target_uri(uri, response)
            redirects += 1
          else
            raise TransportError, "web_fetch failed with status #{status}"
          end
        end
      end

      private

      def parse_uri(raw_url)
        uri = URI.parse(raw_url.to_s)
        raise ValidationError, "web_fetch URL must use http or https" unless %w[http https].include?(uri.scheme)
        raise ValidationError, "web_fetch URL must include a host" if uri.host.blank?

        uri
      rescue URI::InvalidURIError => error
        raise ValidationError, "invalid web_fetch URL: #{error.message}"
      end

      def validate_remote!(uri)
        host = uri.host.to_s
        raise ValidationError, "web_fetch host is required" if host.blank?
        raise ValidationError, "web_fetch blocks private or loopback destinations" if localhost?(host)

        resolved_addresses(host).each do |address|
          next unless private_or_loopback_address?(address)

          raise ValidationError, "web_fetch blocks private or loopback destinations"
        end
      end

      def resolved_addresses(host)
        return [host] if ip_literal?(host)

        Array(@resolver.call(host))
      rescue SocketError => error
        raise TransportError, "web_fetch could not resolve #{host}: #{error.message}"
      end

      def ip_literal?(host)
        IPAddr.new(host)
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      def localhost?(host)
        host.casecmp("localhost").zero? || host.end_with?(".local")
      end

      def private_or_loopback_address?(address)
        ip = IPAddr.new(address)
        blocked_address_ranges.any? { |range| range.include?(ip) }
      rescue IPAddr::InvalidAddressError
        false
      end

      def redirect_target_uri(current_uri, response)
        location = response.headers.to_h.transform_keys(&:downcase).fetch("location", nil)
        raise ValidationError, "web_fetch redirect location is missing" if location.blank?

        parse_uri(current_uri.merge(location).to_s)
      end

      def normalized_content_type(response)
        response.headers.to_h.transform_keys(&:downcase).fetch("content-type", "text/plain").to_s.split(";").first
      end

      def extracted_content(response)
        body = response.body.to_s
        content_type = normalized_content_type(response)
        return body.gsub(/<[^>]+>/, " ").squish if content_type.include?("html")

        body
      end

      def default_transport(uri)
        request = Net::HTTP::Get.new(uri)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 10,
          write_timeout: 10
        ) do |http|
          http.request(request)
        end

        Response.new(status: response.code.to_i, headers: response.to_hash, body: response.body.to_s)
      end

      def default_resolver(host)
        Addrinfo.getaddrinfo(host, nil).map(&:ip_address).uniq
      end

      def blocked_address_ranges
        @blocked_address_ranges ||= [
          IPAddr.new("0.0.0.0/32"),
          IPAddr.new("10.0.0.0/8"),
          IPAddr.new("127.0.0.0/8"),
          IPAddr.new("169.254.0.0/16"),
          IPAddr.new("172.16.0.0/12"),
          IPAddr.new("192.168.0.0/16"),
          IPAddr.new("224.0.0.0/4"),
          IPAddr.new("::/128"),
          IPAddr.new("::1/128"),
          IPAddr.new("fc00::/7"),
          IPAddr.new("fe80::/10"),
          IPAddr.new("ff00::/8"),
        ]
      end
    end
  end
end
