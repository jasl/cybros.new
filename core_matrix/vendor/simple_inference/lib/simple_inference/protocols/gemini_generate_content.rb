# frozen_string_literal: true

require_relative "base"

module SimpleInference
  module Protocols
    class GeminiGenerateContent < Base
      def create(model:, input:, **options)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?

        response = request_json(
          method: :post,
          url: generate_content_url(model),
          headers: gemini_headers,
          body: build_request_body(input: input, options: options),
          expect_json: true,
          raise_on_http_error: nil
        )

        body = response.body.is_a?(Hash) ? response.body : {}
        candidate = Array(body["candidates"]).first || {}
        parts = candidate.dig("content", "parts")
        output_items = normalize_output_items(parts)

        SimpleInference::Responses::Result.new(
          id: body["responseId"] || body["id"],
          output_text: extract_text(parts),
          output_items: output_items,
          tool_calls: [],
          usage: normalize_usage(body["usageMetadata"]),
          finish_reason: candidate["finishReason"],
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

      def generate_content_url(model)
        "#{config.base_url}/v1beta/models/#{model}:generateContent"
      end

      def gemini_headers
        config.headers
          .reject { |key, _value| key.to_s.casecmp("authorization").zero? }
          .merge("x-goog-api-key" => config.api_key.to_s)
      end

      def build_request_body(input:, options:)
        system_instruction, contents = coerce_contents(input, options)

        body = {
          contents: contents,
        }

        if system_instruction && !system_instruction.empty?
          body[:systemInstruction] = {
            parts: [
              { text: system_instruction },
            ],
          }
        end

        tools = normalize_tools(options[:tools] || options["tools"])
        body[:tools] = tools if tools.any?

        generation_config = {}
        generation_config[:maxOutputTokens] = options[:max_output_tokens] if options.key?(:max_output_tokens)
        generation_config[:temperature] = options[:temperature] if options.key?(:temperature)
        generation_config[:topP] = options[:top_p] if options.key?(:top_p)
        generation_config[:topK] = options[:top_k] if options.key?(:top_k)
        body[:generationConfig] = generation_config unless generation_config.empty?

        body
      end

      def coerce_contents(input, options)
        entries = input.is_a?(Array) ? input : [{ role: "user", content: input }]
        entries = entries.map { |entry| entry.is_a?(Hash) ? stringify_hash(entry) : { "role" => "user", "content" => entry } }

        system_segments = []
        instructions = options[:instructions] || options["instructions"]
        system_segments << instructions.to_s unless instructions.to_s.strip.empty?

        contents = []
        function_names = {}

        entries.each do |entry|
          if entry["role"].to_s == "system"
            text = stringify_content(entry["content"])
            system_segments << text unless text.empty?
            next
          end

          append_entry(contents, entry, function_names)
        end

        system_instruction = system_segments.join("\n\n").strip
        system_instruction = nil if system_instruction.empty?

        [system_instruction, contents]
      end

      def append_entry(contents, entry, function_names)
        if entry["type"].to_s == "function_call"
          call_id = entry["call_id"] || entry["id"]
          arguments = parse_arguments(entry["arguments"])
          function_names[call_id] = entry["name"] if call_id && entry["name"]

          append_content(
            contents,
            role: "model",
            parts: [
              function_call_part(
                name: entry["name"],
                arguments: arguments,
                call_id: call_id,
                provider_payload: entry["provider_payload"]
              ),
            ]
          )
          return
        end

        if entry["type"].to_s == "function_call_output"
          call_id = entry["call_id"]
          tool_name = entry["name"] || function_names[call_id]
          raise SimpleInference::ValidationError, "function_call_output is missing a tool name for #{call_id}" if tool_name.to_s.empty?

          append_content(
            contents,
            role: "user",
            parts: [
              {
                functionResponse: {
                  name: tool_name,
                  response: normalize_function_response(entry["output"]),
                  id: call_id,
                },
              },
            ]
          )
          return
        end

        role = normalize_role(entry["role"])
        parts = normalize_message_parts(entry, function_names)
        append_content(contents, role: role, parts: parts) if role && parts.any?
      end

      def normalize_role(role)
        case role.to_s
        when "assistant", "model"
          "model"
        when "tool"
          "user"
        else
          "user"
        end
      end

      def normalize_message_parts(entry, function_names)
        if entry["role"].to_s == "tool"
          call_id = entry["tool_call_id"] || entry["call_id"]
          tool_name = entry["name"] || function_names[call_id]
          raise SimpleInference::ValidationError, "tool result message is missing a tool name for #{call_id}" if tool_name.to_s.empty?

          return [
            {
              functionResponse: {
                name: tool_name,
                response: normalize_function_response(entry["content"]),
                id: call_id,
              },
            },
          ]
        end

        parts = normalize_content_parts(entry["content"])
        parts.concat(normalize_tool_call_parts(entry["tool_calls"], function_names)) if entry["tool_calls"].is_a?(Array)
        parts
      end

      def normalize_content_parts(content)
        case content
        when Array
          content.filter_map { |part| normalize_content_part(part) }
        when nil
          []
        else
          text = content.to_s
          text.empty? ? [] : [{ text: text }]
        end
      end

      def normalize_content_part(part)
        return { text: part.to_s } unless part.is_a?(Hash)

        normalized = stringify_hash(part)
        type = normalized["type"].to_s

        case type
        when "", "text", "input_text", "output_text"
          text = normalized["text"].to_s
          text.empty? ? nil : { text: text }
        else
          raise SimpleInference::ValidationError, "unsupported gemini content part #{type.inspect}"
        end
      end

      def normalize_tool_call_parts(tool_calls, function_names)
        Array(tool_calls).filter_map do |tool_call|
          next unless tool_call.is_a?(Hash)

          normalized = stringify_hash(tool_call)
          call_id = normalized["id"] || normalized["call_id"]
          function = normalized["function"].is_a?(Hash) ? stringify_hash(normalized["function"]) : normalized
          function_names[call_id] = function["name"] if call_id && function["name"]

          function_call_part(
            name: function["name"],
            arguments: parse_arguments(function["arguments"] || normalized["arguments"]),
            call_id: call_id,
            provider_payload: normalized["provider_payload"]
          )
        end
      end

      def function_call_part(name:, arguments:, call_id:, provider_payload: nil)
        if provider_payload.is_a?(Hash)
          normalized_payload = stringify_hash(provider_payload)
          function_call = normalized_payload["functionCall"]
          if function_call.is_a?(Hash)
            normalized_call = stringify_hash(function_call)
            normalized_call["id"] ||= call_id if call_id
            part = { functionCall: normalized_call }
            thought_signature = normalized_payload["thoughtSignature"] || normalized_payload["thought_signature"]
            part[:thoughtSignature] = thought_signature if thought_signature
            return part
          end
        end

        {
          functionCall: {
            name: name,
            args: arguments || {},
            id: call_id,
          }.compact,
        }
      end

      def append_content(contents, role:, parts:)
        return if role.to_s.empty? || Array(parts).empty?

        if contents.last&.fetch(:role, nil) == role
          contents.last[:parts].concat(Array(parts))
        else
          contents << {
            role: role,
            parts: Array(parts),
          }
        end
      end

      def normalize_tools(tools)
        declarations = Array(tools).filter_map do |tool|
          next unless tool.is_a?(Hash)

          normalized = stringify_hash(tool)
          next unless normalized["type"].to_s == "function"

          function = normalized["function"].is_a?(Hash) ? stringify_hash(normalized["function"]) : normalized

          {
            name: function["name"],
            description: function["description"],
            parameters: function["parameters"] || normalized["parameters"],
          }.compact
        end

        return [] if declarations.empty?

        [{ functionDeclarations: declarations }]
      end

      def normalize_output_items(parts)
        Array(parts).filter_map do |part|
          next unless part.is_a?(Hash)

          normalized = stringify_hash(part)
          function_call = normalized["functionCall"]

          if function_call.is_a?(Hash)
            normalized_call = stringify_hash(function_call)
            provider_payload = { "functionCall" => normalized_call }
            thought_signature = normalized["thoughtSignature"] || normalized["thought_signature"]
            provider_payload["thoughtSignature"] = thought_signature if thought_signature

            {
              "type" => "function_call",
              "id" => normalized_call["id"],
              "call_id" => normalized_call["id"],
              "name" => normalized_call["name"],
              "arguments" => JSON.generate(normalized_call["args"] || {}),
              "provider_payload" => provider_payload,
            }.compact
          elsif normalized["text"]
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

      def extract_text(parts)
        Array(parts).filter_map { |part| part.is_a?(Hash) ? part["text"] : nil }.join
      end

      def normalize_usage(usage_metadata)
        return nil unless usage_metadata.is_a?(Hash)

        {
          "input_tokens" => usage_metadata["promptTokenCount"],
          "output_tokens" => usage_metadata["candidatesTokenCount"],
          "total_tokens" => usage_metadata["totalTokenCount"],
        }.compact
      end

      def normalize_function_response(value)
        return value if value.is_a?(Hash)

        parsed = parse_json(value)
        parsed.is_a?(Hash) ? parsed : { "result" => value.to_s }
      rescue SimpleInference::DecodeError
        { "result" => value.to_s }
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
