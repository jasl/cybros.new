require_relative "test_helper"

class VerificationProjectShellSmokeTest < Minitest::Test
  def test_verification_namespace_is_available
    assert defined?(Verification), "expected Verification to be defined"
    refute defined?(Rails), "expected pure verification boot to stay outside Rails"
  end
end
