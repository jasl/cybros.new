require "json"
require "net/http"
require "uri"

module CybrosNexus
  module Attachments
    class Client
      DEFAULT_REFRESH_PATH = "/execution_runtime_api/attachments/request".freeze
      DEFAULT_PUBLISH_PATH = "/execution_runtime_api/attachments/publish".freeze

      def initialize(base_url:, connection_credential:, http_transport: nil)
        @base_url = base_url
        @connection_credential = connection_credential
        @http_transport = http_transport
      end

      def refresh_attachment(turn_id:, attachment_id:, path: DEFAULT_REFRESH_PATH)
        request_json(
          :post,
          path,
          json: {
            "turn_id" => turn_id,
            "attachment_id" => attachment_id,
          }
        )
      end

      def publish_attachment(turn_id:, publication_role:, files:, path: DEFAULT_PUBLISH_PATH)
        request_multipart(
          :post,
          path,
          form: {
            "turn_id" => turn_id,
            "publication_role" => publication_role,
            "files" => Array(files),
          }
        )
      end

      private

      def request_json(method, path, json:)
        headers = default_headers("Content-Type" => "application/json")

        response =
          if @http_transport
            @http_transport.call(method: method, path: path, headers: headers, json: json)
          else
            perform_json_request(method: method, path: path, headers: headers, json: json)
          end

        normalize_response(path: path, response: response)
      end

      def request_multipart(method, path, form:)
        headers = default_headers

        response =
          if @http_transport
            @http_transport.call(method: method, path: path, headers: headers, form: form)
          else
            perform_multipart_request(method: method, path: path, headers: headers, form: form)
          end

        normalize_response(path: path, response: response)
      end

      def perform_json_request(method:, path:, headers:, json:)
        uri = URI.join(@base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = request_class_for(method).new(uri)
        headers.each { |name, value| request[name] = value }
        request.body = JSON.generate(json)

        response = http.request(request)

        {
          status: response.code.to_i,
          body: response.body.to_s.empty? ? {} : JSON.parse(response.body),
        }
      end

      def perform_multipart_request(method:, path:, headers:, form:)
        uri = URI.join(@base_url, path)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"

        request = request_class_for(method).new(uri)
        headers.each { |name, value| request[name] = value }
        request.set_form(multipart_pairs(form), "multipart/form-data")

        response = http.request(request)

        {
          status: response.code.to_i,
          body: response.body.to_s.empty? ? {} : JSON.parse(response.body),
        }
      end

      def multipart_pairs(form)
        Array(form["files"]).map do |file|
          [
            "files[]",
            file.fetch("io"),
            {
              filename: file.fetch("filename"),
              content_type: file.fetch("content_type"),
            },
          ]
        end.tap do |pairs|
          pairs.unshift(["publication_role", form["publication_role"]]) if form["publication_role"]
          pairs.unshift(["turn_id", form.fetch("turn_id")])
        end
      end

      def normalize_response(path:, response:)
        status = response[:status] || response["status"]
        body = normalize_body(response[:body] || response["body"] || {})
        raise CybrosNexus::Error, "request to #{path} failed with status #{status}" unless status.to_i.between?(200, 299)

        body
      end

      def normalize_body(body)
        return JSON.parse(body) if body.is_a?(String)

        JSON.parse(JSON.generate(body))
      rescue JSON::ParserError
        body
      end

      def default_headers(extra = {})
        {
          "Accept" => "application/json",
          "Authorization" => %(Token token="#{@connection_credential}"),
        }.merge(extra)
      end

      def request_class_for(method)
        case method
        when :post
          Net::HTTP::Post
        else
          raise ArgumentError, "unsupported request method #{method.inspect}"
        end
      end
    end
  end
end
