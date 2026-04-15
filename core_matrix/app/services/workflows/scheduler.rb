module Workflows
  class Scheduler
    def self.call(...)
      RunnableSelection.new(...).call
    end

    def self.apply_during_generation_policy(...)
      DuringGenerationPolicy.new(...).call
    end

    def self.guard_expected_tail!(...)
      ExpectedTailGuard.new(...).call
    end

    class RunnableSelection
      def initialize(workflow_run:)
        @workflow_run = workflow_run
      end

      def call
        return [] if @workflow_run.waiting? || !@workflow_run.active?

        workflow_nodes_scope.select do |node|
          next false unless node.pending?

          predecessor_edges = incoming_edges_by_node.fetch(node.id, [])
          runnable_without_predecessors?(predecessor_edges) || runnable_with_predecessors?(predecessor_edges)
        end
      end

      private

      def workflow_nodes_scope
        @workflow_nodes_scope ||= WorkflowNode.where(workflow_run: @workflow_run).order(:ordinal).to_a
      end

      def incoming_edges_by_node
        @incoming_edges_by_node ||= WorkflowEdge
          .where(workflow_run: @workflow_run)
          .includes(:from_node, :to_node)
          .group_by(&:to_node_id)
      end

      def runnable_without_predecessors?(predecessor_edges)
        predecessor_edges.empty?
      end

      def runnable_with_predecessors?(predecessor_edges)
        predecessor_edges.any? { |edge| edge.from_node.completed? } &&
          predecessor_edges.select(&:required?).all? { |edge| edge.from_node.completed? }
      end
    end

    class DuringGenerationPolicy
      def initialize(turn:, content:, policy_mode:, origin_kind: nil, origin_payload: nil, source_ref_type: nil, source_ref_id: nil)
        @turn = turn
        @content = content
        @policy_mode = policy_mode.to_s
        @origin_kind = origin_kind
        @origin_payload = origin_payload
        @source_ref_type = source_ref_type
        @source_ref_id = source_ref_id
      end

      def call
        raise_invalid!(@turn, :lifecycle_state, "must be active for during-generation policy") unless @turn.active?

        case @policy_mode
        when "reject"
          raise_invalid!(@turn, :base, "reject policy does not allow new input while active work exists")
        when "restart"
          queue_follow_up!(wait_for_restart: true)
        when "queue"
          queue_follow_up!(wait_for_restart: false)
        else
          raise_invalid!(@turn, :base, "must use a supported during-generation policy")
        end
      end

      private

      def queue_follow_up!(wait_for_restart:)
        ApplicationRecord.transaction do
          cancel_existing_queued_turns!

          queued_turn = queue_follow_up_service.call(**queue_follow_up_attributes)

          queued_turn.update!(
            origin_payload: queued_turn.origin_payload.merge(
              "during_generation_policy" => @policy_mode,
              "expected_tail_message_id" => @turn.selected_output_message&.public_id,
              "queued_from_turn_id" => @turn.public_id
            )
          )

          if wait_for_restart
            workflow_run = WorkflowRun.find_by(turn_id: @turn.id)
            raise_invalid!(@turn, :workflow_run, "must exist for restart policy") if workflow_run.blank?

            workflow_run.update!(
              Workflows::WaitState.cleared_detail_attributes.merge(
                wait_state: "waiting",
                wait_reason_kind: "policy_gate",
                wait_reason_payload: {},
                wait_policy_mode: "restart",
                waiting_since_at: Time.current,
                blocking_resource_type: "Turn",
                blocking_resource_id: queued_turn.public_id
              )
            )
          end

          queued_turn
        end
      end

      def queue_follow_up_service
        @turn.channel_ingress? ? Turns::QueueChannelFollowUp : Turns::QueueFollowUp
      end

      def queue_follow_up_attributes
        base_attributes = {
          conversation: @turn.conversation,
          content: @content,
          resolved_config_snapshot: @turn.resolved_config_snapshot,
          resolved_model_selection_snapshot: @turn.resolved_model_selection_snapshot,
        }

        return base_attributes unless @turn.channel_ingress?

        base_attributes.merge(
          origin_payload: @origin_payload,
          source_ref_id: @source_ref_id
        )
      end

      def cancel_existing_queued_turns!
        @turn.conversation.turns.where(lifecycle_state: "queued").update_all(
          lifecycle_state: "canceled",
          updated_at: Time.current
        )
      end

      def raise_invalid!(record, attribute, message)
        record.errors.add(attribute, message)
        raise ActiveRecord::RecordInvalid, record
      end
    end

    class ExpectedTailGuard
      def initialize(turn:)
        @turn = turn
      end

      def call
        return @turn unless @turn.queued?

        ApplicationRecord.transaction do
          @turn.conversation.with_lock do
            @turn.with_lock do
              guarded_turn = @turn.reload
              return guarded_turn unless guarded_turn.queued?

              expected_tail_message_id = guarded_turn.origin_payload["expected_tail_message_id"]
              return guarded_turn if expected_tail_message_id.blank?

              predecessor_turn = predecessor_turn_for(guarded_turn)
              current_predecessor_output_id = predecessor_turn&.selected_output_message&.public_id
              return guarded_turn if current_predecessor_output_id == expected_tail_message_id

              guarded_turn.update!(lifecycle_state: "canceled")
              release_matching_policy_gate!(predecessor_turn: predecessor_turn, queued_turn: guarded_turn)
              guarded_turn
            end
          end
        end
      end

      private

      def predecessor_turn_for(turn)
        queued_from_turn_id = turn.origin_payload["queued_from_turn_id"]
        return turn.conversation.turns.find_by(public_id: queued_from_turn_id) if queued_from_turn_id.present?

        turn.conversation.turns.where("sequence < ?", turn.sequence).order(sequence: :desc).first
      end

      def release_matching_policy_gate!(predecessor_turn:, queued_turn:)
        workflow_run = predecessor_turn&.workflow_run
        return if workflow_run.blank?

        workflow_run.with_lock do
          workflow_run.reload
          return unless workflow_run.waiting? &&
            workflow_run.wait_reason_kind == "policy_gate" &&
            workflow_run.blocking_resource_type == "Turn" &&
            workflow_run.blocking_resource_id == queued_turn.public_id

          workflow_run.update!(Workflows::WaitState.ready_attributes)
        end
      end
    end
  end
end
