# frozen_string_literal: true

require_relative "base"

module SimpleInference
  module Protocols
    class AnthropicMessages < Base
      def create(model:, input:, **options)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?

        response = request_json(
          method: :post,
          url: "#{config.base_url}/v1/messages",
          headers: anthropic_headers,
          body: build_request_body(model: model, input: input, options: options),
          expect_json: true,
          raise_on_http_error: nil
        )

        body = response.body.is_a?(Hash) ? response.body : {}
        content = Array(body["content"])
        output_items = normalize_output_items(content)

        SimpleInference::Responses::Result.new(
          id: body["id"],
          output_text: content.filter_map { |item| item.is_a?(Hash) ? item["text"] : nil }.join,
          output_items: output_items,
          tool_calls: [],
          usage: normalize_usage(body["usage"]),
          finish_reason: body["stop_reason"],
          provider_response: response,
          provider_format: "responses"
        )
      end

      def stream(model:, input:, **options)
        SimpleInference::Responses::Stream.new do |&emit|
          result = create(model: model, input: input, **options)
          emit.call(SimpleInference::Responses::Events::TextDelta.new(delta: result.output_text)) if result.output_text && !result.output_text.empty?
          emit.call(SimpleInference::Responses::Events::Completed.new(result: result, raw: result.provider_response&.body))
          result
        end
      end

      private

      def anthropic_headers
        config.headers
          .reject { |key, _value| key.to_s.casecmp("authorization").zero? }
          .merge(
            "x-api-key" => config.api_key.to_s,
            "anthropic-version" => "2023-06-01"
          )
      end

      def build_request_body(model:, input:, options:)
        system_text, messages = coerce_messages(input, options)

        body = {
          model: model,
          max_tokens: options[:max_output_tokens] || 1024,
          messages: messages,
        }

        body[:system] = system_text if system_text && !system_text.empty?

        tools = normalize_tools(options[:tools] || options["tools"])
        body[:tools] = tools if tools.any?

        body[:temperature] = options[:temperature] if options.key?(:temperature)
        body[:top_p] = options[:top_p] if options.key?(:top_p)
        body[:top_k] = options[:top_k] if options.key?(:top_k)

        body
      end

      def coerce_messages(input, options)
        entries = input.is_a?(Array) ? input : [{ role: "user", content: input }]
        entries = entries.map { |entry| entry.is_a?(Hash) ? stringify_hash(entry) : { "role" => "user", "content" => entry } }

        system_segments = []
        instructions = options[:instructions] || options["instructions"]
        system_segments << instructions.to_s unless instructions.to_s.strip.empty?

        messages = []

        entries.each do |entry|
          if entry["role"].to_s == "system"
            text = stringify_content(entry["content"])
            system_segments << text unless text.empty?
            next
          end

          append_entry(messages, entry)
        end

        system_text = system_segments.join("\n\n").strip
        system_text = nil if system_text.empty?

        [system_text, messages]
      end

      def append_entry(messages, entry)
        if entry["type"].to_s == "function_call"
          append_message(
            messages,
            role: "assistant",
            content: [
              {
                type: "tool_use",
                id: entry["call_id"] || entry["id"],
                name: entry["name"],
                input: parse_arguments(entry["arguments"]),
              }.compact,
            ]
          )
          return
        end

        if entry["type"].to_s == "function_call_output"
          append_message(
            messages,
            role: "user",
            content: [
              {
                type: "tool_result",
                tool_use_id: entry["call_id"],
                content: stringify_content(entry["output"]),
              }.compact,
            ]
          )
          return
        end

        role = normalize_role(entry["role"])
        content = normalize_message_content(entry)
        append_message(messages, role: role, content: content) if role && content.any?
      end

      def normalize_role(role)
        case role.to_s
        when "assistant", "model"
          "assistant"
        when "tool"
          "user"
        when "user", ""
          "user"
        else
          role.to_s
        end
      end

      def normalize_message_content(entry)
        if entry["role"].to_s == "tool"
          return [
            {
              type: "tool_result",
              tool_use_id: entry["tool_call_id"] || entry["call_id"],
              content: stringify_content(entry["content"]),
            }.compact,
          ]
        end

        blocks = normalize_content_blocks(entry["content"])
        blocks.concat(normalize_tool_call_blocks(entry["tool_calls"])) if entry["tool_calls"].is_a?(Array)
        blocks
      end

      def normalize_content_blocks(content)
        case content
        when Array
          content.filter_map { |part| normalize_content_part(part) }
        when nil
          []
        else
          text = content.to_s
          text.empty? ? [] : [{ type: "text", text: text }]
        end
      end

      def normalize_content_part(part)
        return { type: "text", text: part.to_s } unless part.is_a?(Hash)

        normalized = stringify_hash(part)
        type = normalized["type"].to_s

        case type
        when "", "text", "input_text", "output_text"
          text = normalized["text"].to_s
          text.empty? ? nil : { type: "text", text: text }
        else
          raise SimpleInference::ValidationError, "unsupported anthropic content part #{type.inspect}"
        end
      end

      def normalize_tool_call_blocks(tool_calls)
        Array(tool_calls).filter_map do |tool_call|
          next unless tool_call.is_a?(Hash)

          normalized = stringify_hash(tool_call)
          call_id = normalized["id"] || normalized["call_id"]
          function = normalized["function"].is_a?(Hash) ? stringify_hash(normalized["function"]) : normalized

          {
            type: "tool_use",
            id: call_id,
            name: function["name"],
            input: parse_arguments(function["arguments"] || normalized["arguments"]),
          }.compact
        end
      end

      def append_message(messages, role:, content:)
        return if role.to_s.empty? || Array(content).empty?

        if messages.last&.fetch(:role, nil) == role
          messages.last[:content].concat(Array(content))
        else
          messages << {
            role: role,
            content: Array(content),
          }
        end
      end

      def normalize_tools(tools)
        Array(tools).filter_map do |tool|
          next unless tool.is_a?(Hash)

          normalized = stringify_hash(tool)
          next unless normalized["type"].to_s == "function"

          function = normalized["function"].is_a?(Hash) ? stringify_hash(normalized["function"]) : normalized

          {
            name: function["name"],
            description: function["description"],
            input_schema: function["parameters"] || normalized["parameters"],
          }.compact
        end
      end

      def normalize_output_items(content)
        Array(content).filter_map do |item|
          next unless item.is_a?(Hash)

          normalized = stringify_hash(item)

          case normalized["type"].to_s
          when "tool_use"
            {
              "type" => "function_call",
              "id" => normalized["id"],
              "call_id" => normalized["id"],
              "name" => normalized["name"],
              "arguments" => JSON.generate(normalized["input"] || {}),
              "provider_payload" => normalized,
            }.compact
          when "text"
            {
              "type" => "message",
              "content" => [
                {
                  "type" => "output_text",
                  "text" => normalized["text"].to_s,
                },
              ],
            }
          end
        end
      end

      def normalize_usage(usage)
        return nil unless usage.is_a?(Hash)

        stringify_hash(usage)
      end

      def parse_arguments(value)
        return value if value.is_a?(Hash)
        return {} if value.nil? || value == ""

        JSON.parse(value.to_s)
      rescue JSON::ParserError
        {}
      end

      def stringify_content(value)
        case value
        when String
          value
        when Hash, Array
          JSON.generate(value)
        else
          value.to_s
        end
      end

      def stringify_hash(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), out|
          out[key.to_s] = entry
        end
      end
    end
  end
end
