module Workflows
  class CreateForTurn
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, root_node_key:, root_node_type:, decision_source:, metadata:, presentation_policy: "internal_only", selector_source: "conversation", selector: nil)
      @turn = turn
      @root_node_key = root_node_key
      @root_node_type = root_node_type
      @decision_source = decision_source
      @metadata = metadata
      @presentation_policy = presentation_policy
      @selector_source = selector_source
      @selector = selector
    end

    def call
      ApplicationRecord.transaction do
        Conversations::RefreshRuntimeContract.call(conversation: @turn.conversation)
        resolved_model_selection_snapshot = Workflows::ResolveModelSelector.call(
          turn: @turn,
          selector_source: @selector_source,
          selector: @selector
        )
        @turn.update!(resolved_model_selection_snapshot: resolved_model_selection_snapshot)
        execution_snapshot = Workflows::BuildExecutionSnapshot.call(turn: @turn)
        @turn.update!(
          resolved_config_snapshot: @turn.resolved_config_snapshot,
          execution_snapshot_payload: execution_snapshot.to_h
        )

        workflow_run = WorkflowRun.create!(
          installation: @turn.installation,
          workspace: @turn.conversation.workspace,
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
          presentation_policy: @presentation_policy,
          decision_source: @decision_source,
          metadata: @metadata
        )

        workflow_run
      end
    end
  end
end
