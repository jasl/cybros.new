module EmbeddedAgents
  module ConversationSupervision
    class BuildHumanSummary
      def self.call(...)
        new(...).call
      end

      def initialize(machine_status:)
        @machine_status = machine_status
      end

      def call
        [current_work_sentence, recent_change_sentence, grounding_sentence].compact.join(" ")
      end

      private

      def current_work_sentence
        overall_state = @machine_status.fetch("overall_state")
        focus = @machine_status["current_focus_summary"] || @machine_status["request_summary"]

        case overall_state
        when "idle"
          if @machine_status["last_terminal_state"].present?
            "Right now the conversation is idle. The last work segment ended #{@machine_status["last_terminal_state"]}."
          else
            "Right now the conversation is idle with no active work."
          end
        when "waiting"
          "Right now the conversation is waiting. #{waiting_sentence}"
        when "blocked"
          "Right now the conversation is blocked. #{blocked_sentence}"
        else
          return "Right now the conversation is #{@machine_status["overall_state"]}." if focus.blank?

          "Right now the conversation is working on #{focus.downcase}."
        end
      end

      def recent_change_sentence
        latest_entry = Array(@machine_status["activity_feed"]).last
        summary = latest_entry&.fetch("summary", nil) || @machine_status["recent_progress_summary"]
        return if summary.blank?

        "Most recently, #{summary.downcase}."
      end

      def waiting_sentence
        @machine_status["waiting_summary"].presence || "It is waiting for a dependency to clear."
      end

      def blocked_sentence
        @machine_status["blocked_summary"].presence || "It is blocked until a failure is resolved."
      end

      def grounding_sentence
        parts = ["the frozen supervision state"]
        parts << "recent activity" if Array(@machine_status["activity_feed"]).any?
        parts << "compact context facts" if Array(@machine_status.dig("conversation_context", "facts")).any?

        if parts.one?
          "Grounded in #{parts.first}."
        else
          "Grounded in #{parts[0...-1].join(", ")} and #{parts.last}."
        end
      end
    end
  end
end
