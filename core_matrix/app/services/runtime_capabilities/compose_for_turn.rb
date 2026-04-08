module RuntimeCapabilities
  class ComposeForTurn
    ToolNotVisibleError = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def self.visible_tool_entry!(turn:, tool_name:)
      new(turn: turn).visible_tool_entry!(tool_name:)
    end

    def initialize(turn:)
      @turn = turn
    end

    def call
      {
        "executor_program_id" => @turn.executor_program&.public_id,
        "agent_program_version_id" => @turn.agent_program_version.public_id,
        "tool_catalog" => visible_tool_catalog,
      }.compact
    end

    def visible_tool_entry!(tool_name:)
      visible_tool_catalog.find { |entry| entry.fetch("tool_name") == tool_name } ||
        raise(ToolNotVisibleError, "#{tool_name} is not visible for turn #{@turn.public_id}")
    end

    def contract
      visible_tool_catalog_composer.contract
    end

    def current_profile_key
      visible_tool_catalog_composer.current_profile_key
    end

    private

    def visible_tool_catalog
      @visible_tool_catalog ||= visible_tool_catalog_composer.call
    end

    def visible_tool_catalog_composer
      @visible_tool_catalog_composer ||= RuntimeCapabilities::ComposeVisibleToolCatalog.new(
        conversation: @turn.conversation,
        agent_program_version: @turn.agent_program_version,
        executor_program: @turn.executor_program
      )
    end
  end
end
