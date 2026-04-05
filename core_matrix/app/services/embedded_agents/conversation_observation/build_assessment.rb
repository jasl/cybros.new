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
          "overall_state" => overall_state,
          "current_activity" => current_activity,
          "last_progress_at" => last_progress_at&.iso8601(6),
          "stall_for_ms" => stall_for_ms,
          "blocking_reason" => blocking_reason,
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
