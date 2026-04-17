module CoreMatrixCLI
  module Support
    module Polling
      DEFAULT_CLOCK = -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
      DEFAULT_SLEEPER = ->(interval) { sleep(interval) }

      def self.until(timeout:, interval:, stop_on:, clock: DEFAULT_CLOCK, sleeper: DEFAULT_SLEEPER)
        started_at = clock.call
        last_result = nil

        loop do
          last_result = yield
          return last_result if stop_on.call(last_result)
          return last_result if clock.call - started_at >= timeout

          sleeper.call(interval)
        end
      end
    end
  end
end
