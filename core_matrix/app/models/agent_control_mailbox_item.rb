class AgentControlMailboxItem < ApplicationRecord
  include HasPublicId

  RUNTIME_PLANES = %w[program execution].freeze

  enum :item_type,
    {
      execution_assignment: "execution_assignment",
      agent_program_request: "agent_program_request",
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
  belongs_to :target_agent_program, class_name: "AgentProgram"
  belongs_to :target_agent_program_version, class_name: "AgentProgramVersion", optional: true
  belongs_to :target_execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :agent_task_run, optional: true
  belongs_to :leased_to_agent_session, class_name: "AgentSession", optional: true
  belongs_to :leased_to_execution_session, class_name: "ExecutionSession", optional: true

  has_many :agent_control_report_receipts, foreign_key: :mailbox_item_id, dependent: :restrict_with_exception

  validates :protocol_message_id, presence: true, uniqueness: { scope: :installation_id }
  validates :runtime_plane, presence: true, inclusion: { in: RUNTIME_PLANES }
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
  validate :lease_holder_match
  validate :runtime_plane_contract

  def program_plane?
    runtime_plane == "program"
  end

  def execution_plane?
    runtime_plane == "execution"
  end

  def target_agent_program_version?
    target_agent_program_version_id.present?
  end

  def targets?(deployment)
    return false if deployment.blank?

    if execution_plane?
      target_execution_runtime_id.present? &&
        target_execution_runtime_id == execution_runtime_id_for(deployment)
    else
      if target_agent_program_version_id.present?
        deployment.id == target_agent_program_version_id
      else
        deployment.agent_program_id == target_agent_program_id
      end
    end
  end

  def leased_to?(deployment)
    return false if deployment.blank?

    case deployment
    when AgentSession
      leased_to_agent_session_id == deployment.id
    when AgentProgramVersion
      leased_to_agent_session&.agent_program_version_id == deployment.id
    when ExecutionSession
      leased_to_execution_session_id == deployment.id
    else
      false
    end
  end

  def leased_to_agent_program_version
    leased_to_agent_session&.agent_program_version
  end

  def lease_stale?(at: Time.current)
    leased? && lease_expires_at.present? && lease_expires_at < at
  end

  private

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
  end

  def target_installation_match
    return if target_agent_program.blank? || target_agent_program.installation_id == installation_id

    errors.add(:target_agent_program, "must belong to the same installation")
  end

  def target_program_version_match
    return if target_agent_program_version.blank?

    errors.add(:target_agent_program_version, "must belong to the same installation") if target_agent_program_version.installation_id != installation_id
    errors.add(:target_agent_program_version, "must belong to the targeted agent program") if target_agent_program_version.agent_program_id != target_agent_program_id
  end

  def target_execution_runtime_match
    return if target_execution_runtime.blank?
    return if target_execution_runtime.installation_id == installation_id

    errors.add(:target_execution_runtime, "must belong to the same installation")
  end

  def agent_task_run_match
    return if agent_task_run.blank?

    errors.add(:agent_task_run, "must belong to the same installation") if agent_task_run.installation_id != installation_id
    errors.add(:agent_task_run, "must belong to the targeted agent program") if agent_task_run.agent_program_id != target_agent_program_id
  end

  def lease_holder_match
    return if leased_to_agent_session.blank? && leased_to_execution_session.blank?

    if leased_to_agent_session.present?
      errors.add(:leased_to_agent_session, "must belong to the same installation") if leased_to_agent_session.installation_id != installation_id
      errors.add(:leased_to_agent_session, "must satisfy the mailbox target") unless targets?(leased_to_agent_session.agent_program_version)
    end

    if leased_to_execution_session.present?
      errors.add(:leased_to_execution_session, "must belong to the same installation") if leased_to_execution_session.installation_id != installation_id
      if execution_plane?
        errors.add(:leased_to_execution_session, "must belong to the targeted execution runtime") if leased_to_execution_session.execution_runtime_id != target_execution_runtime_id
      else
        errors.add(:leased_to_execution_session, "is only valid for execution-plane work")
      end
    end
  end

  def runtime_plane_contract
    return unless execution_plane?

    if target_execution_runtime.blank?
      errors.add(:target_execution_runtime, "must be present for execution-plane work")
      return
    end

    return if target_execution_runtime.installation_id == installation_id

    errors.add(:target_execution_runtime, "must reference an execution runtime in the same installation")
  end

  def execution_runtime_id_for(deployment)
    deployment.agent_program.default_execution_runtime_id
  end
end
