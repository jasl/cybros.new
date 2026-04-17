require_relative "../pure_test_helper"
require "open3"
require "rbconfig"

class VerificationRuntimeBoundaryContractTest < Minitest::Test
  def test_verification_gemfile_does_not_inherit_core_matrix_bundle
    gemfile = VerificationPureTestHelper.verification_root.join("Gemfile").read

    refute_includes gemfile, "eval_gemfile"
  end

  def test_pure_boot_does_not_default_bundle_gemfile_to_core_matrix
    boot = VerificationPureTestHelper.verification_root.join("lib", "verification", "boot.rb").read

    refute_includes boot, "BUNDLE_GEMFILE"
  end

  def test_test_helper_does_not_require_core_matrix_test_helper
    test_helper = VerificationPureTestHelper.verification_root.join("test", "test_helper.rb").read

    refute_includes test_helper, "core_matrix/test/test_helper"
  end

  def test_verification_entrypoint_does_not_eager_load_hosted_helpers
    verification = VerificationPureTestHelper.verification_root.join("lib", "verification.rb").read

    refute_includes verification, "manual_support"
    refute_includes verification, "governed_validation_support"
    refute_includes verification, "capstone_review_artifacts"
  end

  def test_require_verification_does_not_load_rails
    stdout, stderr, status = Open3.capture3(
      {
        "BUNDLE_GEMFILE" => VerificationPureTestHelper.verification_root.join("Gemfile").to_s,
      },
      RbConfig.ruby,
      "-I#{VerificationPureTestHelper.verification_root.join('lib')}",
      "-e",
      'require "verification"; puts(defined?(Rails) ? "RAILS" : "NO_RAILS")'
    )

    assert status.success?, stderr
    assert_equal "NO_RAILS", stdout.strip
  end

  def test_core_matrix_hosted_loader_exists
    loader = VerificationPureTestHelper.verification_root.join("lib", "verification", "hosted", "core_matrix.rb")

    assert loader.exist?, "expected explicit CoreMatrix-hosted loader to exist"
  end
end
