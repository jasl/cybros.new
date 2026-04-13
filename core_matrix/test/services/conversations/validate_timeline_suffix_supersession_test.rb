require "test_helper"

class Conversations::ValidateTimelineSuffixSupersessionTest < ActiveSupport::TestCase
  test "rejects rollback while later queued turns remain" do
    context = build_suffix_supersession_context!(later_turn_state: "queued")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateTimelineSuffixSupersession.call(
        conversation: context[:conversation],
        turn: context[:target_turn]
      )
    end

    assert_includes error.record.errors[:base], "must not roll back the timeline while later queued turns remain"
  end

  test "rejects rollback while later active workflow runs remain" do
    context = build_suffix_supersession_context!
    context[:workflow_run].update!(lifecycle_state: "active")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::ValidateTimelineSuffixSupersession.call(
        conversation: context[:conversation],
        turn: context[:target_turn]
      )
    end

    assert_includes error.record.errors[:base], "must not roll back the timeline while later workflow runs remain active"
  end

  test "rejects rollback while later turns still own live runtime resources" do
    shared_context = create_workspace_context!
    cases = [
      [
        "queued agent task",
        "must not roll back the timeline while later queued agent tasks remain",
        lambda do |context|
          create_agent_task_run!(
            workflow_node: context[:workflow_node],
            workflow_run: context[:workflow_run],
            turn: context[:later_turn],
            lifecycle_state: "queued"
          )
        end,
      ],
      [
        "running agent task",
        "must not roll back the timeline while later agent tasks remain active",
        lambda do |context|
          create_agent_task_run!(
            workflow_node: context[:workflow_node],
            workflow_run: context[:workflow_run],
            turn: context[:later_turn],
            lifecycle_state: "running",
            started_at: Time.current
          )
        end,
      ],
      [
        "open human interaction",
        "must not roll back the timeline while later human interactions remain open",
        lambda do |context|
          HumanTaskRequest.create!(
            installation: context[:installation],
            workflow_run: context[:workflow_run],
            workflow_node: context[:workflow_node],
            conversation: context[:conversation],
            turn: context[:later_turn],
            user: context[:conversation].user,
            workspace: context[:conversation].workspace,
            agent: context[:conversation].agent,
            lifecycle_state: "open",
            request_payload: { "instructions" => "Still pending" },
            result_payload: {},
            blocking: false
          )
        end,
      ],
      [
        "running process",
        "must not roll back the timeline while later process execution remains active",
        lambda do |context|
          create_process_run!(
            workflow_node: context[:workflow_node],
            conversation: context[:conversation],
            turn: context[:later_turn],
            execution_runtime: context[:execution_runtime],
            lifecycle_state: "running"
          )
        end,
      ],
      [
        "running subagent",
        "must not roll back the timeline while later subagent execution remains active",
        lambda do |context|
          child_conversation = create_conversation_record!(
            installation: context[:installation],
            workspace: context[:workspace],
            parent_conversation: context[:conversation],
            kind: "fork",
            execution_runtime: context[:execution_runtime],
            agent_definition_version: context[:agent_definition_version],
            addressability: "agent_addressable"
          )

          SubagentConnection.create!(
            installation: context[:installation],
            owner_conversation: context[:conversation],
            conversation: child_conversation,
            user: child_conversation.user,
            workspace: child_conversation.workspace,
            agent: child_conversation.agent,
            origin_turn: context[:later_turn],
            scope: "turn",
            profile_key: "researcher",
            depth: 0,
            observed_status: "running"
          )
        end,
      ],
      [
        "active execution lease",
        "must not roll back the timeline while later execution leases remain active",
        lambda do |context|
          process_run = create_process_run!(
            workflow_node: context[:workflow_node],
            conversation: context[:conversation],
            turn: context[:later_turn],
            execution_runtime: context[:execution_runtime],
            lifecycle_state: "stopped",
            ended_at: Time.current
          )
          Leases::Acquire.call(
            leased_resource: process_run,
            holder_key: context[:agent_definition_version].public_id,
            heartbeat_timeout_seconds: 30
          )
        end,
      ],
    ]

    cases.each do |label, expected_message, setup|
      context = build_suffix_supersession_context!(context: shared_context)
      setup.call(context)

      error = assert_raises(ActiveRecord::RecordInvalid, label) do
        Conversations::ValidateTimelineSuffixSupersession.call(
          conversation: context[:conversation],
          turn: context[:target_turn]
        )
      end

      assert_includes error.record.errors[:base], expected_message, label
    end
  end

  private

  def build_suffix_supersession_context!(context: create_workspace_context!, later_turn_state: "completed")
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    target_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Earlier input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(target_turn, content: "Earlier output")
    target_turn.update!(lifecycle_state: "completed")

    later_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Later input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(later_turn, content: "Later output") if later_turn_state == "completed"
    later_turn.update!(lifecycle_state: later_turn_state)

    workflow_run = create_workflow_run!(turn: later_turn, lifecycle_state: "completed")
    workflow_node = create_workflow_node!(workflow_run: workflow_run, node_type: "turn_step")

    context.merge(
      conversation: conversation,
      target_turn: target_turn,
      later_turn: later_turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node
    )
  end
end
