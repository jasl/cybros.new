module AgentControl
  module ExecutionReports
    class ToolInvocationReconciler
      def initialize(agent_task_run:, method_id:, occurred_at:, base_runtime_payload:, broadcast_runtime_event:)
        @agent_task_run = agent_task_run
        @method_id = method_id
        @occurred_at = occurred_at
        @base_runtime_payload = base_runtime_payload
        @broadcast_runtime_event = broadcast_runtime_event
      end

      def apply_progress!(progress_payload)
        invocation_payload = progress_payload["tool_invocation"]
        if invocation_payload.present? && invocation_payload["event"] == "started"
          invocation = find_or_start_tool_invocation!(invocation_payload)
          broadcast_tool_invocation_event!(
            "runtime.tool_invocation.started",
            tool_invocation: invocation,
            payload: {
              "command_run_id" => invocation_payload["command_run_id"],
              "call_id" => invocation_payload["call_id"],
              "tool_name" => invocation_payload["tool_name"],
              "request_payload" => invocation_payload.fetch("request_payload", {}),
            }.compact
          )
        end

        output_payload = progress_payload["tool_invocation_output"]
        return if output_payload.blank?

        broadcast_tool_invocation_output!(output_payload)
      end

      def apply_terminal!(terminal_payload)
        Array(terminal_payload["tool_invocations"]).each do |invocation_payload|
          invocation = find_or_start_tool_invocation!(invocation_payload)
          command_run = find_command_run_for_payload(invocation, invocation_payload)

          case invocation_payload["event"]
          when "completed"
            ToolInvocations::Complete.call(
              tool_invocation: invocation,
              response_payload: invocation_payload.fetch("response_payload", {}),
              metadata: {
                "reported_via" => @method_id,
              }
            )
            reconcile_completed_command_run!(command_run, invocation_payload.fetch("response_payload", {}))
            broadcast_tool_invocation_event!(
              "runtime.tool_invocation.completed",
              tool_invocation: invocation.reload,
              payload: {
                "command_run_id" => invocation_payload["command_run_id"] || invocation_payload.dig("response_payload", "command_run_id"),
                "call_id" => invocation_payload["call_id"],
                "tool_name" => invocation_payload["tool_name"],
                "response_payload" => invocation_payload.fetch("response_payload", {}),
              }
            )
          when "failed"
            ToolInvocations::Fail.call(
              tool_invocation: invocation,
              error_payload: invocation_payload.fetch("error_payload", {}),
              metadata: {
                "reported_via" => @method_id,
              }
            )
            reconcile_failed_command_run!(command_run, invocation_payload.fetch("error_payload", {}))
            broadcast_tool_invocation_event!(
              "runtime.tool_invocation.failed",
              tool_invocation: invocation.reload,
              payload: {
                "command_run_id" => invocation_payload["command_run_id"] || invocation_payload.dig("error_payload", "command_run_id"),
                "call_id" => invocation_payload["call_id"],
                "tool_name" => invocation_payload["tool_name"],
                "error_payload" => invocation_payload.fetch("error_payload", {}),
              }
            )
          end
        end
      end

      private

      def find_or_start_tool_invocation!(invocation_payload)
        if invocation_payload["tool_invocation_id"].present?
          return @agent_task_run.tool_invocations.find_by!(public_id: invocation_payload.fetch("tool_invocation_id"))
        end

        binding = tool_binding_for!(invocation_payload.fetch("tool_name"))
        result = ToolInvocations::Provision.call(
          tool_binding: binding,
          request_payload: invocation_payload.fetch("request_payload", {}),
          idempotency_key: invocation_payload["call_id"],
          metadata: {
            "reported_via" => @method_id,
          }
        )
        result.tool_invocation
      end

      def tool_binding_for!(tool_name)
        @agent_task_run.tool_bindings
          .joins(:tool_definition)
          .find_by!(tool_definitions: { tool_name: tool_name })
      end

      def broadcast_tool_invocation_event!(event_kind, tool_invocation:, payload:)
        @broadcast_runtime_event.call(
          event_kind,
          @base_runtime_payload.merge(
            "tool_invocation_id" => tool_invocation.public_id,
            "tool_name" => tool_invocation.tool_definition.tool_name
          ).merge(payload)
        )
      end

      def broadcast_tool_invocation_output!(output_payload)
        invocation = find_tool_invocation_for_output!(output_payload)

        Array(output_payload["output_chunks"]).each do |chunk|
          @broadcast_runtime_event.call(
            "runtime.tool_invocation.output",
            @base_runtime_payload.merge(
              "tool_invocation_id" => invocation.public_id,
              "tool_name" => invocation.tool_definition.tool_name,
              "command_run_id" => output_payload["command_run_id"],
              "call_id" => output_payload["call_id"],
              "stream" => chunk["stream"],
              "text" => chunk["text"]
            )
          )
        end
      end

      def find_tool_invocation_for_output!(output_payload)
        if output_payload["tool_invocation_id"].present?
          return @agent_task_run.tool_invocations.find_by!(public_id: output_payload.fetch("tool_invocation_id"))
        end

        binding = tool_binding_for!(output_payload.fetch("tool_name"))

        binding.tool_invocations.find_by!(
          idempotency_key: output_payload.fetch("call_id")
        )
      end

      def find_command_run_for_payload(invocation, invocation_payload)
        command_run_id =
          invocation_payload["command_run_id"] ||
          invocation_payload.dig("response_payload", "command_run_id") ||
          invocation_payload.dig("error_payload", "command_run_id")
        return if command_run_id.blank?

        invocation.command_run || @agent_task_run.command_runs.find_by!(public_id: command_run_id)
      end

      def reconcile_completed_command_run!(command_run, response_payload)
        return if command_run.blank?
        return if response_payload["session_closed"] == false

        CommandRuns::Terminalize.call(
          command_run: command_run,
          lifecycle_state: "completed",
          ended_at: @occurred_at,
          exit_status: response_payload["exit_status"],
          metadata: {
            "output_streamed" => response_payload["output_streamed"],
            "stdout_bytes" => response_payload["stdout_bytes"],
            "stderr_bytes" => response_payload["stderr_bytes"],
          }.compact
        )
      end

      def reconcile_failed_command_run!(command_run, error_payload)
        return if command_run.blank?

        CommandRuns::Terminalize.call(
          command_run: command_run,
          lifecycle_state: "failed",
          ended_at: @occurred_at,
          metadata: {
            "last_error" => error_payload,
          }
        )
      end
    end
  end
end
