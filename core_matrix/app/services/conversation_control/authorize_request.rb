module ConversationControl
  class AuthorizeRequest
    Result = Struct.new(
      :allowed,
      :rejection_reason,
      :conversation,
      :policy,
      :target_record,
      :target_kind,
      :target_public_id,
      :agent_snapshot,
      keyword_init: true
    ) do
      def allowed?
        allowed == true
      end
    end

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
      return rejected_result("conversation supervision session is not open") unless @conversation_supervision_session.open?

      authority = EmbeddedAgents::ConversationSupervision::Authority.call(
        actor: @actor,
        conversation: conversation
      )
      return rejected_result("control is not enabled for this conversation", policy: authority.policy) unless authority.control_enabled?

      resolved_target = ConversationControl::ResolveTargetRuntime.call(
        conversation: conversation,
        request_kind: @request_kind,
        request_payload: @request_payload
      )

      return allowed_result(authority:, resolved_target:) if authority.allowed?
      return allowed_result(authority:, resolved_target:) if explicit_capability_grant?

      rejected_result(
        "actor is not allowed to control this conversation",
        policy: authority.policy,
        resolved_target:
      )
    end

    private

    def conversation
      @conversation_supervision_session.target_conversation
    end

    def allowed_result(authority:, resolved_target:)
      Result.new(
        allowed: true,
        rejection_reason: nil,
        conversation: conversation,
        policy: authority.policy,
        target_record: resolved_target.target_record,
        target_kind: resolved_target.target_kind,
        target_public_id: resolved_target.target_public_id,
        agent_snapshot: resolved_target.agent_snapshot
      )
    end

    def rejected_result(reason, policy: nil, resolved_target: nil)
      Result.new(
        allowed: false,
        rejection_reason: reason,
        conversation: conversation,
        policy: policy,
        target_record: resolved_target&.target_record,
        target_kind: resolved_target&.target_kind,
        target_public_id: resolved_target&.target_public_id,
        agent_snapshot: resolved_target&.agent_snapshot
      )
    end

    def explicit_capability_grant?
      return false unless @actor.respond_to?(:public_id) && @actor.respond_to?(:installation_id)
      return false unless @actor.installation_id == conversation.installation_id

      ConversationCapabilityGrant.where(
        installation: conversation.installation,
        target_conversation: conversation,
        grantee_kind: @actor.class.base_class.name.underscore,
        grantee_public_id: @actor.public_id,
        grant_state: "active",
        capability: [@request_kind, "conversation_control"]
      ).where("expires_at IS NULL OR expires_at > ?", Time.current).exists?
    end
  end
end
