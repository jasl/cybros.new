require "test_helper"

module AppSurface
  module Presenters
  end
end

class AppSurface::Presenters::OnboardingSessionPresenterTest < ActiveSupport::TestCase
  test "emits only public ids and stable onboarding session fields" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    agent = create_agent!(installation: installation)
    onboarding_session = create_onboarding_session!(
      installation: installation,
      target_kind: "agent",
      target: agent,
      issued_by_user: admin
    )

    payload = AppSurface::Presenters::OnboardingSessionPresenter.call(onboarding_session: onboarding_session)

    assert_equal onboarding_session.public_id, payload.fetch("onboarding_session_id")
    assert_equal "agent", payload.fetch("target_kind")
    assert_equal agent.public_id, payload.fetch("target_agent_id")
    assert_equal admin.public_id, payload.fetch("issued_by_user_id")
    assert_equal onboarding_session.status, payload.fetch("status")
    refute_includes payload.to_json, %("#{onboarding_session.id}")
  end
end
