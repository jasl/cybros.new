class CanonicalVariable < ApplicationRecord
  SCOPES = %w[workspace conversation].freeze
  PROJECTION_POLICIES = %w[silent conversation_event].freeze

  belongs_to :installation
  belongs_to :workspace
  belongs_to :conversation, optional: true
  belongs_to :writer, polymorphic: true, optional: true
  belongs_to :source_conversation, class_name: "Conversation", optional: true
  belongs_to :source_turn, class_name: "Turn", optional: true
  belongs_to :source_workflow_run, class_name: "WorkflowRun", optional: true
  belongs_to :superseded_by, class_name: "CanonicalVariable", optional: true

  validates :scope, presence: true, inclusion: { in: SCOPES }
  validates :projection_policy, presence: true, inclusion: { in: PROJECTION_POLICIES }
  validates :key, presence: true
  validates :source_kind, presence: true
  validate :typed_value_payload_must_be_hash
  validate :workspace_installation_match
  validate :conversation_installation_match
  validate :conversation_workspace_match
  validate :writer_pairing
  validate :source_conversation_installation_match
  validate :source_turn_installation_match
  validate :source_workflow_run_installation_match
  validate :source_turn_conversation_match
  validate :source_workflow_run_conversation_match
  validate :scope_rules
  validate :supersession_state

  def self.effective_for(workspace:, key:, conversation: nil)
    if conversation.present?
      conversation_value = where(
        workspace: workspace,
        conversation: conversation,
        scope: "conversation",
        key: key,
        current: true
      ).order(created_at: :desc).first
      return conversation_value if conversation_value.present?
    end

    where(
      workspace: workspace,
      scope: "workspace",
      key: key,
      current: true
    ).order(created_at: :desc).first
  end

  def workspace_scope?
    scope == "workspace"
  end

  def conversation_scope?
    scope == "conversation"
  end

  def superseded?
    !current?
  end

  private

  def typed_value_payload_must_be_hash
    errors.add(:typed_value_payload, "must be a hash") unless typed_value_payload.is_a?(Hash)
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def conversation_installation_match
    return if conversation.blank?
    return if conversation.installation_id == installation_id

    errors.add(:conversation, "must belong to the same installation")
  end

  def conversation_workspace_match
    return if conversation.blank? || workspace.blank?
    return if conversation.workspace_id == workspace_id

    errors.add(:conversation, "must belong to the same workspace")
  end

  def writer_pairing
    return if writer_id.blank? && writer_type.blank?
    return if writer_id.present? && writer_type.present?

    errors.add(:writer, "must include both type and id")
  end

  def source_conversation_installation_match
    return if source_conversation.blank?
    return if source_conversation.installation_id == installation_id

    errors.add(:source_conversation, "must belong to the same installation")
  end

  def source_turn_installation_match
    return if source_turn.blank?
    return if source_turn.installation_id == installation_id

    errors.add(:source_turn, "must belong to the same installation")
  end

  def source_workflow_run_installation_match
    return if source_workflow_run.blank?
    return if source_workflow_run.installation_id == installation_id

    errors.add(:source_workflow_run, "must belong to the same installation")
  end

  def source_turn_conversation_match
    return if source_turn.blank? || source_conversation.blank?
    return if source_turn.conversation_id == source_conversation_id

    errors.add(:source_turn, "must belong to the source conversation")
  end

  def source_workflow_run_conversation_match
    return if source_workflow_run.blank? || source_conversation.blank?
    return if source_workflow_run.conversation_id == source_conversation_id

    errors.add(:source_workflow_run, "must belong to the source conversation")
  end

  def scope_rules
    if workspace_scope?
      errors.add(:conversation, "must be blank for workspace scope") if conversation.present?
      return
    end

    errors.add(:conversation, "must exist for conversation scope") if conversation.blank?
  end

  def supersession_state
    if current?
      errors.add(:superseded_at, "must be blank while canonical variable is current") if superseded_at.present?
      errors.add(:superseded_by, "must be blank while canonical variable is current") if superseded_by.present?
      return
    end

    errors.add(:superseded_at, "must exist once a canonical variable is superseded") if superseded_at.blank?
    errors.add(:superseded_by, "must exist once a canonical variable is superseded") if superseded_by.blank?
  end
end
