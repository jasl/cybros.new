class ToolInvocation < ApplicationRecord
  include HasPublicId

  STRUCTURED_METADATA_KEYS = %w[provider_format stream_output fenix].freeze

  def self.idempotency_lookup_scope(tool_binding:)
    if tool_binding.workflow_node_id.present?
      where(workflow_node_id: tool_binding.workflow_node_id)
    elsif tool_binding.agent_task_run_id.present?
      where(agent_task_run_id: tool_binding.agent_task_run_id)
    else
      where(tool_binding_id: tool_binding.id)
    end
  end

  enum :status,
    {
      running: "running",
      succeeded: "succeeded",
      failed: "failed",
      canceled: "canceled",
    },
    validate: true

  belongs_to :installation
  belongs_to :user
  belongs_to :workspace
  belongs_to :agent
  belongs_to :agent_task_run, optional: true
  belongs_to :conversation
  belongs_to :turn
  belongs_to :workflow_run
  belongs_to :workflow_node, optional: true
  belongs_to :tool_binding
  belongs_to :tool_definition
  belongs_to :tool_implementation
  belongs_to :request_document, class_name: "JsonDocument", optional: true
  belongs_to :response_document, class_name: "JsonDocument", optional: true
  belongs_to :error_document, class_name: "JsonDocument", optional: true
  belongs_to :trace_document, class_name: "JsonDocument", optional: true

  has_one :command_run, dependent: :destroy

  before_validation :materialize_pending_documents

  validates :attempt_no, numericality: { only_integer: true, greater_than: 0 }
  validate :execution_subject_present
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :installation_matches_task
  validate :installation_matches_conversation
  validate :installation_matches_turn
  validate :installation_matches_workflow_run
  validate :installation_matches_workflow_node
  validate :installation_matches_binding
  validate :installation_matches_tool_definition
  validate :installation_matches_tool_implementation
  validate :binding_projection_alignment
  validate :execution_subject_context_alignment
  validate :metadata_must_be_hash
  validate :lifecycle_timestamps

  def request_payload
    request_document&.payload || {}
  end

  def request_payload=(value)
    @pending_request_payload = value
  end

  def response_payload
    response_document&.payload || {}
  end

  def response_payload=(value)
    @pending_response_payload = value
  end

  def error_payload
    error_document&.payload || {}
  end

  def error_payload=(value)
    @pending_error_payload = value
  end

  def trace_payload
    trace_document&.payload || {}
  end

  def trace_payload=(value)
    @pending_trace_payload = value
  end

  private

  def materialize_pending_documents
    return if installation.blank?

    if defined?(@pending_request_payload)
      self.request_document =
        if @pending_request_payload.blank?
          nil
        else
          JsonDocuments::Store.call(
            installation: installation,
            document_kind: "tool_invocation_request",
            payload: @pending_request_payload
          )
        end
    end

    if defined?(@pending_response_payload)
      self.response_document =
        if @pending_response_payload.blank?
          nil
        else
          JsonDocuments::Store.call(
            installation: installation,
            document_kind: "tool_invocation_response",
            payload: @pending_response_payload
          )
        end
    end

    if defined?(@pending_error_payload)
      self.error_document =
        if @pending_error_payload.blank?
          nil
        else
          JsonDocuments::Store.call(
            installation: installation,
            document_kind: "tool_invocation_error",
            payload: @pending_error_payload
          )
        end
    end

    if defined?(@pending_trace_payload)
      self.trace_document =
        if @pending_trace_payload.blank?
          nil
        else
          JsonDocuments::Store.call(
            installation: installation,
            document_kind: "tool_invocation_trace",
            payload: @pending_trace_payload
          )
        end
    end
  end

  def execution_subject_present
    return if agent_task_run.present? || workflow_node.present?

    errors.add(:base, "must belong to an agent task run or workflow node")
  end

  def user_installation_match
    return if user.blank? || user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank? || workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank? || agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def installation_matches_task
    return if agent_task_run.blank? || agent_task_run.installation_id == installation_id

    errors.add(:installation, "must match the task installation")
  end

  def installation_matches_conversation
    return if conversation.blank? || conversation.installation_id == installation_id

    errors.add(:installation, "must match the conversation installation")
  end

  def installation_matches_turn
    return if turn.blank? || turn.installation_id == installation_id

    errors.add(:installation, "must match the turn installation")
  end

  def installation_matches_workflow_run
    return if workflow_run.blank? || workflow_run.installation_id == installation_id

    errors.add(:installation, "must match the workflow run installation")
  end

  def installation_matches_workflow_node
    return if workflow_node.blank? || workflow_node.installation_id == installation_id

    errors.add(:installation, "must match the workflow node installation")
  end

  def installation_matches_binding
    return if tool_binding.blank? || tool_binding.installation_id == installation_id

    errors.add(:installation, "must match the tool binding installation")
  end

  def installation_matches_tool_definition
    return if tool_definition.blank? || tool_definition.installation_id == installation_id

    errors.add(:installation, "must match the tool definition installation")
  end

  def installation_matches_tool_implementation
    return if tool_implementation.blank? || tool_implementation.installation_id == installation_id

    errors.add(:installation, "must match the tool implementation installation")
  end

  def binding_projection_alignment
    return if tool_binding.blank?

    if tool_binding.agent_task_run_id != agent_task_run_id
      errors.add(:agent_task_run, "must match the frozen tool binding")
    end

    if tool_binding.workflow_node_id != workflow_node_id
      errors.add(:workflow_node, "must match the frozen tool binding")
    end

    if tool_definition.present? && tool_binding.tool_definition_id != tool_definition_id
      errors.add(:tool_definition, "must match the frozen tool binding")
    end

    if tool_implementation.present? && tool_binding.tool_implementation_id != tool_implementation_id
      errors.add(:tool_implementation, "must match the frozen tool binding")
    end
  end

  def execution_subject_context_alignment
    subject = execution_subject
    return if subject.blank?

    errors.add(:user, "must match the execution subject user") if user.present? && subject.user_id != user_id
    errors.add(:workspace, "must match the execution subject workspace") if workspace.present? && subject.workspace_id != workspace_id
    errors.add(:agent, "must match the execution subject agent") if agent.present? && subject.agent_id != agent_id
    errors.add(:conversation, "must match the execution subject conversation") if conversation.present? && subject.conversation_id != conversation_id
    errors.add(:turn, "must match the execution subject turn") if turn.present? && subject.turn_id != turn_id
    errors.add(:workflow_run, "must match the execution subject workflow run") if workflow_run.present? && subject.workflow_run_id != workflow_run_id
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
    return unless metadata.is_a?(Hash)

    duplicate_keys = metadata.stringify_keys.keys & STRUCTURED_METADATA_KEYS
    return if duplicate_keys.empty?

    errors.add(:metadata, "must not duplicate structured invocation fields")
  end

  def lifecycle_timestamps
    if running?
      errors.add(:started_at, "must exist while the invocation is running") if started_at.blank?
      errors.add(:finished_at, "must be blank while the invocation is running") if finished_at.present?
      return
    end

    errors.add(:started_at, "must exist when the invocation has started") if started_at.blank?
    errors.add(:finished_at, "must exist when the invocation is terminal") if finished_at.blank?
  end

  def execution_subject
    agent_task_run || workflow_node
  end
end
