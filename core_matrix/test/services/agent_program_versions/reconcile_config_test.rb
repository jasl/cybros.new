require "test_helper"

module AgentProgramVersions
end

class AgentProgramVersions::ReconcileConfigTest < ActiveSupport::TestCase
  test "preserves selector-bearing defaults and slot references when the new schema still allows them" do
    result = AgentProgramVersions::ReconcileConfig.call(
      previous_default_config_snapshot: default_default_config_snapshot(include_selector_slots: true),
      next_config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      next_default_config_snapshot: {
        "sandbox" => "workspace-read",
        "interactive" => { "selector" => "role:main" },
      }
    )

    assert_equal "workspace-read", result.reconciled_config["sandbox"]
    assert_equal "role:researcher", result.reconciled_config.dig("model_slots", "research", "selector")
    assert_equal "role:summary", result.reconciled_config.dig("model_slots", "summary", "selector")
    assert_equal ["model_slots"], result.report["retained_keys"]
    assert_equal "reconciled", result.report["status"]
  end

  test "retains runtime-owned interactive profile and subagent policy defaults" do
    result = AgentProgramVersions::ReconcileConfig.call(
      previous_default_config_snapshot: profile_aware_default_config_snapshot,
      next_config_schema_snapshot: profile_aware_config_schema_snapshot,
      next_default_config_snapshot: {
        "sandbox" => "workspace-read",
        "interactive" => {},
        "subagents" => {
          "enabled" => false,
        },
      }
    )

    assert_equal "workspace-read", result.reconciled_config["sandbox"]
    assert_equal "main", result.reconciled_config.dig("interactive", "profile")
    assert_equal false, result.reconciled_config.dig("subagents", "enabled")
    assert_equal true, result.reconciled_config.dig("subagents", "allow_nested")
    assert_equal 3, result.reconciled_config.dig("subagents", "max_depth")
    assert_equal ["interactive", "subagents"], result.report["retained_keys"].sort
    assert_equal "reconciled", result.report["status"]
  end
end
