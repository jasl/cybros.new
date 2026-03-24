require "test_helper"

module Installations
end

class Installations::BootstrapFirstAdminTest < ActiveSupport::TestCase
  test "bootstraps the first installation admin identity and audit log" do
    result = Installations::BootstrapFirstAdmin.call(
      name: "Primary Installation",
      email: " ADMIN@example.com ",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin"
    )

    assert_equal 1, Installation.count
    assert_equal 1, Identity.count
    assert_equal 1, User.count
    assert_equal "bootstrapped", result.installation.bootstrap_state
    assert_equal "admin@example.com", result.identity.email
    assert result.user.admin?

    audit_log = AuditLog.find_by!(action: "installation.bootstrapped")
    assert_equal result.user, audit_log.actor
    assert_equal result.installation, audit_log.subject
  end

  test "rejects a second bootstrap attempt" do
    Installations::BootstrapFirstAdmin.call(
      name: "Primary Installation",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin"
    )

    assert_raises(Installations::BootstrapFirstAdmin::AlreadyBootstrapped) do
      Installations::BootstrapFirstAdmin.call(
        name: "Another Installation",
        email: "second@example.com",
        password: "Password123!",
        password_confirmation: "Password123!",
        display_name: "Second Admin"
      )
    end
  end
end
