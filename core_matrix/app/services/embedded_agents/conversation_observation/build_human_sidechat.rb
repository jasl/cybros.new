module EmbeddedAgents
  module ConversationObservation
    class BuildHumanSidechat
      CURRENT_ACTIVITY_KEYWORDS = %w[
        current doing progress status happening active now
      ].freeze
      CURRENT_ACTIVITY_PHRASES = [
        "what are you doing",
        "what are you working on",
        "what is happening",
        "what's happening",
        "in progress",
        "在做",
        "进展",
        "状态",
        "现在",
      ].freeze
      RECENT_CHANGE_KEYWORDS = %w[
        latest recent changed change recently
      ].freeze
      RECENT_CHANGE_PHRASES = [
        "most recently",
        "what changed",
        "what changed most recently",
        "刚才",
        "最近",
        "变化",
      ].freeze
      WAIT_REASON_KEYWORDS = %w[
        waiting blocked stuck why blocker
      ].freeze
      WAIT_REASON_PHRASES = [
        "why are you waiting",
        "why is it waiting",
        "why is it blocked",
        "为什么",
        "阻塞",
        "等待",
        "卡住",
      ].freeze
      SUBAGENT_KEYWORDS = %w[
        subagent child worker delegate delegated
      ].freeze
      SUBAGENT_PHRASES = [
        "子代理",
        "子任务",
      ].freeze
      TRANSCRIPT_DETAIL_KEYWORDS = %w[
        said earlier before detail details discuss discussed
      ].freeze
      TRANSCRIPT_DETAIL_PHRASES = [
        "what did",
        "tell me about",
        "previous plan",
        "earlier plan",
        "before this",
        "方案",
        "细节",
        "之前",
        "刚才说",
        "讨论",
      ].freeze
      def self.call(...)
        new(...).call
      end

      def initialize(question:, assessment:, observation_bundle:, previous_supervisor_status: nil)
        @question = question.to_s
        @assessment = assessment
        @observation_bundle = observation_bundle
        @previous_supervisor_status = previous_supervisor_status.is_a?(Hash) ? previous_supervisor_status : {}
      end

      def call
        {
          "observation_session_id" => @assessment.fetch("observation_session_id"),
          "observation_frame_id" => @assessment.fetch("observation_frame_id"),
          "conversation_id" => @assessment.fetch("conversation_id"),
          "overall_state" => @assessment.fetch("overall_state"),
          "current_activity" => @assessment.fetch("current_activity"),
          "content" => content,
          "proof_refs" => @assessment.fetch("proof_refs"),
        }
      end

      private

      def content
        return BuildHumanSummary.call(assessment: @assessment) if requested_topics.empty?

        segments = requested_topics.filter_map do |topic|
          case topic
          when :current_activity then current_activity_sentence
          when :recent_change then recent_change_sentence
          when :wait_reason then wait_reason_sentence
          when :subagent then subagent_sentence
          when :transcript_detail then transcript_detail_sentence
          end
        end

        segments << grounding_sentence
        segments.uniq.join(" ")
      end

      def requested_topics
        @requested_topics ||= begin
          topics = []
          topics << :current_activity if question_matches?(CURRENT_ACTIVITY_KEYWORDS, CURRENT_ACTIVITY_PHRASES)
          topics << :recent_change if question_matches?(RECENT_CHANGE_KEYWORDS, RECENT_CHANGE_PHRASES)
          topics << :wait_reason if question_matches?(WAIT_REASON_KEYWORDS, WAIT_REASON_PHRASES)
          topics << :subagent if question_matches?(SUBAGENT_KEYWORDS, SUBAGENT_PHRASES)
          topics << :transcript_detail if question_matches?(TRANSCRIPT_DETAIL_KEYWORDS, TRANSCRIPT_DETAIL_PHRASES)
          topics
        end
      end

      def question_matches?(keywords, phrases)
        normalized = normalized_question
        keywords.any? { |keyword| normalized.include?(keyword) } ||
          phrases.any? { |phrase| @question.include?(phrase) || normalized.include?(phrase) }
      end

      def normalized_question
        @normalized_question ||= @question.downcase
      end

      def current_activity_sentence
        case @assessment.fetch("overall_state")
        when "completed"
          "Right now the latest workflow run is completed at #{activity_label}."
        when "failed"
          "Right now the latest workflow run failed at #{activity_label}."
        else
          "Right now the conversation is #{overall_state_phrase}. The current activity is #{humanize(@assessment.fetch("current_activity"))}."
        end
      end

      def overall_state_phrase
        case @assessment.fetch("overall_state")
        when "waiting" then "waiting"
        when "blocked" then "blocked"
        else
          "running"
        end
      end

      def activity_label
        humanize(@assessment.fetch("current_activity"))
          .sub(/\ARunning /, "")
          .sub(/\ACompleted /, "")
          .sub(/\AFailed /, "")
      end

      def recent_change_sentence
        if previous_supervisor_status.blank?
          latest_event_kind = latest_activity_item&.fetch("event_kind", nil)
          return "The most recent durable change in this snapshot was a #{latest_event_kind} event." if latest_event_kind.present?

          return "No durable change has been recorded yet in this snapshot."
        end

        if previous_supervisor_status["overall_state"] != @assessment["overall_state"]
          return "Since the last observation, the conversation moved from #{previous_supervisor_status["overall_state"]} to #{@assessment["overall_state"]}."
        end

        if previous_supervisor_status["current_activity"] != @assessment["current_activity"]
          return "Since the last observation, the current activity moved from #{humanize(previous_supervisor_status["current_activity"])} to #{humanize(@assessment["current_activity"])}."
        end

        previous_latest_sequence = Array(previous_supervisor_status["recent_activity_items"]).last&.fetch("projection_sequence", nil)
        current_latest_sequence = latest_activity_item&.fetch("projection_sequence", nil)
        if current_latest_sequence.present? && current_latest_sequence != previous_latest_sequence
          return "Since the last observation, the latest durable change was a #{latest_activity_item.fetch("event_kind")} event."
        end

        previous_transcript_count = Array(previous_supervisor_status["transcript_refs"]).length
        current_transcript_count = Array(@assessment["transcript_refs"]).length
        return "Since the last observation, new transcript context became available." if current_transcript_count > previous_transcript_count

        "Since the last observation, no newer durable change has been recorded."
      end

      def wait_reason_sentence
        blocking_reason = @assessment["blocking_reason"]
        state = @assessment.fetch("overall_state")

        if blocking_reason.present?
          return "The current blocker is #{humanize(blocking_reason)}."
        end

        if %w[waiting blocked].include?(state)
          "The conversation is #{state}, but this snapshot does not expose a named blocking reason."
        else
          "The conversation is not currently waiting on a named blocker."
        end
      end

      def subagent_sentence
        items = Array(@observation_bundle.dig("subagent_view", "items"))
        return "This snapshot shows no active subagents." if items.empty?

        status_counts = items.each_with_object(Hash.new(0)) do |item, counts|
          counts[item.fetch("observed_status", "unknown")] += 1
        end
        fragments = status_counts.sort.map { |status, count| "#{count} #{humanize(status)}" }
        "This snapshot shows #{items.length} active subagent#{"s" if items.length != 1}: #{fragments.join(", ")}."
      end

      def transcript_detail_sentence
        messages = Array(@observation_bundle.dig("transcript_view", "messages")).last(2)
        return "This snapshot does not include transcript refs to answer that detail question." if messages.empty?

        "This snapshot keeps transcript refs for #{messages.length} recent message#{"s" if messages.length != 1}, but it does not retain raw transcript text. Use the transcript surface for verbatim detail."
      end

      def grounding_sentence
        evidence_parts = ["workflow state"]
        evidence_parts << "transcript context" if Array(@assessment["transcript_refs"]).any?
        evidence_parts << "recent activity" if Array(@assessment["recent_activity_items"]).any?
        evidence_parts << "subagent status" if Array(@assessment.dig("proof_refs", "subagent_session_ids")).any?

        if evidence_parts.one?
          "This answer is grounded in #{evidence_parts.first}."
        else
          "This answer is grounded in #{evidence_parts[0...-1].join(", ")}, and #{evidence_parts.last}."
        end
      end

      def latest_activity_item
        Array(@assessment["recent_activity_items"]).last
      end

      def previous_supervisor_status
        @previous_supervisor_status
      end

      def humanize(value)
        value.to_s.tr("_", " ")
      end
    end
  end
end
