module ToolGovernanceTestSupport
  private

  def governed_execution_runtime_tool_catalog
    [
      {
        "tool_name" => "exec_command",
        "tool_kind" => "execution_runtime",
        "implementation_source" => "execution_runtime",
        "implementation_ref" => "env/exec_command",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
    ]
  end

  def governed_agent_tool_catalog
    [
      {
        "tool_name" => "exec_command",
        "tool_kind" => "agent_observation",
        "implementation_source" => "agent",
        "implementation_ref" => "agent/exec_command",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "compact_context",
        "tool_kind" => "agent_observation",
        "implementation_source" => "agent",
        "implementation_ref" => "agent/compact_context",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
      {
        "tool_name" => "subagent_spawn",
        "tool_kind" => "effect_intent",
        "implementation_source" => "agent",
        "implementation_ref" => "agent/subagent_spawn",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      },
    ]
  end

  def governed_profile_catalog
    {
      "main" => {
        "label" => "Main",
        "description" => "Primary interactive profile",
        "allowed_tool_names" => %w[exec_command compact_context subagent_spawn],
      },
    }
  end

  def build_governed_tool_context!(
    execution_runtime_tool_catalog: governed_execution_runtime_tool_catalog,
    agent_tool_catalog: governed_agent_tool_catalog,
    profile_catalog: governed_profile_catalog
  )
    context = build_agent_control_context!
    execution_runtime = context.fetch(:execution_runtime)
    execution_runtime_version = create_execution_runtime_version!(
      installation: context.fetch(:installation),
      execution_runtime: execution_runtime,
      execution_runtime_fingerprint: execution_runtime.execution_runtime_fingerprint || "runtime-fingerprint-#{next_test_sequence}",
      capability_payload_document: create_json_document!(
        installation: context.fetch(:installation),
        document_kind: "execution_runtime_capability_payload",
        payload: execution_runtime.capability_payload
      ),
      tool_catalog_document: create_json_document!(
        installation: context.fetch(:installation),
        document_kind: "execution_runtime_tool_catalog",
        payload: execution_runtime_tool_catalog
      ),
      reflected_host_metadata_document: create_json_document!(
        installation: context.fetch(:installation),
        document_kind: "reflected_host_metadata",
        payload: execution_runtime.current_execution_runtime_version&.reflected_host_metadata || {}
      )
    )
    execution_runtime.update!(published_execution_runtime_version: execution_runtime_version)
    context.fetch(:execution_runtime_connection).update!(execution_runtime_version: execution_runtime_version)

    activate_agent_definition_version!(
      context,
      tool_catalog: agent_tool_catalog,
      profile_catalog: profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    agent_config_state = context.fetch(:agent).agent_config_state
    context.fetch(:turn).update!(
      agent_definition_version: context.fetch(:agent_definition_version),
      execution_runtime_version: execution_runtime_version,
      agent_config_version: agent_config_state.version,
      agent_config_content_fingerprint: agent_config_state.content_fingerprint
    )
    Workflows::BuildExecutionSnapshot.call(turn: context.fetch(:turn))

    context.merge(
      turn: context.fetch(:turn).reload,
      workflow_node: context.fetch(:workflow_node).reload
    )
  end
end

ActiveSupport::TestCase.include(ToolGovernanceTestSupport)
ActionDispatch::IntegrationTest.include(ToolGovernanceTestSupport)
