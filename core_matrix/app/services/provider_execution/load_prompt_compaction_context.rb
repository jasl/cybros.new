module ProviderExecution
  class LoadPromptCompactionContext
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:)
      @workflow_node = workflow_node
      @workflow_run = workflow_node.workflow_run
    end

    def call
      return if artifact_key.blank? || source_node_key.blank?

      source_node = @workflow_run.workflow_nodes.find_by!(node_key: source_node_key)
      artifact = @workflow_run.workflow_artifacts.find_by!(
        workflow_node: source_node,
        artifact_kind: "prompt_compaction_context",
        artifact_key: artifact_key
      )
      return if artifact.payload.blank?

      Array(artifact.payload["messages"]).map { |entry| entry.deep_stringify_keys }
    end

    private

    def metadata
      @metadata ||= @workflow_node.metadata.is_a?(Hash) ? @workflow_node.metadata.deep_stringify_keys : {}
    end

    def artifact_key
      metadata["prompt_compaction_artifact_key"]
    end

    def source_node_key
      metadata["prompt_compaction_source_node_key"]
    end
  end
end
