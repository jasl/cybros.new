module Workflows
  class ExecuteNodeJob < ApplicationJob
    queue_as :workflow_default

    def perform(workflow_node_id)
      workflow_node = WorkflowNode.find_by_public_id!(workflow_node_id)
      return if workflow_node.terminal? || workflow_node.running?

      Workflows::ExecuteNode.call(workflow_node: workflow_node)
    end
  end
end
