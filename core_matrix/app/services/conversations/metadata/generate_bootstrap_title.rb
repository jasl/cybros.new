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
        return nil unless policy.fetch("enabled")

        runtime_title = runtime_title_candidate(policy)
        return runtime_title if runtime_title.present?

        result = EmbeddedAgents::Invoke.call(
          agent_key: "conversation_title",
          actor: @actor,
          target: { "conversation_id" => @conversation.public_id },
          input: {
            "message_content" => @message.content.to_s,
          }
        )

        title = result.output.fetch("title", "").to_s.squish
        return title if title.present?

        fallback_title
      rescue StandardError => error
        @logger.info("conversation title bootstrap fallback: #{error.class}: #{error.message}")
        fallback_title
      end

      private

      def runtime_title_candidate(policy)
        return nil unless policy.fetch("mode") == "runtime_first"

        Conversations::Metadata::RuntimeBootstrapTitle.call(
          conversation: @conversation,
          message: @message,
          agent_definition_version: @agent_definition_version
        )
      rescue StandardError => error
        @logger.info("conversation title runtime fallback: #{error.class}: #{error.message}")
        nil
      end

      def fallback_title
        Conversations::Metadata::BootstrapTitle.title_from_content(@message.content.to_s)
      end
    end
  end
end
