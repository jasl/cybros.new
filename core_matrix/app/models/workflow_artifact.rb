class WorkflowArtifact < ApplicationRecord
  enum :storage_mode,
    {
      json_document: "json_document",
      attached_file: "attached_file",
    },
    validate: true
  enum :presentation_policy,
    {
      internal_only: "internal_only",
      ops_trackable: "ops_trackable",
      user_projectable: "user_projectable",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_run
  belongs_to :workflow_node
  belongs_to :workspace
  belongs_to :conversation
  belongs_to :turn
  belongs_to :json_document, optional: true

  has_one_attached :file

  before_validation :default_projection_fields_from_workflow_node
  before_validation :materialize_pending_payload

  validates :artifact_key, presence: true
  validates :artifact_kind, presence: true
  validate :json_document_presence_for_json_document_mode
  validate :workflow_run_installation_match
  validate :workflow_node_installation_match
  validate :workflow_node_workflow_run_match
  validate :projection_integrity
  validate :storage_mode_file_rules

  private

  def default_projection_fields_from_workflow_node
    return if workflow_node.blank?

    self.workspace ||= workflow_node.workspace
    self.conversation ||= workflow_node.conversation
    self.turn ||= workflow_node.turn
    self.workflow_node_key ||= workflow_node.node_key
    self.workflow_node_ordinal ||= workflow_node.ordinal
    self.presentation_policy ||= workflow_node.presentation_policy
  end

  def json_document_presence_for_json_document_mode
    errors.add(:json_document, "must be present for json_document storage mode") if json_document.blank? && json_document?
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

  def projection_integrity
    return if workflow_node.blank?

    if workspace.present? && workflow_node.workspace_id != workspace_id
      errors.add(:workspace, "must match the workflow node workspace")
    end
    if conversation.present? && workflow_node.conversation_id != conversation_id
      errors.add(:conversation, "must match the workflow node conversation")
    end
    if turn.present? && workflow_node.turn_id != turn_id
      errors.add(:turn, "must match the workflow node turn")
    end
    if workflow_node_key.present? && workflow_node.node_key != workflow_node_key
      errors.add(:workflow_node_key, "must match the workflow node key")
    end
    if !workflow_node_ordinal.nil? && workflow_node.ordinal != workflow_node_ordinal
      errors.add(:workflow_node_ordinal, "must match the workflow node ordinal")
    end
    if presentation_policy.present? && workflow_node.presentation_policy != presentation_policy
      errors.add(:presentation_policy, "must match the workflow node presentation policy")
    end
  end

  def storage_mode_file_rules
    if attached_file?
      errors.add(:file, "must be attached for attached_file storage mode") unless file.attached?
      return
    end

    errors.add(:file, "must be blank for json_document storage mode") if file.attached?
  end

  public

  def payload
    json_document&.payload || {}
  end

  def payload=(value)
    @pending_payload = value
  end

  def json_document?
    storage_mode == "json_document"
  end

  def attached_file?
    storage_mode == "attached_file"
  end

  def materialize_pending_payload
    return unless defined?(@pending_payload)
    return if @pending_payload.nil?
    return if installation.blank?
    return if @pending_payload.blank?

    self.json_document = JsonDocuments::Store.call(
      installation: installation,
      document_kind: "workflow_artifact_payload",
      payload: @pending_payload
    )
    self.storage_mode = "json_document" if storage_mode.blank? || json_document?
  end
end
