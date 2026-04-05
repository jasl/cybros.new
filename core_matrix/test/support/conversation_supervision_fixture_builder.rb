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
      agent_program_version: context.fetch(:agent_program_version),
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
      capability_snapshot = create_capability_snapshot!(
        agent_program_version: context.fetch(:agent_program_version),
        config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
        default_config_snapshot: default_default_config_snapshot(include_selector_slots: true).deep_merge(
          "model_slots" => {
            "summary" => { "selector" => summary_slot_selector }
          }
        )
      )
      adopt_agent_program_version!(context, capability_snapshot, turn: current_turn)
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
      decision_source: "agent_program",
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
    AgentTaskPlanItem.create!(
      installation: context.fetch(:installation),
      agent_task_run: agent_task_run,
      item_key: "projection",
      title: "Freeze the supervision snapshot",
      status: "completed",
      position: 0,
      details_payload: {}
    )
    AgentTaskPlanItem.create!(
      installation: context.fetch(:installation),
      agent_task_run: agent_task_run,
      item_key: "renderer",
      title: "Render the human supervisor reply",
      status: "in_progress",
      position: 1,
      details_payload: {}
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
      agent_program_version: context.fetch(:agent_program_version),
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context.fetch(:installation),
      owner_conversation: conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running",
      supervision_state: "running",
      request_summary: "Verify the capstone acceptance path",
      current_focus_summary: "Checking the 2048 acceptance flow",
      recent_progress_summary: "Confirmed the control acceptance wiring",
      next_step_hint: "Report the acceptance status back to the parent task",
      last_progress_at: 30.seconds.ago,
      supervision_payload: {}
    )

    policy = ConversationCapabilityPolicy.create!(
      installation: context.fetch(:installation),
      target_conversation: conversation,
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
      subagent_session: subagent_session.reload,
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
end
