require "securerandom"

module AgentControl
  class CreateExecutionAssignment
    ENVELOPE_KEYS = %w[
      protocol_version
      request_kind
      task
      conversation_projection
      capability_projection
      provider_context
      runtime_context
      task_payload
    ].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:, payload:, dispatch_deadline_at:, execution_hard_deadline_at: nil, protocol_message_id: nil, causation_id: nil, lease_timeout_seconds: 30, priority: 1)
      @agent_task_run = agent_task_run
      @payload = payload.deep_stringify_keys
      @dispatch_deadline_at = dispatch_deadline_at
      @execution_hard_deadline_at = execution_hard_deadline_at
      @protocol_message_id = protocol_message_id || "kernel-assignment-#{SecureRandom.uuid}"
      @causation_id = causation_id
      @lease_timeout_seconds = lease_timeout_seconds
      @priority = priority
    end

    def call
      mailbox_item = AgentControlMailboxItem.create!(
        installation: @agent_task_run.installation,
        target_agent_installation: @agent_task_run.agent_installation,
        agent_task_run: @agent_task_run,
        item_type: "execution_assignment",
        runtime_plane: "agent",
        target_kind: "agent_installation",
        target_ref: @agent_task_run.agent_installation.public_id,
        logical_work_id: @agent_task_run.logical_work_id,
        attempt_no: @agent_task_run.attempt_no,
        protocol_message_id: @protocol_message_id,
        causation_id: @causation_id,
        priority: @priority,
        status: "queued",
        available_at: Time.current,
        dispatch_deadline_at: @dispatch_deadline_at,
        lease_timeout_seconds: @lease_timeout_seconds,
        execution_hard_deadline_at: @execution_hard_deadline_at,
        payload: assignment_payload
      )

      @agent_task_run.workflow_node.update!(
        lifecycle_state: "queued",
        started_at: nil,
        finished_at: nil
      )

      PublishPending.call(mailbox_item: mailbox_item)
      mailbox_item
    end

    private

    def assignment_payload
      extra_payload = @payload.except(*ENVELOPE_KEYS)

      base_payload.merge(extra_payload)
    end

    def base_payload
      {
        "protocol_version" => "agent-program/2026-04-01",
        "request_kind" => "execution_assignment",
        "task" => task,
        "conversation_projection" => conversation_projection,
        "capability_projection" => capability_projection,
        "provider_context" => provider_context,
        "runtime_context" => runtime_context,
        "task_payload" => normalized_task_payload,
      }
    end

    def execution_snapshot
      @execution_snapshot ||= @agent_task_run.turn.execution_snapshot
    end

    def normalized_task_payload
      explicit_task_payload = @payload["task_payload"]
      return explicit_task_payload.deep_stringify_keys if explicit_task_payload.is_a?(Hash)

      @agent_task_run.task_payload.deep_stringify_keys
    end

    def task
      {
        "agent_task_run_id" => @agent_task_run.public_id,
        "workflow_run_id" => @agent_task_run.workflow_run.public_id,
        "workflow_node_id" => @agent_task_run.workflow_node.public_id,
        "conversation_id" => @agent_task_run.conversation.public_id,
        "turn_id" => @agent_task_run.turn.public_id,
        "kind" => @agent_task_run.kind,
      }
    end

    def conversation_projection
      execution_snapshot.conversation_projection.merge(
        "prior_tool_results" => Array(@payload["prior_tool_results"]).map { |entry| entry.deep_stringify_keys }
      )
    end

    def capability_projection
      execution_snapshot.capability_projection
    end

    def provider_context
      execution_snapshot.provider_context
    end

    def runtime_context
      execution_snapshot.runtime_context.merge(
        "logical_work_id" => @agent_task_run.logical_work_id,
        "attempt_no" => @agent_task_run.attempt_no,
        "deployment_public_id" => @agent_task_run.turn.agent_deployment.public_id
      )
    end
  end
end
