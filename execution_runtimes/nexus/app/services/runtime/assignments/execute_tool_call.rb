module Runtime
  module Assignments
    class ExecuteToolCall
      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, payload:, control_client:)
        @mailbox_item = mailbox_item.deep_stringify_keys
        @payload = payload.deep_stringify_keys
        @control_client = control_client
      end

      def call
        tool_call = @payload.fetch("tool_call").deep_stringify_keys
        execution = ToolExecutor.new(
          context: payload_context,
          collector: progress_reporter,
          control_client: @control_client
        ).call(
          tool_call: tool_call,
          command_run: runtime_resource_refs["command_run"],
          process_run: runtime_resource_refs["process_run"]
        )

        {
          "tool_invocations" => [
            {
              "event" => "completed",
              "tool_invocation_id" => tool_invocation_id,
              "call_id" => tool_call.fetch("call_id"),
              "tool_name" => tool_call.fetch("tool_name"),
              "command_run_id" => execution.tool_result["command_run_id"],
              "response_payload" => execution.tool_result,
            }.compact,
          ],
          "output" => summarize_success(execution.tool_result),
        }
      rescue StandardError => error
        error_payload = ToolExecutor.error_payload_for(error)

        {
          "tool_invocations" => [
            {
              "event" => "failed",
              "tool_invocation_id" => tool_invocation_id,
              "call_id" => tool_call.fetch("call_id"),
              "tool_name" => tool_call.fetch("tool_name"),
              "command_run_id" => runtime_resource_refs.dig("command_run", "command_run_id"),
              "error_payload" => error_payload,
            }.compact,
          ],
          "last_error_summary" => error_payload["message"],
        }
      end

      private

      def payload_context
        @payload_context ||= Shared::PayloadContext.call(
          payload: @payload,
          memory_store: Memory::Store.new(
            workspace_root: workspace_root,
            conversation_id: conversation_id
          )
        )
      end

      def progress_reporter
        @progress_reporter ||= ProgressReporter.new(
          mailbox_item: @mailbox_item,
          control_client: @control_client,
          tool_call: @payload.fetch("tool_call"),
          tool_invocation_id: tool_invocation_id,
          command_run_id: runtime_resource_refs.dig("command_run", "command_run_id")
        )
      end

      def runtime_resource_refs
        @runtime_resource_refs ||= @payload.fetch("runtime_resource_refs", {}).deep_stringify_keys
      end

      def tool_invocation_id
        runtime_resource_refs.dig("tool_invocation", "tool_invocation_id")
      end

      def workspace_root
        @workspace_root ||= begin
          explicit_workspace_root = @payload.fetch("workspace_context", {}).deep_stringify_keys["workspace_root"]
          explicit_workspace_root.presence || ENV["NEXUS_WORKSPACE_ROOT"].presence || Dir.pwd
        end
      end

      def conversation_id
        @conversation_id ||= @payload.fetch("task").deep_stringify_keys.fetch("conversation_id")
      end

      def summarize_success(result)
        case result["tool_name"]
        when "process_exec"
          "Started the requested process."
        else
          "Execution runtime completed the requested tool call."
        end
      end

      class ProgressReporter
        def initialize(mailbox_item:, control_client:, tool_call:, tool_invocation_id:, command_run_id:)
          @mailbox_item = mailbox_item.deep_stringify_keys
          @control_client = control_client
          @tool_call = tool_call.deep_stringify_keys
          @tool_invocation_id = tool_invocation_id
          @command_run_id = command_run_id
        end

        def progress!(progress_payload:)
          return if @control_client.blank?

          normalized = progress_payload.deep_stringify_keys
          output_payload = normalized["tool_invocation_output"]
          return if output_payload.blank?

          enriched_output = output_payload.merge(
            "tool_invocation_id" => @tool_invocation_id,
            "call_id" => @tool_call.fetch("call_id"),
            "tool_name" => @tool_call.fetch("tool_name"),
            "command_run_id" => output_payload["command_run_id"] || @command_run_id
          ).compact

          @control_client.report!(
            payload: {
              "method_id" => "execution_progress",
              "protocol_message_id" => "nexus-execution_progress-#{SecureRandom.uuid}",
              "control_plane" => @mailbox_item.fetch("control_plane"),
              "mailbox_item_id" => @mailbox_item.fetch("item_id"),
              "agent_task_run_id" => @mailbox_item.dig("payload", "task", "agent_task_run_id"),
              "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
              "attempt_no" => @mailbox_item.fetch("attempt_no"),
              "progress_payload" => {
                "tool_invocation_output" => enriched_output,
              },
            }
          )
        end
      end
    end
  end
end
