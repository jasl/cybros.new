# frozen_string_literal: true

require "fileutils"
require "yaml"

module Acceptance
  module Perf
    class ProviderCatalogOverride
      Override = Struct.new(:catalog, :override_path, :payload, keyword_init: true)

      class << self
        def build(profile:, topology:, rails_root:, env: Rails.env)
          new(
            profile: profile,
            topology: topology,
            rails_root: Pathname.new(rails_root.to_s),
            env: env
          ).call
        end
      end

      def initialize(profile:, topology:, rails_root:, env:)
        @profile = profile
        @topology = topology
        @rails_root = rails_root
        @env = env.to_s
      end

      def call
        return unless @profile.workload_kind == "program_exchange_mock"

        payload = {
          "providers" => {
            "dev" => {
              "admission_control" => {
                "max_concurrent_requests" => @profile.conversation_count,
              },
            },
          },
        }
        override_path = override_dir.join("llm_catalog.#{@env}.yml")

        FileUtils.mkdir_p(override_dir)
        File.write(override_path, payload.to_yaml)

        Override.new(
          catalog: ProviderCatalog::Load.call(
            path: @rails_root.join("config/llm_catalog.yml"),
            override_dir: override_dir,
            env: @env
          ),
          override_path: override_path,
          payload: payload
        )
      end

      private

      def override_dir
        @override_dir ||= @topology.run_root.join("core-matrix-config.d")
      end
    end
  end
end
