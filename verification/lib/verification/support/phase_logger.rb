require "fileutils"
require "json"
require "time"

module Verification
  module PhaseLogger
    module_function

    def build(io: $stdout, log_path: nil, clock: -> { Time.now.utc })
      lambda do |phase, details = {}|
        timestamp = clock.call.utc.iso8601
        normalized_details = details.to_h.reject { |_key, value| value.nil? }
        line = "[verification][phase] #{timestamp} #{phase}"
        line = "#{line} #{JSON.generate(normalized_details)}" if normalized_details.any?

        io.puts(line)
        io.flush if io.respond_to?(:flush)

        next if log_path.nil?

        FileUtils.mkdir_p(File.dirname(log_path.to_s))
        File.open(log_path.to_s, "a") do |file|
          file.puts(line)
        end
      end
    end
  end
end
