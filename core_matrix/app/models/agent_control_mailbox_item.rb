class AgentControlMailboxItem < ApplicationRecord
  include HasPublicId

  RUNTIME_PLANES = %w[agent environment].freeze

  enum :item_type,
    {
      execution_assignment: "execution_assignment",
      agent_program_request: "agent_program_request",
      resource_close_request: "resource_close_request",
      capabilities_refresh_request: "capabilities_refresh_request",
      recovery_notice: "recovery_notice",
    },
    validate: true
  enum :target_kind,
    {
      agent_installation: "agent_installation",
      agent_deployment: "agent_deployment",
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
  belongs_to :target_agent_installation, class_name: "AgentInstallation"
  belongs_to :target_agent_deployment, class_name: "AgentDeployment", optional: true
  belongs_to :target_execution_environment, class_name: "ExecutionEnvironment", optional: true
  belongs_to :agent_task_run, optional: true
  belongs_to :leased_to_agent_deployment, class_name: "AgentDeployment", optional: true

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
  validate :target_deployment_match
  validate :target_execution_environment_match
  validate :agent_task_run_match
  validate :lease_holder_match
  validate :target_ref_consistency
  validate :runtime_plane_contract

  def targets?(deployment)
    return false if deployment.blank?

    if environment_plane?
      return false unless deployment.installation_id == installation_id
      return false if target_execution_environment_id.blank?

      deployment.execution_environment_id == target_execution_environment_id
    else
      case target_kind
      when "agent_installation"
        deployment.agent_installation_id == target_agent_installation_id
      when "agent_deployment"
        deployment.id == target_agent_deployment_id
      else
        false
      end
    end
  end

  def agent_plane?
    runtime_plane == "agent"
  end

  def environment_plane?
    runtime_plane == "environment"
  end

  def leased_to?(deployment)
    deployment.present? && leased_to_agent_deployment_id == deployment.id
  end

  def lease_stale?(at: Time.current)
    leased? && lease_expires_at.present? && lease_expires_at < at
  end

  private

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
  end

  def target_installation_match
    return if target_agent_installation.blank? || target_agent_installation.installation_id == installation_id

    errors.add(:target_agent_installation, "must belong to the same installation")
  end

  def target_deployment_match
    return if target_agent_deployment.blank?

    if target_agent_deployment.installation_id != installation_id
      errors.add(:target_agent_deployment, "must belong to the same installation")
    end

    if target_agent_deployment.agent_installation_id != target_agent_installation_id
      errors.add(:target_agent_deployment, "must belong to the targeted agent installation")
    end
  end

  def target_execution_environment_match
    return if target_execution_environment.blank?
    return if target_execution_environment.installation_id == installation_id

    errors.add(:target_execution_environment, "must belong to the same installation")
  end

  def agent_task_run_match
    return if agent_task_run.blank?

    if agent_task_run.installation_id != installation_id
      errors.add(:agent_task_run, "must belong to the same installation")
    end

    if agent_task_run.agent_installation_id != target_agent_installation_id
      errors.add(:agent_task_run, "must belong to the targeted agent installation")
    end
  end

  def lease_holder_match
    return if leased_to_agent_deployment.blank?

    if leased_to_agent_deployment.installation_id != installation_id
      errors.add(:leased_to_agent_deployment, "must belong to the same installation")
    end

    errors.add(:leased_to_agent_deployment, "must satisfy the mailbox target") unless targets?(leased_to_agent_deployment)
  end

  def target_ref_consistency
    expected_ref = if environment_plane?
      target_execution_environment&.public_id
    elsif agent_deployment?
      target_agent_deployment&.public_id
    else
      target_agent_installation&.public_id
    end
    return if target_ref == expected_ref

    errors.add(:target_ref, "must match the durable target reference")
  end

  def runtime_plane_contract
    return unless environment_plane?

    if target_execution_environment.blank?
      errors.add(:target_execution_environment, "must be present for environment-plane work")
      return
    end

    return if target_execution_environment.installation_id == installation_id

    errors.add(:target_execution_environment, "must reference an execution environment in the same installation")
  end
end
