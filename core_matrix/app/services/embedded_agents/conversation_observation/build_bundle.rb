module EmbeddedAgents
  module ConversationObservation
    class BuildBundle
      DEFAULT_ACTIVITY_LIMIT = 10
      DEFAULT_TRANSCRIPT_LIMIT = 10

      def self.call(...)
        new(...).call
      end

      def initialize(conversation_observation_frame:, transcript_limit: DEFAULT_TRANSCRIPT_LIMIT, activity_limit: DEFAULT_ACTIVITY_LIMIT)
        @conversation_observation_frame = conversation_observation_frame
        @transcript_limit = transcript_limit
        @activity_limit = activity_limit
      end

      def call
        conversation = @conversation_observation_frame.target_conversation

        {
          "transcript_view" => transcript_view_for(conversation),
          "workflow_view" => workflow_view_for(conversation),
          "activity_view" => activity_view_for(conversation),
          "subagent_view" => subagent_view_for(conversation),
          "diagnostic_view" => diagnostic_view_for(conversation),
          "memory_view" => {},
        }
      end

      private

      def transcript_view_for(conversation)
        messages = Conversations::TranscriptProjection.call(conversation: conversation).last(@transcript_limit)

        {
          "conversation_id" => conversation.public_id,
          "anchor_turn_id" => @conversation_observation_frame.anchor_turn_public_id,
          "messages" => messages.map { |message| serialize_transcript_message(message) },
        }
      end

      def workflow_view_for(conversation)
        workflow_run = conversation.workflow_runs.find_by(public_id: @conversation_observation_frame.active_workflow_run_public_id) ||
          conversation.workflow_runs.where(lifecycle_state: "active").order(:created_at).last
        workflow_node = workflow_run&.workflow_nodes&.find_by(public_id: @conversation_observation_frame.active_workflow_node_public_id) ||
          active_workflow_node_for(workflow_run)

        {
          "conversation_id" => conversation.public_id,
          "workflow_run_id" => workflow_run&.public_id,
          "workflow_node_id" => workflow_node&.public_id,
          "workflow_lifecycle_state" => workflow_run&.lifecycle_state,
          "wait_state" => workflow_run&.wait_state,
          "wait_reason_kind" => workflow_run&.wait_reason_kind,
          "wait_reason_payload" => workflow_run&.wait_reason_payload || {},
          "resume_policy" => workflow_run&.resume_policy,
          "waiting_since_at" => workflow_run&.waiting_since_at&.iso8601(6),
          "node_key" => workflow_node&.node_key,
          "node_type" => workflow_node&.node_type,
          "node_lifecycle_state" => workflow_node&.lifecycle_state,
          "node_started_at" => workflow_node&.started_at&.iso8601(6),
        }.compact
      end

      def activity_view_for(conversation)
        items = ConversationEvent.live_projection(conversation: conversation)
          .select { |event| event.event_kind.start_with?("runtime.") }
          .last(@activity_limit)

        {
          "conversation_id" => conversation.public_id,
          "latest_projection_sequence" => items.last&.projection_sequence,
          "items" => items.map { |event| serialize_activity_item(event) },
        }
      end

      def subagent_view_for(conversation)
        items = conversation.owned_subagent_sessions
          .where(close_state: %w[open requested acknowledged])
          .order(:created_at)
          .map do |session|
            {
              "subagent_session_id" => session.public_id,
              "conversation_id" => session.conversation.public_id,
              "scope" => session.scope,
              "profile_key" => session.profile_key,
              "observed_status" => session.observed_status,
              "derived_close_status" => session.derived_close_status,
              "depth" => session.depth,
            }
          end

        {
          "conversation_id" => conversation.public_id,
          "items" => items,
        }
      end

      def diagnostic_view_for(conversation)
        snapshot = ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)

        {
          "conversation_id" => conversation.public_id,
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

      def active_workflow_node_for(workflow_run)
        return if workflow_run.blank?

        nodes = workflow_run.workflow_nodes.order(:ordinal).to_a

        nodes.find { |node| %w[running waiting].include?(node.lifecycle_state) } ||
          nodes.find { |node| %w[queued pending].include?(node.lifecycle_state) } ||
          nodes.last
      end
    end
  end
end
