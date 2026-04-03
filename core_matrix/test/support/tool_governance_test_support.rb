module ToolGovernanceTestSupport
  private

  def governed_execution_tool_catalog
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
    execution_tool_catalog: governed_execution_tool_catalog,
    agent_tool_catalog: governed_agent_tool_catalog,
    profile_catalog: governed_profile_catalog
  )
    context = build_agent_control_context!
    context.fetch(:execution_runtime).update!(tool_catalog: execution_tool_catalog)

    activate_program_version!(
      context,
      tool_catalog: agent_tool_catalog,
      profile_catalog: profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context.fetch(:turn).update!(
      agent_program_version: context.fetch(:agent_program_version),
      pinned_program_version_fingerprint: context.fetch(:agent_program_version).fingerprint
    )
    execution_snapshot = Workflows::BuildExecutionSnapshot.call(turn: context.fetch(:turn))
    context.fetch(:turn).update!(execution_snapshot_payload: execution_snapshot.to_h)

    context.merge(
      capability_snapshot: context.fetch(:agent_program_version),
      deployment: context.fetch(:agent_program_version),
      turn: context.fetch(:turn).reload,
      workflow_node: context.fetch(:workflow_node).reload
    )
  end
end

ActiveSupport::TestCase.include(ToolGovernanceTestSupport)
ActionDispatch::IntegrationTest.include(ToolGovernanceTestSupport)
