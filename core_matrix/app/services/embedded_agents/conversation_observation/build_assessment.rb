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
          "proof_text" => proof_text,
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

      def proof_text
        segments = []
        segments << "Conversation #{proof_refs.fetch("conversation_id")} is #{overall_state}."
        segments << current_activity
        segments << "Blocking reason: #{blocking_reason}." if blocking_reason.present?
        segments << "Workflow run #{proof_refs["workflow_run_id"]}."
        segments << "Workflow node #{proof_refs["workflow_node_id"]}." if proof_refs["workflow_node_id"].present?
        segments << "Transcript refs: #{transcript_refs.join(", ")}." if transcript_refs.any?
        if proof_refs["subagent_session_ids"].any?
          segments << "Subagent refs: #{proof_refs.fetch("subagent_session_ids").join(", ")}."
        end
        segments.join(" ")
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
