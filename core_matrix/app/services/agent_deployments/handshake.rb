module AgentDeployments
  class Handshake
    FingerprintMismatch = Class.new(StandardError)

    Result = Struct.new(:deployment, :capability_snapshot, :reconciliation_report, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, fingerprint:, protocol_version:, sdk_version:, protocol_methods:, tool_catalog:, config_schema_snapshot:, conversation_override_schema_snapshot:, default_config_snapshot:)
      @deployment = deployment
      @fingerprint = fingerprint
      @protocol_version = protocol_version
      @sdk_version = sdk_version
      @protocol_methods = protocol_methods
      @tool_catalog = tool_catalog
      @config_schema_snapshot = config_schema_snapshot
      @conversation_override_schema_snapshot = conversation_override_schema_snapshot
      @default_config_snapshot = default_config_snapshot
    end

    def call
      raise FingerprintMismatch, "deployment fingerprint does not match the authenticated deployment" if @deployment.fingerprint != @fingerprint

      reconciliation = AgentDeployments::ReconcileConfig.call(
        previous_default_config_snapshot: @deployment.active_capability_snapshot&.default_config_snapshot,
        next_config_schema_snapshot: @config_schema_snapshot,
        next_default_config_snapshot: @default_config_snapshot
      )

      ApplicationRecord.transaction do
        @deployment.with_lock do
          @deployment.reload

          capability_snapshot = find_matching_snapshot(reconciliation.reconciled_config) || create_snapshot!(reconciliation.reconciled_config)
          @deployment.update!(
            protocol_version: @protocol_version,
            sdk_version: @sdk_version,
            active_capability_snapshot: capability_snapshot
          )

          Result.new(
            deployment: @deployment,
            capability_snapshot: capability_snapshot,
            reconciliation_report: reconciliation.report
          )
        end
      end
    end

    private

    def find_matching_snapshot(reconciled_default_config_snapshot)
      @deployment.capability_snapshots.detect do |snapshot|
        snapshot.protocol_methods == @protocol_methods &&
          snapshot.tool_catalog == @tool_catalog &&
          snapshot.config_schema_snapshot == @config_schema_snapshot &&
          snapshot.conversation_override_schema_snapshot == @conversation_override_schema_snapshot &&
          snapshot.default_config_snapshot == reconciled_default_config_snapshot
      end
    end

    def create_snapshot!(reconciled_default_config_snapshot)
      @deployment.capability_snapshots.create!(
        version: @deployment.capability_snapshots.maximum(:version).to_i + 1,
        protocol_methods: @protocol_methods,
        tool_catalog: @tool_catalog,
        config_schema_snapshot: @config_schema_snapshot,
        conversation_override_schema_snapshot: @conversation_override_schema_snapshot,
        default_config_snapshot: reconciled_default_config_snapshot
      )
    end
  end
end
