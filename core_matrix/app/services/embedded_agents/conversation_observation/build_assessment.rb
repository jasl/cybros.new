module EmbeddedAgents
  module ConversationObservation
    class BuildAssessment
      BLOCKED_WAIT_REASON_KINDS = %w[
        external_dependency_blocked
        manual_recovery_required
        human_interaction
        agent_unavailable
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(conversation_observation_frame:, observation_bundle:)
        @conversation_observation_frame = conversation_observation_frame
        @observation_bundle = observation_bundle
      end

      def call
        {
          "observation_session_id" => @conversation_observation_frame.conversation_observation_session.public_id,
          "observation_frame_id" => @conversation_observation_frame.public_id,
          "conversation_id" => @conversation_observation_frame.target_conversation.public_id,
          "overall_state" => overall_state,
          "current_activity" => current_activity,
          "workflow_run_id" => workflow_view["workflow_run_id"],
          "workflow_node_id" => workflow_view["workflow_node_id"],
          "last_progress_at" => last_progress_at&.iso8601(6),
          "stall_for_ms" => stall_for_ms,
          "blocking_reason" => blocking_reason,
          "recent_activity_items" => recent_activity_items,
          "transcript_refs" => transcript_refs,
          "proof_refs" => proof_refs,
          "human_summary" => human_summary,
          "observed_at" => Time.current.iso8601(6),
        }.compact
      end

      private

      def workflow_view
        @observation_bundle.fetch("workflow_view")
      end

      def activity_view
        @observation_bundle.fetch("activity_view")
      end

      def transcript_view
        @observation_bundle.fetch("transcript_view")
      end

      def subagent_view
        @observation_bundle.fetch("subagent_view")
      end

      def overall_state
        lifecycle_state = workflow_view["workflow_lifecycle_state"]
        wait_reason_kind = workflow_view["wait_reason_kind"]

        return "completed" if lifecycle_state == "completed"
        return "failed" if %w[failed canceled].include?(lifecycle_state)
        return "blocked" if workflow_view["wait_state"] == "waiting" && BLOCKED_WAIT_REASON_KINDS.include?(wait_reason_kind)
        return "waiting" if workflow_view["wait_state"] == "waiting"

        "running"
      end

      def current_activity
        node_label = workflow_view["node_key"] || workflow_view["node_type"] || "workflow"

        if workflow_view["wait_state"] == "waiting" && workflow_view["wait_reason_kind"].present?
          return "Waiting on #{workflow_view["wait_reason_kind"]} at #{node_label}"
        end

        return "Completed #{node_label}" if overall_state == "completed"
        return "Failed #{node_label}" if overall_state == "failed"

        node_state = workflow_view["node_lifecycle_state"] || workflow_view["workflow_lifecycle_state"] || "active"
        "Running #{node_label} (#{node_state})"
      end

      def blocking_reason
        workflow_view["wait_reason_kind"]
      end

      def recent_activity_items
        Array(activity_view["items"]).map do |item|
          item.slice("projection_sequence", "turn_id", "event_kind", "stream_key", "stream_revision", "payload", "created_at")
        end
      end

      def transcript_refs
        Array(transcript_view["messages"]).map { |message| message.fetch("message_id") }
      end

      def proof_refs
        {
          "conversation_id" => @conversation_observation_frame.target_conversation.public_id,
          "workflow_run_id" => workflow_view["workflow_run_id"],
          "workflow_node_id" => workflow_view["workflow_node_id"],
          "transcript_message_ids" => transcript_refs,
          "subagent_session_ids" => Array(subagent_view["items"]).map { |item| item.fetch("subagent_session_id") },
          "activity_projection_sequences" => recent_activity_items.map { |item| item.fetch("projection_sequence") },
        }.compact
      end

      def human_summary
        [
          "The conversation is currently #{overall_state}.",
          human_state_sentence,
          latest_activity_sentence,
          grounding_sentence,
        ].compact.join(" ")
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
        humanize_token(workflow_view["node_key"] || workflow_view["node_type"] || "workflow")
      end

      def humanize_token(value)
        value.to_s.tr("_", " ")
      end

      def last_progress_at
        @last_progress_at ||= begin
          timestamps = []
          timestamps.concat(Array(activity_view["items"]).map { |item| parse_time(item["created_at"]) })
          timestamps.concat(Array(transcript_view["messages"]).map { |message| parse_time(message["created_at"]) })
          timestamps << parse_time(workflow_view["node_started_at"])
          timestamps << parse_time(workflow_view["waiting_since_at"])
          timestamps.compact.max
        end
      end

      def stall_for_ms
        return 0 if last_progress_at.blank?

        ((Time.current - last_progress_at) * 1000).round
      end

      def parse_time(value)
        return if value.blank?

        Time.iso8601(value)
      end
    end
  end
end
