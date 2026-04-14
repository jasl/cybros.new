module Conversations
  module Metadata
    class RuntimeBootstrapTitle
      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, message:, agent_definition_version: nil, logger: Rails.logger)
        @conversation = conversation
        @message = message
        @agent_definition_version = agent_definition_version
        @logger = logger
      end

      def call
        result = RuntimeFeatures::Invoke.call(
          feature_key: "title_bootstrap",
          workspace: @conversation.workspace,
          agent_definition_version: @agent_definition_version,
          request_payload: request_payload,
          logger: @logger
        )

        return nil unless result.is_a?(Hash) && result.fetch("status", "").to_s == "ok"

        result.dig("result", "title").to_s.squish.presence
      rescue StandardError => error
        @logger.info("conversation runtime title bootstrap fallback: #{error.class}: #{error.message}")
        nil
      end

      private

      def request_payload
        {
          "conversation_id" => @conversation.public_id,
          "message_content" => @message.content.to_s,
        }
      end
    end
  end
end
