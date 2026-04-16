module IngressAPI
  module Preprocessors
    class CreateOrBindConversation
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("create_or_bind_conversation")
        session = @context.channel_session
        return @context if session.blank?
        update_session_identity_metadata!(session)

        if session.binding_state == "unbound" || rotate_bound_conversation?(session)
          conversation = Conversations::CreateManagedChannelConversation.call(
            workspace_agent: @context.ingress_binding.workspace_agent,
            execution_runtime: resolved_execution_runtime,
            platform: session.platform,
            peer_kind: session.peer_kind,
            peer_id: session.peer_id,
            session_metadata: session.session_metadata
          )
          session.update!(conversation: conversation, binding_state: "active")
        end

        @context.conversation = session.conversation

        @context.active_turn = @context.conversation.latest_active_turn
        @context
      end

      private

      def resolved_execution_runtime
        @context.ingress_binding.default_execution_runtime ||
          @context.ingress_binding.workspace_agent.default_execution_runtime ||
          @context.ingress_binding.workspace_agent.agent.default_execution_runtime
      end

      def rotate_bound_conversation?(session)
        return false if session.binding_state == "unbound"

        session.conversation.archived? || session.conversation.deleted?
      end

      def update_session_identity_metadata!(session)
        metadata = session.session_metadata.deep_stringify_keys
        sender_snapshot = (@context.envelope&.sender_snapshot || {}).deep_stringify_keys
        username = sender_snapshot["username"].to_s
        metadata["sender_username"] = username if username.present?
        label = [
          sender_snapshot["first_name"],
          sender_snapshot["last_name"],
        ].compact.join(" ").presence || sender_snapshot["label"].presence
        metadata["sender_label"] = label if label.present?

        return if metadata == session.session_metadata.deep_stringify_keys

        session.update!(session_metadata: metadata)
      end
    end
  end
end
