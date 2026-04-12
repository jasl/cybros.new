module AgentDefinitionVersions
  class Handshake
    Result = Struct.new(
      :agent_definition_version,
      :agent_config_state,
      :reconciliation_report,
      :runtime_capability_contract,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(agent_connection:, execution_runtime: nil, definition_package:)
      @agent_connection = agent_connection
      @execution_runtime = execution_runtime || agent_connection.agent.default_execution_runtime
      @definition_package = definition_package
    end

    def call
      current_definition_version = @agent_connection.agent_definition_version
      upsert_result = UpsertFromPackage.call(
        agent: @agent_connection.agent,
        definition_package: @definition_package
      )
      agent_definition_version = upsert_result.agent_definition_version
      agent_config_state = AgentConfigStates::Reconcile.call(
        agent: @agent_connection.agent,
        agent_definition_version: agent_definition_version
      )

      ApplicationRecord.transaction do
        @agent_connection.agent.update!(active_agent_definition_version: agent_definition_version)
        @agent_connection.update!(agent_definition_version: agent_definition_version)

        ToolBindings::ProjectCapabilitySnapshot.call(
          agent_definition_version: agent_definition_version,
          execution_runtime: @execution_runtime
        )
      end

      runtime_capability_contract = RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        agent_definition_version: agent_definition_version
      )

      Result.new(
        agent_definition_version: agent_definition_version,
        agent_config_state: agent_config_state,
        reconciliation_report: {
          "definition_changed" => current_definition_version.id != agent_definition_version.id,
          "agent_config_version" => agent_config_state.version
        },
        runtime_capability_contract: runtime_capability_contract
      )
    end
  end
end
