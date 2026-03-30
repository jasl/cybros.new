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

      def create_tool_invocation!(agent_task_run_id:, tool_name:, request_payload:, idempotency_key: nil, stream_output: false, metadata: {})
        post_json("/agent_api/tool_invocations", {
          agent_task_run_id: agent_task_run_id,
          tool_name: tool_name,
          request_payload: request_payload,
          idempotency_key: idempotency_key,
          stream_output: stream_output,
          metadata: metadata,
        }.compact)
      end

      def create_command_run!(tool_invocation_id:, command_line:, timeout_seconds: nil, pty: false, metadata: {})
        post_json("/agent_api/command_runs", {
          tool_invocation_id: tool_invocation_id,
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          pty: pty,
          metadata: metadata,
        }.compact)
      end

      def activate_command_run!(command_run_id:)
        post_json("/agent_api/command_runs/#{command_run_id}/activate", {})
      end

      def create_process_run!(agent_task_run_id:, kind:, command_line:, timeout_seconds: nil, idempotency_key: nil, metadata: {}, policy_sensitive: nil)
        post_json("/agent_api/process_runs", {
          agent_task_run_id: agent_task_run_id,
          kind: kind,
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          idempotency_key: idempotency_key,
          metadata: metadata,
          policy_sensitive: policy_sensitive,
        }.compact)
      end

      private

      def post_json(path, payload)
        uri = URI.join(@base_url, path)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request["Authorization"] = %(Token token="#{@machine_credential}")
        request.body = JSON.generate(payload)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
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
