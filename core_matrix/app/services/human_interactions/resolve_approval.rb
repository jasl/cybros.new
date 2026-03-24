module HumanInteractions
  class ResolveApproval
    DECISIONS = {
      "approved" => true,
      "denied" => false,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(approval_request:, decision:, result_payload: {})
      @approval_request = approval_request
      @decision = decision.to_s
      @result_payload = result_payload
    end

    def call
      raise_invalid!(@approval_request, :base, "must be open before approval resolution") unless @approval_request.open?
      if @approval_request.expired?
        return time_out_request!(@approval_request)
      end

      approved = DECISIONS.fetch(@decision) do
        raise_invalid!(@approval_request, :resolution_kind, "must be approved or denied")
      end

      ApplicationRecord.transaction do
        @approval_request.resolve!(
          resolution_kind: @decision,
          result_payload: @result_payload.merge("approved" => approved)
        )
        resume_workflow!(@approval_request)
        project_event!(@approval_request, "human_interaction.resolved")
        @approval_request
      end
    end

    private

    def time_out_request!(request)
      ApplicationRecord.transaction do
        request.time_out!
        resume_workflow!(request)
        project_event!(request, "human_interaction.timed_out")
        request
      end
    end

    def resume_workflow!(request)
      workflow_run = request.workflow_run
      return unless request.blocking?
      return unless workflow_run.waiting?
      return unless workflow_run.blocking_resource_type == "HumanInteractionRequest"
      return unless workflow_run.blocking_resource_id == request.id.to_s

      workflow_run.update!(
        wait_state: "ready",
        wait_reason_kind: nil,
        wait_reason_payload: {},
        waiting_since_at: nil,
        blocking_resource_type: nil,
        blocking_resource_id: nil
      )
    end

    def project_event!(request, event_kind)
      ConversationEvents::Project.call(
        conversation: request.conversation,
        turn: request.turn,
        source: request,
        event_kind: event_kind,
        stream_key: "human_interaction_request:#{request.id}",
        payload: {
          "request_id" => request.id,
          "request_type" => request.type,
          "lifecycle_state" => request.lifecycle_state,
          "resolution_kind" => request.resolution_kind,
          "result_payload" => request.result_payload,
        }
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
