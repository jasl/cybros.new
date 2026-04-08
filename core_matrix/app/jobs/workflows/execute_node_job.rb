require "time"

module Workflows
  class ExecuteNodeJob < ApplicationJob
    queue_as :workflow_default

    def perform(workflow_node_id, enqueued_at_iso8601: nil, queue_name: nil)
      workflow_node = WorkflowNode.find_by_public_id!(workflow_node_id)
      return if workflow_node.workflow_run.waiting?

      publish_queue_delay_event!(workflow_node, enqueued_at_iso8601:, queue_name:)
      return if workflow_node.terminal? || workflow_node.running?

      Workflows::ExecuteNode.call(workflow_node: workflow_node)
    rescue ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError
      nil
    end

    private

    def publish_queue_delay_event!(workflow_node, enqueued_at_iso8601:, queue_name:)
      enqueued_at = parse_enqueued_at(enqueued_at_iso8601)
      return if enqueued_at.blank?

      payload = {
        "workflow_node_public_id" => workflow_node.public_id,
        "workspace_public_id" => workflow_node.workspace.public_id,
        "conversation_public_id" => workflow_node.conversation.public_id,
        "turn_public_id" => workflow_node.turn.public_id,
        "agent_program_public_id" => workflow_node.conversation.agent_program.public_id,
        "queue_name" => queue_name.presence || self.queue_name,
        "queue_delay_ms" => ((Time.current - enqueued_at) * 1000.0).round(3),
        "success" => true,
        "metadata" => {
          "node_type" => workflow_node.node_type,
        },
      }

      ActiveSupport::Notifications.instrument("perf.workflows.execute_node_queue_delay", payload)
    end

    def parse_enqueued_at(value)
      return if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
