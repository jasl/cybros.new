require "test_helper"

class RuntimeFeatures::PolicyResolverTest < ActiveSupport::TestCase
  test "workspace overrides win over runtime defaults and built in defaults" do
    context = create_workspace_context!
    context[:workspace].update!(
      config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_required",
          },
        },
      }
    )
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      default_canonical_config: {
        "features" => {
          "title_bootstrap" => {
            "strategy" => "runtime_first",
          },
          "prompt_compaction" => {
            "strategy" => "embedded_only",
          },
        },
      }
    )

    title_policy = RuntimeFeatures::PolicyResolver.call(
      feature_key: "title_bootstrap",
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version
    )
    prompt_policy = RuntimeFeatures::PolicyResolver.call(
      feature_key: "prompt_compaction",
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version
    )

    assert_equal({ "strategy" => "runtime_required" }, title_policy)
    assert_equal({ "strategy" => "embedded_only" }, prompt_policy)
  end

  test "falls back to built in defaults when no upstream config exists" do
    context = create_workspace_context!
    context[:workspace].update!(config: {})
    agent_definition_version = create_agent_definition_version!(
      installation: context[:installation],
      agent: context[:agent],
      default_canonical_config: {}
    )

    policy = RuntimeFeatures::PolicyResolver.call(
      feature_key: "title_bootstrap",
      workspace: context[:workspace],
      agent_definition_version: agent_definition_version
    )

    assert_equal({ "strategy" => "embedded_only" }, policy)
  end
end
