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
          "agent_id" => @conversation.agent.public_id,
          "kind" => @conversation.kind,
          "purpose" => @conversation.purpose,
          "lifecycle_state" => @conversation.lifecycle_state,
          "title" => @conversation.title,
          "summary" => @conversation.summary,
          "created_at" => @conversation.created_at&.iso8601(6),
          "updated_at" => @conversation.updated_at&.iso8601(6),
        }.compact
      end
    end
  end
end
