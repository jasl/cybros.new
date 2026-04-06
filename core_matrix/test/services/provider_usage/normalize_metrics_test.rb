require "test_helper"

class ProviderUsage::NormalizeMetricsTest < ActiveSupport::TestCase
  test "extracts chat-completions cache details when cached tokens are present" do
    normalized = ProviderUsage::NormalizeMetrics.call(
      usage: {
        "prompt_tokens" => 12,
        "completion_tokens" => 8,
        "total_tokens" => 20,
        "prompt_tokens_details" => {
          "cached_tokens" => 7,
        },
      }
    )

    assert_equal(
      {
        "input_tokens" => 12,
        "output_tokens" => 8,
        "total_tokens" => 20,
        "prompt_cache_status" => "available",
        "cached_input_tokens" => 7,
      },
      normalized
    )
  end

  test "treats explicit zero cached tokens as available" do
    normalized = ProviderUsage::NormalizeMetrics.call(
      usage: {
        "prompt_tokens" => 12,
        "completion_tokens" => 8,
        "total_tokens" => 20,
        "prompt_tokens_details" => {
          "cached_tokens" => 0,
        },
      }
    )

    assert_equal "available", normalized.fetch("prompt_cache_status")
    assert_equal 0, normalized.fetch("cached_input_tokens")
  end

  test "extracts responses cache details when cached tokens are present" do
    normalized = ProviderUsage::NormalizeMetrics.call(
      usage: {
        "input_tokens" => 11,
        "output_tokens" => 3,
        "total_tokens" => 14,
        "input_tokens_details" => {
          "cached_tokens" => 5,
        },
      }
    )

    assert_equal(
      {
        "input_tokens" => 11,
        "output_tokens" => 3,
        "total_tokens" => 14,
        "prompt_cache_status" => "available",
        "cached_input_tokens" => 5,
      },
      normalized
    )
  end

  test "defaults to unknown when cache details are absent" do
    normalized = ProviderUsage::NormalizeMetrics.call(
      usage: {
        "prompt_tokens" => 12,
        "completion_tokens" => 8,
        "total_tokens" => 20,
      }
    )

    assert_equal(
      {
        "input_tokens" => 12,
        "output_tokens" => 8,
        "total_tokens" => 20,
        "prompt_cache_status" => "unknown",
      },
      normalized
    )
  end

  test "marks prompt cache details unsupported when provider metadata opts out" do
    normalized = ProviderUsage::NormalizeMetrics.call(
      usage: {
        "prompt_tokens" => 12,
        "completion_tokens" => 8,
        "total_tokens" => 20,
      },
      provider_metadata: {
        "usage_capabilities" => {
          "prompt_cache_details" => false,
        },
      }
    )

    assert_equal(
      {
        "input_tokens" => 12,
        "output_tokens" => 8,
        "total_tokens" => 20,
        "prompt_cache_status" => "unsupported",
      },
      normalized
    )
  end
end
