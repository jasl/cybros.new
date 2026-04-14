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
          tool_calls: SimpleInference::Responses::Result.tool_calls_from_output_items(output_items),
          usage: normalize_usage(body["usageMetadata"]),
          finish_reason: candidate["finishReason"],
          provider_response: response,
          provider_format: "responses"
        )
      end

      def stream(model:, input:, **options)
        SimpleInference::Responses::Stream.new do |&emit|
          streamed_tool_calls = {}
          emitted_tool_call_done = {}

          result =
            stream_result(model: model, input: input, **options) do |event, state|
              emit.call(SimpleInference::Responses::Events::Raw.new(type: "gemini.generate_content.chunk", raw: event, snapshot: state[:output_items]))

              unless state[:delta].to_s.empty?
                emit.call(
                  SimpleInference::Responses::Events::TextDelta.new(
                    delta: state[:delta],
                    raw: event,
                    snapshot: state[:output_text]
                  )
                )
              end

              emit_stream_tool_call_events!(
                emit: emit,
                output_items: state[:output_items],
                streamed_tool_calls: streamed_tool_calls,
                emitted_done: emitted_tool_call_done,
                done: false,
                raw: event
              )
            end

          emit_stream_tool_call_events!(
            emit: emit,
            output_items: result.output_items,
            streamed_tool_calls: streamed_tool_calls,
            emitted_done: emitted_tool_call_done,
            done: true,
            raw: result.provider_response&.body
          )
          emit.call(SimpleInference::Responses::Events::Completed.new(result: result, raw: result.provider_response&.body))
          result
        end
      end

      private

      def stream_result(model:, input:, **options)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?

        full = +""
        output_items = []
        last_body = nil

        response =
          stream_generate_content(model: model, input: input, **options) do |event|
            body = event.is_a?(Hash) ? event : {}
            last_body = body if body.is_a?(Hash)

            parts = Array(body.dig("candidates", 0, "content", "parts"))
            snapshot_text = extract_text(parts)
            delta = incremental_delta(snapshot_text, full)
            full << delta unless delta.empty?

            output_items = merge_output_items(output_items, normalize_output_items(parts))

            yield(event, { delta: delta, output_text: full.dup, output_items: duplicate_items(output_items) }) if block_given?
          end

        response_body =
          if response.body.is_a?(Hash)
            response.body
          else
            last_body || {}
          end

        if response.body.nil? && response_body.is_a?(Hash) && !response_body.empty?
          response = SimpleInference::Response.new(status: response.status, headers: response.headers, body: response_body, raw_body: response.raw_body)
        end

        parts = Array(response_body.dig("candidates", 0, "content", "parts"))
        output_items = merge_output_items(output_items, normalize_output_items(parts))
        full = extract_text(parts) if full.empty?

        candidate = Array(response_body["candidates"]).first || {}

        SimpleInference::Responses::Result.new(
          id: response_body["responseId"] || response_body["id"],
          output_text: full,
          output_items: output_items,
          tool_calls: SimpleInference::Responses::Result.tool_calls_from_output_items(output_items),
          usage: normalize_usage(response_body["usageMetadata"]),
          finish_reason: candidate["finishReason"],
          provider_response: response,
          provider_format: "responses"
        )
      end

      def generate_content_url(model)
        "#{config.base_url}/v1beta/models/#{model}:generateContent"
      end

      def stream_generate_content_url(model)
        "#{config.base_url}/v1beta/models/#{model}:streamGenerateContent?alt=sse"
      end

      def stream_generate_content(model:, input:, **options)
        return enum_for(:stream_generate_content, model: model, input: input, **options) unless block_given?

        request_env = {
          method: :post,
          url: stream_generate_content_url(model),
          headers: gemini_headers.merge(
            "Content-Type" => "application/json",
            "Accept" => "text/event-stream, application/json"
          ),
          body: serialize_json_body(build_request_body(input: input, options: options)),
          timeout: config.timeout,
          open_timeout: config.open_timeout,
          read_timeout: config.read_timeout,
        }

        handle_stream_response(request_env) do |_event_name, event|
          yield event
        end
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

      def handle_stream_response(request_env, &on_event)
        validate_url!(request_env[:url])

        sse_buffer = +""
        streamed = false

        raw_response =
          @adapter.call_stream(request_env) do |chunk|
            streamed = true
            sse_buffer << chunk.to_s
            consume_sse_buffer!(sse_buffer, &on_event)
          end

        status = raw_response[:status].to_i
        headers = (raw_response[:headers] || {}).transform_keys { |key| key.to_s.downcase }
        body = raw_response[:body]
        body_str = body.nil? ? "" : body.to_s
        content_type = headers["content-type"].to_s

        if status >= 200 && status < 300 && (content_type.include?("text/event-stream") || sse_like_body?(body_str))
          consume_sse_buffer!(body_str.dup, &on_event) unless streamed
          return SimpleInference::Response.new(status: status, headers: headers, body: nil, raw_body: body_str)
        end

        should_parse_json = content_type.include?("json") || json_like_body?(body_str)
        parsed_body = should_parse_json ? parse_json(body_str) : body_str
        response = SimpleInference::Response.new(status: status, headers: headers, body: parsed_body, raw_body: body_str)
        maybe_raise_http_error(response: response, raise_on_http_error: nil)
        response
      rescue Timeout::Error => error
        raise SimpleInference::TimeoutError, error.message
      rescue SocketError, SystemCallError => error
        raise SimpleInference::ConnectionError, error.message
      end

      def consume_sse_buffer!(buffer, &on_event)
        extract_sse_blocks!(buffer).each do |block|
          _event_name, data = sse_event_and_data_from_block(block)
          next if data.nil?

          payload = data.strip
          next if payload.empty? || payload == "[DONE]"

          on_event&.call(nil, JSON.parse(payload))
        rescue JSON::ParserError => error
          raise SimpleInference::DecodeError, "Failed to parse Gemini SSE JSON event: #{error.message}"
        end
      end

      def extract_sse_blocks!(buffer)
        blocks = []

        loop do
          idx_lf = buffer.index("\n\n")
          idx_crlf = buffer.index("\r\n\r\n")
          idx = [idx_lf, idx_crlf].compact.min
          break if idx.nil?

          sep_len = (idx == idx_crlf) ? 4 : 2
          blocks << buffer.slice!(0, idx)
          buffer.slice!(0, sep_len)
        end

        blocks
      end

      def sse_event_and_data_from_block(block)
        event_name = nil
        data_lines = []

        block.to_s.split(/\r?\n/).each do |line|
          next if line.nil? || line.empty?
          next if line.start_with?(":")

          if line.start_with?("event:")
            event_name = line[6..]&.strip
          elsif line.start_with?("data:")
            data_lines << (line[5..]&.lstrip).to_s
          end
        end

        [event_name, data_lines.empty? ? nil : data_lines.join("\n")]
      end

      def sse_like_body?(body_str)
        body = body_str.to_s.lstrip
        return false if body.empty?

        (body.start_with?("data:", "event:") || body.include?("\ndata:") || body.include?("\nevent:")) &&
          (body.include?("\n\n") || body.include?("\r\n\r\n"))
      end

      def json_like_body?(body_str)
        body = body_str.to_s.lstrip
        return false if body.empty?

        body.start_with?("{", "[")
      end

      def incremental_delta(snapshot_text, accumulated_text)
        snapshot = snapshot_text.to_s
        return "" if snapshot.empty?
        return snapshot unless snapshot.start_with?(accumulated_text)

        snapshot.delete_prefix(accumulated_text)
      end

      def incremental_argument_delta(current_arguments, previous_arguments)
        current = current_arguments.to_s
        previous = previous_arguments.to_s
        return "" if current.empty?
        return current if previous.empty?
        return current.delete_prefix(previous) if current.start_with?(previous)

        prefix_length = 0
        limit = [current.length, previous.length].min
        while prefix_length < limit && current.getbyte(prefix_length) == previous.getbyte(prefix_length)
          prefix_length += 1
        end

        delta = current.byteslice(prefix_length..)
        delta.to_s.empty? ? current : delta.to_s
      end

      def merge_output_items(existing_items, incoming_items)
        merged = duplicate_items(existing_items)

        Array(incoming_items).each do |item|
          next unless item.is_a?(Hash)
          next unless item["type"].to_s == "function_call"

          index =
            merged.find_index do |candidate|
              next false unless candidate.is_a?(Hash)
              next false unless candidate["type"].to_s == "function_call"

              same_id = candidate["id"].to_s != "" && candidate["id"].to_s == item["id"].to_s
              same_call_id = candidate["call_id"].to_s != "" && candidate["call_id"].to_s == item["call_id"].to_s
              same_name = candidate["name"].to_s != "" && candidate["name"].to_s == item["name"].to_s
              same_id || same_call_id || same_name
            end

          if index
            merged[index] = merged[index].merge(item)
          else
            merged << item
          end
        end

        merged
      end

      def duplicate_items(items)
        Array(items).map do |item|
          next item unless item.is_a?(Hash)

          item.each_with_object({}) do |(key, value), out|
            out[key.to_s] =
              case value
              when Hash
                duplicate_items([value]).first
              when Array
                duplicate_items(value)
              else
                value
              end
          end
        end
      end

      def emit_stream_tool_call_events!(emit:, output_items:, streamed_tool_calls:, emitted_done:, done:, raw:)
        tool_calls = Array(output_items).filter_map do |item|
          next unless item.is_a?(Hash)
          next unless item["type"].to_s == "function_call"

          stringify_hash(item)
        end

        tool_calls.each_with_index do |item, index|
          item_id = item["id"] || item["call_id"] || "tool_call_#{index}"
          previous = streamed_tool_calls[item_id] || {}
          arguments = item["arguments"].to_s
          previous_arguments = previous["arguments"].to_s
          delta = incremental_argument_delta(arguments, previous_arguments)

          unless delta.empty?
            emit.call(
              SimpleInference::Responses::Events::ToolCallDelta.new(
                item_id: item_id,
                call_id: item["call_id"] || item["id"],
                name: item["name"],
                delta: delta,
                raw: raw,
                snapshot: arguments
              )
            )
          end

          streamed_tool_calls[item_id] = duplicate_items([item]).first
          next unless done
          next if emitted_done[item_id]

          emit.call(
            SimpleInference::Responses::Events::ToolCallDone.new(
              item_id: item_id,
              call_id: item["call_id"] || item["id"],
              name: item["name"],
              arguments: arguments,
              raw: raw,
              snapshot: duplicate_items([item]).first
            )
          )
          emitted_done[item_id] = true
        end
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
