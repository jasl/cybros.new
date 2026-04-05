module EmbeddedAgents
  module ConversationObservation
    class BuildHumanSummary
      def self.call(...)
        new(...).call
      end

      def initialize(assessment:, supervisor_status:)
        @assessment = assessment
        @supervisor_status = supervisor_status
      end

      def call
        [
          "The conversation is currently #{overall_state}.",
          human_state_sentence,
          latest_activity_sentence,
          grounding_sentence,
        ].compact.join(" ")
      end

      private

      def overall_state
        @assessment.fetch("overall_state")
      end

      def current_activity
        @assessment.fetch("current_activity")
      end

      def blocking_reason
        @assessment["blocking_reason"]
      end

      def recent_activity_items
        Array(@supervisor_status["recent_activity_items"])
      end

      def transcript_refs
        Array(@supervisor_status["transcript_refs"])
      end

      def proof_refs
        @supervisor_status.fetch("proof_refs")
      end

      def human_state_sentence
        node_label = human_node_label

        case overall_state
        when "waiting"
          if blocking_reason == "subagent_barrier"
            "It is waiting for a running subagent before work on #{node_label} can continue."
          elsif blocking_reason.present?
            "It is waiting on #{humanize_token(blocking_reason)} before work on #{node_label} can continue."
          else
            "It is waiting before work on #{node_label} can continue."
          end
        when "blocked"
          if blocking_reason.present?
            "It is blocked on #{humanize_token(blocking_reason)} while work on #{node_label} is paused."
          else
            "It is blocked while work on #{node_label} is paused."
          end
        when "completed"
          node_label == "workflow" ? "The latest workflow run has completed." : "The latest workflow run has completed at #{node_label}."
        when "failed"
          node_label == "workflow" ? "The latest workflow run failed." : "The latest workflow run failed while working on #{node_label}."
        else
          node_label == "workflow" ? "It is actively processing the current workflow." : "It is actively working on #{node_label}."
        end
      end

      def latest_activity_sentence
        latest_activity = recent_activity_items.last
        return if latest_activity.blank? || latest_activity["event_kind"].blank?

        "The latest tracked activity was a #{latest_activity.fetch("event_kind")} event."
      end

      def grounding_sentence
        evidence_parts = ["workflow state"]
        evidence_parts << "transcript context" if transcript_refs.any?
        evidence_parts << "recent activity" if recent_activity_items.any?
        evidence_parts << "subagent status" if Array(proof_refs["subagent_session_ids"]).any?

        if evidence_parts.one?
          "This summary is grounded in #{evidence_parts.first}."
        else
          "This summary is grounded in #{evidence_parts[0...-1].join(", ")}, and #{evidence_parts.last}."
        end
      end

      def human_node_label
        humanize_token(current_activity)
          .sub(/\ARunning /, "")
          .sub(/\ACompleted /, "")
          .sub(/\AFailed /, "")
      end

      def humanize_token(value)
        value.to_s.tr("_", " ")
      end
    end
  end
end
