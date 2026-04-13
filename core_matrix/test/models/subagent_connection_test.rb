require "test_helper"

class SubagentConnectionTest < ActiveSupport::TestCase
  test "requires owner and child conversations plus a profile key" do
    assert Object.const_defined?(:SubagentConnection), "Expected SubagentConnection to be defined"
    assert_includes SubagentConnection.column_names, "owner_conversation_id"
    assert_includes SubagentConnection.column_names, "conversation_id"
    assert_includes SubagentConnection.column_names, "profile_key"
    assert_includes SubagentConnection.column_names, "scope"
    assert_includes SubagentConnection.column_names, "observed_status"

    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )

    session = SubagentConnection.new(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0
    )

    assert session.valid?

    session.profile_key = nil
    assert_not session.valid?
    assert_includes session.errors[:profile_key], "can't be blank"

    session.profile_key = "researcher"
    session.owner_conversation = nil
    assert_not session.valid?
    assert_includes session.errors[:owner_conversation], "must exist"

    session.owner_conversation = owner_conversation
    session.conversation = nil
    assert_not session.valid?
    assert_includes session.errors[:conversation], "must exist"
  end

  test "enforces turn scope, installation alignment, and parent depth invariants" do
    assert Object.const_defined?(:SubagentConnection), "Expected SubagentConnection to be defined"
    assert_includes SubagentConnection.column_names, "origin_turn_id"
    assert_includes SubagentConnection.column_names, "parent_subagent_connection_id"
    assert_includes SubagentConnection.column_names, "depth"

    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    origin_turn = Turns::StartUserTurn.call(
      conversation: owner_conversation,
      content: "Delegate work",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )

    root_session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      origin_turn: origin_turn,
      scope: "turn",
      profile_key: "worker",
      depth: 0
    )

    scoped_without_origin = SubagentConnection.new(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "turn",
      profile_key: "worker",
      depth: 0
    )

    assert_not scoped_without_origin.valid?
    assert_includes scoped_without_origin.errors[:origin_turn], "must exist for turn-scoped sessions"

    wrong_depth_without_parent = SubagentConnection.new(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: create_conversation_record!(
        workspace: context[:workspace],
        parent_conversation: owner_conversation,
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version],
        kind: "fork",
        addressability: "agent_addressable"
      ),
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 1
    )

    assert_not wrong_depth_without_parent.valid?
    assert_includes wrong_depth_without_parent.errors[:depth], "must be zero when there is no parent session"

    child_session = SubagentConnection.new(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: create_conversation_record!(
        workspace: context[:workspace],
        parent_conversation: owner_conversation,
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version],
        kind: "fork",
        addressability: "agent_addressable"
      ),
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "critic",
      parent_subagent_connection: root_session,
      depth: 1
    )

    assert child_session.valid?

    child_session.depth = 0
    assert_not child_session.valid?
    assert_includes child_session.errors[:depth], "must be parent depth plus one"

    foreign_installation = Installation.new(
      name: "Foreign Installation #{next_test_sequence}",
      bootstrap_state: "bootstrapped",
      global_settings: {}
    )
    foreign_installation.save!(validate: false)
    foreign_user = create_user!(installation: foreign_installation)
    foreign_agent = create_agent!(installation: foreign_installation)
    foreign_execution_runtime = create_execution_runtime!(installation: foreign_installation)
    foreign_agent_definition_version = create_agent_definition_version!(
      installation: foreign_installation,
      agent: foreign_agent
    )
    foreign_binding = create_user_agent_binding!(
      installation: foreign_installation,
      user: foreign_user,
      agent: foreign_agent
    )
    foreign_workspace = create_workspace!(
      installation: foreign_installation,
      user: foreign_user,
      user_agent_binding: foreign_binding
    )
    foreign_owner = Conversations::CreateRoot.call(
      workspace: foreign_workspace,
    )

    child_session.owner_conversation = foreign_owner
    assert_not child_session.valid?
    assert_includes child_session.errors[:owner_conversation], "must belong to the same installation"
  end

  test "participates in closable runtime resource control" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )

    session = SubagentConnection.new(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0
    )

    assert_respond_to session, :close_open?
    assert AgentControl::ClosableResourceRegistry.supported?(session)

    session.assign_attributes(
      close_state: "requested",
      close_reason_kind: "turn_interrupt"
    )

    assert_not session.valid?
    assert_includes session.errors[:close_requested_at], "must exist when close has been requested"

    session.assign_attributes(
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_state: "closed",
      close_acknowledged_at: Time.current,
      close_outcome_kind: "graceful"
    )

    assert session.valid?
  end

  test "derives explicit close projection and predicates from close_state" do
    assert_not_includes SubagentConnection.attribute_names, "derived_close_status"

    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    open_session = build_subagent_connection(context:, owner_conversation:)
    requested_session = build_subagent_connection(
      context:,
      owner_conversation:,
      close_state: "requested",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      observed_status: "running"
    )
    acknowledged_session = build_subagent_connection(
      context:,
      owner_conversation:,
      close_state: "acknowledged",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      observed_status: "running"
    )
    closed_session = build_subagent_connection(
      context:,
      owner_conversation:,
      close_state: "closed",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      close_outcome_kind: "graceful",
      observed_status: "completed"
    )
    failed_session = build_subagent_connection(
      context:,
      owner_conversation:,
      close_state: "failed",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      close_outcome_kind: "timed_out_forced",
      observed_status: "failed"
    )

    assert_equal "open", open_session.derived_close_status
    assert_equal "close_requested", requested_session.derived_close_status
    assert_equal "close_requested", acknowledged_session.derived_close_status
    assert_equal "closed", closed_session.derived_close_status
    assert_equal "closed", failed_session.derived_close_status

    assert open_session.close_open?
    refute open_session.close_pending?
    refute open_session.terminal_close?

    assert requested_session.close_pending?
    refute requested_session.terminal_close?
    assert requested_session.running_for_barriers?

    assert acknowledged_session.close_pending?
    refute acknowledged_session.terminal_close?
    assert acknowledged_session.running_for_barriers?

    refute closed_session.close_pending?
    assert closed_session.terminal_close?
    refute closed_session.running_for_barriers?

    refute failed_session.close_pending?
    assert failed_session.terminal_close?
    refute failed_session.running_for_barriers?
    assert_equal "failed", failed_session.observed_status
  end

  test "exposes durable close and running scopes for reader-side guards" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )

    open_session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      close_state: "open",
      observed_status: "running"
    )
    requested_session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: create_conversation_record!(
        workspace: context[:workspace],
        parent_conversation: owner_conversation,
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version],
        kind: "fork",
        addressability: "agent_addressable"
      ),
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      close_state: "requested",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      observed_status: "running"
    )
    acknowledged_session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: create_conversation_record!(
        workspace: context[:workspace],
        parent_conversation: owner_conversation,
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version],
        kind: "fork",
        addressability: "agent_addressable"
      ),
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      close_state: "acknowledged",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      observed_status: "running"
    )
    closed_session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: create_conversation_record!(
        workspace: context[:workspace],
        parent_conversation: owner_conversation,
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version],
        kind: "fork",
        addressability: "agent_addressable"
      ),
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      close_state: "closed",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      close_outcome_kind: "graceful",
      observed_status: "completed"
    )
    failed_session = SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: create_conversation_record!(
        workspace: context[:workspace],
        parent_conversation: owner_conversation,
        execution_runtime: context[:execution_runtime],
        agent_definition_version: context[:agent_definition_version],
        kind: "fork",
        addressability: "agent_addressable"
      ),
      user: owner_conversation.user,
      workspace: owner_conversation.workspace,
      agent: owner_conversation.agent,
      scope: "conversation",
      profile_key: "worker",
      depth: 0,
      close_state: "failed",
      close_reason_kind: "turn_interrupt",
      close_requested_at: Time.current,
      close_grace_deadline_at: 30.seconds.from_now,
      close_force_deadline_at: 60.seconds.from_now,
      close_acknowledged_at: Time.current,
      close_outcome_kind: "timed_out_forced",
      observed_status: "failed"
    )

    assert_equal [open_session.id, requested_session.id, acknowledged_session.id].sort,
      SubagentConnection.close_pending_or_open.order(:id).pluck(:id).sort
    assert_equal [open_session.id, requested_session.id, acknowledged_session.id].sort,
      SubagentConnection.running_for_barriers.order(:id).pluck(:id).sort
    refute_includes SubagentConnection.close_pending_or_open.pluck(:id), closed_session.id
    refute_includes SubagentConnection.close_pending_or_open.pluck(:id), failed_session.id
    assert_equal "open", open_session.reload.derived_close_status
    assert_equal "close_requested", requested_session.reload.derived_close_status
    assert_equal "close_requested", acknowledged_session.reload.derived_close_status
    assert_equal "closed", closed_session.reload.derived_close_status
    assert_equal "closed", failed_session.reload.derived_close_status
  end

  test "stores supervision rollups without changing observed status semantics" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    assert_includes SubagentConnection.column_names, "supervision_state"
    assert_includes SubagentConnection.column_names, "focus_kind"
    assert_includes SubagentConnection.column_names, "request_summary"
    assert_includes SubagentConnection.column_names, "current_focus_summary"
    assert_includes SubagentConnection.column_names, "recent_progress_summary"
    assert_includes SubagentConnection.column_names, "waiting_summary"
    assert_includes SubagentConnection.column_names, "blocked_summary"
    assert_includes SubagentConnection.column_names, "next_step_hint"
    assert_includes SubagentConnection.column_names, "last_progress_at"
    assert_includes SubagentConnection.column_names, "supervision_payload"

    session = build_subagent_connection(
      context:,
      owner_conversation:,
      observed_status: "idle",
      supervision_state: "running",
      focus_kind: "review",
      current_focus_summary: "Checking the delegated worker output",
      recent_progress_summary: "Received the first child update",
      next_step_hint: "Wait for the worker to finish",
      last_progress_at: Time.current,
      supervision_payload: {}
    )

    assert session.valid?
    assert_equal "idle", session.observed_status

    session.focus_kind = "invalid"
    assert_not session.valid?
    assert_includes session.errors[:focus_kind], "is not included in the list"

    session.focus_kind = "review"
    session.last_progress_at = nil
    assert_not session.valid?
    assert_includes session.errors[:last_progress_at], "must exist when supervision has started"
  end

  test "requires duplicated owner context to match the owner conversation" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    foreign = create_workspace_context!

    session = build_subagent_connection(
      context: context,
      owner_conversation: owner_conversation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id
    )

    assert_not session.valid?
    assert_includes session.errors[:user], "must match the owner conversation user"
    assert_includes session.errors[:workspace], "must match the owner conversation workspace"
    assert_includes session.errors[:agent], "must match the owner conversation agent"
  end

  private

  def build_subagent_connection(context: create_workspace_context!, owner_conversation: nil, **overrides)
    owner_conversation ||= Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    child_conversation = create_conversation_record!(
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      kind: "fork",
      addressability: "agent_addressable"
    )

    SubagentConnection.new(
      {
        installation: context[:installation],
        owner_conversation: owner_conversation,
        conversation: child_conversation,
        user_id: owner_conversation.user_id,
        workspace_id: owner_conversation.workspace_id,
        agent_id: owner_conversation.agent_id,
        scope: "conversation",
        profile_key: "worker",
        depth: 0,
        close_state: "open",
        observed_status: "idle",
      }.merge(overrides)
    )
  end
end
