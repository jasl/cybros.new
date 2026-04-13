module EmbeddedAgents
  module ConversationTitle
    class Invoke
      SELECTOR = "role:conversation_title"
      PURPOSE = "conversation_title"
      MAX_OUTPUT_TOKENS = 80
      SYSTEM_PROMPT = <<~TEXT.freeze
        You write concise, user-facing conversation titles.
        Use the same language as the user input.
        Output only the title, with no quotes or explanation.
        Focus on the user's concrete task or question.
        Keep it specific, single-line, and at most 80 characters.
      TEXT

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, target:, input:, options: {}, agent_key: "conversation_title", adapter: nil, catalog: nil, logger: Rails.logger)
        @actor = actor
        @target = target.is_a?(Hash) ? target.deep_stringify_keys : {}
        @input = input.is_a?(Hash) ? input.deep_stringify_keys : {}
        @options = options.is_a?(Hash) ? options.deep_stringify_keys : {}
        @agent_key = agent_key
        @adapter = adapter
        @catalog = catalog
        @logger = logger
      end

      def call
        modeled_title = render_modeled_title
        title = modeled_title || heuristic_title
        source = modeled_title.present? ? "modeled" : "heuristic"
        responder_kind = modeled_title.present? ? "model" : "heuristic"

        EmbeddedAgents::Result.new(
          agent_key: @agent_key,
          status: "ok",
          output: {
            "conversation_id" => conversation.public_id,
            "title" => title,
          },
          metadata: {
            "source" => source,
          },
          responder_kind: responder_kind
        )
      end

      private

      def conversation
        @conversation ||= Conversation.find_by!(public_id: conversation_id_from_target)
      end

      def conversation_id_from_target
        conversation_id = @target.fetch("conversation_id")

        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "target must use public ids" if conversation_id.is_a?(Integer)
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" unless conversation_id.is_a?(String)

        conversation_id
      end

      def render_modeled_title
        result = ProviderGateway::DispatchText.call(
          installation: conversation.installation,
          selector: SELECTOR,
          messages: prompt_messages,
          max_output_tokens: MAX_OUTPUT_TOKENS,
          purpose: PURPOSE,
          request_overrides: {},
          adapter: @adapter,
          catalog: @catalog
        )

        normalize_modeled_title(result.content)
      rescue StandardError => error
        @logger.info("conversation title embedded fallback: #{error.class}: #{error.message}")
        nil
      end

      def prompt_messages
        [
          {
            "role" => "system",
            "content" => SYSTEM_PROMPT,
          },
          {
            "role" => "user",
            "content" => JSON.generate(prompt_payload),
          },
        ]
      end

      def prompt_payload
        {
          "message_content" => message_content,
          "request_summary" => heuristic_title,
        }
      end

      def normalize_modeled_title(content)
        normalized = content.to_s.tr("\r", "").lines.first.to_s.squish
        normalized = normalized.gsub(/\A["“”'`]+|["“”'`]+\z/, "").squish
        normalized = normalized.tr("\n", " ").squish.truncate(Conversations::Metadata::BootstrapTitle::MAX_TITLE_LENGTH)

        return nil if normalized.blank?
        return nil if Conversations::Metadata::InternalContentGuard.internal_metadata_content?(normalized)

        normalized
      end

      def heuristic_title
        @heuristic_title ||= Conversations::Metadata::BootstrapTitle.title_from_content(message_content)
      end

      def message_content
        @input.fetch("message_content", "").to_s
      end
    end
  end
end
