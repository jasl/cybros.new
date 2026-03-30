module Fenix
  module Plugins
    class Catalog
      attr_reader :manifests

      def initialize(manifests:)
        @manifests = manifests
      end

      def tool_catalog
        manifests.flat_map(&:tool_catalog)
      end

      def environment_tool_catalog
        manifests.select(&:environment_plane?).flat_map(&:tool_catalog)
      end

      def agent_tool_catalog
        manifests.select(&:agent_plane?).flat_map(&:tool_catalog)
      end

      def environment_tool_names
        environment_tool_catalog.map { |entry| entry.fetch("tool_name") }
      end
    end
  end
end
