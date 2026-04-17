require "json"
require "webrick"

module CybrosNexus
  module HTTP
    class Server
      def initialize(config:, manifest:)
        @config = config
        @manifest = manifest
        @server = nil
      end

      def base_url
        @config.public_base_url
      end

      def start
        @server = build_server
        mount_routes(@server)
        @server.start
      end

      def stop
        @server&.shutdown
      end

      private

      def build_server
        WEBrick::HTTPServer.new(
          BindAddress: @config.http_bind,
          Port: @config.http_port,
          Logger: WEBrick::Log.new(File::NULL, WEBrick::Log::FATAL),
          AccessLog: []
        )
      end

      def mount_routes(server)
        server.mount_proc("/runtime/manifest") do |_request, response|
          render_json(response, status: 200, body: manifest_payload)
        end

        server.mount_proc("/health/live") do |_request, response|
          render_json(response, status: 200, body: { "status" => "ok" })
        end

        server.mount_proc("/health/ready") do |_request, response|
          render_json(response, status: 200, body: { "status" => "ready" })
        end
      end

      def manifest_payload
        @manifest.respond_to?(:call) ? @manifest.call : @manifest
      end

      def render_json(response, status:, body:)
        response.status = status
        response["Content-Type"] = "application/json"
        response.body = JSON.generate(body)
      end
    end
  end
end
