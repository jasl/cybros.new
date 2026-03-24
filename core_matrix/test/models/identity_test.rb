require "test_helper"

class IdentityTest < ActiveSupport::TestCase
  test "normalizes email and enforces uniqueness" do
    identity = Identity.create!(
      email: " ADMIN@example.COM ",
      password: "Password123!",
      password_confirmation: "Password123!",
      auth_metadata: {}
    )

    assert_equal "admin@example.com", identity.email

    duplicate = Identity.new(
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      auth_metadata: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:email], "has already been taken"
  end

  test "requires password on create and authenticates it" do
    identity = Identity.new(email: unique_email, auth_metadata: {})

    assert_not identity.valid?
    assert_includes identity.errors[:password], "can't be blank"

    identity.password = "Password123!"
    identity.password_confirmation = "Password123!"

    assert identity.valid?
    identity.save!

    assert_equal identity, identity.authenticate("Password123!")
    assert_not identity.authenticate("not-the-password")
  end

  test "reports disabled state from disabled_at" do
    identity = create_identity!

    assert_not identity.disabled?

    identity.update!(disabled_at: Time.current)

    assert identity.disabled?
  end
end
