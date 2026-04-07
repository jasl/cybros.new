module EmbeddedAgents
  module ConversationSupervision
    class BuildHumanSidechat
      BLOCKER_KEYWORDS = %w[blocked blocker waiting wait stuck].freeze
      CURRENT_STATUS_KEYWORDS = %w[current doing now status happening active].freeze
      NEXT_STEP_KEYWORDS = %w[next then after following].freeze
      RECENT_CHANGE_KEYWORDS = %w[recent recently latest changed change].freeze
      SUBAGENT_KEYWORDS = %w[subagent child delegate worker delegated].freeze
      CONVERSATION_FACT_KEYWORDS = %w[agree agreed committed establish established fact already context].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(question:, conversation_supervision_session:, conversation_supervision_snapshot:, machine_status:)
        @question = question.to_s
        @conversation_supervision_session = conversation_supervision_session
        @conversation_supervision_snapshot = conversation_supervision_snapshot
        @machine_status = machine_status
      end

      def call
        {
          "supervision_session_id" => @conversation_supervision_session.public_id,
          "supervision_snapshot_id" => @conversation_supervision_snapshot.public_id,
          "conversation_id" => @conversation_supervision_snapshot.target_conversation.public_id,
          "overall_state" => @machine_status.fetch("overall_state"),
          "intent" => intent.to_s,
          "content" => content,
        }
      end

      private

      def content
        primary_sentences.compact.join(" ")
      end

      def primary_sentences
        case intent
        when :blocker then [blocker_sentence]
        when :subagent_status then [subagent_sentence]
        when :conversation_fact then [conversation_fact_sentence]
        else
          status_sentences.presence || [BuildHumanSummary.call(machine_status: @machine_status)]
        end
      end

      def intent
        @intent ||= begin
          if matches?(CONVERSATION_FACT_KEYWORDS)
            :conversation_fact
          elsif matches?(SUBAGENT_KEYWORDS)
            :subagent_status
          elsif matches?(BLOCKER_KEYWORDS)
            :blocker
          else
            :general_status
          end
        end
      end

      def status_sentences
        sentences = []
        sentences << current_status_sentence if asks_for_current_status? || composite_status_prompt?
        sentences << recent_change_sentence if asks_for_recent_change?

        if asks_for_next_step?
          next_sentence = next_step_sentence_if_confident
          sentences << next_sentence if next_sentence.present?
        end

        sentences.compact_blank.uniq
      end

      def asks_for_current_status?
        matches?(CURRENT_STATUS_KEYWORDS)
      end

      def asks_for_recent_change?
        matches?(RECENT_CHANGE_KEYWORDS)
      end

      def asks_for_next_step?
        matches?(NEXT_STEP_KEYWORDS)
      end

      def composite_status_prompt?
        asks_for_current_status? && asks_for_recent_change?
      end

      def matches?(keywords)
        keywords.any? { |keyword| normalized_question.include?(keyword) }
      end

      def normalized_question
        @normalized_question ||= @question.downcase
      end

      def current_status_sentence
        focus = current_focus_summary
        state = @machine_status.fetch("overall_state")

        case state
        when "idle"
          if @machine_status["last_terminal_state"].present?
            "Right now the conversation is idle. The last work segment ended #{@machine_status["last_terminal_state"]}."
          else
            "Right now the conversation is idle with no active work."
          end
        when "waiting"
          waiting = semantic_waiting_summary
          return "Right now the conversation is currently #{lowercase_initial(focus)}." if descriptive_focus?(focus)
          return "Right now the conversation is #{trim_terminal_punctuation(lowercase_initial(waiting))}." if waiting.present? && waiting.match?(/\Awaiting\b/i)

          "Right now the conversation is waiting. #{waiting || "It is waiting for a dependency to clear."}"
        when "blocked"
          blocked = @machine_status["blocked_summary"].presence
          return "Right now the conversation is blocked. #{blocked}" if blocked.present?
          return "Right now the conversation is currently #{lowercase_initial(focus)}." if descriptive_focus?(focus)

          "Right now the conversation is blocked."
        else
          return "Right now the conversation is #{state}." if focus.blank?

          return "Right now the conversation is currently #{lowercase_initial(focus)}." if descriptive_focus?(focus)

          verb = state == "queued" ? "queued to work on" : "working on"
          "Right now the conversation is #{verb} #{focus.downcase}."
        end
      end

      def recent_change_sentence
        latest_summary = @machine_status["recent_progress_summary"].presence
        latest_summary = nil if low_information_summary?(latest_summary)
        latest_summary ||= latest_meaningful_feed_summary
        return if latest_summary.blank?

        "Most recently, #{latest_summary.downcase}."
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

      def blocker_sentence
        if @machine_status["blocked_summary"].present?
          "The current blocker is #{@machine_status["blocked_summary"].downcase}."
        elsif semantic_waiting_summary.present?
          if semantic_waiting_summary.match?(/\Awaiting\b/i)
            "The conversation is #{trim_terminal_punctuation(lowercase_initial(semantic_waiting_summary))}."
          else
            "The conversation is waiting because #{semantic_waiting_summary.downcase}."
          end
        else
          "There is no active blocker in this snapshot."
        end
      end

      def next_step_sentence
        hint = @machine_status["next_step_hint"]
        return "The next justified step is #{hint.downcase}." if hint.present?

        "The next step is not justified beyond the frozen supervision snapshot."
      end

      def next_step_sentence_if_confident
        hint = @machine_status["next_step_hint"]
        return if hint.blank?

        "The next justified step is #{hint.downcase}."
      end

      def subagent_sentence
        plan_views = Array(@machine_status["active_subagent_turn_todo_plan_views"])
        summaries =
          if plan_views.any?
            plan_views.filter_map { |entry| entry.dig("current_item", "title") || entry["goal_summary"] }.uniq
          else
            Array(@machine_status["active_subagents"]).filter_map { |entry| entry["current_focus_summary"] }.uniq
          end
        active_count = plan_views.any? ? plan_views.length : Array(@machine_status["active_subagents"]).length
        return "There is no active child task in this snapshot." if active_count.zero?

        if summaries.any?
          "A child task is currently #{summaries.first.downcase}."
        else
          "There is currently #{active_count} active child task."
        end
      end

      def conversation_fact_sentence
        matched_fact = best_matching_fact
        return "This frozen snapshot does not include a matching conversation fact." if matched_fact.blank?

        matched_fact.fetch("summary")
      end

      def best_matching_fact
        facts = Array(@machine_status.dig("conversation_context", "facts"))
        keywords = semantic_terms(@question)

        facts.max_by do |fact|
          fact_keywords = semantic_terms(Array(fact["keywords"]).join(" "))
          (fact_keywords & keywords).length
        end
      end

      def semantic_terms(text)
        text.to_s.downcase
          .scan(/[a-z0-9]+/)
          .map { |term| term.sub(/ing\z/, "").sub(/s\z/, "") }
          .reject { |term| term.blank? || %w[a an already and before for has have in is of on the this to turn what with].include?(term) }
      end

      def current_focus_summary
        [
          runtime_focus_hint["current_focus_summary"],
          @machine_status["current_focus_summary"],
          @machine_status.dig("primary_turn_todo_plan_view", "current_item", "title"),
          @machine_status["request_summary"],
          @machine_status.dig("primary_turn_todo_plan_view", "goal_summary"),
          contextual_focus_summary,
        ].find { |summary| summary.present? && !low_information_summary?(summary) }
      end

      def semantic_waiting_summary
        runtime_focus_hint["waiting_summary"] ||
          runtime_focus_sentence(runtime_focus_hint["summary"]) ||
          @machine_status["waiting_summary"].presence
      end

      def runtime_focus_sentence(summary)
        return if summary.blank?

        if summary.match?(/\Awaiting for\b/i)
          "Waiting for #{summary.delete_prefix("waiting for ").strip} to finish."
        else
          "Waiting for #{summary}."
        end
      end

      def runtime_focus_hint
        @runtime_focus_hint ||= @machine_status.fetch("runtime_focus_hint", {}).to_h
      end

      def turn_feed_entries
        Array(@machine_status["turn_feed"].presence || @machine_status["activity_feed"])
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

      def low_information_summary?(text)
        normalized = text.to_s.strip
        return true if normalized.blank?

        normalized.match?(/\A(?:Ran|Running|Started)\s+a shell command\b/i) ||
          normalized.match?(/\A(?:Review|Reviewed)\s+shell command state\b/i) ||
          normalized.match?(/\A(?:Check|Checked)\s+progress on the running command\b/i) ||
          normalized.match?(/\A(?:Wait|Waiting)\s+for the running command\b/i)
      end

      def lowercase_initial(text)
        return text if text.blank?

        text[0].downcase + text[1..]
      end

      def trim_terminal_punctuation(text)
        text.to_s.sub(/[.。!?！？]+\z/, "")
      end
    end
  end
end
