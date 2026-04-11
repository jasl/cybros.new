class AgentControlMailboxItem < ApplicationRecord
  include HasPublicId

  CONTROL_PLANES = %w[agent execution_runtime].freeze

  enum :item_type,
    {
      execution_assignment: "execution_assignment",
      agent_request: "agent_request",
      resource_close_request: "resource_close_request",
      capabilities_refresh_request: "capabilities_refresh_request",
      recovery_notice: "recovery_notice",
    },
    validate: true
  enum :status,
    {
      queued: "queued",
      leased: "leased",
      acked: "acked",
      completed: "completed",
      failed: "failed",
      expired: "expired",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :target_agent, class_name: "Agent"
  belongs_to :target_agent_snapshot, class_name: "AgentSnapshot", optional: true
  belongs_to :target_execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :agent_task_run, optional: true
  belongs_to :workflow_node, optional: true
  belongs_to :execution_contract, optional: true
  belongs_to :payload_document, class_name: "JsonDocument", optional: true
  belongs_to :leased_to_agent_connection, class_name: "AgentConnection", optional: true
  belongs_to :leased_to_execution_runtime_connection, class_name: "ExecutionRuntimeConnection", optional: true

  has_many :agent_control_report_receipts, foreign_key: :mailbox_item_id, dependent: :restrict_with_exception

  validates :protocol_message_id, presence: true, uniqueness: { scope: :installation_id }
  validates :control_plane, presence: true, inclusion: { in: CONTROL_PLANES }
  validates :logical_work_id, presence: true
  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validates :delivery_no, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :priority, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :lease_timeout_seconds, numericality: { only_integer: true, greater_than: 0 }
  validate :payload_must_be_hash
  validate :target_installation_match
  validate :target_program_version_match
  validate :target_execution_runtime_match
  validate :agent_task_run_match
  validate :workflow_node_match
  validate :lease_holder_match
  validate :control_plane_contract

  def payload
    materialized_payload
  end

  def materialized_payload(execution_snapshot: nil)
    if payload_document.present?
      return reconstructed_agent_request_payload(execution_snapshot:) if agent_request?

      return payload_document.payload.deep_dup
    end
    return payload_body unless execution_assignment? && execution_contract.present?

    AgentControl::SerializeMailboxItem.serialized_payload(
      self,
      compact_payload: payload_body,
      execution_snapshot:
    )
  end

  def payload_body
    value = self[:payload]
    value.is_a?(Hash) ? value.deep_dup : {}
  end

  def agent_plane?
    control_plane == "agent"
  end

  def execution_runtime_plane?
    control_plane == "execution_runtime"
  end

  def target_agent_snapshot?
    target_agent_snapshot_id.present?
  end

  def targets?(agent_snapshot)
    return false if agent_snapshot.blank?

    if execution_runtime_plane?
      target_execution_runtime_id.present? &&
        target_execution_runtime_id == execution_runtime_id_for(agent_snapshot)
    else
      if target_agent_snapshot_id.present?
        agent_snapshot.id == target_agent_snapshot_id
      else
        agent_snapshot.agent_id == target_agent_id
      end
    end
  end

  def leased_to?(agent_snapshot)
    return false if agent_snapshot.blank?

    case agent_snapshot
    when AgentConnection
      leased_to_agent_connection_id == agent_snapshot.id
    when AgentSnapshot
      leased_to_agent_connection&.agent_snapshot_id == agent_snapshot.id
    when ExecutionRuntimeConnection
      leased_to_execution_runtime_connection_id == agent_snapshot.id
    else
      false
    end
  end

  def leased_to_agent_snapshot
    leased_to_agent_connection&.agent_snapshot
  end

  def lease_stale?(at: Time.current)
    leased? && lease_expires_at.present? && lease_expires_at < at
  end

  private

  def reconstructed_agent_request_payload(execution_snapshot: nil)
    payload = payload_document.payload.deep_dup
    payload.merge!(payload_body)
    payload["protocol_version"] ||= "agent-runtime/2026-04-01"

    task = payload["task"].is_a?(Hash) ? payload["task"].deep_dup : {}
    if workflow_node.present?
      task["kind"] ||= workflow_node.node_type
      task["workflow_node_id"] = workflow_node.public_id
      task["workflow_run_id"] = workflow_node.workflow_run.public_id
      task["conversation_id"] = workflow_node.conversation.public_id
      task["turn_id"] = workflow_node.turn.public_id
    end
    payload["task"] = task if task.present?

    snapshot = execution_snapshot || execution_contract&.turn&.execution_snapshot

    if execution_contract.present? && !payload.key?("provider_context")
      payload["provider_context"] = execution_contract.provider_context
    end

    request_kind = payload["request_kind"]
    if execution_contract.present? && !payload.key?("agent_context")
      payload["agent_context"] = reconstructed_agent_context(payload, execution_snapshot: snapshot)
    end
    if execution_contract.present? && request_kind == "prepare_round" && !payload.key?("round_context")
      payload["round_context"] = reconstructed_round_context(execution_snapshot: snapshot)
    end

    runtime_context = payload["runtime_context"].is_a?(Hash) ? payload["runtime_context"].deep_dup : {}
    snapshot_runtime_context = snapshot&.runtime_context.to_h
    runtime_context["logical_work_id"] = logical_work_id
    runtime_context["attempt_no"] = attempt_no
    runtime_context["control_plane"] = control_plane
    runtime_context["agent_snapshot_id"] = target_agent_snapshot.public_id if target_agent_snapshot.present?
    runtime_context["agent_id"] ||= snapshot_runtime_context["agent_id"]
    runtime_context["user_id"] ||= snapshot_runtime_context["user_id"]
    runtime_context["agent_id"] ||= target_agent.public_id if target_agent.present?
    runtime_context["user_id"] ||= execution_contract&.turn&.conversation&.workspace&.user&.public_id
    payload["runtime_context"] = runtime_context if runtime_context.present?

    payload
  end

  def reconstructed_agent_context(payload, execution_snapshot:)
    capability_projection = execution_snapshot&.capability_projection || {}
    tool_name = payload.dig("tool_call", "tool_name")
    allowed_tool_names =
      if tool_name.present?
        [tool_name]
      else
        capability_projection.fetch("tool_surface", []).map { |entry| entry.fetch("tool_name") }.uniq
      end

    {
      "profile" => capability_projection.fetch("profile_key", "main"),
      "is_subagent" => capability_projection["is_subagent"] == true,
      "subagent_connection_id" => capability_projection["subagent_connection_id"],
      "parent_subagent_connection_id" => capability_projection["parent_subagent_connection_id"],
      "subagent_depth" => capability_projection["subagent_depth"],
      "owner_conversation_id" => capability_projection["owner_conversation_id"],
      "allowed_tool_names" => allowed_tool_names,
    }.compact
  end

  def reconstructed_round_context(execution_snapshot:)
    (execution_snapshot&.conversation_projection || {}).slice(
      "messages",
      "context_imports",
      "projection_fingerprint"
    )
  end

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload_body.is_a?(Hash)
  end

  def target_installation_match
    return if target_agent.blank? || target_agent.installation_id == installation_id

    errors.add(:target_agent, "must belong to the same installation")
  end

  def target_program_version_match
    return if target_agent_snapshot.blank?

    errors.add(:target_agent_snapshot, "must belong to the same installation") if target_agent_snapshot.installation_id != installation_id
    errors.add(:target_agent_snapshot, "must belong to the targeted agent") if target_agent_snapshot.agent_id != target_agent_id
  end

  def target_execution_runtime_match
    return if target_execution_runtime.blank?
    return if target_execution_runtime.installation_id == installation_id

    errors.add(:target_execution_runtime, "must belong to the same installation")
  end

  def agent_task_run_match
    return if agent_task_run.blank?

    errors.add(:agent_task_run, "must belong to the same installation") if agent_task_run.installation_id != installation_id
    errors.add(:agent_task_run, "must belong to the targeted agent") if agent_task_run.agent_id != target_agent_id
  end

  def workflow_node_match
    return if workflow_node.blank?

    errors.add(:workflow_node, "must belong to the same installation") if workflow_node.installation_id != installation_id
    errors.add(:workflow_node, "must belong to the targeted agent") if workflow_node.conversation&.agent_id != target_agent_id

    return if execution_contract.blank? || workflow_node.turn_id == execution_contract.turn_id

    errors.add(:execution_contract, "must belong to the workflow node turn")
  end

  def lease_holder_match
    return if leased_to_agent_connection.blank? && leased_to_execution_runtime_connection.blank?

    if leased_to_agent_connection.present?
      errors.add(:leased_to_agent_connection, "must belong to the same installation") if leased_to_agent_connection.installation_id != installation_id
      errors.add(:leased_to_agent_connection, "must satisfy the mailbox target") unless targets?(leased_to_agent_connection.agent_snapshot)
    end

    if leased_to_execution_runtime_connection.present?
      errors.add(:leased_to_execution_runtime_connection, "must belong to the same installation") if leased_to_execution_runtime_connection.installation_id != installation_id
      if execution_runtime_plane?
        errors.add(:leased_to_execution_runtime_connection, "must belong to the targeted execution runtime") if leased_to_execution_runtime_connection.execution_runtime_id != target_execution_runtime_id
      end
      errors.add(:leased_to_execution_runtime_connection, "is only valid for execution-runtime-plane work") unless execution_runtime_plane?
    end
  end

  def control_plane_contract
    return unless execution_runtime_plane?

    if target_execution_runtime.blank?
      errors.add(:target_execution_runtime, "must be present for execution-runtime-plane work")
      return
    end

    return if target_execution_runtime.installation_id == installation_id

    errors.add(:target_execution_runtime, "must reference an execution runtime in the same installation")
  end

  def execution_runtime_id_for(agent_snapshot)
    agent_snapshot.agent.default_execution_runtime_id
  end
end
