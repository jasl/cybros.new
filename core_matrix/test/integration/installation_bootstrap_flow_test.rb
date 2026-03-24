require "test_helper"

class InstallationBootstrapFlowTest < ActionDispatch::IntegrationTest
  test "bootstraps the installation and manages invited admin changes" do
    bootstrap = Installations::BootstrapFirstAdmin.call(
      name: "Primary Installation",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin"
    )

    assert_equal 1, Installation.count
    assert bootstrap.user.admin?

    assert_raises(Installations::BootstrapFirstAdmin::AlreadyBootstrapped) do
      Installations::BootstrapFirstAdmin.call(
        name: "Secondary Installation",
        email: "secondary@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        display_name: "Secondary Admin"
      )
    end

    invitation = Invitation.issue!(
      installation: bootstrap.installation,
      inviter: bootstrap.user,
      email: "member@example.com",
      expires_at: 2.days.from_now
    )

    consume = Invitations::Consume.call(
      token: invitation.plaintext_token,
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Member"
    )

    assert consume.user.member?

    Users::GrantAdmin.call(user: consume.user, actor: bootstrap.user)
    assert consume.user.reload.admin?

    Users::RevokeAdmin.call(user: consume.user, actor: bootstrap.user)
    assert consume.user.reload.member?

    assert_equal 1, AuditLog.where(action: "installation.bootstrapped").count
    assert_equal 1, AuditLog.where(action: "invitation.consumed").count
    assert_equal 1, AuditLog.where(action: "user.admin_granted").count
    assert_equal 1, AuditLog.where(action: "user.admin_revoked").count
  end
end
