module RuntimeCapabilities
  class ComposeForConversation
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
      @visible_tool_catalog ||= begin
        preview_turn = Turn.new(
          installation: @conversation.installation,
          conversation: @conversation,
          agent_program_version: agent_program_version,
          execution_runtime: execution_runtime,
          lifecycle_state: "queued",
          origin_kind: "manual_user",
          origin_payload: {},
          sequence: @conversation.turns.maximum(:sequence).to_i + 1,
          pinned_program_version_fingerprint: agent_program_version.fingerprint
        )

        RuntimeCapabilities::ComposeForTurn.call(turn: preview_turn).fetch("tool_catalog")
      end
    end

    def agent_program_version
      @agent_program_version ||= Turns::FreezeProgramVersion.call(conversation: @conversation)
    end

    def execution_runtime
      @execution_runtime ||= Turns::SelectExecutionRuntime.call(conversation: @conversation)
    rescue ActiveRecord::RecordInvalid
      nil
    end
  end
end
