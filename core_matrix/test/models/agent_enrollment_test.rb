require "test_helper"

class AgentEnrollmentTest < ActiveSupport::TestCase
  test "attaches plaintext token explicitly" do
    enrollment = AgentEnrollment.new

    assert_equal enrollment, enrollment.attach_plaintext_token("plaintext-token")
    assert_equal "plaintext-token", enrollment.plaintext_token
  end

  test "tracks token lifecycle" do
    installation = create_installation!
    agent_installation = create_agent_installation!(installation: installation)

    enrollment = AgentEnrollment.issue!(
      installation: installation,
      agent_installation: agent_installation,
      expires_at: 1.hour.from_now
    )

    assert enrollment.matches_token?(enrollment.plaintext_token)
    assert enrollment.active?

    travel_to 61.minutes.from_now do
      assert enrollment.expired?
      assert_not enrollment.active?
    end

    enrollment.update!(expires_at: 1.hour.from_now)
    enrollment.consume!

    assert enrollment.consumed?
    assert_not enrollment.active?
  end
end
