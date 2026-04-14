module MockLLM
  module V1
    class ImagesController < MockLLM::V1::ChatCompletionsController
      TINY_PNG_BASE64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jm6cAAAAASUVORK5CYII=".freeze

      def create
        payload = request.request_parameters
        model = payload["model"].to_s
        prompt = payload["prompt"].presence || extract_text_content(payload["input"])

        return render_openai_error("model is required", status: :bad_request) if model.blank?
        return render_openai_error("prompt or input is required", status: :bad_request) if prompt.blank?

        render json: {
          created: Time.current.to_i,
          data: [
            {
              b64_json: TINY_PNG_BASE64,
              revised_prompt: prompt,
            },
          ],
        }
      rescue ActionDispatch::Http::Parameters::ParseError, JSON::ParserError
        render_openai_error("invalid JSON body", status: :bad_request)
      end
    end
  end
end
