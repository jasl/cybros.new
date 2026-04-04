module EmbeddedAgents
  module ConversationObservation
    class BuildBundleSnapshot
      DEFAULT_ACTIVITY_LIMIT = 10
      DEFAULT_TRANSCRIPT_LIMIT = 10

      def self.call(...)
        new(...).call
      end

      def initialize(
        conversation:,
        anchor_turn:,
        latest_projection_sequence:,
        workflow_run:,
        workflow_node:,
        active_subagent_sessions:,
        transcript_limit: DEFAULT_TRANSCRIPT_LIMIT,
        activity_limit: DEFAULT_ACTIVITY_LIMIT
      )
        @conversation = conversation
        @anchor_turn = anchor_turn
        @latest_projection_sequence = latest_projection_sequence
        @workflow_run = workflow_run
        @workflow_node = workflow_node
        @active_subagent_sessions = Array(active_subagent_sessions)
        @transcript_limit = transcript_limit
        @activity_limit = activity_limit
      end

      def call
        {
          "transcript_view" => transcript_view,
          "workflow_view" => workflow_view,
          "activity_view" => activity_view,
          "subagent_view" => subagent_view,
        }
      end

      private

      def transcript_view
        {
          "messages" => transcript_messages.map { |message| serialize_transcript_message(message) },
        }
      end

      def transcript_messages
        Conversations::TranscriptProjection.call(conversation: @conversation)
          .select { |message| transcript_message_visible_for_anchor?(message) }
          .last(@transcript_limit)
      end

      def transcript_message_visible_for_anchor?(message)
        return true if message.conversation_id != @conversation.id
        return false if @anchor_turn.blank?
        return false if message.turn.blank?

        message.turn.sequence <= @anchor_turn.sequence
      end

      def workflow_view
        {
          "workflow_run_id" => @workflow_run&.public_id,
          "workflow_node_id" => @workflow_node&.public_id,
          "workflow_lifecycle_state" => @workflow_run&.lifecycle_state,
          "wait_state" => @workflow_run&.wait_state,
          "wait_reason_kind" => @workflow_run&.wait_reason_kind,
          "waiting_since_at" => @workflow_run&.waiting_since_at&.iso8601(6),
          "node_key" => @workflow_node&.node_key,
          "node_type" => @workflow_node&.node_type,
          "node_lifecycle_state" => @workflow_node&.lifecycle_state,
          "node_started_at" => @workflow_node&.started_at&.iso8601(6),
        }.compact
      end

      def activity_view
        items =
          if @latest_projection_sequence.present?
            ConversationEvent.live_projection(
              conversation: @conversation,
              max_projection_sequence: @latest_projection_sequence
            ).select { |event| event.event_kind.start_with?("runtime.") }.last(@activity_limit)
          else
            []
          end

        {
          "latest_projection_sequence" => items.last&.projection_sequence,
          "items" => items.map { |event| serialize_activity_item(event) },
        }
      end

      def subagent_view
        {
          "items" => @active_subagent_sessions.map do |session|
            {
              "subagent_session_id" => session.public_id,
              "profile_key" => session.profile_key,
              "observed_status" => session.observed_status,
            }
          end,
        }
      end

      def serialize_transcript_message(message)
        {
          "message_id" => message.public_id,
          "role" => message.role,
          "slot" => message.slot,
          "created_at" => message.created_at&.iso8601(6),
        }.compact
      end

      def serialize_activity_item(event)
        {
          "projection_sequence" => event.projection_sequence,
          "event_kind" => event.event_kind,
          "created_at" => event.created_at&.iso8601(6),
        }.compact
      end
    end
  end
end
