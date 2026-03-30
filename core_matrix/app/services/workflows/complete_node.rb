module Workflows
  class CompleteNode
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, occurred_at: Time.current, event_payload: {})
      @workflow_node = workflow_node
      @occurred_at = occurred_at
      @event_payload = event_payload.deep_stringify_keys
    end

    def call
      ApplicationRecord.transaction do
        @workflow_node.with_lock do
          workflow_node = @workflow_node.reload
          return workflow_node if workflow_node.completed?
          return workflow_node if workflow_node.failed? || workflow_node.canceled?

          workflow_node.update!(
            lifecycle_state: "completed",
            started_at: workflow_node.started_at || @occurred_at,
            finished_at: @occurred_at
          )

          WorkflowNodeEvent.create!(
            installation: workflow_node.installation,
            workflow_run: workflow_node.workflow_run,
            workflow_node: workflow_node,
            ordinal: workflow_node.workflow_node_events.maximum(:ordinal).to_i + 1,
            event_kind: "status",
            payload: {
              "state" => "completed",
            }.merge(@event_payload)
          )

          workflow_node
        end
      end
    end
  end
end
