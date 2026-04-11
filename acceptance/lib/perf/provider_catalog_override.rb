# frozen_string_literal: true

require 'fileutils'
require 'yaml'

module Acceptance
  module Perf
    # Persists load-harness provider overrides so web, jobs, and scenario code share one catalog view.
    class ProviderCatalogOverride
      Override = Struct.new(:catalog, :override_path, :payload, keyword_init: true)

      class << self
        def payload_for(profile:)
          return unless profile.workload_kind == 'agent_request_exchange_mock'

          {
            'providers' => {
              'dev' => {
                'admission_control' => {
                  'max_concurrent_requests' => profile.conversation_count
                }
              }
            }
          }
        end

        def write(profile:, override_dir:, env:)
          payload = payload_for(profile:)
          return unless payload

          override_path = override_path_for(override_dir:, env:)

          FileUtils.mkdir_p(override_path.dirname)
          File.write(override_path, payload.to_yaml)

          Override.new(
            catalog: nil,
            override_path: override_path,
            payload: payload
          )
        end

        def build(profile:, topology:, rails_root:, env: Rails.env)
          new(
            profile: profile,
            topology: topology,
            rails_root: Pathname.new(rails_root.to_s),
            env: env
          ).call
        end

        private

        def override_path_for(override_dir:, env:)
          Pathname(override_dir).join("llm_catalog.#{env}.yml")
        end
      end

      def initialize(profile:, topology:, rails_root:, env:)
        @profile = profile
        @topology = topology
        @rails_root = rails_root
        @env = env.to_s
      end

      def call
        override = self.class.write(profile: @profile, override_dir: override_dir, env: @env)
        return unless override

        override.catalog = load_catalog
        override
      end

      private

      def catalog_path
        @catalog_path ||= @rails_root.join('config/llm_catalog.yml')
      end

      def override_dir
        @override_dir ||= @topology.run_root.join('core-matrix-config.d')
      end

      def load_catalog
        ProviderCatalog::Load.call(
          path: catalog_path,
          override_dir: override_dir,
          env: @env
        )
      end
    end
  end
end
