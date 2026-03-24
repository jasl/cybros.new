require "test_helper"

module Invitations
end

class Invitations::ConsumeTest < ActiveSupport::TestCase
  test "consumes an invitation by creating identity user and audit log" do
    installation = create_installation!
    inviter = create_user!(installation: installation, role: "admin")
    invitation = Invitation.issue!(
      installation: installation,
      inviter: inviter,
      email: "invitee@example.com",
      expires_at: 1.day.from_now
    )

    result = Invitations::Consume.call(
      token: invitation.plaintext_token,
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Invitee"
    )

    assert_equal installation, result.user.installation
    assert_equal result.identity, result.user.identity
    assert_equal "invitee@example.com", result.identity.email
    assert result.invitation.reload.consumed?

    audit_log = AuditLog.find_by!(action: "invitation.consumed")
    assert_equal result.user, audit_log.actor
    assert_equal invitation, audit_log.subject
  end

  test "rejects expired invitations" do
    installation = create_installation!
    inviter = create_user!(installation: installation, role: "admin")
    invitation = Invitation.issue!(
      installation: installation,
      inviter: inviter,
      email: "invitee@example.com",
      expires_at: 30.minutes.from_now
    )

    travel_to 31.minutes.from_now do
      assert_raises(Invitations::Consume::ExpiredInvitation) do
        Invitations::Consume.call(
          token: invitation.plaintext_token,
          password: "Password123!",
          password_confirmation: "Password123!",
          display_name: "Invitee"
        )
      end
    end
  end
end
