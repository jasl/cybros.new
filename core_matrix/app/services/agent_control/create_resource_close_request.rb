require "securerandom"

module AgentControl
  class CreateResourceCloseRequest
    def self.call(...)
      new(...).call
    end

    def initialize(resource:, request_kind:, reason_kind:, strictness:, grace_deadline_at:, force_deadline_at:, message_id: nil, causation_id: nil)
      @resource = resource
      @request_kind = request_kind
      @reason_kind = reason_kind
      @strictness = strictness
      @grace_deadline_at = grace_deadline_at
      @force_deadline_at = force_deadline_at
      @message_id = message_id || "kernel-close-#{SecureRandom.uuid}"
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
      target_deployment = delivery_endpoint
      target_agent_installation = target_deployment&.agent_installation || ClosableResourceRouting.owning_agent_installation_for(@resource)

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
        target_agent_installation: target_agent_installation,
        target_agent_deployment: target_deployment,
        target_execution_environment: environment_plane? ? ClosableResourceRouting.execution_environment_for(@resource) : nil,
        agent_task_run: agent_task_run,
        item_type: "resource_close_request",
        runtime_plane: runtime_plane,
        target_kind: target_deployment.present? ? "agent_deployment" : "agent_installation",
        target_ref: durable_target_ref(target_agent_installation:, target_deployment:),
        logical_work_id: agent_task_run&.logical_work_id || "close:#{@resource.class.name}:#{@resource.public_id}",
        attempt_no: agent_task_run&.attempt_no || 1,
        message_id: @message_id,
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
      if environment_plane?
        execution_environment = ClosableResourceRouting.execution_environment_for(@resource)
        return if execution_environment.blank?

        return ExecutionEnvironments::ResolveDeliveryEndpoint.call(execution_environment: execution_environment)
      end

      @resource.execution_lease&.holder_deployment
    end

    def agent_task_run
      @resource if @resource.is_a?(AgentTaskRun)
    end

    def runtime_plane
      environment_plane? ? "environment" : "agent"
    end

    def environment_plane?
      @resource.is_a?(ProcessRun)
    end

    def durable_target_ref(target_agent_installation:, target_deployment:)
      execution_environment = ClosableResourceRouting.execution_environment_for(@resource)
      return execution_environment.public_id if environment_plane? && execution_environment.present?

      target_deployment&.public_id || target_agent_installation.public_id
    end
  end
end
