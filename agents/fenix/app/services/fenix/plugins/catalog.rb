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

      def environment_tool_catalog
        @environment_tool_catalog ||= decorate(manifests.select(&:environment_plane?).flat_map(&:tool_catalog))
      end

      def agent_tool_catalog
        @agent_tool_catalog ||= decorate(manifests.select(&:agent_plane?).flat_map(&:tool_catalog))
      end

      def environment_tool_names
        environment_tool_catalog.map { |entry| entry.fetch("tool_name") }
      end

      private

      def decorate(entries)
        entries.map { |entry| Fenix::Operator::Catalog.decorate_tool_entry(entry) }
      end
    end
  end
end
