require "test_helper"

class InvitationTest < ActiveSupport::TestCase
  test "attaches plaintext token explicitly" do
    invitation = Invitation.new

    assert_equal invitation, invitation.attach_plaintext_token("plaintext-token")
    assert_equal "plaintext-token", invitation.plaintext_token
  end

  test "generates and resolves a public id" do
    installation = create_installation!
    inviter = create_user!(installation: installation, role: "admin")
    invitation = Invitation.issue!(
      installation: installation,
      inviter: inviter,
      email: "invitee@example.com",
      expires_at: 2.days.from_now
    )

    assert invitation.public_id.present?
    assert_equal invitation, Invitation.find_by_public_id!(invitation.public_id)
  end

  test "issues unique tokens and stores digests" do
    installation = create_installation!
    inviter = create_user!(installation: installation, role: "admin")

    invitation_one = Invitation.issue!(
      installation: installation,
      inviter: inviter,
      email: "invitee-one@example.com",
      expires_at: 2.days.from_now
    )
    invitation_two = Invitation.issue!(
      installation: installation,
      inviter: inviter,
      email: "invitee-two@example.com",
      expires_at: 2.days.from_now
    )

    assert invitation_one.matches_token?(invitation_one.plaintext_token)
    assert invitation_two.matches_token?(invitation_two.plaintext_token)
    assert_not_equal invitation_one.plaintext_token, invitation_two.plaintext_token
    assert_not_equal invitation_one.token_digest, invitation_two.token_digest
  end

  test "tracks expiration and consumption" do
    installation = create_installation!
    inviter = create_user!(installation: installation, role: "admin")
    invitation = Invitation.issue!(
      installation: installation,
      inviter: inviter,
      email: "invitee@example.com",
      expires_at: 1.day.from_now
    )

    assert invitation.active?

    travel_to 2.days.from_now do
      assert invitation.expired?
      assert_not invitation.active?
    end

    invitation.consume!

    assert invitation.consumed?
    assert_not invitation.active?
  end
end
