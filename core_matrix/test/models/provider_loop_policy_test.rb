require "test_helper"

class ProviderLoopPolicyTest < ActiveSupport::TestCase
  test "builds the canonical default loop policy" do
    policy = ProviderLoopPolicy.build(runtime_overrides: {})

    assert_equal(
      {
        "max_rounds" => 64,
        "parallel_tool_calls" => false,
        "max_parallel_tool_calls" => 1,
        "loop_detection" => {
          "enabled" => false,
        },
      },
      policy
    )
  end

  test "accepts nested loop_policy overrides and preserves reserved defaults" do
    policy = ProviderLoopPolicy.build(
      runtime_overrides: {
        "loop_policy" => {
          "max_rounds" => 80,
        },
        "temperature" => 0.2,
      }
    )

    assert_equal(
      {
        "max_rounds" => 80,
        "parallel_tool_calls" => false,
        "max_parallel_tool_calls" => 1,
        "loop_detection" => {
          "enabled" => false,
        },
      },
      policy
    )
  end

  test "supports legacy top-level max_rounds as a shorthand override" do
    policy = ProviderLoopPolicy.build(
      runtime_overrides: {
        "max_rounds" => 24,
      }
    )

    assert_equal 24, policy.fetch("max_rounds")
  end

  test "rejects invalid max_rounds overrides" do
    error = assert_raises(ProviderLoopPolicy::InvalidPolicy) do
      ProviderLoopPolicy.build(
        runtime_overrides: {
          "loop_policy" => {
            "max_rounds" => 0,
          },
        }
      )
    end

    assert_includes error.message, "loop_policy.max_rounds"
  end
end
