module Fenix
  module Plugins
    class Catalog
      attr_reader :manifests

      def initialize(manifests:)
        @manifests = manifests
      end

      def tool_catalog
        @tool_catalog ||= decorate(manifests.flat_map(&:tool_catalog))
      end

      def executor_tool_catalog
        @executor_tool_catalog ||= decorate(manifests.select(&:executor_plane?).flat_map(&:tool_catalog)).map do |entry|
          entry.merge(
            "tool_kind" => "executor_program",
            "implementation_source" => "executor_program"
          )
        end
      end

      def program_tool_catalog
        @program_tool_catalog ||= decorate(manifests.select(&:program_plane?).flat_map(&:tool_catalog))
      end

      def executor_tool_names
        executor_tool_catalog.map { |entry| entry.fetch("tool_name") }
      end

      private

      def decorate(entries)
        entries.map { |entry| Fenix::Operator::Catalog.decorate_tool_entry(entry) }
      end
    end
  end
end
