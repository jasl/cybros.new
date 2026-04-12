require "test_helper"

class OnboardingSessionTest < ActiveSupport::TestCase
  test "attaches plaintext token explicitly" do
    onboarding_session = OnboardingSession.new

    assert_equal onboarding_session, onboarding_session.attach_plaintext_token("plaintext-token")
    assert_equal "plaintext-token", onboarding_session.plaintext_token
  end

  test "tracks onboarding-session lifecycle" do
    onboarding_session = create_onboarding_session!(expires_at: 1.hour.from_now)

    assert onboarding_session.matches_token?(onboarding_session.plaintext_token)
    assert onboarding_session.active?

    travel_to 61.minutes.from_now do
      assert onboarding_session.expired?
      assert_not onboarding_session.active?
    end

    onboarding_session.update!(expires_at: 1.hour.from_now, runtime_registered_at: Time.current, agent_registered_at: Time.current)
    assert onboarding_session.active?

    onboarding_session.close!
    assert_not onboarding_session.active?
  end

  test "allows runtime onboarding sessions without an agent target" do
    installation = create_installation!
    runtime = create_execution_runtime!(installation: installation)

    onboarding_session = create_onboarding_session!(
      installation: installation,
      target_kind: "execution_runtime",
      target: runtime
    )

    assert_equal "execution_runtime", onboarding_session.target_kind
    assert_nil onboarding_session.target_agent
    assert_equal runtime, onboarding_session.target_execution_runtime
  end
end
