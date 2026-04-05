module EmbeddedAgents
  module ConversationObservation
    class BuildFrame
      def self.call(...)
        new(...).call
      end

      def initialize(conversation_observation_session:)
        @conversation_observation_session = conversation_observation_session
      end

      def call
        conversation = @conversation_observation_session.target_conversation
        anchor_turn = anchor_turn_for(conversation)
        workflow_run = current_workflow_run_for(conversation)
        workflow_node = current_workflow_node_for(workflow_run)
        active_subagent_sessions = active_subagent_sessions_for(conversation)
        latest_projection_sequence = latest_projection_sequence_for(conversation)
        bundle_snapshot = BuildBundleSnapshot.call(
          conversation: conversation,
          anchor_turn: anchor_turn,
          latest_projection_sequence: latest_projection_sequence,
          workflow_run: workflow_run,
          workflow_node: workflow_node,
          active_subagent_sessions: active_subagent_sessions
        )

        frame = @conversation_observation_session.conversation_observation_frames.create!(
          installation: conversation.installation,
          target_conversation: conversation,
          anchor_turn_public_id: anchor_turn&.public_id,
          anchor_turn_sequence_snapshot: anchor_turn&.sequence,
          conversation_event_projection_sequence_snapshot: latest_projection_sequence,
          active_workflow_run_public_id: workflow_run&.public_id,
          active_workflow_node_public_id: workflow_node&.public_id,
          wait_state: workflow_run&.wait_state,
          wait_reason_kind: workflow_run&.wait_reason_kind,
          active_subagent_session_public_ids: active_subagent_sessions.map(&:public_id),
          bundle_snapshot: bundle_snapshot,
          assessment_payload: {}
        )

        @conversation_observation_session.update!(last_observed_at: frame.created_at)
        frame
      end

      private

      def anchor_turn_for(conversation)
        conversation.turns.where.not(lifecycle_state: "canceled").order(:sequence).last
      end

      def current_workflow_run_for(conversation)
        conversation.workflow_runs.where(lifecycle_state: "active").order(:created_at).last ||
          conversation.workflow_runs.order(:created_at).last
      end

      def current_workflow_node_for(workflow_run)
        return if workflow_run.blank?

        nodes = workflow_run.workflow_nodes.order(:ordinal).to_a

        nodes.find { |node| %w[running waiting].include?(node.lifecycle_state) } ||
          nodes.find { |node| %w[queued pending].include?(node.lifecycle_state) } ||
          nodes.last
      end

      def active_subagent_sessions_for(conversation)
        conversation.owned_subagent_sessions
          .where(close_state: %w[open requested acknowledged])
          .order(:created_at)
          .to_a
      end

      def latest_projection_sequence_for(conversation)
        ConversationEvent.where(conversation: conversation).maximum(:projection_sequence)
      end
    end
  end
end
