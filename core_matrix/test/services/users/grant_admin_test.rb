require "test_helper"

module Users
end

class Users::GrantAdminTest < ActiveSupport::TestCase
  test "promotes a member to admin and writes an audit log" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    target = create_user!(installation: installation, role: "member")

    Users::GrantAdmin.call(user: target, actor: actor)

    assert target.reload.admin?

    audit_log = AuditLog.find_by!(action: "user.admin_granted")
    assert_equal actor, audit_log.actor
    assert_equal target, audit_log.subject
  end
end
