class WorkflowArtifact < ApplicationRecord
  enum :storage_mode,
    {
      inline_json: "inline_json",
      attached_file: "attached_file",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workflow_node

  has_one_attached :file

  validates :artifact_key, presence: true
  validates :artifact_kind, presence: true
  validate :payload_must_be_hash
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :workflow_node_workflow_run_match
  validate :storage_mode_file_rules

  private

  def payload_must_be_hash
    errors.add(:payload, "must be a hash") unless payload.is_a?(Hash)
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

  def storage_mode_file_rules
    if attached_file?
      errors.add(:file, "must be attached for attached_file storage mode") unless file.attached?
      return
    end

    errors.add(:file, "must be blank for inline_json storage mode") if file.attached?
  end
end
