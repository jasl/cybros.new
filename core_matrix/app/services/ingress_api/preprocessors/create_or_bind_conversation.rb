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

        if session.binding_state == "unbound"
          conversation = Conversations::CreateRoot.call(
            workspace_agent: @context.ingress_binding.workspace_agent,
            execution_runtime: resolved_execution_runtime
          )
          session.update!(conversation: conversation, binding_state: "active")
          @context.conversation = conversation
        else
          @context.conversation = session.conversation
        end

        @context.active_turn = @context.conversation.latest_active_turn
        @context
      end

      private

      def resolved_execution_runtime
        @context.ingress_binding.default_execution_runtime ||
          @context.ingress_binding.workspace_agent.default_execution_runtime ||
          @context.ingress_binding.workspace_agent.agent.default_execution_runtime
      end
    end
  end
end
