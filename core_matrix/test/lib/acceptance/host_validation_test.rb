require "test_helper"
require Rails.root.join("../acceptance/lib/host_validation")

class AcceptanceHostValidationTest < ActiveSupport::TestCase
  test "runtime and host validation predicates require the expected success conditions" do
    runtime_validation = {
      "runtime_test_passed" => true,
      "runtime_build_passed" => true,
      "runtime_dev_server_ready" => true,
      "runtime_browser_loaded" => true,
      "runtime_browser_mentions_2048" => true,
    }
    host_validation = {
      "npm_install" => { "success" => true },
      "npm_test" => { "success" => true },
      "npm_build" => { "success" => true },
      "preview_http" => { "status" => 200 },
    }
    playwright_validation = { "result" => { "restartResetScore" => true } }

    assert Acceptance::HostValidation.runtime_validation_passed?(runtime_validation)
    assert Acceptance::HostValidation.host_validation_passed?(host_validation:, playwright_validation:)

    runtime_validation["runtime_browser_mentions_2048"] = false
    host_validation["npm_build"]["success"] = false

    refute Acceptance::HostValidation.runtime_validation_passed?(runtime_validation)
    refute Acceptance::HostValidation.host_validation_passed?(host_validation:, playwright_validation:)
  end

  test "run! records missing generated app paths as a skip and still writes review artifacts" do
    Dir.mktmpdir do |dir|
      artifact_dir = Pathname(dir)
      generated_app_dir = artifact_dir.join("missing-app")
      runtime_validation = {
        "runtime_test_passed" => true,
        "runtime_build_passed" => true,
        "runtime_dev_server_ready" => true,
        "runtime_browser_loaded" => true,
        "runtime_browser_mentions_2048" => true,
        "runtime_browser_content_excerpt" => "2048 ready",
      }

      result = Acceptance::HostValidation.run!(
        generated_app_dir: generated_app_dir,
        artifact_dir: artifact_dir,
        preview_port: 4174,
        runtime_validation: runtime_validation,
        persist_artifacts: true
      )

      assert_equal "Generated application path was missing.", result.fetch("host_playability_skip_reason")
      assert_equal({}, result.fetch("host_validation"))
      assert_equal({}, result.fetch("playwright_validation"))
      assert_equal false, result.fetch("dist_artifact_present")
      assert_equal [], result.fetch("host_validation_notes")
      assert artifact_dir.join("workspace-validation.md").exist?
      assert artifact_dir.join("playability-verification.md").exist?
      assert_includes artifact_dir.join("workspace-validation.md").read, generated_app_dir.to_s
      assert_includes artifact_dir.join("playability-verification.md").read, "Generated application path was missing."
    end
  end
end
