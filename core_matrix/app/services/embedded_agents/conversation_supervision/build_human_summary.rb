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
        [current_work_sentence, recent_change_sentence].compact.join(" ")
      end

      private

      def current_work_sentence
        state = prompt_payload.fetch("overall_state")
        focus = current_focus_summary

        case state
        when "idle"
          if prompt_payload["last_terminal_state"].present?
            "Right now the conversation is idle. The last work segment ended #{prompt_payload["last_terminal_state"]}."
          else
            "Right now the conversation is idle with no active work."
          end
        when "waiting"
          waiting = prompt_payload["waiting_summary"].presence || "It is waiting for a dependency to clear."
          return "Right now the conversation is #{lowercase_initial(focus)}." if activity_focus?(focus)

          "Right now the conversation is waiting. #{waiting}"
        when "blocked"
          blocked = prompt_payload["blocked_summary"].presence || "It is blocked until a failure is resolved."
          return "Right now the conversation is #{lowercase_initial(focus)}." if activity_focus?(focus)

          "Right now the conversation is blocked. #{blocked}"
        else
          return "Right now the conversation is #{state}." if focus.blank?
          return "Right now the conversation is #{lowercase_initial(focus)}." if activity_focus?(focus)
          return "Right now the conversation is working on this task: #{focus}." if request_like_focus?(focus)

          "Right now the conversation is working on #{focus.downcase}."
        end
      end

      def recent_change_sentence
        summary = preferred_recent_progress_summary
        return if summary.blank?

        "Most recently, #{trim_terminal_punctuation(summary).downcase}."
      end

      def preferred_recent_progress_summary
        primary_summary = prompt_payload["recent_progress_summary"].presence
        runtime_summary = prompt_payload.dig("runtime_facts", "recent_progress_summary").presence

        if low_signal_recent_progress?(primary_summary) && runtime_summary.present?
          runtime_summary
        else
          primary_summary || runtime_summary || latest_meaningful_plan_transition
        end
      end

      def current_focus_summary
        current_focus = prompt_payload["current_focus_summary"].presence
        runtime_focus = prompt_payload.dig("runtime_facts", "active_focus_summary").presence
        fallback_focus =
          [
            prompt_payload.dig("primary_turn_todo_plan", "current_item_title"),
            prompt_payload["request_summary"],
            prompt_payload.dig("primary_turn_todo_plan", "goal_summary"),
          ].find(&:present?)

        if generic_current_turn_focus?(current_focus)
          runtime_focus || fallback_focus || current_focus
        else
          current_focus || fallback_focus || runtime_focus
        end
      end

      def latest_meaningful_plan_transition
        Array(prompt_payload["recent_plan_transitions"]).reverse_each do |entry|
          summary = entry.to_h["summary"].to_s
          next if summary.blank?

          return summary
        end

        nil
      end

      def activity_focus?(text)
        text.to_s.match?(/\A(?:building|checking|verifying|writing|adding|implementing|fixing|running|preparing|wait|waiting|continuing|reviewing|investigating|inspecting|monitoring|resolving|working)\b/i)
      end

      def request_like_focus?(text)
        text.to_s.match?(/\A(?:build|check|verify|write|add|implement|fix|run|prepare|continue|review|investigate|inspect|monitor|resolve|work)\b/i)
      end

      def low_signal_recent_progress?(text)
        text.to_s.match?(/\A(?:Execution runtime completed the requested tool call|The turn completed|Hit a blocker|Cleared the blocker)\.?\z/i)
      end

      def generic_current_turn_focus?(text)
        text.to_s.match?(/\A(?:Working through the current turn|Waiting on the current workflow step|Resolving the blocked workflow step)\z/i)
      end

      def lowercase_initial(text)
        return text if text.blank?

        text[0].downcase + text[1..]
      end

      def trim_terminal_punctuation(text)
        text.to_s.sub(/[.。!?！？]+\z/, "")
      end

      def prompt_payload
        @prompt_payload ||= Responders::BuildPromptPayload.call(machine_status: @machine_status)
      end
    end
  end
end
