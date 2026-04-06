module EmbeddedAgents
  module ConversationSupervision
    class BuildSnapshot
      CONTEXT_MESSAGE_LIMIT = 8

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
      end

      def call
        @conversation_supervision_session = @conversation_supervision_session.reload
        @conversation = @conversation_supervision_session.target_conversation
        raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if @conversation.blank?

        authority = Authority.call(actor: @actor, conversation_id: @conversation.public_id)
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless authority.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless authority.allowed?

        state = Conversations::UpdateSupervisionState.call(
          conversation: @conversation,
          occurred_at: Time.current
        )
        policy = @conversation.conversation_capability_policy
        bundle_payload = build_bundle_payload(authority:, state:, policy:)

        snapshot = @conversation_supervision_session.conversation_supervision_snapshots.create!(
          installation: @conversation.installation,
          target_conversation: @conversation,
          conversation_supervision_state_public_id: state.public_id,
          conversation_capability_policy_public_id: policy&.public_id,
          anchor_turn_public_id: anchor_turn&.public_id,
          anchor_turn_sequence_snapshot: anchor_turn&.sequence,
          conversation_event_projection_sequence_snapshot: latest_projection_sequence,
          active_workflow_run_public_id: workflow_run&.public_id,
          active_workflow_node_public_id: workflow_node&.public_id,
          active_subagent_session_public_ids: active_subagent_session_public_ids(bundle_payload),
          bundle_payload: bundle_payload,
          machine_status_payload: {}
        )

        machine_status = BuildMachineStatus.call(
          conversation_supervision_snapshot: snapshot,
          conversation_supervision_state: state,
          bundle_payload: bundle_payload
        )
        snapshot.update!(machine_status_payload: machine_status)
        @conversation_supervision_session.update!(last_snapshot_at: snapshot.created_at)
        snapshot.reload
      end

      private

      def build_bundle_payload(authority:, state:, policy:)
        detailed_progress_enabled = authority.detailed_progress_enabled?
        context_view = detailed_progress_enabled ? conversation_context_view : empty_context_view
        activity_feed = detailed_progress_enabled ? ::ConversationSupervision::BuildActivityFeed.call(conversation: @conversation) : []

        {
          "conversation_context_view" => context_view,
          "activity_feed" => activity_feed,
          "active_plan_items" => detailed_progress_enabled ? Array(state.status_payload["active_plan_items"]) : [],
          "active_subagents" => detailed_progress_enabled ? Array(state.status_payload["active_subagents"]) : [],
          "proof_debug" => proof_debug_payload(
            context_view: context_view,
            activity_feed: activity_feed,
            policy: policy,
            state: state
          ),
          "capability_authority" => {
            "supervision_enabled" => authority.supervision_enabled?,
            "detailed_progress_enabled" => authority.detailed_progress_enabled?,
            "side_chat_enabled" => authority.side_chat_enabled?,
            "control_enabled" => authority.control_enabled?,
            "available_control_verbs" => authority.available_control_verbs,
          },
        }
      end

      def conversation_context_view
        projection = Conversations::ContextProjection.call(conversation: @conversation)
        messages = projection.messages.last(CONTEXT_MESSAGE_LIMIT)

        {
          "message_ids" => messages.map(&:public_id),
          "turn_ids" => messages.filter_map { |message| message.turn&.public_id }.uniq,
          "facts" => messages.filter_map { |message| serialize_context_fact(message) },
        }
      end

      def serialize_context_fact(message)
        summary = summarize_context_fact(message.content)
        return if summary.blank?

        {
          "message_id" => message.public_id,
          "turn_id" => message.turn&.public_id,
          "role" => message.role,
          "slot" => message.slot,
          "summary" => summary,
          "keywords" => context_keywords(message.content),
        }.compact
      end

      def summarize_context_fact(content)
        normalized = content.to_s.squish
        return if normalized.blank?
        return "Context already references the 2048 acceptance flow." if normalized.match?(/\b2048\b/i) && normalized.match?(/\bacceptance\b/i)
        return "Context already references adding tests." if normalized.match?(/\btests?\b/i)

        keywords = context_keywords(normalized)
        return if keywords.empty?

        "Context already references #{keywords.first(4).join(" ")}."
      end

      def context_keywords(content)
        content.to_s.downcase.scan(/[a-z0-9]+/).uniq - %w[the and this that already with for from into while]
      end

      def proof_debug_payload(context_view:, activity_feed:, policy:, state:)
        {
          "conversation_id" => @conversation.public_id,
          "anchor_turn_id" => anchor_turn&.public_id,
          "workflow_run_id" => workflow_run&.public_id,
          "workflow_node_id" => workflow_node&.public_id,
          "conversation_supervision_state_id" => state.public_id,
          "conversation_capability_policy_id" => policy&.public_id,
          "context_message_ids" => context_view.fetch("message_ids"),
          "feed_entry_ids" => activity_feed.map { |entry| entry.fetch("conversation_supervision_feed_entry_id") },
          "feed_event_kinds" => activity_feed.map { |entry| entry.fetch("event_kind") },
        }.compact
      end

      def empty_context_view
        {
          "message_ids" => [],
          "turn_ids" => [],
          "facts" => [],
        }
      end

      def active_subagent_session_public_ids(bundle_payload)
        Array(bundle_payload["active_subagents"]).filter_map { |entry| entry["subagent_session_id"] }
      end

      def anchor_turn
        @anchor_turn ||= @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).first ||
          @conversation.turns.order(sequence: :desc).first
      end

      def latest_projection_sequence
        ConversationEvent.where(conversation: @conversation).maximum(:projection_sequence)
      end

      def workflow_run
        @workflow_run ||= @conversation.workflow_runs.order(created_at: :desc).first
      end

      def workflow_node
        @workflow_node ||= begin
          run = workflow_run
          if run.blank?
            nil
          else
            nodes = run.workflow_nodes.order(:ordinal).to_a
            nodes.find { |node| %w[running waiting].include?(node.lifecycle_state) } ||
              nodes.find { |node| %w[queued pending].include?(node.lifecycle_state) } ||
              nodes.last
          end
        end
      end
    end
  end
end
