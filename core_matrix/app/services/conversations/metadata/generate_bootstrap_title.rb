module Conversations
  module Metadata
    class GenerateBootstrapTitle
      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, message:, agent_definition_version: nil, actor: nil, logger: Rails.logger)
        @conversation = conversation
        @message = message
        @agent_definition_version = agent_definition_version
        @actor = actor || conversation.user
        @logger = logger
      end

      def call
        policy = TitleBootstrapPolicy.call(
          workspace: @conversation.workspace,
          agent_definition_version: @agent_definition_version
        )

        title = runtime_title_candidate(policy)
        return title if title.present?

        return nil if strict_runtime_policy?(policy)

        embedded_title = embedded_title_candidate
        return embedded_title if embedded_title.present?

        fallback_title
      rescue StandardError => error
        @logger.info("conversation title bootstrap fallback: #{error.class}: #{error.message}")
        return nil if strict_runtime_policy?(policy)

        embedded_title = embedded_title_candidate
        return embedded_title if embedded_title.present?

        fallback_title
      end

      private

      def runtime_title_candidate(policy)
        return nil if policy.fetch("strategy") == "disabled"

        Conversations::Metadata::RuntimeBootstrapTitle.call(
          conversation: @conversation,
          message: @message,
          agent_definition_version: @agent_definition_version
        )
      end

      def strict_runtime_policy?(policy)
        return false unless policy.is_a?(Hash)

        %w[disabled runtime_required].include?(policy.fetch("strategy", ""))
      end

      def embedded_title_candidate
        embedded_title = EmbeddedFeatures::TitleBootstrap::Invoke.call(
          request_payload: {
            "conversation_id" => @conversation.public_id,
            "message_content" => @message.content.to_s,
            "actor" => @actor,
          }
        )

        embedded_title.fetch("title", "").to_s.squish.presence
      end

      def fallback_title
        Conversations::Metadata::BootstrapTitle.title_from_content(@message.content.to_s)
      end
    end
  end
end
