require "securerandom"

module AgentControl
  class CreateExecutionAssignment
    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, payload:, dispatch_deadline_at:, execution_hard_deadline_at: nil, message_id: nil, causation_id: nil, lease_timeout_seconds: 30)
      @agent_task_run = agent_task_run
      @payload = payload.deep_stringify_keys
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @message_id = message_id || "kernel-assignment-#{SecureRandom.uuid}"
      @causation_id = causation_id
      @lease_timeout_seconds = lease_timeout_seconds
    end

    def call
      mailbox_item = AgentControlMailboxItem.create!(
        installation: @agent_task_run.installation,
        target_agent_installation: @agent_task_run.agent_installation,
        agent_task_run: @agent_task_run,
        item_type: "execution_assignment",
        target_kind: "agent_installation",
        target_ref: @agent_task_run.agent_installation.public_id,
        logical_work_id: @agent_task_run.logical_work_id,
        attempt_no: @agent_task_run.attempt_no,
        message_id: @message_id,
        causation_id: @causation_id,
        priority: 1,
        status: "queued",
        available_at: Time.current,
        dispatch_deadline_at: @dispatch_deadline_at,
        lease_timeout_seconds: @lease_timeout_seconds,
        execution_hard_deadline_at: @execution_hard_deadline_at,
        payload: base_payload.merge(@payload)
      )

      PublishPending.call(mailbox_item: mailbox_item)
      mailbox_item
    end

    private

    def base_payload
      {
        "agent_task_run_id" => @agent_task_run.public_id,
        "workflow_run_id" => @agent_task_run.workflow_run.public_id,
        "workflow_node_id" => @agent_task_run.workflow_node.public_id,
        "conversation_id" => @agent_task_run.conversation.public_id,
        "turn_id" => @agent_task_run.turn.public_id,
        "task_kind" => @agent_task_run.task_kind,
      }
    end
  end
end
