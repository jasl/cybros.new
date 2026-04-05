module EmbeddedAgents
  module ConversationObservation
    class BuildSupervisorStatus
      def self.call(...)
        new(...).call
      end

      def initialize(conversation_observation_frame:, assessment:, observation_bundle:)
        @conversation_observation_frame = conversation_observation_frame
        @assessment = assessment
        @observation_bundle = observation_bundle
      end

      def call
        {
          "observation_session_id" => @conversation_observation_frame.conversation_observation_session.public_id,
          "observation_frame_id" => @conversation_observation_frame.public_id,
          "conversation_id" => @conversation_observation_frame.target_conversation.public_id,
          "overall_state" => @assessment.fetch("overall_state"),
          "current_activity" => @assessment.fetch("current_activity"),
          "workflow_run_id" => workflow_view["workflow_run_id"],
          "workflow_node_id" => workflow_view["workflow_node_id"],
          "last_progress_at" => @assessment["last_progress_at"],
          "stall_for_ms" => @assessment.fetch("stall_for_ms"),
          "blocking_reason" => @assessment["blocking_reason"],
          "recent_activity_items" => recent_activity_items,
          "transcript_refs" => transcript_refs,
          "proof_refs" => proof_refs,
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
    end
  end
end
