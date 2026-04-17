require_relative "../../test_helper"
require "verification/support/host_validation"

class VerificationHostValidationTest < ActiveSupport::TestCase
  test "host preview verification creates the logs directory before opening the preview log" do
    Dir.mktmpdir("host-validation") do |tmpdir|
      root = Pathname.new(tmpdir)
      dist_dir = root.join("dist")
      artifact_dir = root.join("artifacts")
      generated_app_dir = root.join("generated-app")

      dist_dir.mkpath
      artifact_dir.mkpath
      generated_app_dir.mkpath
      dist_dir.join("index.html").write("<!doctype html><title>2048</title>")

      host_validation_singleton = Verification::HostValidation.singleton_class
      host_validation_singleton.alias_method :__original_run_host_playwright_verification_for_test, :run_host_playwright_verification!
      host_validation_singleton.define_method(:run_host_playwright_verification!) do |**|
        { "test" => { "success" => true }, "result" => {} }
      end

      result = Verification::HostValidation.send(
        :run_host_preview_and_verification!,
        dist_dir: dist_dir,
        artifact_dir: artifact_dir,
        generated_app_dir: generated_app_dir,
        preview_port: 4274
      )

      assert_equal 200, result.fetch("preview_http").fetch("status")
      assert artifact_dir.join("logs", "host-preview.log").exist?
    ensure
      if host_validation_singleton.method_defined?(:__original_run_host_playwright_verification_for_test)
        host_validation_singleton.alias_method :run_host_playwright_verification!, :__original_run_host_playwright_verification_for_test
        host_validation_singleton.remove_method :__original_run_host_playwright_verification_for_test
      end
    end
  end
end
