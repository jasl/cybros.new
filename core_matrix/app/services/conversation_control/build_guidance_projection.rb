module ConversationControl
  class BuildGuidanceProjection
    RECENT_LIMIT = 5
    GUIDANCE_OUTCOME_KIND = "guidance_acknowledged"

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      items = recent_guidance_items
      return nil if items.empty?

      {
        "guidance_scope" => guidance_scope,
        "latest_guidance" => items.last,
        "recent_guidance" => items,
      }
    end

    private

    def recent_guidance_items
      ordered_requests
        .reverse
        .map { |request| serialize_request(request) }
    end

    def ordered_requests
      guidance_requests
        .includes(:target_conversation)
        .where("result_payload -> 'response_payload' -> 'control_outcome' ->> 'outcome_kind' = ?", GUIDANCE_OUTCOME_KIND)
        .order(completed_at: :desc, id: :desc)
        .limit(RECENT_LIMIT)
    end

    def guidance_requests
      if subagent_session.present?
        ConversationControlRequest.where(
          installation_id: conversation.installation_id,
          request_kind: "send_guidance_to_subagent",
          lifecycle_state: "completed",
          target_kind: "subagent_session",
          target_public_id: subagent_session.public_id
        )
      else
        ConversationControlRequest.where(
          installation_id: conversation.installation_id,
          request_kind: "send_guidance_to_active_agent",
          lifecycle_state: "completed",
          target_kind: "conversation",
          target_conversation_id: conversation.id
        )
      end
    end

    def serialize_request(request)
      {
        "conversation_control_request_id" => request.public_id,
        "request_kind" => request.request_kind,
        "target_kind" => request.target_kind,
        "target_public_id" => request.target_public_id,
        "content" => request.request_payload["content"].to_s.strip,
        "source_conversation_id" => source_conversation_public_id(request),
        "delivered_at" => request.completed_at&.iso8601,
      }.compact
    end

    def source_conversation_public_id(request)
      return subagent_session.owner_conversation.public_id if request.request_kind == "send_guidance_to_subagent" && subagent_session.present?

      request.target_conversation.public_id
    end

    def guidance_scope
      subagent_session.present? ? "subagent" : "conversation"
    end

    attr_reader :conversation

    def subagent_session
      @subagent_session ||= conversation.subagent_session
    end
  end
end
