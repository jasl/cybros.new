require "test_helper"

class HumanInteractions::RequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "execution complete wait transition materializes a blocking human task request on the workflow" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      deployment: context.fetch(:deployment),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    report_execution_complete!(
      deployment: context.fetch(:deployment),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      terminal_payload: {
        "output" => "Need operator input",
      }.merge(
        human_task_wait_transition_payload(
          batch_id: "batch-human-1",
          successor_node_key: "agent_step_2",
          instructions: "Collect the operator confirmation."
        )
      )
    )

    request = HumanTaskRequest.find_by!(
      workflow_run: context.fetch(:workflow_run),
      workflow_node: context.fetch(:workflow_run).reload.workflow_nodes.find_by!(node_key: "human_gate")
    )
    workflow_run = context.fetch(:workflow_run).reload
    human_gate = workflow_run.workflow_nodes.find_by!(node_key: "human_gate")

    assert request.open?
    assert_equal "Collect the operator confirmation.", request.request_payload["instructions"]
    assert_equal "batch-human-1", human_gate.intent_batch_id
    assert_equal "batch-human-1:human", human_gate.intent_id
    assert_equal request, human_gate.opened_human_interaction_request
    assert_equal(
      {
        "request_type" => "HumanTaskRequest",
        "blocking" => true,
        "request_payload" => {
          "instructions" => "Collect the operator confirmation.",
        },
      },
      human_gate.intent_payload
    )
    refute human_gate.metadata.key?("payload")
    refute human_gate.metadata.key?("human_interaction_request_id")
    refute human_gate.metadata.key?("blocking")
    assert workflow_run.waiting?
    assert_equal "human_interaction", workflow_run.wait_reason_kind
    assert_equal request.public_id, workflow_run.blocking_resource_id
    assert_equal "agent_step_2", workflow_run.resume_metadata.dig("successor", "node_key")
    assert_equal %w[root agent_turn_step human_gate], workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key)
    assert_equal "completed", agent_task_run.reload.lifecycle_state
    assert workflow_run.workflow_nodes.find_by!(node_key: "human_gate").completed?
    assert_equal ["completed"],
      workflow_run.workflow_node_events.where(
        workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "human_gate"),
        event_kind: "status"
      ).order(:ordinal).map { |event| event.payload.fetch("state") }
  end

  test "rejects opening a human interaction when the frozen workflow feature policy disables it" do
    context = prepare_workflow_execution_setup!(create_workspace_context!)
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    conversation.update!(enabled_feature_ids: Conversation::FEATURE_IDS - ["human_interaction"])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Human interaction input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = Workflows::CreateForTurn.call(
      turn: turn,
      root_node_key: "root",
      root_node_type: "turn_root",
      decision_source: "system",
      metadata: {}
    )

    Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "human_gate",
          node_type: "human_interaction",
          decision_source: "agent_program",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "root", to_node_key: "human_gate" },
      ]
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "HumanTaskRequest",
        workflow_node: workflow_run.reload.workflow_nodes.find_by!(node_key: "human_gate"),
        blocking: true,
        request_payload: { "instructions" => "Need operator input" }
      )
    end

    assert_equal :feature_not_enabled, error.record.errors.details[:base].first[:error]
    assert_equal "human_interaction", error.record.errors.details[:base].first[:feature_id]
  end

  test "creates blocking approval requests, waits the workflow, and projects a conversation event" do
    context = build_human_interaction_context!

    request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" },
      expires_at: 1.hour.from_now
    )

    assert_instance_of ApprovalRequest, request
    assert request.open?
    assert_equal context[:workflow_run], request.workflow_run

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "human_interaction", workflow_run.wait_reason_kind
    assert_equal "HumanInteractionRequest", workflow_run.blocking_resource_type
    assert_equal request.public_id, workflow_run.blocking_resource_id
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_equal request, context[:workflow_node].reload.opened_human_interaction_request

    event = ConversationEvent.find_by!(source: request, event_kind: "human_interaction.opened")
    assert_equal 0, event.projection_sequence
    assert_equal "human_interaction_request:#{request.id}", event.stream_key
    assert_equal 0, event.stream_revision
    assert_equal request.public_id, event.payload["request_id"]
  end

  test "non-blocking human interaction completion dispatches runnable successors" do
    context = build_human_interaction_context!
    workflow_run = context.fetch(:workflow_run)

    Workflows::Mutate.call(
      workflow_run: workflow_run,
      nodes: [
        {
          node_key: "leaf",
          node_type: "turn_step",
          decision_source: "system",
          metadata: {},
        },
      ],
      edges: [
        { from_node_key: "human_gate", to_node_key: "leaf" },
      ]
    )
    Workflows::CompleteNode.call(workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "root"))

    assert_enqueued_jobs 1 do
      HumanInteractions::Request.call(
        request_type: "HumanTaskRequest",
        workflow_node: workflow_run.reload.workflow_nodes.find_by!(node_key: "human_gate"),
        blocking: false,
        request_payload: { "instructions" => "Optional task" }
      )
    end

    leaf = workflow_run.reload.workflow_nodes.find_by!(node_key: "leaf")

    assert leaf.queued?
  end

  test "rejects opening a human interaction on a pending delete conversation" do
    context = build_human_interaction_context!
    context[:conversation].update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_equal context[:workflow_run].id, error.record.id
    assert_includes error.record.errors[:deletion_state], "must be retained before opening human interaction"
  end

  test "rejects opening a human interaction on an archived conversation" do
    context = build_human_interaction_context!
    context[:conversation].update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_equal context[:workflow_run].id, error.record.id
    assert_includes error.record.errors[:lifecycle_state], "must be active before opening human interaction"
  end

  test "rejects opening a human interaction while close is in progress" do
    context = build_human_interaction_context!
    ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_equal context[:workflow_run].id, error.record.id
    assert_includes error.record.errors[:base], "must not open human interaction while close is in progress"
  end

  test "rejects opening another blocking human interaction from a stale workflow snapshot" do
    context = build_human_interaction_context!
    stale_workflow_node = WorkflowNode.find(context[:workflow_node].id)
    stale_workflow_node.workflow_run

    first_request = HumanInteractions::Request.call(
      request_type: "ApprovalRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "approval_scope" => "publish" }
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: stale_workflow_node,
        blocking: true,
        request_payload: { "approval_scope" => "publish-again" }
      )
    end

    assert_includes error.record.errors[:wait_state], "must be ready before opening another blocking human interaction"
    assert_equal [first_request.id], HumanInteractionRequest.where(workflow_run: context[:workflow_run]).order(:id).pluck(:id)
  end

  test "rejects opening a human interaction after the turn has been interrupted" do
    context = build_human_interaction_context!
    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      HumanInteractions::Request.call(
        request_type: "ApprovalRequest",
        workflow_node: context[:workflow_node],
        blocking: true,
        request_payload: { "approval_scope" => "publish" }
      )
    end

    assert_includes error.record.errors[:turn], "must not be fenced by turn interrupt"
  end
end
