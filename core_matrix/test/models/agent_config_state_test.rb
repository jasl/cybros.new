require "test_helper"

class AgentConfigStateTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    config_state = create_agent_config_state!

    assert config_state.public_id.present?
    assert_equal config_state, AgentConfigState.find_by_public_id!(config_state.public_id)
  end

  test "allows only one config state row per agent" do
    installation = create_installation!
    agent = create_agent!(installation: installation)
    create_agent_config_state!(installation: installation, agent: agent)

    duplicate = build_agent_config_state(installation: installation, agent: agent)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:agent_id], "has already been taken"
  end
end
