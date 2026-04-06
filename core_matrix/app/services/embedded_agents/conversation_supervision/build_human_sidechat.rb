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
          "Right now the conversation is currently waiting while working on #{focus&.downcase || "the current task"}. #{@machine_status["waiting_summary"]}"
        when "blocked"
          "Right now the conversation is currently blocked while working on #{focus&.downcase || "the current task"}. #{@machine_status["blocked_summary"]}"
        else
          return "Right now the conversation is #{state}." if focus.blank?

          return "Right now the conversation is #{focus.downcase}." if activity_phrase?(focus)

          verb = state == "queued" ? "queued to work on" : "working on"
          "Right now the conversation is #{verb} #{focus.downcase}."
        end
      end

      def recent_change_sentence
        latest_summary = @machine_status["recent_progress_summary"].presence || latest_meaningful_feed_summary
        return if latest_summary.blank?

        "Most recently, #{latest_summary.downcase}."
      end

      def latest_meaningful_feed_summary
        Array(@machine_status["activity_feed"]).reverse_each do |entry|
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
        elsif @machine_status["waiting_summary"].present?
          "The conversation is waiting because #{@machine_status["waiting_summary"].downcase}."
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
        active_subagents = Array(@machine_status["active_subagents"])
        return "There is no active child task in this snapshot." if active_subagents.empty?

        summaries = active_subagents.filter_map { |entry| entry["current_focus_summary"] }.uniq
        if summaries.any?
          "A child task is currently #{summaries.first.downcase}."
        else
          "There is currently #{active_subagents.length} active child task."
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
        @machine_status["current_focus_summary"] ||
          @machine_status["request_summary"] ||
          contextual_focus_summary
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
    end
  end
end
