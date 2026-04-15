require "test_helper"

class Turns::SteerCurrentInputTest < ActiveSupport::TestCase
  ChannelInboundMessage = Struct.new(:public_id)

  test "creates a new selected input variant for the active turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
    ),
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    steered = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Revised input"
    )

    assert_equal turn.id, steered.id
    assert_equal "Revised input", steered.selected_input_message.content
    assert_equal 1, steered.selected_input_message.variant_index
    assert_equal ["Original input", "Revised input"],
      UserMessage.where(turn: turn).order(:variant_index).pluck(:content)
    assert_equal steered.selected_input_message, turn.conversation.reload.latest_message
    assert_equal steered.selected_input_message.created_at.to_i, turn.conversation.last_activity_at.to_i
  end

  test "keeps pre-boundary channel ingress follow up on the same turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turn.create!(
      installation: conversation.installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      execution_runtime_version: context[:execution_runtime].current_execution_runtime_version,
      execution_epoch: initialize_current_execution_epoch!(conversation, execution_runtime: context[:execution_runtime]),
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "channel_ingress",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_1",
        "external_sender_id" => "telegram:user:42",
      },
      source_ref_type: "ChannelInboundMessage",
      source_ref_id: "channel_inbound_message_1",
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: 1,
      agent_config_content_fingerprint: context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    original_message = UserMessage.create!(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Original inbound input"
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: original_message)

    steered = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Revised inbound input"
    )

    assert_equal turn.id, steered.id
    assert_equal "channel_ingress", steered.origin_kind
    assert_equal "ChannelInboundMessage", steered.source_ref_type
    assert_equal "channel_inbound_message_1", steered.source_ref_id
    assert_equal "Revised inbound input", steered.selected_input_message.content
  end

  test "queues follow up work after the first transcript side-effect boundary" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_workflow_run!(turn: turn)
    output = attach_selected_output!(turn, content: "Streaming output")

    queued = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued follow up",
      policy_mode: "queue"
    )

    assert queued.queued?
    assert_equal 2, queued.sequence
    assert_equal "Original input", turn.reload.selected_input_message.content
    assert_equal "Queued follow up", queued.selected_input_message.content
    assert_equal output.public_id, queued.origin_payload["expected_tail_message_id"]
    assert_equal turn.public_id, queued.origin_payload["queued_from_turn_id"]
  end

  test "queues channel ingress follow up after the first transcript side-effect boundary without falling back to manual provenance" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turn.create!(
      installation: conversation.installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      execution_runtime_version: context[:execution_runtime].current_execution_runtime_version,
      execution_epoch: initialize_current_execution_epoch!(conversation, execution_runtime: context[:execution_runtime]),
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "channel_ingress",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_1",
        "external_sender_id" => "telegram:user:42",
      },
      source_ref_type: "ChannelInboundMessage",
      source_ref_id: "channel_inbound_message_1",
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: 1,
      agent_config_content_fingerprint: context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    original_message = UserMessage.create!(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Original inbound input"
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: original_message)
    output = attach_selected_output!(turn, content: "Streaming output")

    queued = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued inbound follow up",
      policy_mode: "queue",
      source_ref_type: "ChannelInboundMessage",
      source_ref_id: "channel_inbound_message_2",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_2",
        "external_sender_id" => "telegram:user:42",
      }
    )

    assert queued.queued?
    assert_equal "channel_ingress", queued.origin_kind
    assert_equal "ChannelInboundMessage", queued.source_ref_type
    assert_equal "channel_inbound_message_2", queued.source_ref_id
    assert_equal "channel_inbound_message_2", queued.origin_payload["channel_inbound_message_id"]
    assert_equal output.public_id, queued.origin_payload["expected_tail_message_id"]
    assert_equal turn.public_id, queued.origin_payload["queued_from_turn_id"]
  end

  test "detects side-effect boundaries from freshly persisted workflow node metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)

    turn.workflow_run.workflow_nodes.load
    create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "first_side_effect",
      transcript_side_effect_committed: true,
      metadata: {}
    )

    queued = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued from node metadata",
      policy_mode: "queue"
    )

    assert queued.queued?
    assert_equal "Queued from node metadata", queued.selected_input_message.content
  end

  test "detects side-effect boundaries from a freshly persisted workflow run on a stale turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_nil turn.workflow_run

    workflow_run = create_workflow_run!(turn: Turn.find(turn.id))
    create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "first_side_effect",
      transcript_side_effect_committed: true,
      metadata: {}
    )

    queued = Turns::SteerCurrentInput.call(
      turn: turn,
      content: "Queued from stale turn workflow",
      policy_mode: "queue"
    )

    assert queued.queued?
    assert_equal "Queued from stale turn workflow", queued.selected_input_message.content
  end

  test "rejects steering current input after the turn has been interrupted" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::SteerCurrentInput.call(turn: turn, content: "Should not steer")
    end

    assert_includes error.record.errors[:base], "must not steer current input after turn interruption"
  end

  test "rejects steering when the expected turn public id does not match the active turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
    ),
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::SteerCurrentInput.call(
        turn: turn,
        content: "Should not steer",
        expected_turn_id: "turn_other"
      )
    end

    assert_includes error.record.errors[:base], "must match the active turn public id"
  end

  test "allows steering a paused turn because the turn remains active and resumable" do
    context = build_agent_control_context!
    root_node = context[:workflow_run].workflow_nodes.find_by!(node_key: "root")
    root_node.update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      logical_work_id: "pause-steer-#{next_test_sequence}",
      task_payload: { "step" => "mainline" }
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_definition_version].public_id,
      heartbeat_timeout_seconds: 30
    )

    occurred_at = Time.zone.parse("2026-04-01 10:20:00 UTC")
    Conversations::RequestTurnPause.call(turn: context[:turn], occurred_at: occurred_at)
    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      agent_task_run: agent_task_run
    )
    AgentControl::ApplyCloseOutcome.call(
      resource: agent_task_run,
      mailbox_item: close_request,
      close_state: "closed",
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "test" },
      occurred_at: occurred_at + 5.seconds
    )

    steered = Turns::SteerCurrentInput.call(
      turn: context[:turn].reload,
      content: "Paused steering input"
    )

    assert_equal context[:turn].id, steered.id
    assert steered.active?
    assert_equal "Paused steering input", steered.selected_input_message.content
  end

  test "allows steering a paused turn when the expected turn public id matches" do
    context = build_agent_control_context!
    root_node = context[:workflow_run].workflow_nodes.find_by!(node_key: "root")
    root_node.update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      logical_work_id: "pause-steer-#{next_test_sequence}",
      task_payload: { "step" => "mainline" }
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_definition_version].public_id,
      heartbeat_timeout_seconds: 30
    )

    occurred_at = Time.zone.parse("2026-04-01 10:20:00 UTC")
    Conversations::RequestTurnPause.call(turn: context[:turn], occurred_at: occurred_at)
    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      agent_task_run: agent_task_run
    )
    AgentControl::ApplyCloseOutcome.call(
      resource: agent_task_run,
      mailbox_item: close_request,
      close_state: "closed",
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "test" },
      occurred_at: occurred_at + 5.seconds
    )

    steered = Turns::SteerCurrentInput.call(
      turn: context[:turn].reload,
      content: "Paused steering input",
      expected_turn_id: context[:turn].public_id
    )

    assert_equal "Paused steering input", steered.selected_input_message.content
  end

  test "steers a paused turn in place even after a transcript side-effect boundary" do
    context = build_agent_control_context!
    root_node = context[:workflow_run].workflow_nodes.find_by!(node_key: "root")
    root_node.update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )
    create_workflow_node!(
      workflow_run: context[:workflow_run],
      node_key: "tool_side_effect",
      transcript_side_effect_committed: true,
      metadata: {}
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      logical_work_id: "pause-steer-boundary-#{next_test_sequence}",
      task_payload: { "step" => "mainline" }
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_definition_version].public_id,
      heartbeat_timeout_seconds: 30
    )

    occurred_at = Time.zone.parse("2026-04-01 10:20:00 UTC")
    Conversations::RequestTurnPause.call(turn: context[:turn], occurred_at: occurred_at)
    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      agent_task_run: agent_task_run
    )
    AgentControl::ApplyCloseOutcome.call(
      resource: agent_task_run,
      mailbox_item: close_request,
      close_state: "closed",
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "test" },
      occurred_at: occurred_at + 5.seconds
    )

    steered = Turns::SteerCurrentInput.call(
      turn: context[:turn].reload,
      content: "Paused steering after boundary",
      policy_mode: "queue",
      expected_turn_id: context[:turn].public_id
    )

    assert_equal context[:turn].id, steered.id
    assert steered.active?
    refute steered.queued?
    assert_equal "Paused steering after boundary", steered.selected_input_message.content
  end

  test "steers an active turn without a full conversation anchor rescan" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
        workspace: context[:workspace],
      ),
      content: "Original input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_sql_query_count_at_most(13) do
      Turns::SteerCurrentInput.call(
        turn: turn,
        content: "Revised input"
      )
    end
  end
end
