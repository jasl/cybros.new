module ProviderExecution
  module ToolCallRunners
    class Program
      def self.call(...)
        new(...).call
      end

      def initialize(workflow_node:, tool_call:, binding:, program_exchange:, **)
        @workflow_node = workflow_node
        @tool_call = tool_call
        @binding = binding
        @program_exchange = program_exchange
      end

      def call
        provision = ToolInvocations::Provision.call(
          tool_binding: @binding,
          request_payload: {
            "arguments" => @tool_call.fetch("arguments", {}),
          },
          idempotency_key: @tool_call.fetch("call_id"),
          metadata: {
            "provider_format" => @tool_call["provider_format"],
          }.compact
        )
        invocation = provision.tool_invocation
        return existing_result(invocation) unless provision.created

        runtime_resource_refs = { command_run: nil, process_run: nil, payload: {} }

        begin
          runtime_resource_refs = provision_runtime_resource_refs(invocation:)
          response = @program_exchange.execute_program_tool(
            payload: execute_program_tool_payload(
              invocation: invocation,
              runtime_resource_refs: runtime_resource_refs.fetch(:payload)
            )
          )

          if response.fetch("status") == "ok"
            ToolInvocations::Complete.call(
              tool_invocation: invocation,
              response_payload: response.fetch("result"),
              metadata: tool_execution_metadata(response)
            )
            reconcile_runtime_resources_on_success!(
              command_run: runtime_resource_refs[:command_run],
              process_run: runtime_resource_refs[:process_run],
              response_payload: response.fetch("result")
            )
            ProviderExecution::RouteToolCall::Result.new(
              tool_call: @tool_call,
              tool_binding: @binding,
              tool_invocation: invocation.reload,
              result: response.fetch("result")
            )
          else
            ToolInvocations::Fail.call(
              tool_invocation: invocation,
              error_payload: response.fetch("failure"),
              metadata: tool_execution_metadata(response)
            )
            reconcile_runtime_resources_on_failure!(
              command_run: runtime_resource_refs[:command_run],
              process_run: runtime_resource_refs[:process_run],
              error_payload: response.fetch("failure")
            )
            ProviderExecution::RouteToolCall::Result.new(
              tool_call: @tool_call,
              tool_binding: @binding,
              tool_invocation: invocation.reload,
              result: { "error" => response.fetch("failure") }
            )
          end
        rescue StandardError => error
          ToolInvocations::Fail.call(
            tool_invocation: invocation,
            error_payload: execution_error_payload_for(error)
          )
          reconcile_runtime_resources_on_failure!(
            command_run: runtime_resource_refs[:command_run],
            process_run: runtime_resource_refs[:process_run],
            error_payload: execution_error_payload_for(error)
          )
          raise
        end
      end

      private

      def existing_result(invocation)
        ProviderExecution::RouteToolCall::Result.new(
          tool_call: @tool_call,
          tool_binding: @binding,
          tool_invocation: invocation,
          result: invocation.succeeded? ? invocation.response_payload : { "error" => invocation.error_payload }
        )
      end

      def execute_program_tool_payload(invocation:, runtime_resource_refs:)
        {
          "protocol_version" => "agent-program/2026-04-01",
          "request_kind" => "execute_program_tool",
          "task" => {
            "workflow_node_id" => @workflow_node.public_id,
            "conversation_id" => @workflow_node.conversation.public_id,
            "turn_id" => @workflow_node.turn.public_id,
            "kind" => "turn_step",
          },
          "agent_context" => agent_context,
          "provider_context" => {
            "provider_execution" => @workflow_node.workflow_run.provider_execution,
            "model_context" => @workflow_node.workflow_run.model_context,
          },
          "runtime_context" => {
            "runtime_plane" => "program",
            "logical_work_id" => "program-tool:#{@workflow_node.public_id}:#{@tool_call.fetch("call_id")}",
            "attempt_no" => 1,
            "agent_program_version_id" => @workflow_node.turn.agent_program_version.public_id,
          },
          "program_tool_call" => {
            "call_id" => @tool_call.fetch("call_id"),
            "tool_name" => @tool_call.fetch("tool_name"),
            "arguments" => @tool_call.fetch("arguments", {}),
          },
          "runtime_resource_refs" => runtime_resource_refs.merge(
            "tool_invocation" => {
              "tool_invocation_id" => invocation.public_id,
            }
          ),
        }.compact
      end

      def agent_context
        capability_projection = @workflow_node.workflow_run.execution_snapshot.capability_projection

        {
          "profile" => capability_projection.fetch("profile_key", "main"),
          "is_subagent" => capability_projection["is_subagent"] == true,
          "subagent_session_id" => capability_projection["subagent_session_id"],
          "parent_subagent_session_id" => capability_projection["parent_subagent_session_id"],
          "subagent_depth" => capability_projection["subagent_depth"],
          "owner_conversation_id" => capability_projection["owner_conversation_id"],
          "allowed_tool_names" => [@tool_call.fetch("tool_name")],
        }.compact
      end

      def provision_runtime_resource_refs(invocation:)
        command_run = resolve_command_run_ref!(invocation:)
        process_run = resolve_process_run_ref!

        {
          command_run: command_run,
          process_run: process_run,
          payload: {
            "command_run" => serialize_command_run_ref(command_run),
            "process_run" => serialize_process_run_ref(process_run),
          }.compact,
        }
      end

      def resolve_command_run_ref!(invocation:)
        case @tool_call.fetch("tool_name")
        when "exec_command"
          CommandRuns::Provision.call(
            tool_invocation: invocation,
            command_line: @tool_call.dig("arguments", "command_line"),
            timeout_seconds: @tool_call.dig("arguments", "timeout_seconds"),
            pty: @tool_call.dig("arguments", "pty") == true,
            metadata: runtime_resource_metadata
          ).command_run
        when "command_run_wait", "command_run_read_output", "command_run_terminate", "write_stdin"
          find_command_run!(@tool_call.dig("arguments", "command_run_id"))
        end
      end

      def resolve_process_run_ref!
        case @tool_call.fetch("tool_name")
        when "process_exec"
          Processes::Provision.call(
            workflow_node: @workflow_node,
            execution_runtime: @workflow_node.turn.execution_runtime,
            kind: normalize_process_kind(@tool_call.dig("arguments", "kind")),
            command_line: @tool_call.dig("arguments", "command_line"),
            timeout_seconds: @tool_call.dig("arguments", "timeout_seconds"),
            metadata: runtime_resource_metadata,
            idempotency_key: @tool_call.fetch("call_id")
          ).process_run
        when "process_proxy_info", "process_read_output"
          find_process_run!(@tool_call.dig("arguments", "process_run_id"))
        end
      end

      def serialize_command_run_ref(command_run)
        return if command_run.blank?

        {
          "command_run_id" => command_run.public_id,
        }
      end

      def serialize_process_run_ref(process_run)
        return if process_run.blank?

        {
          "process_run_id" => process_run.public_id,
          "agent_task_run_id" => @workflow_node.turn.public_id,
        }
      end

      def runtime_resource_metadata
        {
          "logical_work_id" => "program-tool:#{@workflow_node.public_id}:#{@tool_call.fetch("call_id")}",
          "attempt_no" => 1,
          "provider_format" => @tool_call["provider_format"],
          "proxy" => {
            "target_port" => @tool_call.dig("arguments", "proxy_port"),
          }.compact.presence,
        }.compact
      end

      def normalize_process_kind(kind)
        case kind.to_s
        when "", "background", "background_service", "command", "process", "web", "web_server", "server", "default"
          "background_service"
        else
          kind
        end
      end

      def find_command_run!(public_id)
        CommandRun.find_by!(installation: @workflow_node.installation, public_id: public_id)
      end

      def find_process_run!(public_id)
        ProcessRun.find_by!(installation: @workflow_node.installation, public_id: public_id)
      end

      def reconcile_runtime_resources_on_success!(command_run:, process_run:, response_payload:)
        reconcile_command_run_on_success!(command_run:, response_payload:)
        reconcile_process_run_on_success!(process_run:, response_payload:)
      end

      def reconcile_runtime_resources_on_failure!(command_run:, process_run:, error_payload:)
        reconcile_command_run_on_failure!(command_run:, error_payload:)
        reconcile_process_run_on_failure!(process_run:, error_payload:)
      end

      def reconcile_command_run_on_success!(command_run:, response_payload:)
        return if command_run.blank?

        if response_payload["session_closed"] == false || response_payload["attached"] == true
          CommandRuns::Activate.call(command_run:) if command_run.starting?
          return
        end

        CommandRuns::Terminalize.call(
          command_run: command_run,
          lifecycle_state: command_run_terminal_state_for(response_payload:),
          ended_at: Time.current,
          exit_status: response_payload["exit_status"],
          metadata: {
            "output_streamed" => response_payload["output_streamed"],
            "stdout_bytes" => response_payload["stdout_bytes"],
            "stderr_bytes" => response_payload["stderr_bytes"],
          }.compact
        )
      end

      def command_run_terminal_state_for(response_payload:)
        return "interrupted" if response_payload["terminated"] == true

        "completed"
      end

      def reconcile_command_run_on_failure!(command_run:, error_payload:)
        return if command_run.blank?

        CommandRuns::Terminalize.call(
          command_run: command_run,
          lifecycle_state: "failed",
          ended_at: Time.current,
          metadata: {
            "last_error" => error_payload,
          }
        )
      end

      def reconcile_process_run_on_success!(process_run:, response_payload:)
        return if process_run.blank?

        case response_payload["lifecycle_state"]
        when "running"
          Processes::Activate.call(process_run:) if process_run.starting?
        when "stopped", "failed"
          Processes::Exit.call(
            process_run: process_run,
            lifecycle_state: response_payload.fetch("lifecycle_state"),
            reason: "tool_response",
            exit_status: response_payload["exit_status"],
            metadata: {}
          )
        end
      end

      def reconcile_process_run_on_failure!(process_run:, error_payload:)
        return if process_run.blank?

        Processes::Exit.call(
          process_run: process_run,
          lifecycle_state: "failed",
          reason: "tool_execution_failed",
          metadata: {
            "last_error" => error_payload,
          }
        )
      end

      def tool_execution_metadata(response)
        {
          "fenix" => {
            "summary_artifacts" => response["summary_artifacts"],
            "output_chunks" => response["output_chunks"],
          }.compact,
        }
      end

      def execution_error_payload_for(error)
        classification =
          case error
          when ActiveRecord::RecordNotFound, KeyError
            "semantic"
          when ActiveRecord::RecordInvalid
            "authorization"
          else
            "runtime"
          end

        {
          "classification" => classification,
          "code" => "tool_execution_failed",
          "message" => error.message,
          "retryable" => false,
        }
      end
    end
  end
end
