class WorkspaceAgent < ApplicationRecord
  include HasPublicId

  LIFECYCLE_STATES = %w[active revoked retired].freeze

  belongs_to :installation
  belongs_to :workspace
  belongs_to :agent
  belongs_to :default_execution_runtime, class_name: "ExecutionRuntime", optional: true

  has_many :conversations, dependent: :restrict_with_exception

  validates :lifecycle_state, presence: true, inclusion: { in: LIFECYCLE_STATES }
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :default_execution_runtime_installation_match
  validate :single_active_mount

  after_commit :lock_conversations_after_revocation, on: %i[create update]

  def active? = lifecycle_state == "active"

  def revoked? = lifecycle_state == "revoked"

  def retired? = lifecycle_state == "retired"

  private

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def default_execution_runtime_installation_match
    return if default_execution_runtime.blank?
    return if default_execution_runtime.installation_id == installation_id

    errors.add(:default_execution_runtime, "must belong to the same installation")
  end

  def single_active_mount
    return unless active?

    conflicting_scope = self.class.where(
      workspace_id: workspace_id,
      agent_id: agent_id,
      lifecycle_state: "active"
    )
    conflicting_scope = conflicting_scope.where.not(id: id) if persisted?
    return unless conflicting_scope.exists?

    errors.add(:agent_id, "already has an active mount for this workspace")
  end

  def lock_conversations_after_revocation
    return unless revoked? || retired?

    conversations.where(interaction_lock_state: "mutable").update_all(
      interaction_lock_state: "locked_agent_access_revoked",
      updated_at: Time.current
    )
  end
end
