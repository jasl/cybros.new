module RuntimeCapabilities
  class PreviewForConversation
    ToolNotVisibleError = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def self.visible_tool_entry!(conversation:, tool_name:)
      new(conversation: conversation).visible_tool_entry!(tool_name:)
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      {
        "executor_program_id" => executor_program&.public_id,
        "agent_program_version_id" => agent_program_version.public_id,
        "tool_catalog" => visible_tool_catalog,
      }.compact
    end

    def visible_tool_entry!(tool_name:)
      visible_tool_catalog.find { |entry| entry.fetch("tool_name") == tool_name } ||
        raise(ToolNotVisibleError, "#{tool_name} is not visible for conversation #{@conversation.public_id}")
    end

    private

    def visible_tool_catalog
      @visible_tool_catalog ||= visible_tool_catalog_composer.call
    end

    def agent_program_version
      @agent_program_version ||= Turns::FreezeProgramVersion.call(conversation: @conversation)
    end

    def executor_program
      @executor_program ||= Turns::SelectExecutorProgram.call(conversation: @conversation)
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def visible_tool_catalog_composer
      @visible_tool_catalog_composer ||= RuntimeCapabilities::ComposeVisibleToolCatalog.new(
        conversation: @conversation,
        agent_program_version: agent_program_version,
        executor_program: executor_program
      )
    end
  end
end
