require "test_helper"

class AppSurface::Policies::AdminAccessTest < ActiveSupport::TestCase
  test "allows an admin user for their own installation" do
    installation = create_installation!
    admin = create_user!(installation: installation, role: "admin")

    assert AppSurface::Policies::AdminAccess.call(user: admin, installation: installation)
  end

  test "denies a non-admin user" do
    installation = create_installation!
    member = create_user!(installation: installation, role: "member")

    assert_not AppSurface::Policies::AdminAccess.call(user: member, installation: installation)
  end

  test "denies an admin from another installation" do
    installation = create_installation!
    foreign_admin = User.new(
      installation_id: installation.id + 1,
      identity: create_identity!,
      role: "admin",
      display_name: "Foreign Admin",
      preferences: {}
    )

    assert_not AppSurface::Policies::AdminAccess.call(user: foreign_admin, installation: installation)
  end
end
