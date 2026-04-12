require "test_helper"

class AppSurface::Policies::OnboardingSessionAccessTest < ActiveSupport::TestCase
  test "allows an admin from the same installation to access an onboarding session" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    onboarding_session = create_onboarding_session!(
      installation: installation,
      issued_by_user: admin
    )

    assert AppSurface::Policies::OnboardingSessionAccess.call(
      user: admin,
      onboarding_session: onboarding_session
    )
  end

  test "denies a non-admin from the same installation" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")
    member = create_user!(
      installation: installation,
      identity: create_identity!,
      role: "member",
      display_name: "Member"
    )
    onboarding_session = create_onboarding_session!(
      installation: installation,
      issued_by_user: admin
    )

    assert_not AppSurface::Policies::OnboardingSessionAccess.call(
      user: member,
      onboarding_session: onboarding_session
    )
  end

  test "denies an admin from another installation" do
    onboarding_session = create_onboarding_session!
    foreign_admin = User.new(
      installation_id: onboarding_session.installation_id + 1,
      identity: create_identity!,
      role: "admin",
      display_name: "Foreign Admin",
      preferences: {}
    )

    assert_not AppSurface::Policies::OnboardingSessionAccess.call(
      user: foreign_admin,
      onboarding_session: onboarding_session
    )
  end
end
