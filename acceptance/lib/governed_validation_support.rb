module GovernedValidationSupport
  module_function

  DEFAULT_PROTOCOL_METHODS = [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
  ].freeze

  def base_config_schema_snapshot
    {
      "type" => "object",
      "properties" => {
        "interactive" => {
          "type" => "object",
          "properties" => {
            "selector" => { "type" => "string" },
            "profile" => { "type" => "string" },
          },
        },
        "subagents" => {
          "type" => "object",
          "properties" => {
            "enabled" => { "type" => "boolean" },
            "allow_nested" => { "type" => "boolean" },
            "max_depth" => { "type" => "integer" },
          },
        },
      },
    }
  end

  def bootstrap_runtime!(
    agent_key:,
    display_name:,
    executor_fingerprint:,
    fingerprint:,
    tool_catalog:,
    profile_catalog:,
    default_config_snapshot:,
    executor_capability_payload: {},
    executor_tool_catalog: []
  )
    raise "expected an empty database; run core_matrix_reset_backend_state first" if Installation.exists?

    bootstrap = Installations::BootstrapFirstAdmin.call(
      name: "Primary Installation",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin",
      bundled_agent_configuration: { enabled: false }
    )

    runtime = Installations::RegisterBundledAgentRuntime.call(
      installation: bootstrap.installation,
      configuration: {
        enabled: true,
        agent_key: agent_key,
        display_name: display_name,
        visibility: "global",
        lifecycle_state: "active",
        executor_kind: "local",
        executor_fingerprint: executor_fingerprint,
        connection_metadata: {
          "transport" => "http",
          "base_url" => "http://127.0.0.1:4100",
        },
        endpoint_metadata: {
          "transport" => "http",
          "base_url" => "http://127.0.0.1:4100",
          "runtime_manifest_path" => "/runtime/manifest",
        },
        executor_capability_payload: executor_capability_payload,
        executor_tool_catalog: executor_tool_catalog,
        fingerprint: fingerprint,
        protocol_version: "2026-03-24",
        sdk_version: "fenix-0.1.0",
        protocol_methods: DEFAULT_PROTOCOL_METHODS,
        tool_catalog: tool_catalog,
        profile_catalog: profile_catalog,
        config_schema_snapshot: base_config_schema_snapshot,
        conversation_override_schema_snapshot: {
          "type" => "object",
          "properties" => {},
        },
        default_config_snapshot: default_config_snapshot,
      }
    )

    user_binding = UserProgramBindings::Enable.call(
      user: bootstrap.user,
      agent_program: runtime.agent_program
    ).binding

    ProviderEntitlement.find_or_create_by!(
      installation: bootstrap.installation,
      provider_handle: "dev",
      entitlement_key: "manual-runtime"
    ) do |entitlement|
      entitlement.window_kind = "rolling_five_hours"
      entitlement.window_seconds = 5.hours.to_i
      entitlement.quota_limit = 200_000
      entitlement.active = true
      entitlement.metadata = {}
    end

    {
      bootstrap: bootstrap,
      runtime: runtime,
      workspace: user_binding.workspaces.find_by!(is_default: true),
    }
  end

  def create_task_context!(
    workspace:,
    deployment:,
    capability_snapshot:,
    content:,
    allowed_tool_names:,
    normalized_selector: "candidate:dev/mock-model",
    node_key: "agent_turn_step",
    node_type: "turn_step"
  )
    conversation = Conversations::CreateRoot.call(
      workspace: workspace,
      agent_program: deployment.agent_program
    )

    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: content,
      agent_program_version: deployment,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: resolved_model_selection_snapshot(
        capability_snapshot: capability_snapshot,
        normalized_selector: normalized_selector
      )
    )

    turn.update!(
      execution_snapshot_payload: {
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => allowed_tool_names,
        },
      }
    )

    workflow_run = WorkflowRun.create!(
      installation: conversation.installation,
      workspace: workspace,
      conversation: conversation,
      turn: turn,
      lifecycle_state: "active"
    )

    root_node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      ordinal: 0,
      node_key: "root",
      node_type: "turn_root",
      presentation_policy: "internal_only",
      decision_source: "system",
      metadata: {}
    )

    workflow_node = WorkflowNode.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      ordinal: 1,
      node_key: node_key,
      node_type: node_type,
      presentation_policy: "internal_only",
      decision_source: "agent_program",
      metadata: {}
    )

    WorkflowEdge.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      from_node: root_node,
      to_node: workflow_node,
      ordinal: 0
    )

    agent_task_run = AgentTaskRun.create!(
      installation: workflow_run.installation,
      agent_program: deployment.agent_program,
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      conversation: conversation,
      turn: turn,
      kind: "turn_step",
      lifecycle_state: "queued",
      logical_work_id: "turn-step:#{turn.public_id}:#{node_key}",
      attempt_no: 1,
      task_payload: { "step" => node_key },
      progress_payload: {},
      terminal_payload: {}
    )

    {
      conversation: conversation,
      turn: turn.reload,
      workflow_run: workflow_run.reload,
      root_node: root_node,
      workflow_node: workflow_node.reload,
      agent_task_run: agent_task_run.reload,
    }
  end

  def dag_edges(workflow_run)
    workflow_run.workflow_edges.includes(:from_node, :to_node).order(:ordinal).map do |edge|
      "#{edge.from_node.node_key}->#{edge.to_node.node_key}"
    end
  end

  def conversation_state(conversation:, workflow_run:)
    {
      "conversation_state" => conversation.lifecycle_state,
      "workflow_lifecycle_state" => workflow_run.lifecycle_state,
      "workflow_wait_state" => workflow_run.wait_state,
      "turn_lifecycle_state" => workflow_run.turn.lifecycle_state,
    }
  end

  def resolved_model_selection_snapshot(capability_snapshot:, normalized_selector:)
    provider_handle, model_ref = normalized_selector.delete_prefix("candidate:").split("/", 2)

    {
      "normalized_selector" => normalized_selector,
      "selector_source" => "conversation",
      "capability_snapshot_id" => capability_snapshot.id,
      "resolved_provider_handle" => provider_handle.presence,
      "resolved_model_ref" => model_ref.presence,
    }.compact
  end
end
