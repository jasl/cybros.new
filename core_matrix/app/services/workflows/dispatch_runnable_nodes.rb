module Workflows
  class DispatchRunnableNodes
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, workflow_node_key: nil, runnable_nodes: nil)
      @workflow_run = workflow_run
      @workflow_node_key = workflow_node_key&.to_s
      @runnable_nodes = runnable_nodes
    end

    def call
      dispatched_nodes = []

      ApplicationRecord.transaction do
        @workflow_run.with_lock do
          runnable_nodes.each do |workflow_node|
            workflow_node.with_lock do
              next unless workflow_node.pending?

              mark_queued!(workflow_node)
              dispatched_nodes << workflow_node
            end
          end
        end
      end

      dispatched_nodes.each do |workflow_node|
        queue_name = queue_name_for(workflow_node)
        Workflows::ExecuteNodeJob.set(queue: queue_name).perform_later(
          workflow_node.public_id,
          enqueued_at_iso8601: Time.current.iso8601(6),
          queue_name: queue_name
        )
      end

      dispatched_nodes.sort_by(&:ordinal)
    end

    private

    def runnable_nodes
      nodes = @runnable_nodes || Workflows::Scheduler.call(workflow_run: @workflow_run)
      return nodes if @workflow_node_key.blank?

      nodes.select { |workflow_node| workflow_node.node_key == @workflow_node_key }
    end

    def mark_queued!(workflow_node)
      updated_at = Time.current

      workflow_node.lifecycle_state = "queued"
      workflow_node.started_at = nil
      workflow_node.finished_at = nil
      workflow_node.updated_at = updated_at
      workflow_node.update_columns(
        lifecycle_state: "queued",
        started_at: nil,
        finished_at: nil,
        updated_at: updated_at,
      )
    end

    def queue_name_for(workflow_node)
      case workflow_node.node_type
      when "turn_step"
        RuntimeTopology::CoreMatrix.llm_queue_name(workflow_node.turn.resolved_provider_handle)
      when "tool_call"
        RuntimeTopology::CoreMatrix.shared_queue_name("tool_calls")
      when "prompt_compaction"
        RuntimeTopology::CoreMatrix.shared_queue_name("workflow_default")
      else
        RuntimeTopology::CoreMatrix.shared_queue_name("workflow_default")
      end
    end
  end
end
