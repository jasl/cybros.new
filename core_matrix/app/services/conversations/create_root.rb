module Conversations
  class CreateRoot
    include Conversations::CreationSupport

    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, agent_program: nil, purpose: "interactive", **_ignored)
      @workspace = workspace
      @agent_program = agent_program || workspace.user_program_binding.agent_program
      @purpose = purpose
    end

    def call
      ApplicationRecord.transaction do
        create_root_conversation!(
          workspace: @workspace,
          agent_program: @agent_program,
          purpose: @purpose
        )
      end
    end
  end
end
