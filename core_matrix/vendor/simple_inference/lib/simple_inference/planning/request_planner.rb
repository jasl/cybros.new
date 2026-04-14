# frozen_string_literal: true

module SimpleInference
  module Planning
    class RequestPlanner
      CONVERSATION_STATE_KEYS = %i[previous_response_id conversation conversation_id].freeze

      def initialize(client:, provider_profile:, model_profile:)
        @client = client
        @provider_profile = provider_profile
        @model_profile = model_profile
      end

      def responses_protocol
        case protocol_family
        when :gemini
          Protocols::GeminiGenerateContent.new(@client.protocol_options)
        when :anthropic
          Protocols::AnthropicMessages.new(@client.protocol_options)
        when :responses
          Protocols::OpenAIResponses.new(
            @client.protocol_options(responses_path: @provider_profile.responses_path)
          )
        when :openrouter_chat_completions
          Protocols::OpenRouterResponses.new(@client.protocol_options(responses_path: @provider_profile.responses_path))
        else
          Protocols::OpenAICompatibleResponses.new(@client.protocol_options)
        end
      end

      def responses_strategy
        case protocol_family
        when :responses, :gemini, :anthropic
          :responses
        when :openrouter_chat_completions
          :openrouter_chat_completions
        else
          :chat_completions
        end
      end

      def prepare_responses_request(input:, options:, streaming: false)
        ensure_streaming! if streaming

        normalized_options = normalize_options(options)

        validate_tool_request!(normalized_options)
        validate_conversation_state_request!(normalized_options)
        validate_multimodal_request!(input, normalized_options)

        [input, normalized_options]
      end

      def prepare_images_request(options:)
        ensure_image_generation!
        normalized_options = normalize_options(options)

        return normalized_options unless option_explicitly_false?(normalized_options, :allow_image_generation)

        raise SimpleInference::CapabilityError, "images.generate is disabled for this request"
      end

      def images_protocol
        ensure_image_generation!

        if @provider_profile.adapter_key.include?("openrouter")
          Protocols::OpenRouterImages.new(@client.protocol_options(responses_path: @provider_profile.responses_path))
        else
          Protocols::OpenAIImages.new(@client.protocol_options)
        end
      end

      def ensure_image_generation!
        return if @model_profile.image_generation?

        raise SimpleInference::CapabilityError, "images.generate is not enabled for this model profile"
      end

      def ensure_streaming!
        return if @model_profile.streaming?

        raise SimpleInference::CapabilityError, "responses.stream is not enabled for this model profile"
      end

      private

      def protocol_family
        adapter_key = @provider_profile.adapter_key

        return :gemini if adapter_key.include?("gemini")
        return :anthropic if adapter_key.include?("anthropic")
        return :responses if @provider_profile.wire_api == "responses"
        return :openrouter_chat_completions if adapter_key.include?("openrouter")

        :chat_completions
      end

      def normalize_options(options)
        return {} unless options.is_a?(Hash)

        options.each_with_object({}) do |(key, value), out|
          out[key.to_sym] = value
        end
      end

      def validate_tool_request!(options)
        tools = Array(options[:tools]).filter_map { |entry| entry if entry.is_a?(Hash) }
        return if tools.empty?

        function_tools, builtin_tools = tools.partition { |entry| tool_type(entry) == "function" }

        if function_tools.any? && !@model_profile.tool_calls?
          raise SimpleInference::CapabilityError, "function tools are not enabled for this model profile"
        end

        return if builtin_tools.empty?
        raise SimpleInference::CapabilityError, "builtin tools are disabled for this request" if option_explicitly_false?(options, :allow_builtin_tools)
        raise SimpleInference::CapabilityError, "builtin tools are not enabled for this model profile" unless @model_profile.provider_builtin_tools?
      end

      def validate_conversation_state_request!(options)
        stateful_keys = CONVERSATION_STATE_KEYS.select { |key| present_option?(options, key) }
        return if stateful_keys.empty?

        if option_explicitly_false?(options, :prefer_stateful_responses)
          raise SimpleInference::CapabilityError, "conversation state is disabled for this request"
        end

        return if @model_profile.conversation_state?

        raise SimpleInference::CapabilityError, "conversation state is not enabled for this model profile"
      end

      def validate_multimodal_request!(input, options)
        part_kinds = extract_part_kinds(input)
        return if part_kinds.empty?

        if option_explicitly_false?(options, :allow_multimodal_inputs)
          raise SimpleInference::CapabilityError, "multimodal inputs are disabled for this request"
        end

        part_kinds.each do |kind|
          if option_explicitly_false?(options, :"allow_#{kind}_input")
            raise SimpleInference::CapabilityError, "#{kind} inputs are disabled for this request"
          end

          next if @model_profile.multimodal_input_enabled?(kind)

          raise SimpleInference::CapabilityError, "#{kind} inputs are not enabled for this model profile"
        end
      end

      def extract_part_kinds(input)
        case input
        when Array
          input.flat_map { |entry| extract_part_kinds(entry) }.uniq
        when Hash
          extract_part_kinds_from_hash(input)
        else
          []
        end
      end

      def extract_part_kinds_from_hash(entry)
        if entry.key?(:content) || entry.key?("content")
          return extract_part_kinds(entry[:content] || entry["content"])
        end

        type = (entry[:type] || entry["type"]).to_s
        return [type_to_part_kind(type)].compact if value_present?(type)

        keys_to_part_kinds(entry)
      end

      def keys_to_part_kinds(entry)
        normalized_entry = stringify_hash(entry)

        if value_present?(normalized_entry["image_url"])
          ["image"]
        elsif value_present?(normalized_entry["file_id"]) || value_present?(normalized_entry["file_data"])
          ["file"]
        elsif value_present?(normalized_entry["input_audio"])
          ["audio"]
        elsif value_present?(normalized_entry["input_video"])
          ["video"]
        elsif normalized_entry["inline_data"].is_a?(Hash)
          kind = inline_data_kind(normalized_entry["inline_data"])
          kind ? [kind] : []
        else
          []
        end
      end

      def inline_data_kind(inline_data)
        mime_type = inline_data["mime_type"].to_s
        return "image" if mime_type.start_with?("image/")
        return "audio" if mime_type.start_with?("audio/")
        return "video" if mime_type.start_with?("video/")
        return "file" if mime_type.present?

        nil
      end

      def type_to_part_kind(type)
        case type
        when "input_image", "image", "image_url"
          "image"
        when "input_audio", "audio"
          "audio"
        when "input_video", "video"
          "video"
        when "input_file", "file"
          "file"
        else
          nil
        end
      end

      def tool_type(tool)
        (tool[:type] || tool["type"]).to_s
      end

      def option_explicitly_false?(options, key)
        return false unless options.key?(key)

        options[key] == false
      end

      def present_option?(options, key)
        value = options[key]
        value_present?(value)
      end

      def stringify_hash(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), out|
          out[key.to_s] = entry
        end
      end

      def value_present?(value)
        !(value.nil? || (value.respond_to?(:empty?) && value.empty?))
      end
    end
  end
end
