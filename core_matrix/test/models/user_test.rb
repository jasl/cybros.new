require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "reflects member and admin role state" do
    user = create_user!(role: "member")

    assert user.member?
    assert_not user.admin?

    user.admin!

    assert user.admin?
    assert_not user.member?
  end

  test "counts only users with enabled identities as active admins" do
    installation = create_installation!
    enabled_admin = create_user!(installation: installation, role: "admin")
    disabled_identity = create_identity!(disabled_at: Time.current)
    create_user!(installation: installation, identity: disabled_identity, role: "admin")

    assert_equal [enabled_admin.id], User.active_admins.pluck(:id)
  end
end
