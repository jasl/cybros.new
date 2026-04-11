require "test_helper"

module Agents
end

class Agents::VisibleToUserQueryTest < ActiveSupport::TestCase
  test "returns active public agents plus the current users private agents" do
    installation = create_installation!
    user = create_user!(installation: installation, display_name: "Owner")
    other_user = create_user!(
      installation: installation,
      identity: create_identity!,
      display_name: "Other"
    )
    public_agent = create_agent!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      key: "public-agent",
      display_name: "Public Agent"
    )
    private_agent = create_agent!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: user,
      key: "private-agent",
      display_name: "Private Agent"
    )
    create_agent!(
      installation: installation,
      visibility: "private",
      provisioning_origin: "user_created",
      owner_user: other_user,
      key: "other-users-agent",
      display_name: "Other Users Agent"
    )
    create_agent!(
      installation: installation,
      visibility: "public",
      provisioning_origin: "system",
      lifecycle_state: "retired",
      key: "retired-agent",
      display_name: "Retired Agent"
    )
    result = Agents::VisibleToUserQuery.call(user: user)

    assert_equal [public_agent, private_agent], result
  end
end
