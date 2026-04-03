require "test_helper"

module AgentPrograms
end

class AgentPrograms::VisibleToUserQueryTest < ActiveSupport::TestCase
  test "returns active global agents plus the current users personal agents" do
    installation = create_installation!
    user = create_user!(installation: installation, display_name: "Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other"
    )
    shared_agent = create_agent_program!(
      installation: installation,
      visibility: "global",
      key: "shared-agent",
      display_name: "Shared Agent"
    )
    personal_agent = create_agent_program!(
      installation: installation,
      visibility: "personal",
      owner_user: user,
      key: "personal-agent",
      display_name: "Personal Agent"
    )
    create_agent_program!(
      installation: installation,
      visibility: "personal",
      owner_user: other_user,
      key: "other-users-agent",
      display_name: "Other Users Agent"
    )
    create_agent_program!(
      installation: installation,
      visibility: "global",
      lifecycle_state: "retired",
      key: "retired-agent",
      display_name: "Retired Agent"
    )
    result = AgentPrograms::VisibleToUserQuery.call(user: user)

    assert_equal [shared_agent, personal_agent], result
  end
end
