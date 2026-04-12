module ConversationSupervisionFixtureBuilder
  def prepare_conversation_supervision_context!(waiting: true, detailed_progress_enabled: true, side_chat_enabled: true, control_enabled: false, summary_slot_selector: nil)
    context = build_canonical_variable_context!
    conversation = context.fetch(:conversation)
    previous_turn = context.fetch(:turn)
    previous_output = attach_selected_output!(previous_turn, content: "We already agreed to add tests before refactoring.")
    previous_turn.update!(lifecycle_state: "completed")
    context.fetch(:workflow_run).update!(lifecycle_state: "completed")

    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Has this turn already committed to the 2048 acceptance flow work?",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    if summary_slot_selector.present?
      ProviderEntitlement.create!(
        installation: context.fetch(:installation),
        provider_handle: "dev",
        entitlement_key: "mock-runtime",
        window_kind: "rolling_five_hours",
        window_seconds: 5.hours.to_i,
        quota_limit: 200_000,
        active: true,
        metadata: {}
      )
      capability_snapshot = create_compatible_agent_definition_version!(
        agent_definition_version: context.fetch(:agent_definition_version),
        canonical_config_schema: default_canonical_config_schema(include_selector_slots: true),
        default_canonical_config: default_default_canonical_config(include_selector_slots: true).deep_merge(
          "model_slots" => {
            "summary" => { "selector" => summary_slot_selector },
          }
        )
      )
      adopt_agent_definition_version!(context, capability_snapshot, turn: current_turn)
      current_turn = current_turn.reload
    end
    current_output = attach_selected_output!(current_turn, content: "The 2048 acceptance flow is already wired.")
    workflow_run = create_workflow_run!(turn: current_turn, wait_state: "ready", wait_reason_payload: {})
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "implement_supervision_snapshot",
      node_type: "turn_step",
      lifecycle_state: "running",
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      started_at: 3.minutes.ago,
      metadata: {}
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: workflow_node,
      lifecycle_state: "running",
      started_at: 3.minutes.ago,
      supervision_state: "running",
      focus_kind: "implementation",
      request_summary: "Rebuild the supervision sidechat surface",
      current_focus_summary: "Rendering the frozen supervision snapshot",
      recent_progress_summary: "Replaced the old observation bundle with structured supervision data",
      next_step_hint: "Return a supervisor-facing summary",
      last_progress_at: 1.minute.ago,
      supervision_payload: {}
    )
    TurnTodoPlans::ApplyUpdate.call(
      agent_task_run: agent_task_run,
      payload: {
        "goal_summary" => "Rebuild the supervision sidechat surface",
        "current_item_key" => "render-snapshot",
        "items" => [
          {
            "item_key" => "freeze-snapshot",
            "title" => "Freeze the supervision snapshot",
            "status" => "completed",
            "position" => 0,
            "kind" => "implementation",
          },
          {
            "item_key" => "render-snapshot",
            "title" => "Rendering the frozen supervision snapshot",
            "status" => "in_progress",
            "position" => 1,
            "kind" => "implementation",
          },
        ],
      },
      occurred_at: 1.minute.ago
    )
    AgentTaskProgressEntry.create!(
      installation: context.fetch(:installation),
      agent_task_run: agent_task_run,
      sequence: 1,
      entry_kind: "progress_recorded",
      summary: "Replaced the old observation bundle with structured supervision data",
      details_payload: {},
      occurred_at: 1.minute.ago
    )

    child_conversation = create_conversation_record!(
      installation: context.fetch(:installation),
      workspace: context.fetch(:workspace),
      parent_conversation: conversation,
      kind: "fork",
      execution_runtime: context.fetch(:execution_runtime),
      agent_definition_version: context.fetch(:agent_definition_version),
      addressability: "agent_addressable"
    )
    subagent_connection = SubagentConnection.create!(
      installation: context.fetch(:installation),
      owner_conversation: conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      request_summary: "Verify the acceptance flow",
      current_focus_summary: "Checking the 2048 acceptance flow",
      recent_progress_summary: "Confirmed the control acceptance wiring",
      next_step_hint: "Report the acceptance status back to the parent task",
      last_progress_at: 30.seconds.ago,
      supervision_payload: {}
    )

    policy = upsert_conversation_capability_policy!(
      conversation: conversation,
      supervision_enabled: true,
      detailed_progress_enabled: detailed_progress_enabled,
      side_chat_enabled: side_chat_enabled,
      control_enabled: control_enabled,
      policy_payload: {}
    )

    Conversations::UpdateSupervisionState.call(
      conversation: conversation,
      occurred_at: 2.minutes.ago
    )

    if waiting
      workflow_run.update!(
        wait_state: "waiting",
        wait_reason_kind: "subagent_barrier",
        wait_reason_payload: {},
        waiting_since_at: 20.seconds.ago,
        blocking_resource_type: "SubagentBarrier",
        blocking_resource_id: "barrier-1"
      )
      Conversations::UpdateSupervisionState.call(
        conversation: conversation,
        occurred_at: Time.current
      )
    end

    context.merge(
      conversation: conversation.reload,
      previous_turn: previous_turn.reload,
      previous_output: previous_output,
      current_turn: current_turn.reload,
      current_output: current_output,
      workflow_run: workflow_run.reload,
      workflow_node: workflow_node.reload,
      agent_task_run: agent_task_run.reload,
      subagent_connection: subagent_connection.reload,
      policy: policy
    )
  end

  def create_conversation_supervision_session!(fixture, initiator: fixture.fetch(:user), responder_strategy: "builtin")
    ConversationSupervisionSession.create!(
      installation: fixture.fetch(:installation),
      target_conversation: fixture.fetch(:conversation),
      initiator: initiator,
      lifecycle_state: "open",
      responder_strategy: responder_strategy,
      capability_policy_snapshot: supervision_policy_snapshot_for(fixture.fetch(:policy))
    )
  end

  def supervision_policy_snapshot_for(policy)
    {
      "supervision_enabled" => policy.supervision_enabled,
      "detailed_progress_enabled" => policy.detailed_progress_enabled,
      "side_chat_enabled" => policy.side_chat_enabled,
      "control_enabled" => policy.control_enabled,
    }
  end

  def prepare_conversation_supervision_context_with_turn_todo_plan!(**kwargs)
    fixture = prepare_conversation_supervision_context!(**kwargs)

    child_conversation = fixture.fetch(:subagent_connection).conversation
    child_turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Verify the acceptance flow",
      sender_kind: "owner_agent",
      sender_conversation: fixture.fetch(:conversation),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_workflow_run = create_workflow_run!(
      installation: fixture.fetch(:installation),
      conversation: child_conversation,
      turn: child_turn,
      lifecycle_state: "active"
    )
    child_workflow_node = create_workflow_node!(
      workflow_run: child_workflow_run,
      installation: fixture.fetch(:installation),
      node_key: "subagent_step",
      node_type: "subagent_step",
      lifecycle_state: "running",
      started_at: 90.seconds.ago
    )
    child_agent_task_run = create_agent_task_run!(
      installation: fixture.fetch(:installation),
      workflow_run: child_workflow_run,
      workflow_node: child_workflow_node,
      conversation: child_conversation,
      turn: child_turn,
      agent: fixture.fetch(:agent_task_run).agent,
      subagent_connection: fixture.fetch(:subagent_connection),
      origin_turn: fixture.fetch(:current_turn),
      kind: "subagent_step",
      lifecycle_state: "running",
      started_at: 90.seconds.ago,
      supervision_state: "running",
      request_summary: "Verify the acceptance flow",
      current_focus_summary: "Stale child focus summary",
      recent_progress_summary: "Confirmed the control acceptance wiring",
      next_step_hint: "Report the acceptance status back to the parent task",
      last_progress_at: 30.seconds.ago,
      supervision_payload: {}
    )
    TurnTodoPlans::ApplyUpdate.call(
      agent_task_run: child_agent_task_run,
      payload: {
        "goal_summary" => "Verify the acceptance flow",
        "current_item_key" => "check-hard-gate",
        "items" => [
          {
            "item_key" => "check-hard-gate",
            "title" => "Checking the 2048 acceptance flow",
            "status" => "in_progress",
            "position" => 0,
            "kind" => "verification",
          },
        ],
      },
      occurred_at: 30.seconds.ago
    )

    Conversations::UpdateSupervisionState.call(
      conversation: fixture.fetch(:conversation),
      occurred_at: Time.current
    )

    fixture.merge(
      child_turn: child_turn.reload,
      child_workflow_run: child_workflow_run.reload,
      child_workflow_node: child_workflow_node.reload,
      child_agent_task_run: child_agent_task_run.reload,
    )
  end

  def prepare_provider_backed_conversation_supervision_context!
    context = build_agent_control_context!
    context.fetch(:turn).selected_input_message.update!(
      content: "Build the 2048 acceptance supervision bundle and keep the supervisor informed."
    )
    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 90.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 1,
      metadata: {}
    )
    completed_tool_call = JsonDocuments::Store.call(
      installation: context.fetch(:installation),
      document_kind: "workflow_node_tool_call",
      payload: {
        "call_id" => "call-#{next_test_sequence}",
        "tool_name" => "exec_command",
      }
    )
    completed_tool_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_1_tool_1",
      node_type: "tool_call",
      lifecycle_state: "completed",
      started_at: 80.seconds.ago,
      finished_at: 70.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      tool_call_document: completed_tool_call,
      provider_round_index: 1,
      metadata: {}
    )
    completed_tool_execution = create_exec_command_execution!(
      context: context,
      workflow_node: completed_tool_node,
      command_line: "cd /workspace/game-2048 && npm test",
      tool_status: "succeeded",
      command_state: "completed",
      started_at: 80.seconds.ago,
      finished_at: 70.seconds.ago
    )
    planning_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2",
      node_type: "turn_step",
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 2,
      metadata: {}
    )
    active_tool_node = create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2_tool_1",
      node_type: "tool_call",
      lifecycle_state: "running",
      started_at: 20.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent",
      provider_round_index: 2,
      metadata: {}
    )
    active_tool_execution = create_exec_command_execution!(
      context: context,
      workflow_node: active_tool_node,
      command_line: "cd /workspace/game-2048 && npm test && npm run build",
      tool_status: "running",
      command_state: "running",
      started_at: 20.seconds.ago
    )
    active_tool_node.update!(
      tool_call_document: JsonDocuments::Store.call(
        installation: context.fetch(:installation),
        document_kind: "workflow_node_tool_call",
        payload: {
          "call_id" => "call-#{next_test_sequence}",
          "tool_name" => "command_run_wait",
          "command_run_public_id" => active_tool_execution.fetch(:command_run).public_id,
          "command_summary" => "the test-and-build check in /workspace/game-2048",
        }
      )
    )
    policy = upsert_conversation_capability_policy!(
      conversation: context.fetch(:conversation),
      supervision_enabled: true,
      detailed_progress_enabled: true,
      side_chat_enabled: true,
      control_enabled: false,
      policy_payload: {}
    )

    Conversations::UpdateSupervisionState.call(
      conversation: context.fetch(:conversation),
      occurred_at: Time.current
    )

    context.merge(
      workflow_run: context.fetch(:workflow_run).reload,
      workflow_node: active_tool_node.reload,
      planning_node: planning_node.reload,
      completed_tool_node: completed_tool_node.reload,
      completed_command_run: completed_tool_execution.fetch(:command_run).reload,
      active_tool_node: active_tool_node.reload,
      active_command_run: active_tool_execution.fetch(:command_run).reload,
      policy: policy,
    )
  end

  def create_exec_command_execution!(context:, workflow_node:, command_line:, tool_status:, command_state:, started_at:, finished_at: nil)
    tool_definition = ToolDefinition.find_or_create_by!(
      installation: context.fetch(:installation),
      agent_definition_version: context.fetch(:agent_definition_version),
      tool_name: "exec_command"
    ) do |definition|
      definition.tool_kind = "function"
      definition.governance_mode = "reserved"
      definition.policy_payload = {}
    end
    implementation_source = ImplementationSource.find_or_create_by!(
      installation: context.fetch(:installation),
      source_kind: "kernel",
      source_ref: "core_matrix.exec_command.shared"
    ) do |source|
      source.metadata = {}
    end
    tool_implementation = ToolImplementation.find_or_create_by!(
      installation: context.fetch(:installation),
      tool_definition: tool_definition,
      implementation_ref: "core_matrix.exec_command.shared"
    ) do |implementation|
      implementation.implementation_source = implementation_source
      implementation.idempotency_policy = "idempotent"
      implementation.default_for_snapshot = true
      implementation.input_schema = {}
      implementation.result_schema = {}
      implementation.metadata = {}
    end
    tool_binding = ToolBinding.find_or_create_by!(
      installation: context.fetch(:installation),
      workflow_node: workflow_node,
      tool_definition: tool_definition
    ) do |binding|
      binding.tool_implementation = tool_implementation
      binding.binding_reason = "snapshot_default"
      binding.runtime_state = {}
    end
    tool_invocation = ToolInvocation.create!(
      installation: context.fetch(:installation),
      workflow_node: workflow_node,
      tool_binding: tool_binding,
      tool_definition: tool_definition,
      tool_implementation: tool_implementation,
      attempt_no: tool_binding.tool_invocations.count + 1,
      status: tool_status,
      request_payload: {},
      response_payload: {},
      error_payload: {},
      metadata: {},
      started_at: started_at,
      finished_at: finished_at
    )
    command_run = CommandRun.create!(
      installation: context.fetch(:installation),
      workflow_node: workflow_node,
      tool_invocation: tool_invocation,
      command_line: command_line,
      lifecycle_state: command_state,
      metadata: {},
      started_at: started_at,
      ended_at: finished_at,
      exit_status: (command_state == "completed" ? 0 : nil)
    )

    {
      tool_definition: tool_definition,
      tool_implementation: tool_implementation,
      tool_binding: tool_binding,
      tool_invocation: tool_invocation,
      command_run: command_run,
    }
  end
end
