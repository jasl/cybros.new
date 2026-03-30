module Fenix
  module Prompts
    class Assembler
      AGENT_PROMPT = <<~TEXT.freeze
        You are Fenix, the default agent runtime for Core Matrix.
        Follow the code-owned agent instructions first, then apply workspace overrides.
      TEXT

      def self.call(...)
        new(...).call
      end

      def initialize(workspace_root:, conversation_id:, profile: "main", is_subagent: false)
        @layout = Fenix::Workspace::Layout.new(workspace_root:, conversation_id:)
        @memory_store = Fenix::Memory::Store.new(workspace_root:, conversation_id:)
        @profile = profile
        @is_subagent = is_subagent
      end

      def call
        payload = {
          "agent_prompt" => AGENT_PROMPT,
          "soul" => prompt_contents("SOUL.md", built_in_prompt("SOUL.md")),
          "user" => prompt_contents("USER.md", built_in_prompt("USER.md")),
          "memory" => @memory_store.root_memory,
          "conversation_summary" => @memory_store.conversation_summary,
        }

        return payload unless include_operator_layer?

        payload.merge(
          "operator_prompt" => built_in_prompt("OPERATOR.md"),
          "operator_state" => current_operator_state
        )
      end

      private

      def include_operator_layer?
        @profile == "main" && !@is_subagent
      end

      def current_operator_state
        path = @layout.conversation_operator_state_file
        return {} unless path&.exist?

        JSON.parse(path.read)
      rescue JSON::ParserError
        {}
      end

      def prompt_contents(filename, fallback)
        override = @layout.workspace_root.join(filename)
        return override.read if override.exist?

        fallback
      end

      def built_in_prompt(filename)
        Rails.root.join("prompts", filename).read
      end
    end
  end
end
