module EmbeddedFeatures
  module TitleBootstrap
    class Invoke
      def self.call(...)
        new(...).call
      end

      def initialize(request_payload:, logger: Rails.logger)
        @request_payload = request_payload.deep_stringify_keys
        @logger = logger
      end

      def call
        {
          "title" => modeled_title.presence || fallback_title,
        }
      rescue StandardError => error
        @logger.info("embedded title bootstrap fallback: #{error.class}: #{error.message}")
        {
          "title" => fallback_title,
        }
      end

      private

      def modeled_title
        return if conversation_id.blank? || actor.blank?

        result = EmbeddedAgents::Invoke.call(
          agent_key: "conversation_title",
          actor: actor,
          target: { "conversation_id" => conversation_id },
          input: {
            "message_content" => message_content,
          }
        )

        result.output.fetch("title", "").to_s.squish
      end

      def fallback_title
        Conversations::Metadata::BootstrapTitle.title_from_content(message_content)
      end

      def actor
        @request_payload["actor"].presence || conversation&.user
      end

      def conversation
        return if conversation_id.blank?

        @conversation ||= Conversation.find_by(public_id: conversation_id)
      end

      def conversation_id
        @request_payload["conversation_id"]
      end

      def message_content
        @request_payload.fetch("message_content", "").to_s
      end
    end
  end
end
