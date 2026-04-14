require "test_helper"

class RuntimeFeaturePolicies::RootSchemaTest < ActiveSupport::TestCase
  test "publishes shared feature defaults and strategy schema" do
    defaults = RuntimeFeaturePolicies::RootSchema.default_features
    schema = RuntimeFeaturePolicies::RootSchema.json_schema

    assert_equal({ "strategy" => "embedded_only" }, defaults.fetch("title_bootstrap"))
    assert_equal({ "strategy" => "runtime_first" }, defaults.fetch("prompt_compaction"))
    assert_equal(
      %w[disabled embedded_only runtime_first runtime_required],
      schema.dig("properties", "features", "properties", "title_bootstrap", "properties", "strategy", "enum")
    )
  end

  test "validates strategy-only feature payloads" do
    assert_equal [], RuntimeFeaturePolicies::RootSchema.validation_errors(
      {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_required",
          },
        },
      }
    )

    errors = RuntimeFeaturePolicies::RootSchema.validation_errors(
      {
        "features" => {
          "title_bootstrap" => {
            "mode" => "embedded_only",
          },
        },
      }
    )

    assert_includes errors, "features.title_bootstrap.mode is not supported"
  end
end
