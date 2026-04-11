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
      target_connection = delivery_endpoint
      target_agent =
        if target_connection.is_a?(AgentConnection)
          target_connection.agent
        else
          ClosableResourceRouting.owning_agent_for(@resource)
        end
      target_agent_snapshot =
        if execution_runtime_plane?
          nil
        else
          resolved_target_agent_snapshot(target_connection:, target_agent:)
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
        target_agent: target_agent,
        target_agent_snapshot: target_agent_snapshot,
        target_execution_runtime: execution_runtime_plane? ? ClosableResourceRouting.execution_runtime_for(@resource) : nil,
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

    def resolved_target_agent_snapshot(target_connection:, target_agent:)
      return target_connection.agent_snapshot if target_connection.is_a?(AgentConnection)
      return if target_agent.blank?

      target_agent.current_agent_snapshot ||
        AgentConnection.where(agent: target_agent).order(created_at: :desc, id: :desc).limit(1).pick(:agent_snapshot_id)&.yield_self do |agent_snapshot_id|
          AgentSnapshot.find_by(id: agent_snapshot_id)
        end
    end

    def validate_supported_resource!
      return if ClosableResourceRegistry.supported?(@resource)

      raise ArgumentError, "unsupported close resource #{@resource.class.name}"
    end

    def delivery_endpoint
      if execution_runtime_plane?
        execution_runtime = ClosableResourceRouting.execution_runtime_for(@resource)
        return if execution_runtime.blank?

        return ExecutionRuntimeConnections::ResolveActiveConnection.call(execution_runtime: execution_runtime)
      end

      return @resource.holder_agent_connection if @resource.respond_to?(:holder_agent_connection)

      execution_lease = @resource.try(:execution_lease)
      return if execution_lease.blank?

      AgentConnection.find_by(public_id: execution_lease.holder_key)
    end

    def agent_task_run
      @resource if @resource.is_a?(AgentTaskRun)
    end

    def control_plane
      execution_runtime_plane? ? "execution_runtime" : "agent"
    end

    def execution_runtime_plane?
      @resource.is_a?(ProcessRun)
    end
  end
end
