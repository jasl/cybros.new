require "test_helper"

class ProviderCatalog::ValidateTest < ActiveSupport::TestCase
  test "rejects provider handles outside the allowed format" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        providers: {
          "OpenAI" => {
            display_name: "OpenAI",
            metadata: {},
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition,
            },
          },
        },
        model_roles: {
          "main" => ["OpenAI/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "provider handle"
  end

  test "rejects models with invalid multimodal capability flags or metadata shape" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        providers: {
          "openai" => {
            display_name: "OpenAI",
            metadata: [],
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition(
                capabilities: {
                  text_output: true,
                  tool_calls: true,
                  structured_output: true,
                  multimodal_inputs: {
                    image: true,
                    audio: "sometimes",
                    video: false,
                    file: true,
                  },
                }
              ),
            },
          },
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "metadata"
  end

  test "rejects role catalogs that point at unknown provider model references" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        providers: {
          "openai" => {
            display_name: "OpenAI",
            metadata: {},
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition,
            },
          },
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
          "coder" => ["codex_subscription/gpt-5.4"],
        }
      )
    end

    assert_includes error.message, "unknown model role candidate"
    assert_includes error.message, "codex_subscription/gpt-5.4"
  end

  private

  def valid_model_definition(**attrs)
    {
      display_name: "GPT-5.3 Chat Latest",
      context_window_tokens: 272_000,
      max_output_tokens: 128_000,
      metadata: {},
      capabilities: {
        text_output: true,
        tool_calls: true,
        structured_output: true,
        multimodal_inputs: {
          image: true,
          audio: false,
          video: false,
          file: true,
        },
      },
    }.merge(attrs)
  end
end
