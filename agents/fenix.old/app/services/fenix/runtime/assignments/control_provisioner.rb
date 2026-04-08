module Fenix
  module Runtime
    module Assignments
      class ControlProvisioner
        def initialize(control_client:, context:, agent_task_run_id:)
          @control_client = control_client
          @context = context.deep_stringify_keys
          @agent_task_run_id = agent_task_run_id
        end

        def create_tool_invocation!(tool_call:)
          @control_client.create_tool_invocation!(
            agent_task_run_id: @agent_task_run_id,
            tool_name: tool_call.fetch("tool_name"),
            request_payload: tool_call.except("call_id"),
            idempotency_key: tool_call.fetch("call_id"),
            stream_output: streaming_tool?(tool_call.fetch("tool_name")),
            metadata: execution_metadata(tool_call:)
          )
        end

        def create_command_run_if_needed!(tool_call:, tool_invocation:)
          return unless tool_call.fetch("tool_name") == "exec_command"

          @control_client.create_command_run!(
            tool_invocation_id: tool_invocation.fetch("tool_invocation_id"),
            command_line: tool_call.dig("arguments", "command_line"),
            timeout_seconds: tool_call.dig("arguments", "timeout_seconds"),
            pty: tool_call.dig("arguments", "pty"),
            metadata: base_metadata
          )
        end

        def create_process_run!(tool_call:)
          @control_client.create_process_run!(
            agent_task_run_id: @agent_task_run_id,
            tool_name: tool_call.fetch("tool_name"),
            kind: normalize_process_kind(tool_call.dig("arguments", "kind")),
            command_line: tool_call.dig("arguments", "command_line"),
            idempotency_key: tool_call.fetch("call_id"),
            metadata: execution_metadata(tool_call:)
          )
        end

        private

        def base_metadata
          {
            "logical_work_id" => @context.fetch("logical_work_id"),
            "attempt_no" => @context.fetch("attempt_no"),
          }
        end

        def execution_metadata(tool_call:)
          base_metadata.merge(
            {
              "proxy" => {
                "target_port" => tool_call.dig("arguments", "proxy_port"),
              }.compact.presence,
            }.compact
          )
        end

        def normalize_process_kind(kind)
          case kind.to_s
          when "", "background", "background_service", "command", "process", "web", "web_server", "server", "default"
            "background_service"
          else
            kind
          end
        end

        def streaming_tool?(tool_name)
          %w[exec_command write_stdin].include?(tool_name)
        end
      end
    end
  end
end
