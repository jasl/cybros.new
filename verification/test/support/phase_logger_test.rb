require_relative "../test_helper"
require "stringio"
require "verification/support/phase_logger"

class Verification::PhaseLoggerTest < ActiveSupport::TestCase
  test "phase logger writes timestamped markers to stdout and artifact log" do
    Dir.mktmpdir("phase-logger") do |tmpdir|
      io = StringIO.new
      log_path = Pathname.new(tmpdir).join("logs", "phase.log")
      logger = Verification::PhaseLogger.build(
        io: io,
        log_path: log_path,
        clock: -> { Time.utc(2026, 4, 18, 0, 0, 0) }
      )

      logger.call("turn completed", turn_id: "turn_123")
      logger.call("conversation export started")

      stdout = io.string
      file_log = log_path.read

      assert_includes stdout, "[verification][phase] 2026-04-18T00:00:00Z turn completed"
      assert_includes stdout, '{"turn_id":"turn_123"}'
      assert_includes stdout, "conversation export started"
      assert_equal stdout, file_log
    end
  end
end
