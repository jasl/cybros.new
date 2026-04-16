module AppSurface
  module Presenters
    class ConversationPresenter
      def self.call(...)
        new(...).call
      end

      def initialize(conversation:)
        @conversation = conversation
      end

      def call
        {
          "conversation_id" => @conversation.public_id,
          "workspace_id" => @conversation.workspace.public_id,
          "workspace_agent_id" => @conversation.workspace_agent.public_id,
          "agent_id" => @conversation.agent.public_id,
          "current_execution_epoch_id" => @conversation.current_execution_epoch&.public_id,
          "current_execution_runtime_id" => @conversation.current_execution_runtime&.public_id,
          "execution_continuity_state" => @conversation.execution_continuity_state,
          "kind" => @conversation.kind,
          "purpose" => @conversation.purpose,
          "lifecycle_state" => @conversation.lifecycle_state,
          "title" => @conversation.title,
          "summary" => @conversation.summary,
          "management" => Conversations::ManagedPolicy.call(conversation: @conversation),
          "created_at" => @conversation.created_at&.iso8601(6),
          "updated_at" => @conversation.updated_at&.iso8601(6),
        }.compact
      end
    end
  end
end
