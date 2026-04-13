module WorkspacePolicies
  class Upsert
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, disabled_capabilities:, default_execution_runtime: :__preserve__)
      @workspace = workspace
      @disabled_capabilities = Array(disabled_capabilities).map(&:to_s).uniq
      @default_execution_runtime = default_execution_runtime
    end

    def call
      available_capabilities = WorkspacePolicies::Capabilities.available_for(agent: @workspace.agent)
      unless (@disabled_capabilities - available_capabilities).empty?
        raise ArgumentError, "disabled_capabilities must be a subset of the available capabilities"
      end

      ApplicationRecord.transaction do
        updates = { disabled_capabilities: @disabled_capabilities }
        updates[:default_execution_runtime] = @default_execution_runtime if @default_execution_runtime != :__preserve__
        @workspace.update!(updates)
        @workspace
      end
    end
  end
end
