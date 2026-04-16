module CoreMatrixCLI
  module Polling
    def self.until(timeout:, interval:, stop_on:)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      last_result = nil

      loop do
        last_result = yield
        return last_result if stop_on.call(last_result)
        return last_result if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at >= timeout

        sleep(interval)
      end
    end
  end
end
