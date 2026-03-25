module Conversations
  class QuiesceActiveWork
    REASONS = %w[conversation_deleted conversation_archived].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, reason_kind:, occurred_at: Time.current, revoke_publication: false)
      @conversation = conversation
      @reason_kind = reason_kind
      @occurred_at = occurred_at
      @revoke_publication = revoke_publication
      raise ArgumentError, "unsupported reason_kind: #{@reason_kind}" unless REASONS.include?(@reason_kind)
    end

    def call
      ApplicationRecord.transaction do
        revoke_publication! if @revoke_publication
        cancel_open_human_interactions!
        stop_running_processes!
        cancel_running_subagents!
        release_active_execution_leases!
        cancel_queued_turns!
        cancel_active_workflows!
        cancel_active_turns!
      end

      @conversation
    end

    private

    def revoke_publication!
      publication = @conversation.publication
      return if publication.blank? || !publication.active?

      Publications::Revoke.call(
        publication: publication,
        actor: nil,
        revoked_at: @occurred_at
      )
    end

    def cancel_open_human_interactions!
      HumanInteractionRequest
        .where(conversation: @conversation, lifecycle_state: "open")
        .find_each do |request|
          request.update!(
            lifecycle_state: "canceled",
            resolution_kind: "canceled",
            result_payload: { "reason" => @reason_kind },
            resolved_at: @occurred_at
          )
          project_human_interaction_event!(request)
        end
    end

    def stop_running_processes!
      ProcessRun.where(conversation: @conversation, lifecycle_state: "running").find_each do |process_run|
        Processes::Stop.call(process_run: process_run, reason: @reason_kind)
        release_lease!(process_run.execution_lease)
      end
    end

    def cancel_running_subagents!
      SubagentRun
        .joins(:workflow_run)
        .where(workflow_runs: { conversation_id: @conversation.id }, lifecycle_state: "running")
        .find_each do |subagent_run|
          subagent_run.update!(
            lifecycle_state: "canceled",
            finished_at: @occurred_at
          )
          release_lease!(subagent_run.execution_lease)
        end
    end

    def release_active_execution_leases!
      ExecutionLease
        .joins(:workflow_run)
        .where(workflow_runs: { conversation_id: @conversation.id }, released_at: nil)
        .find_each { |lease| release_lease!(lease) }
    end

    def cancel_queued_turns!
      Turn.where(conversation: @conversation, lifecycle_state: "queued").update_all(
        lifecycle_state: "canceled",
        cancellation_requested_at: @occurred_at,
        cancellation_reason_kind: @reason_kind,
        updated_at: @occurred_at
      )
    end

    def cancel_active_workflows!
      WorkflowRun.where(conversation: @conversation, lifecycle_state: "active").find_each do |workflow_run|
        workflow_run.update!(
          lifecycle_state: "canceled",
          wait_state: "ready",
          wait_reason_kind: nil,
          wait_reason_payload: {},
          waiting_since_at: nil,
          blocking_resource_type: nil,
          blocking_resource_id: nil,
          cancellation_requested_at: workflow_run.cancellation_requested_at || @occurred_at,
          cancellation_reason_kind: @reason_kind
        )
      end
    end

    def cancel_active_turns!
      Turn.where(conversation: @conversation, lifecycle_state: "active").find_each do |turn|
        turn.update!(
          lifecycle_state: "canceled",
          cancellation_requested_at: turn.cancellation_requested_at || @occurred_at,
          cancellation_reason_kind: @reason_kind
        )
      end
    end

    def release_lease!(lease)
      return if lease.blank? || !lease.active?

      lease.update!(
        released_at: @occurred_at,
        release_reason: @reason_kind
      )
    end

    def project_human_interaction_event!(request)
      ConversationEvents::Project.call(
        conversation: request.conversation,
        turn: request.turn,
        source: request,
        event_kind: "human_interaction.canceled",
        stream_key: "human_interaction_request:#{request.id}",
        payload: {
          "request_id" => request.public_id,
          "request_type" => request.type,
          "lifecycle_state" => request.lifecycle_state,
          "resolution_kind" => request.resolution_kind,
          "result_payload" => request.result_payload,
        }
      )
    end
  end
end
