module Workflows
  class CreateForTurn
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, root_node_key:, root_node_type:, decision_source:, metadata:)
      @turn = turn
      @root_node_key = root_node_key
      @root_node_type = root_node_type
      @decision_source = decision_source
      @metadata = metadata
    end

    def call
      ApplicationRecord.transaction do
        resolved_model_selection_snapshot = Workflows::ResolveModelSelector.call(
          turn: @turn,
          selector_source: "conversation"
        )
        @turn.update!(resolved_model_selection_snapshot: resolved_model_selection_snapshot)

        workflow_run = WorkflowRun.create!(
          installation: @turn.installation,
          conversation: @turn.conversation,
          turn: @turn,
          lifecycle_state: "active"
        )

        WorkflowNode.create!(
          installation: workflow_run.installation,
          workflow_run: workflow_run,
          ordinal: 0,
          node_key: @root_node_key,
          node_type: @root_node_type,
          decision_source: @decision_source,
          metadata: @metadata
        )

        workflow_run
      end
    end
  end
end
