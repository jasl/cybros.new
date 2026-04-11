module Memory
  class Store
    def initialize(workspace_root:, conversation_id:)
      @workspace_root = Pathname.new(workspace_root).expand_path
      @conversation_id = conversation_id.to_s
    end

    def root_memory_path
      @workspace_root.join("MEMORY.md")
    end

    def root_memory
      read_if_exists(root_memory_path)
    end

    def session_summary_path
      session_summary_candidates.find(&:exist?) || session_summary_candidates.first
    end

    def session_summary
      read_if_exists(session_summary_path)
    end

    def summary_payload
      root = root_memory
      summary = session_summary
      combined = [root.presence, summary.presence].compact.join("\n\n")

      {
        "root_memory" => root,
        "session_summary" => summary,
        "summary" => combined.presence,
      }.compact
    end

    private

    def session_summary_candidates
      [
        @workspace_root.join(".nexus", "sessions", @conversation_id, "context", "summary.md"),
        @workspace_root.join(".nexus", "conversations", @conversation_id, "context", "summary.md"),
      ]
    end

    def read_if_exists(path)
      return "" unless path.exist?

      path.read
    end
  end
end
