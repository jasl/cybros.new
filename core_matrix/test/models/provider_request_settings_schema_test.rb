require "test_helper"

class ProviderRequestSettingsSchemaTest < ActiveSupport::TestCase
  test "exposes allowed keys per wire api" do
    chat_schema = ProviderRequestSettingsSchema.for("chat_completions")
    responses_schema = ProviderRequestSettingsSchema.for("responses")

    assert_equal(
      %w[min_p presence_penalty repetition_penalty temperature top_k top_p],
      chat_schema.allowed_keys
    )
    assert_equal(
      %w[min_p presence_penalty reasoning_effort repetition_penalty temperature top_k top_p],
      responses_schema.allowed_keys
    )
  end

  test "filters merged execution settings through the canonical schema" do
    schema = ProviderRequestSettingsSchema.for("chat_completions")

    settings = schema.merge_execution_settings(
      request_defaults: {
        temperature: 0.7,
        top_p: 0.8,
      },
      runtime_overrides: {
        "temperature" => 0.4,
        "sandbox" => "workspace-write",
      }
    )

    assert_equal(
      {
        "temperature" => 0.4,
        "top_p" => 0.8,
      },
      settings
    )
  end
end
