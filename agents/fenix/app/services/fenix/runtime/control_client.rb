require "json"
require "net/http"
require "uri"

module Fenix
  module Runtime
    class ControlClient
      def initialize(base_url:, machine_credential:)
        @base_url = base_url
        @machine_credential = machine_credential
      end

      def poll(limit:)
        post_json("/agent_api/control/poll", { limit: limit }).fetch("mailbox_items")
      end

      def report!(payload:)
        post_json("/agent_api/control/report", payload)
      end

      private

      def post_json(path, payload)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = %(Token token="#{@machine_credential}")
        request.body = JSON.generate(payload)

        response = Net::HTTP.start(uri.host, uri.port) do |http|
          http.request(request)
        end

        body = response.body.to_s
        parsed = body.empty? ? {} : JSON.parse(body)
        raise "HTTP #{response.code}: #{body}" unless response.code.to_i.between?(200, 299)

        parsed
      end
    end
  end
end
