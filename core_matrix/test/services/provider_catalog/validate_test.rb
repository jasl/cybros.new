require "test_helper"

class ProviderCatalog::ValidateTest < ActiveSupport::TestCase
  self.uses_real_provider_catalog = true

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

  test "accepts model enabled false and supported request defaults" do
    catalog = ProviderCatalog::Validate.call(
      version: 1,
      providers: {
        "openai" => valid_provider_definition(
          request_governor: {
            max_concurrent_requests: 12,
            throttle_limit: 600,
            throttle_period_seconds: 60,
          },
          models: {
            "gpt-5.3-chat-latest" => valid_model_definition(
              enabled: false,
              request_defaults: {
                reasoning_effort: "medium",
                temperature: 1.0,
                top_p: 0.95,
                top_k: 20,
                min_p: 0.0,
                presence_penalty: 1.5,
                repetition_penalty: 1.0,
              }
            ),
          }
        ),
      },
      model_roles: {
        "main" => ["openai/gpt-5.3-chat-latest"],
      }
    )

    model = catalog.fetch(:providers).fetch("openai").fetch(:models).fetch("gpt-5.3-chat-latest")

    refute model.fetch(:enabled)
    assert_equal 12, catalog.fetch(:providers).fetch("openai").dig(:request_governor, :max_concurrent_requests)
    assert_equal(
      {
        "reasoning_effort" => "medium",
        "temperature" => 1.0,
        "top_p" => 0.95,
        "top_k" => 20,
        "min_p" => 0.0,
        "presence_penalty" => 1.5,
        "repetition_penalty" => 1.0,
      },
      model.fetch(:request_defaults)
    )
  end

  test "accepts disabled models that remain referenced from model roles" do
    catalog = ProviderCatalog::Validate.call(
      version: 1,
      providers: {
        "openai" => valid_provider_definition(
          models: {
            "gpt-5.3-chat-latest" => valid_model_definition(enabled: false),
          }
        ),
      },
      model_roles: {
        "main" => ["openai/gpt-5.3-chat-latest"],
      }
    )

    refute catalog.fetch(:providers).fetch("openai").fetch(:models).fetch("gpt-5.3-chat-latest").fetch(:enabled)
    assert_equal ["openai/gpt-5.3-chat-latest"], catalog.fetch(:model_roles).fetch("main")
  end

  test "defaults missing model enabled to true" do
    catalog = ProviderCatalog::Validate.call(
      version: 1,
      providers: {
        "openai" => valid_provider_definition(
          models: {
            "gpt-5.3-chat-latest" => valid_model_definition.except(:enabled),
          }
        ),
      },
      model_roles: {
        "main" => ["openai/gpt-5.3-chat-latest"],
      }
    )

    assert_equal true, catalog.fetch(:providers).fetch("openai").fetch(:models).fetch("gpt-5.3-chat-latest").fetch(:enabled)
  end

  test "rejects models with non boolean enabled" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openai" => valid_provider_definition(
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition(enabled: "sometimes"),
            }
          ),
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "enabled"
  end

  test "rejects request defaults with unsupported keys" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openai" => valid_provider_definition(
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition(
                request_defaults: {
                  temprature: 1.0,
                }
              ),
            }
          ),
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "request_defaults"
    assert_includes error.message, "temprature"
  end

  test "rejects request defaults not supported by the provider wire api" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openai" => valid_provider_definition(
            wire_api: "chat_completions",
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition(
                request_defaults: {
                  reasoning_effort: "high",
                }
              ),
            }
          ),
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "request_defaults"
    assert_includes error.message, "reasoning_effort"
  end

  test "rejects blank reasoning effort in request defaults" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openai" => valid_provider_definition(
            models: {
              "gpt-5.3-chat-latest" => valid_model_definition(
                request_defaults: {
                  reasoning_effort: "",
                }
              ),
            }
          ),
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "reasoning_effort"
  end

  test "rejects invalid numeric request defaults" do
    {
      "temperature" => -0.1,
      "top_p_negative" => { key: "top_p", value: -0.1 },
      "top_p_over_one" => { key: "top_p", value: 1.1 },
      "top_k_float" => { key: "top_k", value: 1.5 },
      "top_k_negative" => { key: "top_k", value: -1 },
      "min_p_negative" => { key: "min_p", value: -0.1 },
      "presence_penalty_string" => { key: "presence_penalty", value: "high" },
      "repetition_penalty_zero" => { key: "repetition_penalty", value: 0 },
    }.each_value do |entry|
      key = entry.is_a?(Hash) ? entry.fetch(:key) : "temperature"
      value = entry.is_a?(Hash) ? entry.fetch(:value) : entry

      error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
        ProviderCatalog::Validate.call(
          version: 1,
          providers: {
            "openai" => valid_provider_definition(
              models: {
                "gpt-5.3-chat-latest" => valid_model_definition(
                  request_defaults: {
                    key => value,
                  }
                ),
              }
            ),
          },
          model_roles: {
            "main" => ["openai/gpt-5.3-chat-latest"],
          }
        )
      end

    assert_includes error.message, key
    end
  end

  test "rejects invalid provider request governor values" do
    error = assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
      ProviderCatalog::Validate.call(
        version: 1,
        providers: {
          "openai" => valid_provider_definition(
            request_governor: {
              max_concurrent_requests: 0,
              throttle_limit: 600,
              throttle_period_seconds: 60,
            }
          ),
        },
        model_roles: {
          "main" => ["openai/gpt-5.3-chat-latest"],
        }
      )
    end

    assert_includes error.message, "request_governor"
    assert_includes error.message, "max_concurrent_requests"
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
      enabled: true,
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
