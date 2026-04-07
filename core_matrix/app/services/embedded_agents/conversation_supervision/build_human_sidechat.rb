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
          return "Right now the conversation is #{lowercase_initial(focus)}." if descriptive_focus?(focus)

          "Right now the conversation is waiting. #{waiting}"
        when "blocked"
          blocked = prompt_payload["blocked_summary"].presence || "It is blocked."
          return "Right now the conversation is #{lowercase_initial(focus)}." if descriptive_focus?(focus)

          "Right now the conversation is blocked. #{blocked}"
        else
          return "Right now the conversation is #{state}." if focus.blank?
          return "Right now the conversation is currently #{lowercase_initial(focus)}." if descriptive_focus?(focus)

          verb = state == "queued" ? "queued to work on" : "working on"
          "Right now the conversation is #{verb} #{focus.downcase}."
        end
      end

      def recent_change_sentence
        latest_summary = prompt_payload["recent_progress_summary"].presence || latest_meaningful_plan_transition
        return if latest_summary.blank?

        "Most recently, #{trim_terminal_punctuation(latest_summary).downcase}."
      end

      def latest_meaningful_plan_transition
        Array(prompt_payload["recent_plan_transitions"]).reverse_each do |entry|
          summary = entry.to_h["summary"].to_s
          next if summary.blank?

          return summary
        end

        nil
      end

      def blocker_sentence
        if prompt_payload["blocked_summary"].present?
          "The current blocker is #{trim_terminal_punctuation(prompt_payload["blocked_summary"]).downcase}."
        elsif prompt_payload["waiting_summary"].present?
          "The conversation is waiting because #{trim_terminal_punctuation(prompt_payload["waiting_summary"]).downcase}."
        else
          "There is no active blocker in this snapshot."
        end
      end

      def next_step_sentence_if_confident
        hint = prompt_payload["next_step_hint"]
        return if hint.blank?

        "The next justified step is #{hint.downcase}."
      end

      def subagent_sentence
        plan_views = Array(prompt_payload["active_subagent_turn_todo_plans"])
        summaries = plan_views.filter_map { |entry| entry["current_item_title"] || entry["goal_summary"] }.uniq
        active_count = plan_views.length.nonzero? || Array(@machine_status["active_subagents"]).length
        return "There is no active child task in this snapshot." if active_count.to_i.zero?

        if summaries.any?
          "A child task is currently #{summaries.first.downcase}."
        else
          "There is currently #{active_count} active child task."
        end
      end

      def conversation_fact_sentence
        matched_snippet = best_matching_context_snippet
        return "This frozen snapshot does not include a matching conversation fact." if matched_snippet.blank?

        excerpt = matched_snippet.fetch("excerpt")
        "A matching context snippet says: #{excerpt}"
      end

      def best_matching_context_snippet
        snippets = Array(prompt_payload["context_snippets"])
        keywords = semantic_terms(@question)

        snippets.max_by do |snippet|
          snippet_keywords = semantic_terms(Array(snippet["keywords"]).join(" "))
          (snippet_keywords & keywords).length
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
          prompt_payload["current_focus_summary"],
          prompt_payload.dig("primary_turn_todo_plan", "current_item_title"),
          prompt_payload["request_summary"],
          prompt_payload.dig("primary_turn_todo_plan", "goal_summary"),
        ].find(&:present?)
      end

      def descriptive_focus?(text)
        text.to_s.match?(/\A(?:build|building|check|checking|verify|verifying|write|writing|add|adding|implement|implementing|fix|fixing|run|running|prepare|preparing|wait|waiting|continue|continuing|review|reviewing|investigate|investigating|inspect|inspecting|monitor|monitoring|resolve|resolving|work|working)\b/i)
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
