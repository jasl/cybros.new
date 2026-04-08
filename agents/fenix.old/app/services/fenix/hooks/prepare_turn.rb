module Fenix
  module Hooks
    class PrepareTurn
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        transcript_messages = Array(@context.fetch("context_messages")).map(&:deep_stringify_keys)
        likely_model =
          @context.dig("model_context", "likely_model") ||
          @context.dig("model_context", "model_ref") ||
          @context.dig("model_context", "api_model") ||
          @context.dig("provider_execution", "model_ref")
        agent_context = @context.fetch("agent_context", {}).deep_stringify_keys
        skill_selection = Fenix::Runtime::SelectRoundSkills.call(messages: transcript_messages)
        prompt_message = {
          "role" => "system",
          "content" => Fenix::Runtime::BuildRoundPrompt.call(
            prompts: @context.dig("workspace_context", "prompts") || {},
            context_imports: @context.fetch("context_imports", []),
            skill_selection:
          ),
        }
        messages = [prompt_message] + transcript_messages

        {
          "messages" => messages,
          "likely_model" => likely_model,
          "agent_context" => agent_context,
          "estimated_message_count" => EstimateMessages.call(messages: messages),
          "estimated_token_count" => EstimateTokens.call(messages: messages),
          "trace" => {
            "hook" => "prepare_turn",
            "message_count" => EstimateMessages.call(messages: messages),
            "estimated_token_count" => EstimateTokens.call(messages: messages),
            "likely_model" => likely_model,
            "profile" => agent_context["profile"],
            "is_subagent" => agent_context["is_subagent"] == true,
            "allowed_tool_names" => Array(agent_context["allowed_tool_names"]),
            "active_skill_names" => Array(skill_selection["active_catalog"]).map { |entry| entry.fetch("name") },
            "selected_skill_names" => Array(skill_selection["selected_skills"]).map { |entry| entry.fetch("name") },
          },
        }
      end
    end
  end
end
