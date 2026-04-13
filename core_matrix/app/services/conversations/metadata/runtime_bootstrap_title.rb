module Conversations
  module Metadata
    class RuntimeBootstrapTitle
      PROTOCOL_METHOD_ID = "conversation_title_bootstrap".freeze

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
        return nil unless runtime_title_bootstrap_supported?

        nil
      rescue StandardError => error
        @logger.info("conversation runtime title bootstrap fallback: #{error.class}: #{error.message}")
        nil
      end

      private

      def runtime_title_bootstrap_supported?
        Array(@agent_definition_version&.protocol_methods).any? do |entry|
          entry.is_a?(Hash) && entry["method_id"].to_s == PROTOCOL_METHOD_ID
        end
      end
    end
  end
end
