require "test_helper"

class InstallationTest < ActiveSupport::TestCase
  test "only allows a single installation row" do
    Installation.create!(
      name: "Primary",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )

    duplicate = Installation.new(
      name: "Secondary",
      bootstrap_state: "pending",
      global_settings: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:base], "installation already exists"
  end
end
