module MockLLM
  module V1
    class ResponsesController < MockLLM::V1::ChatCompletionsController
      def create
        payload = request.request_parameters

        model = payload["model"].to_s
        input = normalize_input(payload["input"])

        return render_openai_error("model is required", status: :bad_request) if model.blank?
        return render_openai_error("input must be present", status: :bad_request) if input.blank?

        stream = boolean(payload["stream"])
        last_prompt = last_input_prompt(input)
        shortcut_seconds = numeric_prompt_delay_seconds(last_prompt)

        if shortcut_seconds
          delay_seconds = clamp_mock_slow_seconds(shortcut_seconds, default_max: 9.0)
          content = build_delayed_mock_content(seconds: shortcut_seconds)
          usage = build_usage([{ "role" => "user", "content" => last_prompt }], content)
        else
          controls = parse_mock_controls(last_prompt)
          return render_openai_error("invalid mock directive", status: :bad_request) if controls[:invalid_directive]

          if controls[:error_status]
            return render_openai_error(
              controls[:error_message] || "mock error",
              status: controls[:error_status],
              type: openai_error_type_for_status(controls[:error_status])
            )
          end

          effective_prompt = controls[:prompt]
          delay_seconds = controls[:slow_seconds]
          content = build_mock_content([{ "role" => "user", "content" => last_prompt }], prompt_override: effective_prompt)
          usage = build_usage([{ "role" => "user", "content" => last_prompt }], content, prompt_override: effective_prompt)
        end

        if stream
          stream_responses(model: model, content: content, usage: usage, delay_seconds: delay_seconds)
        else
          sleep(delay_seconds) if delay_seconds.to_f.positive?
          render json: build_responses_payload(model: model, content: content, usage: usage)
        end
      rescue ActionDispatch::Http::Parameters::ParseError, JSON::ParserError
        render_openai_error("invalid JSON body", status: :bad_request)
      end

      private

      def normalize_input(raw)
        return raw unless raw.is_a?(Array)

        raw.map do |item|
          item.is_a?(ActionController::Parameters) ? item.to_unsafe_h : item
        end
      end

      def last_input_prompt(input)
        case input
        when String
          input
        when Array
          input.reverse_each do |item|
            next unless item.is_a?(Hash)

            role = item["role"].to_s
            type = item["type"].to_s
            prompt = nil
            prompt = extract_text_content(item["content"]) if role == "user" || type == "message"
            prompt = item["text"].to_s if prompt.blank? && %w[text input_text].include?(type)
            return prompt if prompt.present?
          end

          ""
        else
          extract_text_content(input)
        end
      end

      def build_responses_payload(model:, content:, usage:)
        {
          id: "resp_#{SecureRandom.hex(12)}",
          object: "response",
          created_at: Time.current.to_i,
          model: model,
          status: "completed",
          output: [
            {
              id: "msg_#{SecureRandom.hex(8)}",
              type: "message",
              role: "assistant",
              content: [
                {
                  type: "output_text",
                  text: content,
                },
              ],
            },
          ],
          usage: {
            input_tokens: usage["prompt_tokens"],
            output_tokens: usage["completion_tokens"],
            total_tokens: usage["total_tokens"],
          },
        }
      end

      def stream_responses(model:, content:, usage:, delay_seconds: nil)
        response.status = 200
        response.headers["Content-Type"] = "text/event-stream"
        response.headers["Cache-Control"] = "no-cache"
        response.headers["X-Accel-Buffering"] = "no"

        payload = build_responses_payload(model: model, content: content, usage: usage)
        delay = delay_seconds.nil? ? stream_delay_seconds : delay_seconds.to_f
        item = payload.fetch(:output).first.deep_stringify_keys

        write_sse_event(
          "type" => "response.output_item.added",
          "output_index" => 0,
          "item" => item.merge("content" => []),
        )

        chunk_strings(content).each do |chunk|
          write_sse_event(
            "type" => "response.output_text.delta",
            "delta" => chunk,
          )

          sleep(delay) if delay.positive?
        end

        write_sse_event(
          "type" => "response.output_item.done",
          "output_index" => 0,
          "item" => item,
        )
        write_sse_event(
          "type" => "response.completed",
          "response" => payload.deep_stringify_keys,
        )
        response.stream.write("data: [DONE]\n\n")
      rescue IOError, ActionController::Live::ClientDisconnected
        nil
      ensure
        begin
          response.stream.close
        rescue IOError, ActionController::Live::ClientDisconnected
          nil
        end
      end
    end
  end
end
