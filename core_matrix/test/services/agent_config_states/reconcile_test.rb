require "test_helper"

class AgentConfigStates::ReconcileTest < ActiveSupport::TestCase
  test "creates the first agent config state from the definition defaults" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    agent_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      default_canonical_config_document: create_json_document!(
        installation: installation,
        document_kind: "default_canonical_config",
        payload: {
          "behavior" => { "sandbox" => "workspace-write" },
          "interactive" => { "default_profile_key" => "main" },
        }
      )
    )

    result = AgentConfigStates::Reconcile.call(
      agent: agent,
      agent_definition_version: agent_definition_version
    )

    assert_equal agent, result.agent
    assert_equal agent_definition_version, result.base_agent_definition_version
    assert_equal 1, result.version
    assert_equal "ready", result.reconciliation_state
    assert_equal(
      {
        "behavior" => { "sandbox" => "workspace-write" },
        "interactive" => { "default_profile_key" => "main" },
      },
      result.effective_payload
    )
  end

  test "deep merges overrides into the new default payload and increments version when effective config changes" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    initial_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      default_canonical_config_document: create_json_document!(
        installation: installation,
        document_kind: "default_canonical_config",
        payload: {
          "behavior" => { "sandbox" => "workspace-write" },
          "interactive" => { "default_profile_key" => "main" },
          "subagents" => { "enabled" => true, "allow_nested" => true, "max_depth" => 3 },
        }
      )
    )
    override_document = create_json_document!(
      installation: installation,
      document_kind: "agent_config_override",
      payload: {
        "interactive" => { "default_profile_key" => "researcher" },
        "subagents" => { "enabled" => false },
      }
    )
    create_agent_config_state!(
      installation: installation,
      agent: agent,
      base_agent_definition_version: initial_definition_version,
      override_document: override_document,
      effective_document: create_json_document!(
        installation: installation,
        document_kind: "effective_canonical_config",
        payload: initial_definition_version.default_canonical_config.deep_merge(override_document.payload)
      ),
      content_fingerprint: Digest::SHA256.hexdigest(JSON.generate(initial_definition_version.default_canonical_config.deep_merge(override_document.payload))),
      version: 1
    )
    replacement_definition_version = create_agent_definition_version!(
      installation: installation,
      agent: agent,
      default_canonical_config_document: create_json_document!(
        installation: installation,
        document_kind: "default_canonical_config",
        payload: {
          "behavior" => { "sandbox" => "workspace-read" },
          "interactive" => { "default_profile_key" => "main" },
          "subagents" => { "enabled" => true, "allow_nested" => true, "max_depth" => 5 },
        }
      )
    )

    result = AgentConfigStates::Reconcile.call(
      agent: agent,
      agent_definition_version: replacement_definition_version
    )

    assert_equal replacement_definition_version, result.base_agent_definition_version
    assert_equal 2, result.version
    assert_equal(
      {
        "behavior" => { "sandbox" => "workspace-read" },
        "interactive" => { "default_profile_key" => "researcher" },
        "subagents" => { "enabled" => false, "allow_nested" => true, "max_depth" => 5 },
      },
      result.effective_payload
    )
  end
end
