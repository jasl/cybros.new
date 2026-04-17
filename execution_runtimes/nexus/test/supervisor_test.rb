require "test_helper"

class SupervisorTest < Minitest::Test
  def test_restarts_crashed_role
    starts = Queue.new
    backoff_calls = []
    attempts = 0

    supervisor = CybrosNexus::Supervisor.new(
      roles: {
        control: lambda do |context|
          attempts += 1
          starts << attempts

          raise "boom" if attempts == 1

          sleep 0.01 until context.stopping?
        end,
      },
      sleep_strategy: lambda do |seconds|
        backoff_calls << seconds
      end
    )

    thread = Thread.new { supervisor.run }

    assert_equal 1, starts.pop
    assert_equal 2, starts.pop

    supervisor.request_stop
    assert thread.join(1), "expected supervisor to stop"
    assert_equal [0.1], backoff_calls
  end

  def test_sigterm_stops_supervisor_cleanly
    handlers = {}
    started = Queue.new

    supervisor = CybrosNexus::Supervisor.new(
      roles: {
        control: lambda do |context|
          started << true
          sleep 0.01 until context.stopping?
        end,
      },
      signal_trap: lambda do |signal, &handler|
        handlers[signal] = handler
      end
    )

    thread = Thread.new { supervisor.run }
    started.pop

    handlers.fetch("TERM").call

    assert thread.join(1), "expected supervisor to stop"
    assert_predicate supervisor, :stopping?
  end
end
