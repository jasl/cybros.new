require "json"
require "pathname"
require "time"

module Verification
  module Perf
    class EventReader
      def self.read(paths:)
        Array(paths)
          .flat_map { |path| read_file(path) }
          .sort_by { |event| Time.iso8601(event.fetch("recorded_at")) }
      end

      def self.read_file(path)
        Pathname(path).read.each_line.filter_map do |line|
          stripped = line.strip
          next if stripped.empty?

          JSON.parse(stripped)
        end
      end
      private_class_method :read_file
    end
  end
end
