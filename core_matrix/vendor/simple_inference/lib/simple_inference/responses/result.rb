# frozen_string_literal: true

module SimpleInference
  module Responses
    class Result
      attr_reader :id,
                  :output_text,
                  :output_items,
                  :tool_calls,
                  :usage,
                  :finish_reason,
                  :provider_response,
                  :provider_format

      def initialize(id: nil, output_text:, output_items:, tool_calls:, usage:, finish_reason:, provider_response:, provider_format:)
        @id = id
        @output_text = output_text.to_s
        @output_items = Array(output_items)
        @tool_calls = Array(tool_calls)
        @usage = usage
        @finish_reason = finish_reason
        @provider_response = provider_response
        @provider_format = provider_format
      end

      def self.from_openai_responses(result)
        response = result.respond_to?(:response) ? result.response : nil
        body = response.respond_to?(:body) && response.body.is_a?(Hash) ? response.body : {}

        new(
          id: body["id"],
          output_text: result.respond_to?(:output_text) ? result.output_text : "",
          output_items: result.respond_to?(:output_items) ? result.output_items : [],
          tool_calls: extract_responses_tool_calls(result.respond_to?(:output_items) ? result.output_items : []),
          usage: result.respond_to?(:usage) ? result.usage : nil,
          finish_reason: body["status"] || body["finish_reason"],
          provider_response: response,
          provider_format: "responses"
        )
      end

      def self.from_openai_chat(result)
        response = result.respond_to?(:response) ? result.response : nil
        body = response.respond_to?(:body) && response.body.is_a?(Hash) ? response.body : {}
        message = body.dig("choices", 0, "message")
        tool_calls = message.is_a?(Hash) ? Array(message["tool_calls"]) : []

        new(
          id: body["id"],
          output_text: result.respond_to?(:content) ? result.content : "",
          output_items: [],
          tool_calls: tool_calls,
          usage: result.respond_to?(:usage) ? result.usage : nil,
          finish_reason: result.respond_to?(:finish_reason) ? result.finish_reason : nil,
          provider_response: response,
          provider_format: "chat_completions"
        )
      end

      private_class_method def self.extract_responses_tool_calls(output_items)
        Array(output_items).filter_map do |item|
          next unless item.is_a?(Hash)
          next unless item["type"].to_s == "function_call"

          item
        end
      end
    end
  end
end
