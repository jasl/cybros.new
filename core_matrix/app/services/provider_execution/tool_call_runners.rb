module ProviderExecution
  module ToolCallRunners
    REGISTRY = {
      "mcp" => "ProviderExecution::ToolCallRunners::MCP",
      "agent" => "ProviderExecution::ToolCallRunners::AgentMediated",
      "kernel" => "ProviderExecution::ToolCallRunners::AgentMediated",
      "execution_runtime" => "ProviderExecution::ToolCallRunners::AgentMediated",
      "core_matrix" => "ProviderExecution::ToolCallRunners::CoreMatrix",
    }.freeze

    class << self
      def fetch!(source_kind)
        REGISTRY.fetch(source_kind.to_s) do
          raise ArgumentError, "unsupported tool implementation source #{source_kind}"
        end.constantize
      end
    end
  end
end
