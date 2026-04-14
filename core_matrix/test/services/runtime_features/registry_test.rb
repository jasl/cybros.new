require "test_helper"

class RuntimeFeatures::RegistryTest < ActiveSupport::TestCase
  test "returns the registered title bootstrap definition" do
    definition = RuntimeFeatures::Registry.fetch("title_bootstrap")

    assert_equal "title_bootstrap", definition.key
    assert_equal RuntimeFeaturePolicies::TitleBootstrapSchema, definition.policy_schema
    assert_equal "title_bootstrap", definition.runtime_capability_key
    assert_equal :optional, definition.runtime_requirement
    assert_equal :live_resolved, definition.policy_lifecycle
    assert_equal :live_resolved, definition.capability_lifecycle
    assert_equal :direct, definition.execution_mode
  end

  test "rejects unknown runtime feature keys" do
    assert_raises(KeyError) do
      RuntimeFeatures::Registry.fetch("not_real")
    end
  end
end
