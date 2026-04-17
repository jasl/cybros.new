require "test_helper"

class PollingTest < CoreMatrixCLITestCase
  def test_until_returns_when_stop_condition_matches
    clock_values = [0.0]
    sleeper_calls = []
    attempts = 0

    result = CoreMatrixCLI::Support::Polling.until(
      timeout: 10,
      interval: 2,
      stop_on: ->(payload) { payload[:state] == "authorized" },
      clock: -> { clock_values.last },
      sleeper: ->(interval) do
        sleeper_calls << interval
        clock_values << clock_values.last + interval
      end
    ) do
      attempts += 1
      { state: attempts == 2 ? "authorized" : "pending" }
    end

    assert_equal({ state: "authorized" }, result)
    assert_equal [2], sleeper_calls
  end

  def test_until_returns_last_result_on_timeout
    current_time = 0.0
    sleeper_calls = []

    result = CoreMatrixCLI::Support::Polling.until(
      timeout: 3,
      interval: 1,
      stop_on: ->(_payload) { false },
      clock: -> { current_time },
      sleeper: ->(interval) do
        sleeper_calls << interval
        current_time += interval
      end
    ) do
      { state: "pending", observed_at: current_time }
    end

    assert_equal({ state: "pending", observed_at: 3.0 }, result)
    assert_equal [1, 1, 1], sleeper_calls
  end
end
