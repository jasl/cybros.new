require_relative "../test_helper"

class VerificationManualSupportContractTest < ActiveSupport::TestCase
  test "verification boot does not load manual support directly" do
    boot = Verification.repo_root.join("verification", "lib", "verification", "boot.rb").read

    refute_includes boot, "require_relative 'suites/e2e/manual_support'"
    refute_includes boot, "core_matrix/script/manual/"
  end

  test "core matrix hosted loader loads manual support from a verification-owned helper" do
    loader = Verification.repo_root.join("verification", "lib", "verification", "hosted", "core_matrix.rb").read

    assert_includes loader, 'require_relative "../suites/e2e/manual_support"'
  end
end
