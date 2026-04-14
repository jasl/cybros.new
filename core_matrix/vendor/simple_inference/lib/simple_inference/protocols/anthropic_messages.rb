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
          tool_calls: SimpleInference::Responses::Result.tool_calls_from_output_items(output_items),
          usage: normalize_usage(body["usage"]),
          finish_reason: body["stop_reason"],
          provider_response: response,
          provider_format: "responses"
        )
      end

      def stream(model:, input:, **options)
        SimpleInference::Responses::Stream.new do |&emit|
          result =
            stream_result(model: model, input: input, **options) do |event, state|
              emit.call(SimpleInference::Responses::Events::Raw.new(type: event["type"].to_s, raw: event, snapshot: state[:content]))

              case event.dig("delta", "type").to_s
              when "text_delta"
                emit.call(
                  SimpleInference::Responses::Events::TextDelta.new(
                    delta: event.dig("delta", "text"),
                    raw: event,
                    snapshot: state[:output_text]
                  )
                )
              when "input_json_delta"
                block = state[:content].fetch(event.fetch("index"), {})
                emit.call(
                  SimpleInference::Responses::Events::ToolCallDelta.new(
                    item_id: block["id"],
                    call_id: block["id"],
                    name: block["name"],
                    delta: event.dig("delta", "partial_json"),
                    raw: event,
                    snapshot: block["_input_json"].to_s
                  )
                )
              end

              if event["type"].to_s == "content_block_stop"
                block = state[:content].fetch(event.fetch("index"), {})
                if block["type"].to_s == "tool_use"
                  emit.call(
                    SimpleInference::Responses::Events::ToolCallDone.new(
                      item_id: block["id"],
                      call_id: block["id"],
                      name: block["name"],
                      arguments: JSON.generate(block["input"] || {}),
                      raw: event,
                      snapshot: block
                    )
                  )
                end
              end
            end

          emit.call(SimpleInference::Responses::Events::Completed.new(result: result, raw: result.provider_response&.body))
          result
        end
      end

      private

      def stream_result(model:, input:, **options)
        raise SimpleInference::ValidationError, "model is required" if model.nil? || model.to_s.strip.empty?

        message_snapshot = nil

        response =
          stream_messages(model: model, input: input, **options) do |_event_name, event|
            message_snapshot = apply_stream_event(message_snapshot, event)
            yield(event, { content: Array(message_snapshot && message_snapshot["content"]).map { |item| duplicate_hash(item) }, output_text: extract_stream_output_text(message_snapshot) }) if block_given?
          end

        body =
          if response.body.is_a?(Hash)
            response.body
          else
            message_snapshot || {}
          end

        if response.body.nil? && body.is_a?(Hash) && !body.empty?
          response = SimpleInference::Response.new(status: response.status, headers: response.headers, body: body, raw_body: response.raw_body)
        end

        content = Array(body["content"])
        output_items = normalize_output_items(content)

        SimpleInference::Responses::Result.new(
          id: body["id"],
          output_text: content.filter_map { |item| item.is_a?(Hash) ? item["text"] : nil }.join,
          output_items: output_items,
          tool_calls: SimpleInference::Responses::Result.tool_calls_from_output_items(output_items),
          usage: normalize_usage(body["usage"]),
          finish_reason: body["stop_reason"],
          provider_response: response,
          provider_format: "responses"
        )
      end

      def anthropic_headers
        config.headers
          .reject { |key, _value| key.to_s.casecmp("authorization").zero? }
          .merge(
            "x-api-key" => config.api_key.to_s,
            "anthropic-version" => "2023-06-01"
          )
      end

      def stream_messages(model:, input:, **options)
        return enum_for(:stream_messages, model: model, input: input, **options) unless block_given?

        request_env = {
          method: :post,
          url: "#{config.base_url}/v1/messages",
          headers: anthropic_headers.merge(
            "Content-Type" => "application/json",
            "Accept" => "text/event-stream"
          ),
          body: serialize_json_body(build_request_body(model: model, input: input, options: options).merge(stream: true)),
          timeout: config.timeout,
          open_timeout: config.open_timeout,
          read_timeout: config.read_timeout,
        }

        handle_stream_response(request_env) do |event_name, event|
          yield event_name, event
        end
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
          event_name, data = sse_event_and_data_from_block(block)
          next if data.nil?

          payload = data.strip
          next if payload.empty? || payload == "[DONE]"

          on_event&.call(event_name, JSON.parse(payload))
        rescue JSON::ParserError => error
          raise SimpleInference::DecodeError, "Failed to parse Anthropic SSE JSON event: #{error.message}"
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

      def apply_stream_event(snapshot, event)
        event = stringify_hash(event)
        current = snapshot ? duplicate_hash(snapshot) : nil

        case event["type"].to_s
        when "message_start"
          message = duplicate_hash(event["message"])
          message["content"] = Array(message["content"]).map { |item| duplicate_hash(item) }
          message
        when "content_block_start"
          current ||= { "content" => [] }
          current["content"] ||= []
          current["content"][event.fetch("index")] = duplicate_hash(event["content_block"])
          current
        when "content_block_delta"
          current ||= { "content" => [] }
          current["content"] ||= []
          index = event.fetch("index")
          block = current["content"][index] = duplicate_hash(current["content"][index])
          delta = stringify_hash(event["delta"])

          case delta["type"].to_s
          when "text_delta"
            block["text"] = block["text"].to_s + delta["text"].to_s
          when "input_json_delta"
            block["_input_json"] = block["_input_json"].to_s + delta["partial_json"].to_s
          end

          current
        when "content_block_stop"
          current ||= { "content" => [] }
          index = event.fetch("index")
          block = current["content"][index] = duplicate_hash(current["content"][index])
          finalize_stream_block!(block)
          current
        when "message_delta"
          current ||= { "content" => [] }
          delta = stringify_hash(event["delta"])
          usage = stringify_hash(event["usage"])
          current["stop_reason"] = delta["stop_reason"] unless delta["stop_reason"].nil?
          current["stop_sequence"] = delta["stop_sequence"] unless delta["stop_sequence"].nil?
          current["usage"] = duplicate_hash(current["usage"]).merge(usage)
          current
        else
          current || snapshot || { "content" => [] }
        end
      end

      def finalize_stream_block!(block)
        return unless block["type"].to_s == "tool_use"

        partial_json = block.delete("_input_json").to_s
        return if partial_json.empty?

        block["input"] =
          begin
            JSON.parse(partial_json)
          rescue JSON::ParserError
            {}
          end
      end

      def extract_stream_output_text(snapshot)
        Array(snapshot && snapshot["content"]).filter_map do |item|
          item.is_a?(Hash) ? item["text"] : nil
        end.join
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

      def duplicate_hash(value)
        return {} unless value.is_a?(Hash)

        value.each_with_object({}) do |(key, entry), out|
          out[key.to_s] =
            case entry
            when Hash
              duplicate_hash(entry)
            when Array
              entry.map { |item| item.is_a?(Hash) ? duplicate_hash(item) : item }
            else
              entry
            end
        end
      end
    end
  end
end
