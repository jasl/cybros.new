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
        "execution_runtime_version_id" => execution_runtime_version&.public_id,
        "agent_definition_version_id" => agent_definition_version.public_id,
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

    def execution_identity
      @execution_identity ||= Conversations::ResolveExecutionContext.call(
        conversation: @conversation,
        allow_unavailable_execution_runtime: true
      )
    end

    def agent_definition_version
      execution_identity.agent_definition_version
    end

    def execution_runtime
      execution_identity.execution_runtime
    end

    def execution_runtime_version
      execution_identity.execution_runtime_version
    end

    def visible_tool_catalog_composer
      @visible_tool_catalog_composer ||= RuntimeCapabilities::ComposeVisibleToolCatalog.new(
        conversation: @conversation,
        agent_definition_version: agent_definition_version,
        execution_runtime: execution_runtime
      )
    end
  end
end
