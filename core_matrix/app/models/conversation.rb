class Conversation < ApplicationRecord
  include HasPublicId

  enum :kind,
    {
      root: "root",
      branch: "branch",
      thread: "thread",
      checkpoint: "checkpoint",
    },
    validate: true
  enum :purpose,
    {
      interactive: "interactive",
      automation: "automation",
    },
    validate: true
  enum :lifecycle_state,
    {
      active: "active",
      archived: "archived",
    },
    validate: true
  enum :deletion_state,
    {
      retained: "retained",
      pending_delete: "pending_delete",
      deleted: "deleted",
    },
    validate: true
  enum :interactive_selector_mode,
    {
      auto: "auto",
      explicit_candidate: "explicit_candidate",
    },
    validate: true

  belongs_to :installation
  belongs_to :workspace
  belongs_to :execution_environment
  belongs_to :agent_deployment
  belongs_to :parent_conversation, class_name: "Conversation", optional: true
  belongs_to :historical_anchor_message, class_name: "Message", optional: true

  has_many :messages, dependent: :restrict_with_exception
  has_many :conversation_imports, dependent: :restrict_with_exception
  has_many :turns, dependent: :restrict_with_exception
  has_many :conversation_message_visibilities, dependent: :restrict_with_exception
  has_many :conversation_summary_segments, dependent: :restrict_with_exception
  has_many :conversation_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :workflow_runs, dependent: :restrict_with_exception
  has_many :conversation_close_operations, dependent: :restrict_with_exception
  has_one :publication, dependent: :restrict_with_exception
  has_one :canonical_store_reference, as: :owner, dependent: :restrict_with_exception
  has_one :root_canonical_store,
    class_name: "CanonicalStore",
    foreign_key: :root_conversation_id,
    dependent: :restrict_with_exception
  has_many :child_conversations,
    class_name: "Conversation",
    foreign_key: :parent_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :parent_conversation
  has_many :ancestor_closures,
    class_name: "ConversationClosure",
    foreign_key: :descendant_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :descendant_conversation
  has_many :descendant_closures,
    class_name: "ConversationClosure",
    foreign_key: :ancestor_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :ancestor_conversation

  validate :workspace_installation_match
  validate :execution_environment_installation_match
  validate :agent_deployment_installation_match
  validate :agent_deployment_environment_match
  validate :parent_lineage_rules
  validate :parent_workspace_match
  validate :parent_execution_environment_match
  validate :historical_anchor_membership
  validate :automation_rules
  validate :override_payload_must_be_hash
  validate :override_reconciliation_report_must_be_hash
  validate :interactive_selector_rules
  validate :deleted_at_consistency

  def transcript_projection_includes?(message)
    base_transcript_projection_messages.any? { |candidate| candidate.id == message.id }
  end

  def transcript_projection_messages
    base_messages = base_transcript_projection_messages
    overlay_lookup = visibility_overlay_lookup_for(base_messages)

    base_messages.reject { |message| hidden_in_projection?(message, overlay_lookup) }
  end

  def context_projection_messages
    base_messages = base_transcript_projection_messages
    overlay_lookup = visibility_overlay_lookup_for(base_messages)

    base_messages.reject do |message|
      hidden_in_projection?(message, overlay_lookup) ||
        excluded_from_context_in_projection?(message, overlay_lookup)
    end
  end

  def context_projection_attachments
    context_projection_messages.flat_map { |message| message.message_attachments.order(:id).to_a }
  end

  def historical_anchor_prefix_messages(message)
    raise ActiveRecord::RecordNotFound, "historical anchor is missing from the parent conversation history" if message.blank?

    if message.conversation_id == id
      local_historical_anchor_prefix_messages(message)
    else
      projection_prefix_messages(message)
    end
  end

  def deleting?
    pending_delete? || deleted?
  end

  def unfinished_close_operation
    conversation_close_operations.where.not(lifecycle_state: ConversationCloseOperation::TERMINAL_STATES).order(created_at: :desc).first
  end

  def closing?
    unfinished_close_operation.present?
  end

  def active_turn_exists?(include_descendants: false)
    return turns.where(lifecycle_state: "active").exists? unless include_descendants

    Turn.where(
      conversation_id: descendant_closures.select(:descendant_conversation_id),
      lifecycle_state: "active"
    ).exists?
  end

  def runtime_contract
    Conversations::RefreshRuntimeContract.call(conversation: self)
  end

  def conversation_attachment_upload?
    runtime_contract["conversation_attachment_upload"] == true
  end

  private

  def base_transcript_projection_messages
    inherited_transcript_projection_messages + selected_messages_for_own_turns
  end

  def inherited_transcript_projection_messages
    return [] if parent_conversation.blank?
    return parent_conversation.send(:base_transcript_projection_messages) if thread?

    parent_conversation.historical_anchor_prefix_messages(historical_anchor_message)
  end

  def selected_messages_for_own_turns
    turns.includes(:selected_input_message, :selected_output_message).order(:sequence).flat_map do |turn|
      [turn.selected_input_message, turn.selected_output_message].compact
    end
  end

  def hidden_in_projection?(message, overlay_lookup)
    projection_conversation_chain_ids_for(message)&.any? do |conversation_id|
      overlay_lookup.dig(message.id, conversation_id)&.hidden?
    end
  end

  def excluded_from_context_in_projection?(message, overlay_lookup)
    projection_conversation_chain_ids_for(message)&.any? do |conversation_id|
      overlay_lookup.dig(message.id, conversation_id)&.excluded_from_context?
    end
  end

  def visibility_overlay_lookup_for(messages)
    return {} if messages.empty?

    ConversationMessageVisibility.where(
      conversation_id: projection_lineage_conversation_ids,
      message_id: messages.map(&:id)
    ).each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |overlay, lookup|
      lookup[overlay.message_id][overlay.conversation_id] = overlay
    end
  end

  def projection_lineage_conversation_ids
    ids = []
    current = self

    while current.present?
      ids << current.id
      current = current.parent_conversation
    end

    ids
  end

  def projection_conversation_chain_ids_for(message)
    chain_ids = []
    current = self

    while current.present?
      chain_ids << current.id
      return chain_ids if current.id == message.conversation_id

      current = current.parent_conversation
    end

    nil
  end

  def projection_prefix_messages(message)
    messages = base_transcript_projection_messages
    anchor_index = messages.index { |candidate| candidate.id == message.id }
    raise ActiveRecord::RecordNotFound, "historical anchor is missing from the parent conversation history" unless anchor_index.present?

    prefix_messages_for_anchor(messages, message, anchor_index:)
  end

  def local_historical_anchor_prefix_messages(message)
    raise ActiveRecord::RecordNotFound, "historical anchor is missing from the parent conversation history" unless message.conversation_id == id

    prefix_messages = inherited_transcript_projection_messages
    turns.where("sequence < ?", message.turn.sequence)
      .includes(:selected_input_message, :selected_output_message)
      .order(:sequence)
      .each do |turn|
        prefix_messages.concat([turn.selected_input_message, turn.selected_output_message].compact)
      end

    if message.input?
      prefix_messages << message
      return prefix_messages
    end

    source_input_message = message.source_input_message
    unless source_input_message.present? && source_input_message.turn_id == message.turn_id
      raise ActiveRecord::RecordNotFound, "historical anchor is missing source input provenance"
    end

    prefix_messages + [source_input_message, message]
  end

  def prefix_messages_for_anchor(messages, message, anchor_index:)
    return messages.first(anchor_index) + [message] if message.input?

    source_input_message = message.source_input_message
    source_input_index = messages.index { |candidate| candidate.id == source_input_message&.id }
    if source_input_message.present? &&
        source_input_message.turn_id == message.turn_id &&
        source_input_index.present?
      return messages.first(source_input_index) + [source_input_message, message]
    end

    raise ActiveRecord::RecordNotFound, "historical anchor is missing source input provenance"
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def execution_environment_installation_match
    return if execution_environment.blank?
    return if execution_environment.installation_id == installation_id

    errors.add(:execution_environment, "must belong to the same installation")
  end

  def agent_deployment_installation_match
    return if agent_deployment.blank?
    return if agent_deployment.installation_id == installation_id

    errors.add(:agent_deployment, "must belong to the same installation")
  end

  def agent_deployment_environment_match
    return if agent_deployment.blank? || execution_environment.blank?
    return if agent_deployment.execution_environment_id == execution_environment_id

    errors.add(:agent_deployment, "must belong to the bound execution environment")
  end

  def parent_lineage_rules
    return if kind.blank?

    if root?
      errors.add(:parent_conversation, "must be blank for root conversations") if parent_conversation.present?
      errors.add(:historical_anchor_message_id, "must be blank for root conversations") if historical_anchor_message_id.present?
      return
    end

    errors.add(:parent_conversation, "must exist") if parent_conversation.blank?
    errors.add(:historical_anchor_message_id, "must exist") if (branch? || checkpoint?) && historical_anchor_message_id.blank?
  end

  def historical_anchor_membership
    return if parent_conversation.blank?
    return if historical_anchor_message_id.blank?

    Conversations::ValidateHistoricalAnchor.call(
      parent: parent_conversation,
      kind: kind,
      historical_anchor_message_id: historical_anchor_message_id,
      record: self
    )
  rescue ActiveRecord::RecordInvalid
    nil
  end

  def automation_rules
    return unless automation?

    errors.add(:kind, "must be root for automation conversations") unless root?
  end

  def parent_workspace_match
    return if parent_conversation.blank?
    return if parent_conversation.workspace_id == workspace_id

    errors.add(:workspace, "must match the parent conversation workspace")
  end

  def parent_execution_environment_match
    return if parent_conversation.blank?
    return if parent_conversation.execution_environment_id == execution_environment_id

    errors.add(:execution_environment, "must match the parent conversation execution environment")
  end

  def override_payload_must_be_hash
    errors.add(:override_payload, "must be a hash") unless override_payload.is_a?(Hash)
  end

  def override_reconciliation_report_must_be_hash
    return if override_reconciliation_report.is_a?(Hash)

    errors.add(:override_reconciliation_report, "must be a hash")
  end

  def interactive_selector_rules
    return if interactive_selector_mode.blank?

    if auto?
      errors.add(:interactive_selector_provider_handle, "must be blank for auto selector mode") if interactive_selector_provider_handle.present?
      errors.add(:interactive_selector_model_ref, "must be blank for auto selector mode") if interactive_selector_model_ref.present?
      return
    end

    if interactive_selector_provider_handle.blank?
      errors.add(:interactive_selector_provider_handle, "must exist for explicit candidate selector mode")
    end
    if interactive_selector_model_ref.blank?
      errors.add(:interactive_selector_model_ref, "must exist for explicit candidate selector mode")
    end
    return if errors.any?

    ProviderCatalog::Load.call.model(
      interactive_selector_provider_handle,
      interactive_selector_model_ref
    )
  rescue KeyError
    errors.add(:interactive_selector_model_ref, "must exist in the provider catalog")
  end

  def deleted_at_consistency
    if retained?
      errors.add(:deleted_at, "must be blank while conversation is retained") if deleted_at.present?
      return
    end

    errors.add(:deleted_at, "must exist once deletion is requested") if deleted_at.blank?
  end
end
