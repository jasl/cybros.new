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
        "execution_runtime_id" => execution_runtime&.public_id,
        "agent_snapshot_id" => agent_snapshot.public_id,
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

    def agent_snapshot
      @agent_snapshot ||= Turns::FreezeAgentSnapshot.call(conversation: @conversation)
    end

    def execution_runtime
      @execution_runtime ||= Turns::SelectExecutionRuntime.call(conversation: @conversation)
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def visible_tool_catalog_composer
      @visible_tool_catalog_composer ||= RuntimeCapabilities::ComposeVisibleToolCatalog.new(
        conversation: @conversation,
        agent_snapshot: agent_snapshot,
        execution_runtime: execution_runtime
      )
    end
  end
end
