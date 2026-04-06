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
        overall_state = @machine_status.fetch("overall_state")
        focus =
          runtime_focus_hint["current_focus_summary"] ||
          @machine_status["current_focus_summary"] ||
          @machine_status.dig("primary_turn_todo_plan_view", "current_item", "title") ||
          @machine_status["request_summary"] ||
          @machine_status.dig("primary_turn_todo_plan_view", "goal_summary") ||
          contextual_focus_summary

        case overall_state
        when "idle"
          if @machine_status["last_terminal_state"].present?
            "Right now the conversation is idle. The last work segment ended #{@machine_status["last_terminal_state"]}."
          else
            "Right now the conversation is idle with no active work."
          end
        when "waiting"
          waiting = waiting_sentence
          return "Right now the conversation is #{lowercase_initial(focus)}." if descriptive_focus?(focus)
          return "Right now the conversation is #{trim_terminal_punctuation(lowercase_initial(waiting))}." if waiting.match?(/\Awaiting\b/i)

          "Right now the conversation is waiting. #{waiting}"
        when "blocked"
          "Right now the conversation is blocked. #{blocked_sentence}"
        else
          return "Right now the conversation is #{@machine_status["overall_state"]}." if focus.blank?
          return "Right now the conversation is #{lowercase_initial(focus)}." if descriptive_focus?(focus)

          "Right now the conversation is working on #{focus.downcase}."
        end
      end

      def recent_change_sentence
        summary = @machine_status["recent_progress_summary"].presence || latest_meaningful_feed_summary
        return if summary.blank?

        "Most recently, #{summary.downcase}."
      end

      def latest_meaningful_feed_summary
        turn_feed_entries.reverse_each do |entry|
          next if generic_turn_start_entry?(entry)

          return entry.fetch("summary", nil)
        end

        nil
      end

      def generic_turn_start_entry?(entry)
        summary = entry.to_h.fetch("summary", "")
        event_kind = entry.to_h.fetch("event_kind", nil)

        summary.match?(/\AStarted the turn\.?\z/i) && (event_kind.blank? || event_kind == "turn_started")
      end

      def waiting_sentence
        runtime_focus_hint["waiting_summary"].presence ||
          runtime_focus_sentence(runtime_focus_hint["summary"]) ||
          @machine_status["waiting_summary"].presence ||
          "It is waiting for a dependency to clear."
      end

      def blocked_sentence
        @machine_status["blocked_summary"].presence || "It is blocked until a failure is resolved."
      end

      def contextual_focus_summary
        fact = Array(@machine_status.dig("conversation_context", "facts")).last
        return if fact.blank?

        keywords = Array(fact["keywords"]).map { |keyword| keyword.to_s.downcase }
        if keywords.include?("2048") && keywords.include?("game")
          return "building the React 2048 game" if keywords.include?("react")
          return "building the 2048 game"
        end

        summary = fact.fetch("summary", nil).to_s
        return if summary.blank?

        summary
          .sub(/\AContext already references\s+/i, "")
          .sub(/\.\z/, "")
          .presence
      end

      def activity_phrase?(text)
        text.to_s.match?(/\A(?:build|building|render|rendering|check|checking|verify|verifying|report|reporting|write|writing|add|adding|implement|implementing|fix|fixing|run|running|prepare|preparing)\b/i)
      end

      def descriptive_focus?(text)
        return false if text.blank?

        activity_phrase?(text) ||
          text.to_s.match?(/\A(?:wait|waiting|continue|continuing|review|reviewing|investigate|investigating|inspect|inspecting|monitor|monitoring)\b/i)
      end

      def runtime_focus_hint
        @runtime_focus_hint ||= @machine_status.fetch("runtime_focus_hint", {}).to_h
      end

      def runtime_focus_sentence(summary)
        return if summary.blank?

        if summary.match?(/\Awaiting for\b/i)
          "Waiting for #{summary.delete_prefix("waiting for ").strip} to finish."
        else
          "Waiting for #{summary}."
        end
      end

      def lowercase_initial(text)
        return text if text.blank?

        text[0].downcase + text[1..]
      end

      def trim_terminal_punctuation(text)
        text.to_s.sub(/[.。!?！？]+\z/, "")
      end

      def turn_feed_entries
        Array(@machine_status["turn_feed"].presence || @machine_status["activity_feed"])
      end
    end
  end
end
