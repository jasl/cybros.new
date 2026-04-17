require "securerandom"

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
      else
        raise UnsupportedMailboxItemError, "unsupported mailbox item #{item_type.inspect}"
      end
    end

    private

    def execute_execution_assignment!
      reports = [emit_execution_started]
      dispatch = Runtime::Assignments::DispatchMode.call(
        task_payload: mailbox_payload.fetch("task_payload", {}),
        runtime_context: mailbox_payload.fetch("runtime_context", {})
      )

      case dispatch.fetch("kind")
      when "tool_call"
        emit_execution_completion(
          Runtime::Assignments::ExecuteToolCall.call(
            mailbox_item: @mailbox_item,
            payload: mailbox_payload,
            control_client: @control_client
          ),
          reports: reports
        )
      when "skill_flow"
        emit_execution_completion(dispatch.fetch("output"), reports: reports)
      when "deterministic_tool"
        emit_execution_completion(
          Runtime::Assignments::DeterministicTool.call(
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

    def mailbox_payload
      @mailbox_payload ||= @mailbox_item.fetch("payload", {}).deep_stringify_keys
    end

    def control_plane
      @mailbox_item.fetch("control_plane")
    end

    def execution_assignment_report(method_id:, expected_duration_seconds: nil, terminal_payload: nil)
      {
        "method_id" => method_id,
        "protocol_message_id" => "nexus-#{method_id}-#{SecureRandom.uuid}",
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
      when Skills::Repository::MissingScopeError
        {
          "classification" => "configuration",
          "code" => "missing_skill_scope",
          "message" => error.message,
          "retryable" => false,
        }
      when Skills::PackageValidator::InvalidSkillPackage
        {
          "classification" => "semantic",
          "code" => "invalid_skill_package",
          "message" => error.message,
          "retryable" => false,
        }
      when Skills::Repository::SkillNotFound
        {
          "classification" => "semantic",
          "code" => "skill_not_found",
          "message" => error.message,
          "retryable" => false,
        }
      when Skills::Repository::InvalidFileReference
        {
          "classification" => "semantic",
          "code" => "invalid_skill_file_reference",
          "message" => error.message,
          "retryable" => false,
        }
      when Skills::Repository::ReservedSkillNameError
        {
          "classification" => "semantic",
          "code" => "reserved_skill_name",
          "message" => error.message,
          "retryable" => false,
        }
      when Runtime::Assignments::DeterministicTool::InvalidRequestError
        {
          "classification" => "semantic",
          "code" => "invalid_deterministic_tool_request",
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
  end
end
