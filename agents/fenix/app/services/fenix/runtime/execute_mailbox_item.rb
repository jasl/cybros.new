require "securerandom"

module Fenix
  module Runtime
    class ExecuteMailboxItem
      UnsupportedMailboxItemError = Class.new(StandardError)

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, deliver_reports: false, control_client: nil)
        @mailbox_item = mailbox_item.deep_stringify_keys
        @deliver_reports = deliver_reports
        @control_client = control_client
      end

      def call
        case item_type
        when "execution_assignment"
          execute_execution_assignment!
        when "agent_program_request"
          execute_agent_program_request!
        else
          raise UnsupportedMailboxItemError, "unsupported mailbox item #{item_type.inspect}"
        end
      end

      private

      def execute_execution_assignment!
        reports = [emit_execution_started]
        dispatch = Fenix::Runtime::Assignments::DispatchMode.call(
          task_payload: mailbox_payload.fetch("task_payload", {}),
          runtime_context: mailbox_payload.fetch("runtime_context", {})
        )

        case dispatch.fetch("kind")
        when "skill_flow"
          emit_execution_completion(dispatch.fetch("output"), reports: reports)
        when "deterministic_tool"
          emit_execution_completion(
            Fenix::Runtime::Assignments::DeterministicTool.call(
              task_payload: mailbox_payload.fetch("task_payload", {})
            ),
            reports: reports
          )
        when "raise_error"
          raise RuntimeError, "requested execution assignment failure"
        else
          fail_unsupported_execution_assignment_dispatch!(dispatch_kind: dispatch.fetch("kind"), reports: reports)
        end

      rescue StandardError => error
        emit_execution_failure(execution_assignment_error_payload_for(error), reports: defined?(reports) ? reports : [])
      end

      def emit_execution_started
        report = execution_assignment_report(
          method_id: "execution_started",
          expected_duration_seconds: 30
        )

        @control_client&.report!(payload: report) if @deliver_reports
        report
      end

      def emit_execution_completion(output, reports:)
        report = execution_assignment_report(
          method_id: "execution_complete",
          terminal_payload: output
        )

        @control_client&.report!(payload: report) if @deliver_reports

        {
          "status" => "ok",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "reports" => reports + [report],
          "output" => output,
        }
      end

      def emit_execution_failure(error_payload, reports:)
        report = execution_assignment_report(
          method_id: "execution_fail",
          terminal_payload: error_payload
        )

        emit_result(report: report, reports: reports, error_payload: error_payload)
      end

      def fail_unsupported_execution_assignment_dispatch!(dispatch_kind:, reports:)
        error_payload = {
          "classification" => "configuration",
          "code" => "unsupported_execution_assignment_dispatch_kind",
          "message" => "unsupported execution assignment dispatch kind #{dispatch_kind.inspect}",
          "retryable" => false,
        }
        emit_execution_failure(error_payload, reports: reports)
      end

      def execute_agent_program_request!
        response_payload = execute_agent_program_request

        return emit_agent_program_completion(response_payload) if response_payload.fetch("status") == "ok"

        emit_agent_program_failure(response_payload.fetch("failure"))
      rescue StandardError => error
        emit_agent_program_failure(agent_program_request_error_payload_for(error))
      end

      def execute_agent_program_request
        case request_kind
        when "prepare_round"
          Fenix::Agent::Program::PrepareRound.call(payload: mailbox_payload)
        when "execute_program_tool"
          Fenix::Agent::Program::ExecuteProgramTool.call(
            payload: mailbox_payload,
            supported_system_tool_names: Fenix::Executor::SystemToolRegistry.supported_tool_names,
            system_tool_executor: system_tool_executor
          )
        when "supervision_status_refresh", "supervision_guidance"
          Fenix::Agent::Program::ExecuteConversationControlRequest.call(payload: mailbox_payload)
        else
          raise UnsupportedMailboxItemError, "unsupported agent program request #{request_kind.inspect}"
        end
      end

      def emit_agent_program_completion(response_payload)
        report = {
          "method_id" => "agent_program_completed",
          "protocol_message_id" => "fenix-agent_program_completed-#{SecureRandom.uuid}",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "control_plane" => control_plane,
          "request_kind" => request_kind,
          "workflow_node_id" => mailbox_payload.dig("task", "workflow_node_id"),
          "conversation_id" => mailbox_payload.dig("task", "conversation_id"),
          "turn_id" => mailbox_payload.dig("task", "turn_id"),
          "response_payload" => response_payload,
        }.compact

        @control_client&.report!(payload: report) if @deliver_reports

        {
          "status" => "ok",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "reports" => [report],
          "response" => response_payload,
        }
      end

      def emit_agent_program_failure(error_payload)
        report = {
          "method_id" => "agent_program_failed",
          "protocol_message_id" => "fenix-agent_program_failed-#{SecureRandom.uuid}",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "control_plane" => control_plane,
          "request_kind" => request_kind,
          "workflow_node_id" => mailbox_payload.dig("task", "workflow_node_id"),
          "conversation_id" => mailbox_payload.dig("task", "conversation_id"),
          "turn_id" => mailbox_payload.dig("task", "turn_id"),
          "error_payload" => error_payload,
        }.compact

        emit_result(report: report, reports: [], error_payload: error_payload)
      end

      def emit_result(report:, reports:, error_payload:)
        @control_client&.report!(payload: report) if @deliver_reports

        {
          "status" => "failed",
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "reports" => reports + [report],
          "error" => error_payload,
        }
      end

      def item_type
        @mailbox_item.fetch("item_type", "execution_assignment")
      end

      def request_kind
        mailbox_payload.fetch("request_kind")
      end

      def mailbox_payload
        @mailbox_payload ||= @mailbox_item.fetch("payload", {}).deep_stringify_keys
      end

      def control_plane
        @mailbox_item.fetch("control_plane")
      end

      def system_tool_executor
        @system_tool_executor ||= lambda do |payload_context:, tool_call:, runtime_resource_refs:|
          Fenix::Executor::ProgramToolExecutor.new(
            context: payload_context,
            control_client: @control_client
          ).call(
            tool_call: tool_call,
            command_run: runtime_resource_refs["command_run"],
            process_run: runtime_resource_refs["process_run"]
          )
        end
      end

      def execution_assignment_report(method_id:, expected_duration_seconds: nil, terminal_payload: nil)
        {
          "method_id" => method_id,
          "protocol_message_id" => "fenix-#{method_id}-#{SecureRandom.uuid}",
          "control_plane" => control_plane,
          "mailbox_item_id" => @mailbox_item.fetch("item_id"),
          "agent_task_run_id" => @mailbox_item.dig("payload", "task", "agent_task_run_id"),
          "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
          "attempt_no" => @mailbox_item.fetch("attempt_no"),
          "expected_duration_seconds" => expected_duration_seconds,
          "terminal_payload" => terminal_payload,
        }.compact
      end

      def execution_assignment_error_payload_for(error)
        case error
        when Fenix::Agent::Skills::Repository::MissingScopeError
          {
            "classification" => "configuration",
            "code" => "missing_skill_scope",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Agent::Skills::PackageValidator::InvalidSkillPackage
          {
            "classification" => "semantic",
            "code" => "invalid_skill_package",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Agent::Skills::Repository::SkillNotFound
          {
            "classification" => "semantic",
            "code" => "skill_not_found",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Agent::Skills::Repository::InvalidFileReference
          {
            "classification" => "semantic",
            "code" => "invalid_skill_file_reference",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Agent::Skills::Repository::ReservedSkillNameError
          {
            "classification" => "semantic",
            "code" => "reserved_skill_name",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Runtime::Assignments::DeterministicTool::InvalidRequestError
          {
            "classification" => "semantic",
            "code" => "invalid_deterministic_tool_request",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Agent::Program::ExecuteConversationControlRequest::InvalidRequestError
          {
            "classification" => "semantic",
            "code" => "invalid_conversation_control_request",
            "message" => error.message,
            "retryable" => false,
          }
        else
          {
            "classification" => "runtime",
            "code" => "runtime_error",
            "message" => error.message,
            "retryable" => false,
          }
        end
      end

      def agent_program_request_error_payload_for(error)
        case error
        when Fenix::Agent::Program::ExecuteConversationControlRequest::InvalidRequestError
          {
            "classification" => "semantic",
            "code" => "invalid_conversation_control_request",
            "message" => error.message,
            "retryable" => false,
          }
        else
          runtime_error_payload_for(error)
        end
      end

      def runtime_error_payload_for(error)
        {
          "classification" => "runtime",
          "code" => "program_request_failed",
          "message" => error.message,
          "retryable" => false,
        }
      end
    end
  end
end
