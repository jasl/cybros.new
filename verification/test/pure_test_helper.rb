require "minitest/autorun"
require "pathname"

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

module VerificationPureTestHelper
  module_function

  def verification_root
    Pathname.new(__dir__).join("..").expand_path
  end

  def repo_root
    verification_root.join("..").expand_path
  end
end
