module CapabilitySnapshots
  class Reconcile
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, runtime_capability_contract:, deployment_locked: false)
      @deployment = deployment
      @runtime_capability_contract = runtime_capability_contract
      @deployment_locked = deployment_locked
    end

    def call
      if @deployment_locked
        @deployment.reload
        reconcile_snapshot
      else
        @deployment.with_lock do
          @deployment.reload
          reconcile_snapshot
        end
      end
    end

    private

    def reconcile_snapshot
      snapshot = find_matching_snapshot || create_snapshot!
      @deployment.update!(active_capability_snapshot: snapshot) if @deployment.active_capability_snapshot != snapshot
      snapshot
    end

    def find_matching_snapshot
      @deployment.capability_snapshots.detect do |snapshot|
        snapshot.matches_runtime_capability_contract?(@runtime_capability_contract)
      end
    end

    def create_snapshot!
      @deployment.capability_snapshots.create!(
        version: @deployment.capability_snapshots.maximum(:version).to_i + 1,
        protocol_methods: @runtime_capability_contract.protocol_methods,
        tool_catalog: @runtime_capability_contract.agent_tool_catalog,
        profile_catalog: @runtime_capability_contract.profile_catalog,
        config_schema_snapshot: @runtime_capability_contract.config_schema_snapshot,
        conversation_override_schema_snapshot: @runtime_capability_contract.conversation_override_schema_snapshot,
        default_config_snapshot: @runtime_capability_contract.default_config_snapshot
      )
    end
  end
end
