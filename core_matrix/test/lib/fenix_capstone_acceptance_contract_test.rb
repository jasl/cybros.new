require "test_helper"

class FenixCapstoneAcceptanceContractTest < ActiveSupport::TestCase
  test "host playability script treats hyphenated game-over status as terminal" do
    script = Rails.root.join("script/manual/acceptance/fenix_capstone_app_api_roundtrip_validation.rb").read

    assert_includes script, "/game(?:\\s|-)?over/i",
      "expected host playability verification to accept both 'game over' and 'game-over' status text"
  end
end
