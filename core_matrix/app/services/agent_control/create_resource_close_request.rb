require "securerandom"

module AgentControl
  class CreateResourceCloseRequest
    def self.call(...)
      new(...).call
    end

    def initialize(resource:, request_kind:, reason_kind:, strictness:, grace_deadline_at:, force_deadline_at:, protocol_message_id: nil, causation_id: nil, publish_delivery_endpoint: nil)
      @resource = resource
      @request_kind = request_kind
      @reason_kind = reason_kind
      @strictness = strictness
      @grace_deadline_at = grace_deadline_at
      @force_deadline_at = force_deadline_at
      @protocol_message_id = protocol_message_id || "kernel-close-#{SecureRandom.uuid}"
      @causation_id = causation_id
      @publish_delivery_endpoint = publish_delivery_endpoint
    end

    def call
      validate_supported_resource!

      mailbox_item = ApplicationRecord.transaction do
        create_mailbox_item!
      end

      PublishPending.call(
        mailbox_item: mailbox_item,
        resolved_delivery_endpoint: @publish_delivery_endpoint
      )
      mailbox_item
    end

    private

    def create_mailbox_item!
      requested_at = Time.current
      target_session = delivery_endpoint
      target_agent_program =
        if target_session.is_a?(AgentSession)
          target_session.agent_program
        else
          ClosableResourceRouting.owning_agent_program_for(@resource)
        end
      target_deployment =
        if executor_plane?
          nil
        else
          resolved_target_deployment(target_session:, target_agent_program:)
        end

      resource_updates = {
        close_state: "requested",
        close_reason_kind: @reason_kind,
        close_requested_at: requested_at,
        close_grace_deadline_at: @grace_deadline_at,
        close_force_deadline_at: @force_deadline_at,
      }

      @resource.update!(resource_updates)

      mailbox_item = AgentControlMailboxItem.create!(
        installation: @resource.installation,
        target_agent_program: target_agent_program,
        target_agent_program_version: target_deployment,
        target_executor_program: executor_plane? ? ClosableResourceRouting.executor_program_for(@resource) : nil,
        agent_task_run: agent_task_run,
        item_type: "resource_close_request",
        control_plane: control_plane,
        logical_work_id: agent_task_run&.logical_work_id || "close:#{@resource.class.name}:#{@resource.public_id}",
        attempt_no: agent_task_run&.attempt_no || 1,
        protocol_message_id: @protocol_message_id,
        causation_id: @causation_id,
        priority: 0,
        status: "queued",
        available_at: requested_at,
        dispatch_deadline_at: @force_deadline_at,
        lease_timeout_seconds: 30,
        payload: {
          "resource_type" => @resource.class.name,
          "resource_id" => @resource.public_id,
          "agent_task_run_id" => agent_task_run&.public_id,
          "request_kind" => @request_kind,
          "reason_kind" => @reason_kind,
          "strictness" => @strictness,
          "grace_deadline_at" => @grace_deadline_at.iso8601,
          "force_deadline_at" => @force_deadline_at.iso8601,
        }
      )

      mailbox_item.update!(payload: mailbox_item.payload.merge("close_request_id" => mailbox_item.public_id))
      mailbox_item
    end

    def resolved_target_deployment(target_session:, target_agent_program:)
      return target_session.agent_program_version if target_session.is_a?(AgentSession)
      return if target_agent_program.blank?

      target_agent_program.current_agent_program_version ||
        AgentSession.where(agent_program: target_agent_program).order(created_at: :desc, id: :desc).limit(1).pick(:agent_program_version_id)&.yield_self do |agent_program_version_id|
          AgentProgramVersion.find_by(id: agent_program_version_id)
        end
    end

    def validate_supported_resource!
      return if ClosableResourceRegistry.supported?(@resource)

      raise ArgumentError, "unsupported close resource #{@resource.class.name}"
    end

    def delivery_endpoint
      if executor_plane?
        executor_program = ClosableResourceRouting.executor_program_for(@resource)
        return if executor_program.blank?

        return ExecutorSessions::ResolveActiveSession.call(executor_program: executor_program)
      end

      return @resource.holder_agent_session if @resource.respond_to?(:holder_agent_session)

      execution_lease = @resource.try(:execution_lease)
      return if execution_lease.blank?

      AgentSession.find_by(public_id: execution_lease.holder_key)
    end

    def agent_task_run
      @resource if @resource.is_a?(AgentTaskRun)
    end

    def control_plane
      executor_plane? ? "executor" : "program"
    end

    def executor_plane?
      @resource.is_a?(ProcessRun)
    end
  end
end
