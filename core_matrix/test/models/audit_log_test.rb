require "test_helper"

class AuditLogTest < ActiveSupport::TestCase
  test "requires paired actor and subject identifiers" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    subject = Invitation.issue!(
      installation: installation,
      inviter: actor,
      email: "invitee@example.com",
      expires_at: 1.day.from_now
    )

    log = AuditLog.new(
      installation: installation,
      actor: actor,
      action: "invitation.consumed",
      subject: subject,
      metadata: { source: "test" }
    )

    assert log.valid?

    broken = AuditLog.new(
      installation: installation,
      actor_id: actor.id,
      action: "invitation.consumed",
      metadata: {}
    )

    assert_not broken.valid?
    assert_includes broken.errors[:actor], "must include both type and id"
  end
end
