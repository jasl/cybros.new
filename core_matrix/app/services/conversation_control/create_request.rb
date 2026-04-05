module ConversationControl
  class CreateRequest
    def self.call(...)
      new(...).call
    end

    def initialize(actor:, conversation_supervision_session:, request_kind:, request_payload:)
      @actor = actor
      @conversation_supervision_session = conversation_supervision_session
      @request_kind = request_kind.to_s
      @request_payload = request_payload.deep_stringify_keys
    end

    def call
      authorization = ConversationControl::AuthorizeRequest.call(
        actor: @actor,
        conversation_supervision_session: @conversation_supervision_session,
        request_kind: @request_kind,
        request_payload: @request_payload
      )

      raise ActiveRecord::RecordInvalid, rejected_record(authorization) unless authorization.allowed?

      request = ConversationControlRequest.create!(
        installation: @conversation_supervision_session.installation,
        conversation_supervision_session: @conversation_supervision_session,
        target_conversation: authorization.conversation,
        request_kind: @request_kind,
        target_kind: authorization.target_kind,
        target_public_id: authorization.target_public_id,
        lifecycle_state: "queued",
        request_payload: persisted_request_payload,
        result_payload: {}
      )

      ConversationControl::DispatchRequest.call(conversation_control_request: request)
    end

    private

    def rejected_record(authorization)
      ConversationControlRequest.new(
        installation: @conversation_supervision_session.installation,
        conversation_supervision_session: @conversation_supervision_session,
        target_conversation: @conversation_supervision_session.target_conversation,
        request_kind: @request_kind,
        target_kind: authorization.target_kind || ConversationControl::ResolveTargetRuntime.target_kind_for(@request_kind),
        target_public_id: authorization.target_public_id,
        lifecycle_state: "queued",
        request_payload: persisted_request_payload,
        result_payload: {}
      ).tap do |request|
        request.errors.add(:base, authorization.rejection_reason)
      end
    end

    def persisted_request_payload
      @persisted_request_payload ||= @request_payload.merge(
        "control_actor" => {
          "kind" => @actor.class.base_class.name,
          "public_id" => @actor.public_id
        }
      )
    end
  end
end
