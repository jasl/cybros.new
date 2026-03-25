module Workflows
  class ProjectionQuery
    ProjectionBundle = Struct.new(
      :workflow_run,
      :nodes,
      :edges,
      :events_by_node_key,
      :artifacts_by_node_key,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:)
      @workflow_run = workflow_run
    end

    def call
      nodes = WorkflowNode.where(workflow_run: @workflow_run).order(:ordinal).to_a
      edges = WorkflowEdge.where(workflow_run: @workflow_run).order(:from_node_id, :ordinal).to_a
      events_by_node_key = WorkflowNodeEvent
        .where(workflow_run: @workflow_run)
        .order(:workflow_node_ordinal, :ordinal)
        .group_by(&:workflow_node_key)
      artifacts_by_node_key = WorkflowArtifact
        .where(workflow_run: @workflow_run)
        .order(:workflow_node_ordinal, :artifact_kind, :artifact_key)
        .group_by(&:workflow_node_key)

      ProjectionBundle.new(
        workflow_run: @workflow_run.reload,
        nodes: nodes,
        edges: edges,
        events_by_node_key: events_by_node_key,
        artifacts_by_node_key: artifacts_by_node_key
      )
    end
  end
end
