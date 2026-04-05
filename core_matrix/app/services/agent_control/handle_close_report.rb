module AgentControl
  class HandleCloseReport
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, agent_session: nil, execution_session: nil, resource: nil, method_id:, payload:, occurred_at: Time.current)
      @deployment = deployment
      @agent_session = agent_session
      @execution_session = execution_session
      @resource = resource
      @method_id = method_id
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      { mailbox_item: mailbox_item }
    end

    def call
      mailbox_item.with_lock do
        resource = closable_resource

        resource.with_lock do
          ValidateCloseReportFreshness.call(
            deployment: @deployment,
            execution_session: @execution_session,
            payload: @payload,
            mailbox_item: mailbox_item,
            resource: resource,
            occurred_at: @occurred_at
          )

          case @method_id
          when "resource_close_acknowledged"
            handle_resource_close_acknowledged!(resource)
          when "resource_closed"
            handle_terminal_close_report!(resource, close_state: "closed")
          when "resource_close_failed"
            handle_terminal_close_report!(resource, close_state: "failed")
          else
            raise ArgumentError, "unsupported close report #{@method_id}"
          end
        end
      end
    end

    private

    def handle_resource_close_acknowledged!(resource)
      resource.update!(close_state: "acknowledged", close_acknowledged_at: @occurred_at)
      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
    end

    def handle_terminal_close_report!(resource, close_state:)
      broadcast_process_output_chunks!(resource)

      ApplyCloseOutcome.call(
        resource: resource,
        mailbox_item: mailbox_item,
        close_state: close_state,
        close_outcome_kind: @payload.fetch("close_outcome_kind"),
        close_outcome_payload: @payload.fetch("close_outcome_payload", {}),
        occurred_at: @occurred_at
      )
      refresh_related_supervision_states!(resource)
    end

    def broadcast_process_output_chunks!(resource)
      return unless resource.is_a?(ProcessRun)

      Processes::BroadcastOutputChunks.call(
        process_run: resource,
        output_chunks: @payload["output_chunks"],
        occurred_at: @occurred_at
      )
    end

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def closable_resource
      @resource ||= ClosableResourceRegistry.find!(
        installation_id: @deployment.installation_id,
        resource_type: @payload.fetch("resource_type"),
        public_id: @payload.fetch("resource_id")
      )
    end

    def refresh_related_supervision_states!(resource)
      related_conversations_for(resource).each do |conversation|
        Conversations::UpdateSupervisionState.call(
          conversation: conversation,
          occurred_at: @occurred_at
        )
      end
    end

    def related_conversations_for(resource)
      case resource
      when AgentTaskRun
        [resource.conversation, resource.subagent_session&.owner_conversation].compact.uniq
      when SubagentSession
        [resource.conversation, resource.owner_conversation].compact.uniq
      else
        []
      end
    end
  end
end
