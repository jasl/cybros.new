require "yaml"

module Fenix
  module Plugins
    class Manifest
      attr_reader :plugin_id, :version, :display_name, :default_runtime_plane,
        :tool_catalog, :config_schema, :requirements, :env_contract,
        :healthcheck, :bootstrap, :source_path

      def self.load(pathname)
        payload = YAML.safe_load(pathname.read, aliases: false) || {}
        new(payload:, source_path: pathname)
      end

      def initialize(payload:, source_path:)
        @plugin_id = payload.fetch("plugin_id")
        @version = payload.fetch("version")
        @display_name = payload.fetch("display_name")
        @default_runtime_plane = payload.fetch("default_runtime_plane")
        @tool_catalog = Array(payload.fetch("tool_catalog", [])).map(&:deep_stringify_keys)
        @config_schema = payload.fetch("config_schema", {})
        @requirements = payload.fetch("requirements", {})
        @env_contract = payload.fetch("env_contract", {})
        @healthcheck = payload["healthcheck"]
        @bootstrap = payload["bootstrap"]
        @source_path = source_path.to_s
      end

      def execution_plane?
        default_runtime_plane == "execution"
      end

      def program_plane?
        default_runtime_plane == "program"
      end
    end
  end
end
