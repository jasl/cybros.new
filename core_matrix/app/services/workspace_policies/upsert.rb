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
      available_capabilities = WorkspacePolicies::Capabilities.available_for(agent: @workspace.user_agent_binding.agent)
      unless (@disabled_capabilities - available_capabilities).empty?
        raise ArgumentError, "disabled_capabilities must be a subset of the available capabilities"
      end

      ApplicationRecord.transaction do
        if @default_execution_runtime != :__preserve__
          @workspace.update!(default_execution_runtime: @default_execution_runtime)
        end

        policy = WorkspacePolicy.find_or_initialize_by(
          installation: @workspace.installation,
          workspace: @workspace
        )
        policy.disabled_capabilities = @disabled_capabilities
        policy.save!
        policy
      end
    end
  end
end
