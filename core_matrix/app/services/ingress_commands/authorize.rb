module IngressCommands
  class Authorize
    Authorization = Struct.new(:allowed, :rejection_reason, keyword_init: true) do
      def allowed? = allowed
    end

    def self.call(...)
      new(...).call
    end

    def initialize(command:, context:, sender_external_id:)
      @command = command
      @context = context
      @sender_external_id = sender_external_id
    end

    def call
      case @command.name
      when "stop"
        authorize_stop
      when "report", "btw"
        authorize_sidecar_query
      when "regenerate"
        authorize_regenerate
      else
        Authorization.new(allowed: false, rejection_reason: "unsupported_command")
      end
    end

    private

    def authorize_stop
      return Authorization.new(allowed: false, rejection_reason: "control_not_allowed") unless @context.conversation&.allows_entry_surface?("control")

      active_turn = @context.active_turn || @context.conversation&.latest_active_turn
      return Authorization.new(allowed: false, rejection_reason: "no_active_turn") if active_turn.blank?

      active_sender_id = active_turn.origin_payload["external_sender_id"].presence
      return Authorization.new(allowed: false, rejection_reason: "missing_sender_provenance") if active_sender_id.blank?
      return Authorization.new(allowed: false, rejection_reason: "sender_mismatch") if active_sender_id != @sender_external_id

      Authorization.new(allowed: true, rejection_reason: nil)
    end

    def authorize_sidecar_query
      return Authorization.new(allowed: false, rejection_reason: "sidecar_query_not_allowed") unless @context.conversation&.allows_entry_surface?("sidecar_query")
      return Authorization.new(allowed: false, rejection_reason: "missing_question") if @command.name == "btw" && @command.arguments.blank?
      return Authorization.new(allowed: false, rejection_reason: "sidecar_query_not_allowed") unless sidecar_access_allowed?

      Authorization.new(allowed: true, rejection_reason: nil)
    end

    def authorize_regenerate
      return Authorization.new(allowed: false, rejection_reason: "conversation_not_mutable") unless @context.conversation&.interaction_lock_mutable?

      available = WorkspacePolicies::Capabilities.effective_for(
        workspace: @context.conversation.workspace,
        workspace_agent: @context.conversation.workspace_agent
      )
      return Authorization.new(allowed: false, rejection_reason: "capability_disabled") unless available.include?("regenerate")

      Authorization.new(allowed: true, rejection_reason: nil)
    end

    def sidecar_access_allowed?
      conversation = @context.conversation
      actor = conversation&.user
      return false if conversation.blank? || actor.blank?

      access = AppSurface::Policies::ConversationSupervisionAccess.call(
        user: actor,
        conversation: conversation
      )

      access.side_chat_enabled? && access.read?
    end
  end
end
