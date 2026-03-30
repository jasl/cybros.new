module Fenix
  module Plugins
    class Registry
      def self.default(workspace_root: ENV.fetch("FENIX_WORKSPACE_ROOT", "/workspace"))
        new(plugin_roots: default_plugin_roots(workspace_root:))
      end

      def self.default_plugin_roots(workspace_root:)
        [
          Rails.root.join("app/services/fenix/plugins/system"),
          Rails.root.join("app/services/fenix/plugins/curated"),
          Pathname.new(workspace_root).join(".fenix/plugins"),
        ]
      end

      attr_reader :plugin_roots

      def initialize(plugin_roots:)
        @plugin_roots = plugin_roots.map { |root| Pathname.new(root) }
      end

      def manifests
        @manifests ||= manifest_paths.map { |path| Manifest.load(path) }
      end

      def catalog
        @catalog ||= Catalog.new(manifests:)
      end

      private

      def manifest_paths
        plugin_roots.flat_map do |root|
          next [] unless root.directory?

          root.glob("*/plugin.yml").sort
        end
      end
    end
  end
end
