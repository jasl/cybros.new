module ToolGovernanceTestSupport
  private

  def governed_environment_tool_catalog
    [
      {
        "tool_name" => "shell_exec",
        "tool_kind" => "environment_runtime",
        "implementation_source" => "execution_environment",
        "implementation_ref" => "env/shell_exec",
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
        "tool_name" => "shell_exec",
        "tool_kind" => "agent_observation",
        "implementation_source" => "agent",
        "implementation_ref" => "agent/shell_exec",
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
        "allowed_tool_names" => %w[shell_exec compact_context subagent_spawn],
      },
    }
  end

  def build_governed_tool_context!(
    environment_tool_catalog: governed_environment_tool_catalog,
    agent_tool_catalog: governed_agent_tool_catalog,
    profile_catalog: governed_profile_catalog
  )
    context = build_agent_control_context!
    context.fetch(:execution_environment).update!(tool_catalog: environment_tool_catalog)

    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context.fetch(:deployment),
      version: 2,
      tool_catalog: agent_tool_catalog,
      profile_catalog: profile_catalog,
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context.fetch(:deployment).update!(active_capability_snapshot: capability_snapshot)
    context.fetch(:turn).update!(
      resolved_model_selection_snapshot: context.fetch(:turn).resolved_model_selection_snapshot.merge(
        "capability_snapshot_id" => capability_snapshot.id
      )
    )

    Conversations::RefreshRuntimeContract.call(conversation: context.fetch(:conversation))
    execution_snapshot = Workflows::BuildExecutionSnapshot.call(turn: context.fetch(:turn))
    context.fetch(:turn).update!(execution_snapshot_payload: execution_snapshot.to_h)

    context.merge(
      capability_snapshot: capability_snapshot,
      turn: context.fetch(:turn).reload,
      workflow_node: context.fetch(:workflow_node).reload
    )
  end
end

ActiveSupport::TestCase.include(ToolGovernanceTestSupport)
ActionDispatch::IntegrationTest.include(ToolGovernanceTestSupport)
