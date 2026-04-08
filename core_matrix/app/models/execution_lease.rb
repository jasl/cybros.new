class ExecutionLease < ApplicationRecord
  LEASED_RESOURCE_TYPES = %w[AgentTaskRun ProcessRun SubagentSession].freeze

  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workflow_node
  belongs_to :leased_resource, polymorphic: true, optional: true

  validate :metadata_must_be_hash
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :workflow_node_workflow_run_match
  validate :leased_resource_type_supported
  validate :leased_resource_presence_for_supported_type
  validate :leased_resource_installation_match
  validate :leased_resource_workflow_run_match
  validate :leased_resource_workflow_node_match
  validate :heartbeat_timeout_rules
  validate :release_pairing_rules
  validate :active_resource_uniqueness

  def active?
    released_at.blank?
  end

  def stale?(at: Time.current)
    return false unless active?

    last_heartbeat_at < at - heartbeat_timeout_seconds.seconds
  end

  def holder_deployment
    return if holder_key.blank?

    @holder_deployment ||= AgentProgramVersion.find_by(
      installation_id: installation_id,
      public_id: holder_key
    )
  end

  def holder_executor_program
    holder_deployment&.executor_program
  end

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def workflow_node_installation_match
    return if workflow_node.blank?
    return if workflow_node.installation_id == installation_id

    errors.add(:workflow_node, "must belong to the same installation")
  end

  def workflow_node_workflow_run_match
    return if workflow_node.blank? || workflow_run.blank?
    return if workflow_node.workflow_run_id == workflow_run_id

    errors.add(:workflow_node, "must belong to the same workflow run")
  end

  def leased_resource_type_supported
    return if leased_resource_type.blank?
    return if LEASED_RESOURCE_TYPES.include?(leased_resource_type)

    errors.add(:leased_resource, "must be a supported runtime resource")
  end

  def leased_resource_presence_for_supported_type
    return unless LEASED_RESOURCE_TYPES.include?(leased_resource_type)
    return if supported_leased_resource.present?

    errors.add(:leased_resource, "must exist")
  end

  def leased_resource_installation_match
    resource = supported_leased_resource
    return if resource.blank?
    return if resource.installation_id == installation_id

    errors.add(:leased_resource, "must belong to the same installation")
  end

  def leased_resource_workflow_run_match
    resource = supported_leased_resource
    return if resource.blank? || workflow_run.blank?
    return unless resource.respond_to?(:workflow_run)

    leased_resource_workflow_run = resource.workflow_run
    return if leased_resource_workflow_run.blank? || leased_resource_workflow_run == workflow_run

    errors.add(:leased_resource, "must belong to the same workflow run")
  end

  def leased_resource_workflow_node_match
    resource = supported_leased_resource
    return if resource.blank? || workflow_node.blank?
    return unless resource.respond_to?(:workflow_node)

    leased_resource_workflow_node = resource.workflow_node
    return if leased_resource_workflow_node.blank? || leased_resource_workflow_node == workflow_node

    errors.add(:leased_resource, "must belong to the same workflow node")
  end

  def heartbeat_timeout_rules
    if heartbeat_timeout_seconds.blank? || heartbeat_timeout_seconds <= 0
      errors.add(:heartbeat_timeout_seconds, "must be greater than 0")
    end

    errors.add(:acquired_at, "must exist") if acquired_at.blank?
    errors.add(:last_heartbeat_at, "must exist") if last_heartbeat_at.blank?
  end

  def release_pairing_rules
    if released_at.present? && release_reason.blank?
      errors.add(:release_reason, "must exist when released_at is set")
    end

    if released_at.blank? && release_reason.present?
      errors.add(:released_at, "must exist when release_reason is set")
    end
  end

  def active_resource_uniqueness
    return unless active?
    return if leased_resource_type.blank? || leased_resource_id.blank?

    existing_lease = self.class
      .where(leased_resource_type: leased_resource_type, leased_resource_id: leased_resource_id, released_at: nil)
      .where.not(id: id)
      .exists?
    return unless existing_lease

    errors.add(:leased_resource, "already has an active execution lease")
  end

  def supported_leased_resource
    return unless LEASED_RESOURCE_TYPES.include?(leased_resource_type)

    leased_resource
  end
end
