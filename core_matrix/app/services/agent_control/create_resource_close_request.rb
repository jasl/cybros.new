require "securerandom"

module AgentControl
  class CreateResourceCloseRequest
    def self.call(...)
      new(...).call
    end

    def initialize(resource:, request_kind:, reason_kind:, strictness:, grace_deadline_at:, force_deadline_at:, protocol_message_id: nil, causation_id: nil)
      @resource = resource
      @request_kind = request_kind
      @reason_kind = reason_kind
      @strictness = strictness
      @grace_deadline_at = grace_deadline_at
      @force_deadline_at = force_deadline_at
      @protocol_message_id = protocol_message_id || "kernel-close-#{SecureRandom.uuid}"
      @causation_id = causation_id
    end

    def call
      validate_supported_resource!

      mailbox_item = ApplicationRecord.transaction do
        create_mailbox_item!
      end

      PublishPending.call(mailbox_item: mailbox_item)
      mailbox_item
    end

    private

    def create_mailbox_item!
      requested_at = Time.current
      target_session = delivery_endpoint
      target_deployment = target_session.agent_program_version if target_session.is_a?(AgentSession)
      target_agent_program =
        if target_session.is_a?(AgentSession)
          target_session.agent_program
        else
          ClosableResourceRouting.owning_agent_program_for(@resource)
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
        target_execution_runtime: execution_plane? ? ClosableResourceRouting.execution_runtime_for(@resource) : nil,
        agent_task_run: agent_task_run,
        item_type: "resource_close_request",
        runtime_plane: runtime_plane,
        target_kind: target_deployment.present? ? "agent_program_version" : "agent_program",
        target_ref: durable_target_ref(target_agent_program:, target_deployment:),
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

    def validate_supported_resource!
      return if ClosableResourceRegistry.supported?(@resource)

      raise ArgumentError, "unsupported close resource #{@resource.class.name}"
    end

    def delivery_endpoint
      if execution_plane?
        execution_runtime = ClosableResourceRouting.execution_runtime_for(@resource)
        return if execution_runtime.blank?

        return ExecutionSessions::ResolveActiveSession.call(execution_runtime: execution_runtime)
      end

      return @resource.holder_agent_session if @resource.respond_to?(:holder_agent_session)

      execution_lease = @resource.try(:execution_lease)
      return if execution_lease.blank?

      AgentSession.find_by(public_id: execution_lease.holder_key)
    end

    def agent_task_run
      @resource if @resource.is_a?(AgentTaskRun)
    end

    def runtime_plane
      execution_plane? ? "execution" : "program"
    end

    def execution_plane?
      @resource.is_a?(ProcessRun)
    end

    def durable_target_ref(target_agent_program:, target_deployment:)
      execution_runtime = ClosableResourceRouting.execution_runtime_for(@resource)
      return execution_runtime.public_id if execution_plane? && execution_runtime.present?

      target_deployment&.public_id || target_agent_program.public_id
    end
  end
end
