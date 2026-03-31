module Workflows
  class DispatchRunnableNodes
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, workflow_node_key: nil)
      @workflow_run = workflow_run
      @workflow_node_key = workflow_node_key&.to_s
    end

    def call
      dispatched_node_ids = []

      ApplicationRecord.transaction do
        @workflow_run.with_lock do
          runnable_nodes.each do |workflow_node|
            workflow_node.with_lock do
              workflow_node.reload
              next unless workflow_node.pending?

              workflow_node.update!(
                lifecycle_state: "queued",
                started_at: nil,
                finished_at: nil
              )
              dispatched_node_ids << workflow_node.public_id
            end
          end
        end
      end

      dispatched_node_ids.each do |workflow_node_id|
        workflow_node = WorkflowNode.find_by_public_id!(workflow_node_id)
        Workflows::ExecuteNodeJob.set(queue: queue_name_for(workflow_node)).perform_later(workflow_node_id)
      end

      WorkflowNode.where(public_id: dispatched_node_ids).order(:ordinal).to_a
    end

    private

    def runnable_nodes
      nodes = Workflows::Scheduler.call(workflow_run: @workflow_run.reload)
      return nodes if @workflow_node_key.blank?

      nodes.select { |workflow_node| workflow_node.node_key == @workflow_node_key }
    end

    def queue_name_for(workflow_node)
      case workflow_node.node_type
      when "turn_step"
        RuntimeTopology::CoreMatrix.llm_queue_name(workflow_node.turn.resolved_provider_handle)
      when "tool_call"
        RuntimeTopology::CoreMatrix.shared_queue_name("tool_calls")
      else
        RuntimeTopology::CoreMatrix.shared_queue_name("workflow_default")
      end
    end
  end
end
