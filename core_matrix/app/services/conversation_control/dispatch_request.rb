module ConversationControl
  class DispatchRequest
    def self.call(...)
      new(...).call
    end

    def initialize(conversation_control_request:, occurred_at: Time.current)
      @conversation_control_request = conversation_control_request
      @occurred_at = occurred_at
    end

    def call
      case @conversation_control_request.request_kind
      when "request_status_refresh"
        dispatch_mailbox_request!(
          mailbox_request_kind: "supervision_status_refresh",
          payload: {}
        )
      when "send_guidance_to_active_agent"
        content = @conversation_control_request.request_payload["content"].to_s.strip
        return reject!("control guidance content is required") if content.blank?

        dispatch_mailbox_request!(
          mailbox_request_kind: "supervision_guidance",
          payload: { "content" => content }
        )
      when "send_guidance_to_subagent"
        content = @conversation_control_request.request_payload["content"].to_s.strip
        subagent_connection = resolved_target.subagent_connection
        return reject!("control guidance content is required") if content.blank?
        return reject!("conversation has no active subagent for guidance") if subagent_connection.blank?

        dispatch_mailbox_request!(
          mailbox_request_kind: "supervision_guidance",
          payload: {
            "content" => content,
            "subagent_connection_id" => subagent_connection.public_id,
          }
        )
      when "request_turn_interrupt"
        turn = resolved_target.active_turn
        return reject!("conversation has no active turn to interrupt") if turn.blank?

        Conversations::RequestTurnInterrupt.call(
          turn: turn,
          occurred_at: @occurred_at,
          conversation_control_request: @conversation_control_request
        )
      when "request_conversation_close"
        Conversations::RequestClose.call(
          conversation: conversation,
          intent_kind: @conversation_control_request.request_payload["intent_kind"].presence || "archive",
          occurred_at: @occurred_at,
          conversation_control_request: @conversation_control_request
        )
      when "request_subagent_close"
        subagent_connection = resolved_target.subagent_connection
        return reject!("conversation has no active subagent to close") if subagent_connection.blank?

        SubagentConnections::RequestClose.call(
          subagent_connection: subagent_connection,
          request_kind: "request_subagent_close",
          reason_kind: "supervision_subagent_close_requested",
          strictness: @conversation_control_request.request_payload["strictness"].presence || "graceful",
          conversation_control_request: @conversation_control_request,
          occurred_at: @occurred_at
        )
      when "resume_waiting_workflow"
        workflow_run = resolved_target.workflow_run
        return reject!("workflow is not paused for manual recovery") unless workflow_run&.paused_agent_unavailable?
        return reject!("conversation has no active agent runtime for control dispatch") if resolved_target.agent_definition_version.blank?

        Workflows::ManualResume.call(
          workflow_run: workflow_run,
          agent_definition_version: resolved_target.agent_definition_version,
          actor: request_actor,
          conversation_control_request: @conversation_control_request
        )
      when "retry_blocked_step"
        workflow_run = resolved_target.workflow_run
        return reject!("workflow wait state does not permit step retry") unless workflow_retryable?(workflow_run)

        Workflows::StepRetry.call(
          workflow_run: workflow_run,
          conversation_control_request: @conversation_control_request
        )
      else
        raise ArgumentError, "unsupported conversation control request #{@conversation_control_request.request_kind}"
      end

      @conversation_control_request.reload
    rescue ActiveRecord::RecordInvalid => error
      fail!(error.record.errors.full_messages.to_sentence.presence || error.message)
    end

    private

    def conversation
      @conversation_control_request.target_conversation
    end

    def resolved_target
      @resolved_target ||= ConversationControl::ResolveTargetRuntime.call(
        conversation: conversation,
        request_kind: @conversation_control_request.request_kind,
        request_payload: @conversation_control_request.request_payload
      )
    end

    def dispatch_mailbox_request!(mailbox_request_kind:, payload:)
      return reject!("conversation has no active agent runtime for control dispatch") if resolved_target.agent_definition_version.blank?

      AgentControl::CreateConversationControlRequest.call(
        conversation_control_request: @conversation_control_request,
        agent_definition_version: resolved_target.agent_definition_version,
        request_kind: mailbox_request_kind,
        payload: payload,
        dispatch_deadline_at: @occurred_at + 5.minutes
      )
    end

    def workflow_retryable?(workflow_run)
      workflow_run.present? &&
        workflow_run.waiting? &&
        workflow_run.wait_reason_kind == "retryable_failure" &&
        workflow_run.wait_retry_scope == "step"
    end

    def reject!(reason)
      @conversation_control_request.update!(
        lifecycle_state: "rejected",
        completed_at: @occurred_at,
        result_payload: @conversation_control_request.result_payload.merge(
          "rejection_reason" => reason
        )
      )
      @conversation_control_request
    end

    def fail!(reason)
      @conversation_control_request.update!(
        lifecycle_state: "failed",
        completed_at: @occurred_at,
        result_payload: @conversation_control_request.result_payload.merge(
          "failure_reason" => reason
        )
      )
      @conversation_control_request.reload
    end

    def request_actor
      actor_payload = @conversation_control_request.request_payload["control_actor"]
      fallback_actor = @conversation_control_request.conversation_supervision_session.initiator
      return fallback_actor unless actor_payload.is_a?(Hash)

      actor_class = actor_payload["kind"].to_s.safe_constantize
      return fallback_actor unless actor_class&.respond_to?(:find_by)

      actor_class.find_by(
        installation_id: conversation.installation_id,
        public_id: actor_payload["public_id"]
      ) || fallback_actor
    end
  end
end
