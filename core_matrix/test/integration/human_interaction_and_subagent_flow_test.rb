require "test_helper"

class HumanInteractionAndSubagentFlowTest < ActionDispatch::IntegrationTest
  test "human task wait transition re-enters the workflow with a successor agent step after completion" do
    context = build_agent_control_context!
    complete_root_node!(context.fetch(:workflow_run))
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    report_execution_complete!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      terminal_payload: {
        "output" => "Need operator input",
      }.merge(
        human_task_wait_transition_payload(
          batch_id: "batch-human-2",
          successor_node_key: "agent_step_2",
          instructions: "Confirm the operator decision before continuing."
        )
      )
    )

    workflow_run = context.fetch(:workflow_run).reload
    request = HumanTaskRequest.find_by!(
      workflow_run: workflow_run,
      workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "human_gate")
    )

    assert workflow_run.waiting?
    assert_equal "human_interaction", workflow_run.wait_reason_kind

    HumanInteractions::CompleteTask.call(
      human_task_request: request,
      completion_payload: { "confirmed" => true }
    )

    workflow_run.reload
    successor_node = workflow_run.workflow_nodes.find_by!(node_key: "agent_step_2")
    successor_task = AgentTaskRun.find_by!(workflow_run: workflow_run, workflow_node: successor_node)
    successor_mailbox_item = AgentControlMailboxItem.find_by!(
      agent_task_run: successor_task,
      item_type: "execution_assignment"
    )
    edge_sources = WorkflowEdge.where(workflow_run: workflow_run, to_node: successor_node).includes(:from_node).map { |edge| edge.from_node.node_key }

    assert workflow_run.ready?
    assert workflow_run.workflow_nodes.find_by!(node_key: "human_gate").completed?
    assert_equal "turn_step", successor_task.kind
    assert_equal "queued", successor_task.lifecycle_state
    assert_equal "batch-human-2", successor_task.task_payload["resume_batch_id"]
    assert_equal ["human_gate"], edge_sources
    assert_equal "queued", successor_mailbox_item.status

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: successor_mailbox_item,
      agent_task_run: successor_task
    )
    report_execution_complete!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: successor_mailbox_item,
      agent_task_run: successor_task,
      terminal_payload: { "output" => "Workflow complete" }
    )

    assert workflow_run.reload.completed?
  end

  test "parallel subagent wait_all barrier re-enters the workflow after all sessions finish" do
    context = build_agent_control_context!
    complete_root_node!(context.fetch(:workflow_run))
    promote_subagent_runtime_context!(context)
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )

    report_execution_complete!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      terminal_payload: {
        "output" => "Delegated both research tasks",
      }.merge(
        subagent_wait_all_transition_payload(
          batch_id: "batch-subagents-2",
          successor_node_key: "agent_step_2",
          intents: [
            {
              node_key: "subagent_alpha",
              content: "Investigate alpha",
              scope: "conversation",
              profile_key: "researcher",
            },
            {
              node_key: "subagent_beta",
              content: "Investigate beta",
              scope: "conversation",
              profile_key: "researcher",
            },
          ]
        )
      )
    )

    workflow_run = context.fetch(:workflow_run).reload
    child_tasks = AgentTaskRun.where(origin_turn: context.fetch(:turn), kind: "subagent_step").order(:id).to_a

    assert_equal 2, child_tasks.size
    assert workflow_run.waiting?
    assert_equal "subagent_barrier", workflow_run.wait_reason_kind

    report_subagent_completion!(
      agent_definition_version: context.fetch(:agent_definition_version),
      agent_task_run: child_tasks.first
    )

    assert workflow_run.reload.waiting?

    report_subagent_completion!(
      agent_definition_version: context.fetch(:agent_definition_version),
      agent_task_run: child_tasks.second
    )

    workflow_run.reload
    successor_node = workflow_run.workflow_nodes.find_by!(node_key: "agent_step_2")
    successor_task = AgentTaskRun.find_by!(workflow_run: workflow_run, workflow_node: successor_node)
    successor_mailbox_item = AgentControlMailboxItem.find_by!(
      agent_task_run: successor_task,
      item_type: "execution_assignment"
    )
    edge_sources = WorkflowEdge.where(workflow_run: workflow_run, to_node: successor_node).includes(:from_node).map { |edge| edge.from_node.node_key }.sort

    assert workflow_run.ready?
    assert_equal %w[completed completed],
      workflow_run.workflow_nodes.where(node_key: %w[subagent_alpha subagent_beta]).order(:ordinal).pluck(:lifecycle_state)
    assert_equal "turn_step", successor_task.kind
    assert_equal "queued", successor_task.lifecycle_state
    assert_equal "batch-subagents-2", successor_task.task_payload["resume_batch_id"]
    assert_equal %w[subagent_alpha subagent_beta], edge_sources
    assert_equal "queued", successor_mailbox_item.status

    report_execution_started!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: successor_mailbox_item,
      agent_task_run: successor_task
    )
    report_execution_complete!(
      agent_definition_version: context.fetch(:agent_definition_version),
      mailbox_item: successor_mailbox_item,
      agent_task_run: successor_task,
      terminal_payload: { "output" => "Workflow complete" }
    )

    assert workflow_run.reload.completed?
  end

  private

  def report_subagent_completion!(agent_definition_version:, agent_task_run:)
    mailbox_item = AgentControlMailboxItem.find_by!(
      agent_task_run: agent_task_run,
      item_type: "execution_assignment"
    )

    report_execution_started!(
      agent_definition_version: agent_definition_version,
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run
    )
    report_execution_complete!(
      agent_definition_version: agent_definition_version,
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      terminal_payload: { "output" => "done" }
    )
  end

  def complete_root_node!(workflow_run)
    Workflows::CompleteNode.call(workflow_node: workflow_run.workflow_nodes.find_by!(node_key: "root"))
  end
end
