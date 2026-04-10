require "test_helper"

class AcceptanceManualSupportContractTest < ActiveSupport::TestCase
  test "acceptance boot loads manual support from acceptance-owned helper" do
    boot = Rails.root.join("../acceptance/lib/boot.rb").read

    assert_includes boot, "require_relative 'manual_support'"
    refute_includes boot, "core_matrix/script/manual/manual_acceptance_support"
  end

  test "acceptance-owned manual support helper is loadable" do
    helper_path = Rails.root.join("../acceptance/lib/manual_support.rb")

    assert helper_path.exist?, "expected acceptance-owned manual support helper to exist"

    require helper_path.to_s

    assert defined?(Acceptance::ManualSupport)
  end
end
