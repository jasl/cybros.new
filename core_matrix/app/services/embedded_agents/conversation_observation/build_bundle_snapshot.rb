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
          "diagnostic_view" => diagnostic_view,
          "memory_view" => {},
        }
      end

      private

      def transcript_view
        {
          "conversation_id" => @conversation.public_id,
          "anchor_turn_id" => @anchor_turn&.public_id,
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
          "conversation_id" => @conversation.public_id,
          "workflow_run_id" => @workflow_run&.public_id,
          "workflow_node_id" => @workflow_node&.public_id,
          "workflow_lifecycle_state" => @workflow_run&.lifecycle_state,
          "wait_state" => @workflow_run&.wait_state,
          "wait_reason_kind" => @workflow_run&.wait_reason_kind,
          "wait_reason_payload" => @workflow_run&.wait_reason_payload || {},
          "resume_policy" => @workflow_run&.resume_policy,
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
          "conversation_id" => @conversation.public_id,
          "latest_projection_sequence" => items.last&.projection_sequence,
          "items" => items.map { |event| serialize_activity_item(event) },
        }
      end

      def subagent_view
        {
          "conversation_id" => @conversation.public_id,
          "items" => @active_subagent_sessions.map do |session|
            {
              "subagent_session_id" => session.public_id,
              "conversation_id" => session.conversation.public_id,
              "scope" => session.scope,
              "profile_key" => session.profile_key,
              "observed_status" => session.observed_status,
              "derived_close_status" => session.derived_close_status,
              "depth" => session.depth,
            }
          end,
        }
      end

      def diagnostic_view
        snapshot = ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: @conversation)

        {
          "conversation_id" => @conversation.public_id,
          "lifecycle_state" => snapshot.lifecycle_state,
          "turn_count" => snapshot.turn_count,
          "active_turn_count" => snapshot.active_turn_count,
          "completed_turn_count" => snapshot.completed_turn_count,
          "failed_turn_count" => snapshot.failed_turn_count,
          "provider_round_count" => snapshot.provider_round_count,
          "tool_call_count" => snapshot.tool_call_count,
          "tool_failure_count" => snapshot.tool_failure_count,
          "command_run_count" => snapshot.command_run_count,
          "command_failure_count" => snapshot.command_failure_count,
          "process_run_count" => snapshot.process_run_count,
          "process_failure_count" => snapshot.process_failure_count,
          "subagent_session_count" => snapshot.subagent_session_count,
          "estimated_cost_total" => snapshot.estimated_cost_total.to_s("F"),
          "outlier_refs" => snapshot.metadata.fetch("outlier_refs", {}),
          "cost_summary" => snapshot.metadata.fetch("cost_summary", {}),
          "tool_breakdown" => snapshot.metadata.fetch("tool_breakdown", {}),
          "subagent_status_counts" => snapshot.metadata.fetch("subagent_status_counts", {}),
        }
      end

      def serialize_transcript_message(message)
        {
          "message_id" => message.public_id,
          "conversation_id" => message.conversation.public_id,
          "turn_id" => message.turn.public_id,
          "role" => message.role,
          "slot" => message.slot,
          "content" => message.content,
          "created_at" => message.created_at&.iso8601(6),
        }.compact
      end

      def serialize_activity_item(event)
        {
          "projection_sequence" => event.projection_sequence,
          "turn_id" => event.turn&.public_id,
          "event_kind" => event.event_kind,
          "stream_key" => event.stream_key,
          "stream_revision" => event.stream_revision,
          "payload" => event.payload,
          "created_at" => event.created_at&.iso8601(6),
        }.compact
      end
    end
  end
end
