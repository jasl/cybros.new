require "json"

module ProviderExecution
  class NormalizeProviderResponse
    def self.call(...)
      new(...).call
    end

    def initialize(provider_result:, request_context: nil)
      @provider_result = provider_result
      @request_context = request_context.present? ? ProviderRequestContext.wrap(request_context) : nil
    end

    def call
      unless @provider_result.is_a?(SimpleInference::Responses::Result)
        raise TypeError, "provider_result must be a SimpleInference::Responses::Result"
      end

      normalize_responses_result
    end

    private

    def normalize_responses_result
      {
        "output_text" => @provider_result.output_text.to_s,
        "tool_calls" => normalize_tool_calls,
        "finish_reason" => @provider_result.finish_reason,
        "usage" => normalize_usage(@provider_result.usage),
      }
    end

    def normalize_tool_calls
      if @provider_result.provider_format.to_s == "chat_completions"
        Array(@provider_result.tool_calls).map { |tool_call| normalize_chat_tool_call(tool_call) }
      else
        Array(@provider_result.output_items).filter_map { |item| normalize_responses_tool_call(item) }
      end
    end

    def normalize_chat_tool_call(tool_call)
      {
        "call_id" => tool_call.fetch("id", tool_call.fetch("call_id", nil)),
        "tool_name" => tool_call.dig("function", "name") || tool_call["name"],
        "arguments" => parse_arguments!(tool_call.dig("function", "arguments") || tool_call["arguments"], call_id: tool_call.fetch("id", tool_call.fetch("call_id", "unknown"))),
        "provider_payload" => tool_call["provider_payload"],
        "provider_format" => "chat_completions",
      }
    end

    def normalize_responses_tool_call(item)
      return unless item.is_a?(Hash)
      return unless item["type"].to_s == "function_call"

      {
        "call_id" => item.fetch("call_id"),
        "tool_name" => item.fetch("name"),
        "arguments" => parse_arguments!(item["arguments"], call_id: item.fetch("call_id")),
        "provider_item_id" => item["id"],
        "provider_payload" => item["provider_payload"],
        "provider_format" => "responses",
      }
    end

    def parse_arguments!(raw_arguments, call_id:)
      return {} if raw_arguments.blank?
      return raw_arguments.deep_stringify_keys if raw_arguments.is_a?(Hash)

      parsed = JSON.parse(raw_arguments.to_s)
      raise SimpleInference::DecodeError, "tool call arguments for #{call_id} must decode to a JSON object" unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => error
      raise SimpleInference::DecodeError, "invalid tool call arguments for #{call_id}: #{error.message}"
    end

    def normalize_usage(usage)
      ProviderUsage::NormalizeMetrics.call(usage:, request_context: @request_context)
    end
  end
end
