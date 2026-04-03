module ProviderExecution
  module ToolCallRunners
    REGISTRY = {
      "mcp" => "ProviderExecution::ToolCallRunners::MCP",
      "agent" => "ProviderExecution::ToolCallRunners::Program",
      "kernel" => "ProviderExecution::ToolCallRunners::Program",
      "execution_runtime" => "ProviderExecution::ToolCallRunners::Program",
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
