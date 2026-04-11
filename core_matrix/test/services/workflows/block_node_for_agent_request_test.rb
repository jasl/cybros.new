require "test_helper"

class Workflows::BlockNodeForAgentRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "moves a workflow node turn and run into agent waiting" do
    context = build_agent_control_context!(workflow_node_key: "turn_step", workflow_node_type: "turn_step")
    workflow_node = context.fetch(:workflow_node)
    workflow_run = context.fetch(:workflow_run)
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_snapshot: context.fetch(:agent_snapshot),
      request_kind: "execute_tool",
      payload: {
        "task" => {
          "conversation_id" => context.fetch(:conversation).public_id,
          "workflow_node_id" => workflow_node.public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "kind" => "turn_step",
        },
        "tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => "process_exec",
          "arguments" => { "command_line" => "sleep 1" },
        },
      },
      logical_work_id: "tool-call:#{workflow_node.public_id}:tool-call-1",
      dispatch_deadline_at: 2.minutes.from_now,
      execution_hard_deadline_at: 2.minutes.from_now,
      lease_timeout_seconds: 120
    )

    result = nil
    assert_enqueued_with(
      job: Workflows::ResumeBlockedStepJob,
      queue: "workflow_resume",
      args: ->(job_args) do
        job_args.first == workflow_run.public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:expected_waiting_since_at_iso8601] == workflow_run.reload.waiting_since_at&.utc&.iso8601(6)
      end
    ) do
      result = Workflows::BlockNodeForAgentRequest.call(
        workflow_node: workflow_node,
        mailbox_item: mailbox_item,
        request_kind: "execute_tool",
        logical_work_id: "tool-call:#{workflow_node.public_id}:tool-call-1",
        deadline_at: mailbox_item.dispatch_deadline_at,
        occurred_at: Time.current
      )
    end

    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_run.turn.reload.lifecycle_state
    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "agent_request", workflow_run.wait_reason_kind
    assert_equal "WorkflowNode", workflow_run.blocking_resource_type
    assert_equal workflow_node.public_id, workflow_run.blocking_resource_id
    assert_equal mailbox_item.public_id, workflow_run.wait_reason_payload["mailbox_item_id"]
    assert_equal "execute_tool", workflow_run.wait_reason_payload["request_kind"]
    assert_equal mailbox_item.public_id, result.mailbox_item.public_id
  end

  test "retries after a deadlock while persisting waiting state" do
    context = build_agent_control_context!(workflow_node_key: "turn_step", workflow_node_type: "turn_step")
    workflow_node = context.fetch(:workflow_node)
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_snapshot: context.fetch(:agent_snapshot),
      request_kind: "execute_tool",
      payload: {
        "task" => {
          "conversation_id" => context.fetch(:conversation).public_id,
          "workflow_node_id" => workflow_node.public_id,
          "turn_id" => context.fetch(:turn).public_id,
          "kind" => "turn_step",
        },
        "tool_call" => {
          "call_id" => "tool-call-1",
          "tool_name" => "process_exec",
          "arguments" => { "command_line" => "sleep 1" },
        },
      },
      logical_work_id: "tool-call:#{workflow_node.public_id}:tool-call-1",
      dispatch_deadline_at: 2.minutes.from_now,
      execution_hard_deadline_at: 2.minutes.from_now,
      lease_timeout_seconds: 120
    )

    original_transaction = ApplicationRecord.method(:transaction)
    attempts = 0

    ApplicationRecord.singleton_class.define_method(:transaction) do |*args, **kwargs, &block|
      attempts += 1
      raise ActiveRecord::Deadlocked, "simulated deadlock" if attempts == 1

      original_transaction.call(*args, **kwargs, &block)
    end

    result = Workflows::BlockNodeForAgentRequest.call(
      workflow_node: workflow_node,
      mailbox_item: mailbox_item,
      request_kind: "execute_tool",
      logical_work_id: "tool-call:#{workflow_node.public_id}:tool-call-1",
      deadline_at: mailbox_item.dispatch_deadline_at,
      occurred_at: Time.current
    )

    assert_operator attempts, :>=, 2
    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal mailbox_item.public_id, result.mailbox_item.public_id
  ensure
    ApplicationRecord.singleton_class.define_method(:transaction, original_transaction) if original_transaction
  end
end
