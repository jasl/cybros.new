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
      def initialize(workflow_run:, satisfied_node_keys: [])
        @workflow_run = workflow_run
        @satisfied_node_keys = Array(satisfied_node_keys).map(&:to_s)
      end

      def call
        return [] if @workflow_run.waiting?

        workflow_nodes_scope.select do |node|
          next false if @satisfied_node_keys.include?(node.node_key)

          predecessor_keys = predecessor_node_keys.fetch(node.id, [])
          predecessor_keys.empty? || predecessor_keys.all? { |key| @satisfied_node_keys.include?(key) }
        end
      end

      private

      def workflow_nodes_scope
        @workflow_nodes_scope ||= WorkflowNode.where(workflow_run: @workflow_run).order(:ordinal).to_a
      end

      def predecessor_node_keys
        @predecessor_node_keys ||= WorkflowEdge
          .where(workflow_run: @workflow_run)
          .includes(:from_node)
          .group_by(&:to_node_id)
          .transform_values { |edges| edges.map { |edge| edge.from_node.node_key } }
      end
    end

    class DuringGenerationPolicy
      def initialize(turn:, content:, policy_mode:)
        @turn = turn
        @content = content
        @policy_mode = policy_mode.to_s
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

          queued_turn = Turns::QueueFollowUp.call(
            conversation: @turn.conversation,
            content: @content,
            agent_deployment: @turn.agent_deployment,
            resolved_config_snapshot: @turn.resolved_config_snapshot,
            resolved_model_selection_snapshot: @turn.resolved_model_selection_snapshot
          )

          queued_turn.update!(
            origin_payload: queued_turn.origin_payload.merge(
              "during_generation_policy" => @policy_mode,
              "expected_tail_message_id" => @turn.selected_output_message&.public_id,
              "queued_from_turn_id" => @turn.public_id
            )
          )

          if wait_for_restart
            workflow_run = @turn.workflow_run
            raise_invalid!(@turn, :workflow_run, "must exist for restart policy") if workflow_run.blank?

            workflow_run.update!(
              wait_state: "waiting",
              wait_reason_kind: "policy_gate",
              wait_reason_payload: {
                "policy_mode" => "restart",
                "queued_turn_id" => queued_turn.public_id,
              },
              waiting_since_at: Time.current,
              blocking_resource_type: "Turn",
              blocking_resource_id: queued_turn.public_id
            )
          end

          queued_turn
        end
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

        expected_tail_message_id = @turn.origin_payload["expected_tail_message_id"]
        return @turn if expected_tail_message_id.blank?

        predecessor_turn = @turn.conversation.turns.where("sequence < ?", @turn.sequence).order(sequence: :desc).first
        current_predecessor_output_id = predecessor_turn&.selected_output_message&.public_id
        return @turn if current_predecessor_output_id == expected_tail_message_id

        @turn.update!(lifecycle_state: "canceled")
        @turn
      end
    end
  end
end
