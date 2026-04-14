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
      when "agent_request"
        execute_agent_request!
      else
        raise UnsupportedMailboxItemError, "unsupported mailbox item #{item_type.inspect}"
      end
    end

    private

    def execute_agent_request!
      response_payload = execute_agent_request

      return emit_agent_completion(response_payload) if response_payload.fetch("status") == "ok"

      emit_agent_failure(response_payload.fetch("failure"))
    rescue StandardError => error
      emit_agent_failure(agent_request_error_payload_for(error))
    end

    def execute_agent_request
      case request_kind
      when "prepare_round"
        Requests::PrepareRound.call(payload: mailbox_payload)
      when "execute_tool"
        Requests::ExecuteTool.call(payload: mailbox_payload)
      when "execute_feature"
        Requests::ExecuteFeature.call(payload: mailbox_payload)
      when "consult_prompt_compaction"
        Requests::ConsultPromptCompaction.call(payload: mailbox_payload)
      when "execute_prompt_compaction"
        Requests::ExecutePromptCompaction.call(payload: mailbox_payload)
      when "supervision_status_refresh", "supervision_guidance"
        Requests::ExecuteConversationControlRequest.call(payload: mailbox_payload)
      else
        raise UnsupportedMailboxItemError, "unsupported agent request kind #{request_kind.inspect}"
      end
    end

    def emit_agent_completion(response_payload)
      report = {
        "method_id" => "agent_completed",
        "protocol_message_id" => "fenix-agent_completed-#{SecureRandom.uuid}",
        "mailbox_item_id" => @mailbox_item.fetch("item_id"),
        "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
        "attempt_no" => @mailbox_item.fetch("attempt_no"),
        "control_plane" => control_plane,
        "request_kind" => request_kind,
        "workflow_node_id" => mailbox_payload.dig("task", "workflow_node_id"),
        "conversation_id" => conversation_id,
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

    def emit_agent_failure(error_payload)
      report = {
        "method_id" => "agent_failed",
        "protocol_message_id" => "fenix-agent_failed-#{SecureRandom.uuid}",
        "mailbox_item_id" => @mailbox_item.fetch("item_id"),
        "logical_work_id" => @mailbox_item.fetch("logical_work_id"),
        "attempt_no" => @mailbox_item.fetch("attempt_no"),
        "control_plane" => control_plane,
        "request_kind" => request_kind,
        "workflow_node_id" => mailbox_payload.dig("task", "workflow_node_id"),
        "conversation_id" => conversation_id,
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
      @mailbox_item.fetch("item_type", "agent_request")
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

    def conversation_id
      mailbox_payload.dig("task", "conversation_id") ||
        mailbox_payload.dig("conversation_control", "conversation_id")
    end

    def agent_request_error_payload_for(error)
      case error
      when Requests::ExecuteConversationControlRequest::InvalidRequestError
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
        "code" => "agent_request_failed",
        "message" => error.message,
        "retryable" => false,
      }
    end
  end
end
