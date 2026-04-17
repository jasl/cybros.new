# frozen_string_literal: true

require "pathname"

module Verification
  module Perf
    class RuntimeSlot
      class << self
        def build(index:, run_slug:, repo_root:, verification_root:, artifact_stamp:, runtime_host: "127.0.0.1", runtime_scheme: "http", runtime_base_port: 3201, proxy_base_port: 3410, container_prefix: "nexus-load")
          repo_root = Pathname.new(repo_root.to_s)
          verification_root = Pathname.new(verification_root.to_s)
          label = format("nexus-%<index>02d", index: index)
          runtime_port = runtime_base_port + index - 1
          slot_suffix = format("%02d", index)
          container_stem = "#{container_prefix}-#{run_slug}-#{slot_suffix}"
          slot_root = repo_root.join("tmp", "multi-agent-runtime-core-matrix-load", run_slug, label)

          new(
            index: index,
            label: label,
            runtime_base_url: "#{runtime_scheme}://#{runtime_host}:#{runtime_port}",
            proxy_port: proxy_base_port + index - 1,
            home_root: slot_root.join("home"),
            docker_workspace_root: slot_root.join("workspace"),
            event_output_path: verification_root.join("artifacts", artifact_stamp, "evidence", "#{label}-events.ndjson"),
            runtime_boot_json_path: verification_root.join("artifacts", artifact_stamp, "evidence", "#{label}-runtime-worker.json"),
            container_name: container_stem,
            proxy_container_name: "#{container_stem}-proxy",
            docker_storage_volume: "#{container_stem}-storage",
            docker_proxy_routes_volume: "#{container_stem}-proxy-routes"
          )
        end
      end

      attr_reader :container_name,
        :docker_proxy_routes_volume,
        :docker_storage_volume,
        :docker_workspace_root,
        :event_output_path,
        :home_root,
        :index,
        :label,
        :proxy_container_name,
        :proxy_port,
        :runtime_base_url,
        :runtime_boot_json_path

      def initialize(index:, label:, runtime_base_url:, proxy_port:, home_root:, docker_workspace_root:, event_output_path:, runtime_boot_json_path:, container_name:, proxy_container_name:, docker_storage_volume:, docker_proxy_routes_volume:)
        @index = index
        @label = label
        @runtime_base_url = runtime_base_url
        @proxy_port = proxy_port
        @home_root = home_root
        @docker_workspace_root = docker_workspace_root
        @event_output_path = event_output_path
        @runtime_boot_json_path = runtime_boot_json_path
        @container_name = container_name
        @proxy_container_name = proxy_container_name
        @docker_storage_volume = docker_storage_volume
        @docker_proxy_routes_volume = docker_proxy_routes_volume
        freeze
      end

      def nexus_activation_env
        {
          "NEXUS_RUNTIME_BASE_URL" => runtime_base_url,
          "NEXUS_DOCKER_CONTAINER" => container_name,
          "NEXUS_DOCKER_PROXY_CONTAINER" => proxy_container_name,
          "NEXUS_DOCKER_PROXY_PORT" => proxy_port.to_s,
          "NEXUS_DOCKER_WORKSPACE_ROOT" => docker_workspace_root.to_s,
          "NEXUS_DOCKER_STORAGE_VOLUME" => docker_storage_volume,
          "NEXUS_DOCKER_PROXY_ROUTES_VOLUME" => docker_proxy_routes_volume,
          "NEXUS_HOME_ROOT" => home_root.to_s,
          "NEXUS_RUNTIME_BOOT_JSON" => runtime_boot_json_path.to_s,
          "CYBROS_PERF_EVENTS_PATH" => event_output_path.to_s,
          "CYBROS_PERF_INSTANCE_LABEL" => label
        }
      end
    end
  end
end
