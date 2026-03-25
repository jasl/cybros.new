require "test_helper"

class ProviderCatalog::ValidateTest < ActiveSupport::TestCase
  test "rejects catalogs without a version" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        providers: {
          "openai" => valid_provider_definition,
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "version"
  end

  test "rejects provider handles outside the allowed format" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "OpenAI" => {
            **valid_provider_definition,
            display_name: "OpenAI",
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
        version: 1,
        providers: {
          "openai" => {
            **valid_provider_definition,
            display_name: "OpenAI",
            metadata: [],
            models: valid_provider_definition[:models].deep_merge(
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
              )
            ),
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
        version: 1,
        providers: {
          "openai" => valid_provider_definition,
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

  test "rejects providers missing required runtime fields" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openrouter" => {
            display_name: "OpenRouter",
            metadata: {},
            models: {
              "openai-gpt-5.4" => valid_model_definition,
            },
          },
        },
        model_roles: {
          "main" => ["openrouter/openai-gpt-5.4"],
        }
      )
    end

    assert_includes error.message, "enabled"
  end

  test "rejects models missing api_model or tokenizer_hint" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openrouter" => valid_provider_definition(
            display_name: "OpenRouter",
            models: {
              "openai-gpt-5.4" => valid_model_definition.except(:api_model, :tokenizer_hint),
            }
          ),
        },
        model_roles: {
          "main" => ["openrouter/openai-gpt-5.4"],
        }
      )
    end

    assert_match(/api_model|tokenizer_hint/, error.message)
  end

  private

  def valid_provider_definition(display_name: "OpenAI", **attrs)
    {
      display_name: display_name,
      enabled: true,
      environments: %w[development test production],
      adapter_key: "openai_responses",
      base_url: "https://api.openai.com/v1",
      headers: {},
      wire_api: "responses",
      transport: "https",
      responses_path: "/responses",
      requires_credential: true,
      credential_kind: "api_key",
      metadata: {},
      models: {
        "gpt-5.3-chat-latest" => valid_model_definition,
      },
    }.merge(attrs)
  end

  def valid_model_definition(**attrs)
    {
      display_name: "GPT-5.3 Chat Latest",
      api_model: "gpt-5.3-chat-latest",
      tokenizer_hint: "o200k_base",
      context_window_tokens: 272_000,
      max_output_tokens: 128_000,
      context_soft_limit_ratio: 0.8,
      request_defaults: {},
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
