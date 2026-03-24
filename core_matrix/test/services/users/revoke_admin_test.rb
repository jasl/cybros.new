require "test_helper"

module Users
end

class Users::RevokeAdminTest < ActiveSupport::TestCase
  test "demotes an admin and writes an audit log when another active admin exists" do
    installation = create_installation!
    actor = create_user!(installation: installation, role: "admin")
    target = create_user!(installation: installation, role: "admin")

    Users::RevokeAdmin.call(user: target, actor: actor)

    assert target.reload.member?

    audit_log = AuditLog.find_by!(action: "user.admin_revoked")
    assert_equal actor, audit_log.actor
    assert_equal target, audit_log.subject
  end

  test "forbids revoking the last active admin" do
    installation = create_installation!
    only_admin = create_user!(installation: installation, role: "admin")
    disabled_identity = create_identity!(disabled_at: Time.current)
    create_user!(installation: installation, identity: disabled_identity, role: "admin")

    assert_raises(Users::RevokeAdmin::LastAdminError) do
      Users::RevokeAdmin.call(user: only_admin, actor: only_admin)
    end

    assert only_admin.reload.admin?
  end
end
