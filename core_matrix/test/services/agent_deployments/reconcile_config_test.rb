require "test_helper"

module AgentDeployments
end

class AgentDeployments::ReconcileConfigTest < ActiveSupport::TestCase
  test "preserves selector-bearing defaults and slot references when the new schema still allows them" do
    result = AgentDeployments::ReconcileConfig.call(
      previous_default_config_snapshot: default_default_config_snapshot(include_selector_slots: true),
      next_config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      next_default_config_snapshot: {
        "sandbox" => "workspace-read",
        "interactive" => { "selector" => "role:main" },
      }
    )

    assert_equal "workspace-read", result.reconciled_config["sandbox"]
    assert_equal "role:researcher", result.reconciled_config.dig("model_slots", "research", "selector")
    assert_equal ["model_slots"], result.report["retained_keys"]
    assert_equal "reconciled", result.report["status"]
  end
end
