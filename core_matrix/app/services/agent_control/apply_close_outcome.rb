module AgentControl
  class ApplyCloseOutcome
    CLOSE_STATES = %w[closed failed].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(resource:, mailbox_item:, close_state:, close_outcome_kind:, close_outcome_payload:, occurred_at: Time.current)
      @resource = resource
      @mailbox_item = mailbox_item
      @close_state = close_state
      @close_outcome_kind = close_outcome_kind
      @close_outcome_payload = close_outcome_payload
      @occurred_at = occurred_at
    end

    def call
      raise ArgumentError, "unsupported close state #{@close_state}" unless CLOSE_STATES.include?(@close_state)

      @resource.update!(
        close_state: @close_state,
        close_acknowledged_at: @resource.close_acknowledged_at || @occurred_at,
        close_outcome_kind: @close_outcome_kind,
        close_outcome_payload: @close_outcome_payload
      )

      terminalize_resource!
      @mailbox_item.update!(status: "completed", completed_at: @occurred_at)
      @resource
    end

    private

    def terminalize_resource!
      close_failed? ? terminalize_failed_resource! : terminalize_closed_resource!

      release_resource_lease!
      reconcile_turn_interrupt!
      reconcile_close_operation!
    end

    def terminalize_closed_resource!
      case @resource
      when AgentTaskRun
        @resource.update!(
          lifecycle_state: @mailbox_item.payload["request_kind"] == "turn_interrupt" ? "interrupted" : "canceled",
          finished_at: @resource.finished_at || @occurred_at,
          terminal_payload: @resource.terminal_payload.merge(
            "close_outcome_kind" => @resource.close_outcome_kind
          )
        )
      when ProcessRun
        @resource.update!(
          lifecycle_state: @resource.close_outcome_kind == "residual_abandoned" ? "lost" : "stopped",
          ended_at: @resource.ended_at || @occurred_at,
          metadata: @resource.metadata.merge(
            "stop_reason" => @resource.close_reason_kind,
            "close_request_kind" => @mailbox_item.payload["request_kind"]
          )
        )
      when SubagentRun
        @resource.update!(
          lifecycle_state: "canceled",
          finished_at: @resource.finished_at || @occurred_at
        )
      end
    end

    def terminalize_failed_resource!
      case @resource
      when AgentTaskRun
        @resource.update!(
          lifecycle_state: "failed",
          finished_at: @resource.finished_at || @occurred_at,
          terminal_payload: @resource.terminal_payload.merge(
            "close_outcome_kind" => @resource.close_outcome_kind,
            "close_request_kind" => @mailbox_item.payload["request_kind"]
          )
        )
      when ProcessRun
        @resource.update!(
          lifecycle_state: "lost",
          ended_at: @resource.ended_at || @occurred_at,
          metadata: @resource.metadata.merge(
            "stop_reason" => @resource.close_reason_kind,
            "close_request_kind" => @mailbox_item.payload["request_kind"]
          )
        )
      when SubagentRun
        @resource.update!(
          lifecycle_state: "failed",
          finished_at: @resource.finished_at || @occurred_at
        )
      end
    end

    def release_resource_lease!
      return unless @resource.respond_to?(:execution_lease)

      execution_lease = @resource.execution_lease
      return unless execution_lease&.active?

      Leases::Release.call(
        execution_lease: execution_lease,
        holder_key: execution_lease.holder_key,
        reason: close_failed? ? "resource_close_failed" : "resource_closed",
        released_at: @occurred_at
      )
    rescue ArgumentError
      nil
    end

    def reconcile_turn_interrupt!
      turn = ClosableResourceRouting.turn_for(@resource)
      return if turn.blank?
      return unless turn.cancellation_reason_kind == "turn_interrupted"

      Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: @occurred_at)
    end

    def reconcile_close_operation!
      conversation = ClosableResourceRouting.conversation_for(@resource)
      return if conversation.blank?

      Conversations::ReconcileCloseOperation.call(
        conversation: conversation,
        occurred_at: @occurred_at
      )
    end

    def close_failed?
      @close_state == "failed"
    end
  end
end
