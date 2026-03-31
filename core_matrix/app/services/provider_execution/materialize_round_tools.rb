module ProviderExecution
  class MaterializeRoundTools
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_catalog:)
      @workflow_node = workflow_node
      @tool_catalog = Array(tool_catalog).map { |entry| entry.deep_stringify_keys }
    end

    def call
      ToolBindings::FreezeForWorkflowNode.call(
        workflow_node: @workflow_node,
        tool_catalog: @tool_catalog
      )
    end
  end
end
