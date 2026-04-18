require_relative "../../test_helper"
require "verification/support/host_validation"
require "verification/support/phase_logger"

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

  test "host playwright verification emits phase markers for long-running steps" do
    Dir.mktmpdir("host-validation") do |tmpdir|
      root = Pathname.new(tmpdir)
      artifact_dir = root.join("artifacts")
      generated_app_dir = root.join("generated-app")
      commands_run = []
      emitted_phases = []

      artifact_dir.mkpath
      generated_app_dir.mkpath

      logger = Verification::PhaseLogger.build(
        io: StringIO.new,
        log_path: artifact_dir.join("logs", "phase.log"),
        clock: -> { Time.utc(2026, 4, 18, 0, 0, 0) }
      )

      host_validation_singleton = Verification::HostValidation.singleton_class
      host_validation_singleton.alias_method :__original_capture_command_for_phase_test, :capture_command
      host_validation_singleton.alias_method :__original_capture_command_bang_for_phase_test, :capture_command!

      host_validation_singleton.define_method(:capture_command!) do |*command, **kwargs|
        commands_run << command.join(" ")
        { "command" => command.join(" "), "success" => true, "stdout" => "", "stderr" => "", "exit_status" => 0 }
      end

      host_validation_singleton.define_method(:capture_command) do |*command, **kwargs|
        FileUtils.mkdir_p(artifact_dir.join("playable"))
        File.write(artifact_dir.join("playable", "host-playwright-verification.json"), JSON.generate({ "mergeObserved" => true }))
        commands_run << command.join(" ")
        { "command" => command.join(" "), "success" => true, "stdout" => "", "stderr" => "", "exit_status" => 0 }
      end

      Verification::HostValidation.send(
        :run_host_playwright_verification!,
        artifact_dir: artifact_dir,
        base_url: "http://127.0.0.1:4274/",
        generated_app_dir: generated_app_dir,
        phase_logger: lambda { |phase, details = {}| emitted_phases << phase; logger.call(phase, details) }
      )

      assert_equal(
        [
          "playwright dependency install started",
          "playwright browser install started",
          "playwright verification started",
        ],
        emitted_phases
      )
      assert_equal 3, commands_run.length
    ensure
      if host_validation_singleton.method_defined?(:__original_capture_command_for_phase_test)
        host_validation_singleton.alias_method :capture_command, :__original_capture_command_for_phase_test
        host_validation_singleton.remove_method :__original_capture_command_for_phase_test
      end
      if host_validation_singleton.method_defined?(:__original_capture_command_bang_for_phase_test)
        host_validation_singleton.alias_method :capture_command!, :__original_capture_command_bang_for_phase_test
        host_validation_singleton.remove_method :__original_capture_command_bang_for_phase_test
      end
    end
  end
end
