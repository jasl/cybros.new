# frozen_string_literal: true

require_relative "openai_compatible"

module SimpleInference
  module Protocols
    class OpenAICompatibleResponses < OpenAICompatible
      def create(model:, input:, **options)
        result = chat(model: model, messages: coerce_messages(input, options), stream: false, **chat_options(options))
        SimpleInference::Responses::Result.from_openai_chat(result)
      end

      def stream(model:, input:, **options)
        SimpleInference::Responses::Stream.new do |&emit|
          full = +""
          finish_reason = nil
          last_usage = nil
          collected_logprobs = []
          streamed_tool_calls = []
          emitted_done = {}

          raw_response =
            chat_completions_stream(model: model, messages: coerce_messages(input, options), **chat_options(options)) do |event|
              emit.call(
                SimpleInference::Responses::Events::Raw.new(
                  type: "chat.completion.chunk",
                  raw: event,
                  snapshot: duplicate_tool_calls(streamed_tool_calls)
                )
              )

              delta = OpenAI.chat_completion_chunk_delta(event)
              if delta
                full << delta
                emit.call(
                  SimpleInference::Responses::Events::TextDelta.new(
                    delta: delta,
                    raw: event,
                    snapshot: full
                  )
                )
              end

              chunk_finish_reason = event.is_a?(Hash) ? event.dig("choices", 0, "finish_reason") : nil
              finish_reason = chunk_finish_reason unless chunk_finish_reason.nil? || chunk_finish_reason.to_s.empty?

              chunk_logprobs = event.is_a?(Hash) ? event.dig("choices", 0, "logprobs", "content") : nil
              if chunk_logprobs.is_a?(Array)
                collected_logprobs.concat(chunk_logprobs)
              end

              usage = OpenAI.chat_completion_usage(event)
              last_usage = usage if usage

              merge_stream_tool_calls!(streamed_tool_calls, event)
              emit_stream_tool_call_events!(
                emit: emit,
                event: event,
                streamed_tool_calls: streamed_tool_calls,
                emitted_done: emitted_done
              )
            end

          response_usage = last_usage || OpenAI.chat_completion_usage(raw_response)
          response_finish_reason = finish_reason || OpenAI.chat_completion_finish_reason(raw_response)
          synthesized_body = synthesize_stream_chat_completion_body(
            content: full,
            finish_reason: response_finish_reason,
            usage: response_usage,
            logprobs: collected_logprobs,
            tool_calls: streamed_tool_calls
          )
          raw_response = Response.new(
            status: raw_response.status,
            headers: raw_response.headers,
            body: raw_response.body || synthesized_body,
            raw_body: raw_response.raw_body
          )
          emit_remaining_stream_tool_call_done_events!(
            emit: emit,
            streamed_tool_calls: streamed_tool_calls,
            emitted_done: emitted_done
          )

          raw_result = OpenAI::ChatResult.new(
            content: full,
            usage: response_usage,
            finish_reason: response_finish_reason,
            logprobs: collected_logprobs.empty? ? OpenAI.chat_completion_logprobs(raw_response) : collected_logprobs,
            response: raw_response
          )
          result = SimpleInference::Responses::Result.from_openai_chat(raw_result)
          emit.call(SimpleInference::Responses::Events::Completed.new(result: result, raw: result.provider_response&.body))
          result
        end
      end

      private

      def coerce_messages(input, options)
        return input if input.is_a?(Array)

        messages = []
        instructions = options[:instructions] || options["instructions"]
        messages << { role: "system", content: instructions.to_s } unless instructions.to_s.strip.empty?
        messages << { role: "user", content: input }
        messages
      end

      def chat_options(options)
        normalized = options.each_with_object({}) do |(key, value), out|
          next if key.to_s == "instructions"

          normalized_key = key.to_s == "max_output_tokens" ? :max_tokens : key
          out[normalized_key] = value
        end

        normalized
      end
    end
  end
end
