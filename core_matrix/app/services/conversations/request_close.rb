module Conversations
  class RequestClose
    INTENT_CONFIG = {
      "archive" => {
        queued_turn_reason: "conversation_archived",
        background_request_kind: "archive_force_quiesce",
        close_reason_kind: "conversation_archived",
      },
      "delete" => {
        queued_turn_reason: "conversation_deleted",
        background_request_kind: "deletion_force_quiesce",
        close_reason_kind: "conversation_deleted",
      },
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, intent_kind:, occurred_at: Time.current, conversation_control_request: nil)
      @conversation = conversation
      @intent_kind = intent_kind
      @occurred_at = occurred_at
      @conversation_control_request = conversation_control_request
    end

    def call
      conversation = current_conversation
      config = INTENT_CONFIG.fetch(@intent_kind)
      owned_subagent_tree = nil

      ApplicationRecord.transaction do
        with_close_lock(conversation) do |locked_conversation|
          owned_subagent_tree = SubagentConnections::OwnedTree.new(owner_conversation: locked_conversation)
          publish_delivery_endpoint = active_agent_connection_for(locked_conversation)
          find_or_create_close_operation!(locked_conversation)
          apply_immediate_state!(locked_conversation)
          cancel_queued_turns!(locked_conversation, reason_kind: config.fetch(:queued_turn_reason))
          request_turn_interrupts!(locked_conversation)
          request_owned_subagent_connection_closes!(
            owned_subagent_tree,
            publish_delivery_endpoint: publish_delivery_endpoint,
            request_kind: config.fetch(:background_request_kind),
            reason_kind: config.fetch(:close_reason_kind)
          )
          request_background_process_closes!(
            locked_conversation,
            request_kind: config.fetch(:background_request_kind),
            reason_kind: config.fetch(:close_reason_kind)
          )
        end

        Conversations::ReconcileCloseOperation.call(
          conversation: conversation,
          occurred_at: @occurred_at,
          owned_subagent_connection_ids: owned_subagent_tree.connection_ids,
          owned_subagent_conversation_ids: owned_subagent_tree.conversation_ids
        )
      end

      closed_conversation = conversation.reload
      complete_control_request!(closed_conversation)
      closed_conversation
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end

    def with_close_lock(conversation, &block)
      if @intent_kind == "archive"
        Conversations::WithRetainedLifecycleLock.call(
          conversation: conversation,
          record: conversation,
          retained_message: "must be retained before archival",
          expected_state: "active",
          lifecycle_message: "must be active before archival",
          &block
        )
      else
        conversation.with_lock do
          yield conversation.reload
        end
      end
    end

    def find_or_create_close_operation!(conversation)
      existing = conversation.unfinished_close_operation
      return existing if existing.present? && existing.intent_kind == @intent_kind

      if existing.present?
        raise_invalid!(existing, :intent_kind, "must not change while a close operation is unfinished")
      end

      ConversationCloseOperation.create!(
        installation: conversation.installation,
        conversation: conversation,
        intent_kind: @intent_kind,
        lifecycle_state: "requested",
        requested_at: @occurred_at,
        summary_payload: {}
      )
    end

    def apply_immediate_state!(conversation)
      return unless @intent_kind == "delete"
      return if conversation.deleted?

      conversation.update!(
        deletion_state: "pending_delete",
        deleted_at: conversation.deleted_at || @occurred_at
      )
    end

    def cancel_queued_turns!(conversation, reason_kind:)
      Turn.where(conversation: conversation, lifecycle_state: "queued").update_all(
        lifecycle_state: "canceled",
        cancellation_requested_at: @occurred_at,
        cancellation_reason_kind: reason_kind,
        updated_at: @occurred_at
      )
    end

    def request_turn_interrupts!(conversation)
      Turn.where(conversation: conversation, lifecycle_state: "active").find_each do |turn|
        Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: @occurred_at)
      end
    end

    def request_background_process_closes!(conversation, request_kind:, reason_kind:)
      Conversations::RequestResourceCloses.call(
        relations: ProcessRun.where(
          conversation: conversation,
          lifecycle_state: "running",
          kind: "background_service"
        ),
        request_kind: request_kind,
        reason_kind: reason_kind,
        occurred_at: @occurred_at
      )
    end

    def request_owned_subagent_connection_closes!(owned_subagent_tree, publish_delivery_endpoint:, request_kind:, reason_kind:)
      closeable_owned_subagent_connections(owned_subagent_tree).each do |session|
        next unless session.close_open?

        SubagentConnections::RequestClose.call(
          subagent_connection: session,
          request_kind: request_kind,
          reason_kind: reason_kind,
          strictness: "graceful",
          publish_delivery_endpoint: publish_delivery_endpoint,
          occurred_at: @occurred_at
        )
      end
    end

    def closeable_owned_subagent_connections(owned_subagent_tree)
      return [] if owned_subagent_tree.connection_ids.empty?

      SubagentConnection
        .where(id: owned_subagent_tree.connection_ids)
        .includes(:installation, :conversation, :execution_lease, owner_conversation: :agent)
        .order(:created_at, :id)
    end

    def active_agent_connection_for(conversation)
      AgentConnection.find_by(
        agent: conversation.agent,
        lifecycle_state: "active"
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end

    def complete_control_request!(conversation)
      return if @conversation_control_request.blank?

      @conversation_control_request.update!(
        lifecycle_state: "completed",
        completed_at: @occurred_at,
        result_payload: @conversation_control_request.result_payload.merge(
          "conversation_id" => conversation.public_id,
          "intent_kind" => @intent_kind
        )
      )
    end
  end
end
