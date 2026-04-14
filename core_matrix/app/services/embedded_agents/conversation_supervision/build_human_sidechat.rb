module EmbeddedAgents
  module ConversationSupervision
    class BuildHumanSidechat
      BLOCKER_KEYWORDS = %w[blocked blocker waiting wait stuck].freeze
      COMPLETION_KEYWORDS = %w[complete completed finish finished done].freeze
      CURRENT_STATUS_KEYWORDS = %w[current doing now status happening active].freeze
      NEXT_STEP_KEYWORDS = %w[next then after following].freeze
      RECENT_CHANGE_KEYWORDS = %w[recent recently latest changed change progress progressed progressing].freeze
      SUBAGENT_KEYWORDS = %w[subagent child delegate worker delegated].freeze
      CONVERSATION_FACT_KEYWORDS = %w[agree agreed committed establish established fact already context].freeze
      CHINESE_COMPLETION_KEYWORDS = %w[完成 做完 结束 搞定].freeze

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
        when :completion_status then completion_status_sentences
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
          elsif completion_question?
            :completion_status
          elsif matches?(BLOCKER_KEYWORDS)
            :blocker
          else
            :general_status
          end
        end
      end

      def completion_question?
        COMPLETION_KEYWORDS.any? { |keyword| normalized_question.include?(keyword) } ||
          CHINESE_COMPLETION_KEYWORDS.any? { |keyword| normalized_chinese_question.include?(keyword) }
      end

      def completion_status_sentences
        [completion_state_sentence, completion_plan_sentence].compact
      end

      def completion_state_sentence
        chinese_question? ? chinese_completion_state_sentence : english_completion_state_sentence
      end

      def english_completion_state_sentence
        state = prompt_payload.fetch("overall_state")
        focus = current_focus_summary

        case state
        when "idle"
          case prompt_payload["last_terminal_state"]
          when "completed"
            "There is no active work right now. The latest work segment completed."
          when "failed"
            "There is no active work right now. The latest work segment failed."
          when "interrupted", "canceled"
            "There is no active work right now. The latest work segment was interrupted."
          else
            "There is no active work right now."
          end
        when "waiting"
          waiting = trim_terminal_punctuation(prompt_payload["waiting_summary"].presence || "The conversation is waiting on a dependency to clear")
          "There is still active work right now. #{waiting}."
        when "blocked"
          blocked = trim_terminal_punctuation(prompt_payload["blocked_summary"].presence || "Waiting for the blocker to clear")
          "There is still active work right now. The conversation is currently blocked. #{blocked}."
        when "queued"
          return "There is still active work right now. The conversation is queued to work on this task: #{focus}." if focus.present?

          "There is still active work right now. The conversation is queued to continue."
        else
          return "There is still active work right now." if focus.blank?
          return "There is still active work right now. The conversation is currently #{lowercase_initial(focus)}." if activity_focus?(focus)
          return "There is still active work right now. The conversation is working on this task: #{focus}." if request_like_focus?(focus)

          "There is still active work right now. The conversation is working on #{focus.downcase}."
        end
      end

      def chinese_completion_state_sentence
        state = prompt_payload.fetch("overall_state")
        focus = current_focus_summary

        case state
        when "idle"
          case prompt_payload["last_terminal_state"]
          when "completed"
            "当前没有活跃工作。最近一段执行已完成。"
          when "failed"
            "当前没有活跃工作，但最近一段执行以失败结束。"
          when "interrupted", "canceled"
            "当前没有活跃工作，但最近一段执行已中断。"
          else
            "当前没有活跃工作。"
          end
        when "waiting"
          waiting = trim_terminal_punctuation(prompt_payload["waiting_summary"].presence || "当前正在等待依赖解除")
          "当前仍有活跃工作，正在等待。#{waiting}。"
        when "blocked"
          blocked = trim_terminal_punctuation(prompt_payload["blocked_summary"].presence || "当前被阻塞")
          "当前仍有活跃工作，当前被阻塞。#{blocked}。"
        when "queued"
          return "当前仍有活跃工作，正排队处理这项任务：#{focus}。" if focus.present?

          "当前仍有活跃工作，正排队等待执行。"
        else
          return "当前仍有活跃工作。" if focus.blank?

          "当前仍有活跃工作，当前焦点是：#{focus}。"
        end
      end

      def completion_plan_sentence
        plan = prompt_payload["primary_turn_todo_plan"].to_h
        return if plan.blank?

        completed_count = plan["completed_item_count"].to_i
        total_count = plan["total_item_count"].to_i
        current_item_title = plan["current_item_title"].presence

        if chinese_question?
          return %(可见计划已完成 #{completed_count}/#{total_count} 项，当前项是“#{current_item_title}”。) if total_count.positive? && current_item_title.present?
          return %(可见计划已完成 #{completed_count}/#{total_count} 项。) if total_count.positive?
          return %(当前可见计划项是“#{current_item_title}”。) if current_item_title.present?
        else
          return %(The visible plan shows #{completed_count}/#{total_count} items completed, and the current item is "#{current_item_title}".) if total_count.positive? && current_item_title.present?
          return "The visible plan shows #{completed_count}/#{total_count} items completed." if total_count.positive?
          return %(The current visible plan item is "#{current_item_title}".) if current_item_title.present?
        end

        nil
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

      def normalized_chinese_question
        @normalized_chinese_question ||= @question.gsub(/[[:space:][:punct:]“”‘’！？。、「」『』（）【】]/, "")
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
          return "Right now the conversation is #{lowercase_initial(focus)}." if activity_focus?(focus)

          "Right now the conversation is waiting. #{waiting}"
        when "blocked"
          blocked = prompt_payload["blocked_summary"].presence || "It is blocked."
          return "Right now the conversation is #{lowercase_initial(focus)}." if activity_focus?(focus)

          "Right now the conversation is blocked. #{blocked}"
        else
          return "Right now the conversation is #{state}." if focus.blank?
          return "Right now the conversation is currently #{lowercase_initial(focus)}." if activity_focus?(focus)

          verb = state == "queued" ? "queued to work on" : "working on"
          return "Right now the conversation is #{verb} this task: #{focus}." if request_like_focus?(focus)

          "Right now the conversation is #{verb} #{focus.downcase}."
        end
      end

      def recent_change_sentence
        latest_summary = preferred_recent_progress_summary
        return if latest_summary.blank?

        "Most recently, #{trim_terminal_punctuation(latest_summary).downcase}."
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

      def chinese_question?
        @question.match?(/\p{Han}/)
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
        text.to_s.match?(/\AWorking through the current turn\z/i)
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
