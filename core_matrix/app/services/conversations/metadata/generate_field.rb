module Conversations
  module Metadata
    class GenerateField
      FIELD_CONFIG = {
        "title" => {
          selector: "role:conversation_title",
          purpose: "conversation_title",
          max_output_tokens: 80,
          source: "generated",
          transcript_window: :leading,
          transcript_message_limit: 6,
          transcript_message_char_limit: 280,
        },
        "summary" => {
          selector: "role:conversation_summary",
          purpose: "conversation_summary",
          max_output_tokens: 160,
          source: "generated",
          transcript_window: :trailing,
          transcript_message_limit: 10,
          transcript_message_char_limit: 400,
        },
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, field:, occurred_at: Time.current, adapter: nil, catalog: nil, governor: ProviderExecution::ProviderRequestGovernor, lease_renew_interval_seconds: nil, request_overrides: {}, persist: true)
        @conversation = conversation
        @field = field.to_s
        @occurred_at = occurred_at
        @adapter = adapter
        @catalog = catalog
        @governor = governor
        @lease_renew_interval_seconds = lease_renew_interval_seconds
        @request_overrides = request_overrides || {}
        @persist = persist
      end

      def call
        config = field_config!
        generated_content = generate_content(config)
        return generated_content unless @persist

        @conversation.update!(field_attributes(config.fetch(:source), generated_content))
        @conversation
      rescue ProviderGateway::DispatchText::UnavailableSelector, ActiveRecord::RecordNotFound
        raise_invalid!(@field, "generation is unavailable")
      rescue ProviderExecution::ProviderRequestGovernor::AdmissionRefused, ProviderGateway::DispatchText::RequestFailed
        raise_invalid!(@field, "generation is temporarily unavailable")
      end

      private

      def field_config!
        FIELD_CONFIG.fetch(@field) do
          raise ArgumentError, "unsupported metadata field #{@field.inspect}"
        end
      end

      def generate_content(config)
        response = ProviderGateway::DispatchText.call(
          installation: @conversation.installation,
          selector: config.fetch(:selector),
          messages: prompt_messages(config),
          max_output_tokens: config.fetch(:max_output_tokens),
          request_overrides: @request_overrides,
          purpose: config.fetch(:purpose),
          adapter: @adapter,
          catalog: @catalog,
          governor: @governor,
          lease_renew_interval_seconds: @lease_renew_interval_seconds
        )

        generated_content = response.content.to_s.strip
        raise_invalid!(@field, "generation returned blank content") if generated_content.blank?

        generated_content
      end

      def field_attributes(source, content)
        case @field
        when "title"
          {
            title: content,
            title_source: source,
            title_updated_at: @occurred_at,
          }
        when "summary"
          {
            summary: content,
            summary_source: source,
            summary_updated_at: @occurred_at,
          }
        else
          raise ArgumentError, "unsupported metadata field #{@field.inspect}"
        end
      end

      def prompt_messages(config)
        [
          {
            "role" => "system",
            "content" => system_prompt,
          },
          {
            "role" => "user",
            "content" => JSON.generate(prompt_payload(config)),
          },
        ]
      end

      def system_prompt
        case @field
        when "title"
          "You write concise, user-facing conversation titles. Keep the title short and specific."
        when "summary"
          "You write concise, user-facing conversation summaries. Keep the summary short, factual, and current."
        else
          raise ArgumentError, "unsupported metadata field #{@field.inspect}"
        end
      end

      def prompt_payload(config)
        {
          "field" => @field,
          "conversation" => {
            "title" => @conversation.title,
            "summary" => @conversation.summary,
            "transcript" => transcript_messages(config),
          },
        }
      end

      def transcript_messages(config)
        messages = Conversations::ContextProjection.call(conversation: @conversation).messages
        projected_messages = case config.fetch(:transcript_window)
        when :trailing
          messages.last(config.fetch(:transcript_message_limit))
        else
          messages.first(config.fetch(:transcript_message_limit))
        end

        projected_messages.map do |message|
          {
            "role" => message.role,
            "content" => message.content.to_s.squish.truncate(config.fetch(:transcript_message_char_limit)),
          }
        end
      end

      def raise_invalid!(attribute, message)
        @conversation.errors.add(attribute, message)
        raise ActiveRecord::RecordInvalid, @conversation
      end
    end
  end
end
