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
      target_deployment = delivery_endpoint
      target_agent_installation = target_deployment&.agent_installation || owning_agent_installation

      @resource.update!(
        close_state: "requested",
        close_reason_kind: @reason_kind,
        close_requested_at: Time.current,
        close_grace_deadline_at: @grace_deadline_at,
        close_force_deadline_at: @force_deadline_at
      )

      mailbox_item = AgentControlMailboxItem.create!(
        installation: @resource.installation,
        target_agent_installation: target_agent_installation,
        target_agent_deployment: target_deployment,
        agent_task_run: agent_task_run,
        item_type: "resource_close_request",
        target_kind: target_deployment.present? ? "agent_deployment" : "agent_installation",
        target_ref: durable_target_ref(target_agent_installation:, target_deployment:),
        logical_work_id: agent_task_run&.logical_work_id || "close:#{@resource.class.name}:#{@resource.public_id}",
        attempt_no: agent_task_run&.attempt_no || 1,
        message_id: @message_id,
        causation_id: @causation_id,
        priority: 0,
        status: "queued",
        available_at: Time.current,
        dispatch_deadline_at: @force_deadline_at,
        lease_timeout_seconds: 30,
        payload: {
          "runtime_plane" => runtime_plane,
          "execution_environment_id" => resource_execution_environment&.public_id,
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
      PublishPending.call(mailbox_item: mailbox_item)
      mailbox_item
    end

    private

    def delivery_endpoint
      if environment_plane?
        return if resource_execution_environment.blank?

        ExecutionEnvironments::ResolveDeliveryEndpoint.call(execution_environment: resource_execution_environment)
      end

      @resource.execution_lease&.holder_deployment
    end

    def owning_agent_installation
      return @resource.agent_installation if @resource.respond_to?(:agent_installation)

      @resource.turn.agent_deployment.agent_installation
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

    def resource_execution_environment
      return @resource.execution_environment if @resource.respond_to?(:execution_environment)
      return @resource.turn&.conversation&.execution_environment if @resource.respond_to?(:turn)

      @resource.workflow_run&.conversation&.execution_environment if @resource.respond_to?(:workflow_run)
    end

    def durable_target_ref(target_agent_installation:, target_deployment:)
      return resource_execution_environment.public_id if environment_plane? && resource_execution_environment.present?

      target_deployment&.public_id || target_agent_installation.public_id
    end
  end
end
