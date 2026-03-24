class Conversation < ApplicationRecord
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
  enum :interactive_selector_mode,
    {
      auto: "auto",
      explicit_candidate: "explicit_candidate",
    },
    validate: true

  belongs_to :installation
  belongs_to :workspace
  belongs_to :parent_conversation, class_name: "Conversation", optional: true

  has_many :messages, dependent: :restrict_with_exception
  has_many :conversation_imports, dependent: :restrict_with_exception
  has_many :turns, dependent: :restrict_with_exception
  has_many :conversation_message_visibilities, dependent: :restrict_with_exception
  has_many :conversation_summary_segments, dependent: :restrict_with_exception
  has_many :workflow_runs, dependent: :restrict_with_exception
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
  validate :parent_lineage_rules
  validate :parent_workspace_match
  validate :automation_rules
  validate :override_payload_must_be_hash
  validate :override_reconciliation_report_must_be_hash
  validate :interactive_selector_rules

  def transcript_projection_includes?(message)
    base_transcript_projection_messages.any? { |candidate| candidate.id == message.id }
  end

  def transcript_projection_messages
    base_transcript_projection_messages.reject { |message| hidden_in_projection?(message) }
  end

  def context_projection_messages
    transcript_projection_messages.reject { |message| excluded_from_context_in_projection?(message) }
  end

  def context_projection_attachments
    context_projection_messages.flat_map { |message| message.message_attachments.order(:id).to_a }
  end

  private

  def base_transcript_projection_messages
    inherited_transcript_projection_messages + selected_messages_for_own_turns
  end

  def inherited_transcript_projection_messages
    return [] if parent_conversation.blank?

    inherited_messages = parent_conversation.send(:base_transcript_projection_messages)
    return inherited_messages if thread?

    anchor_index = inherited_messages.index { |message| message.id == historical_anchor_message_id }
    anchor_index ? inherited_messages.first(anchor_index + 1) : []
  end

  def selected_messages_for_own_turns
    turns.includes(:selected_input_message, :selected_output_message).order(:sequence).flat_map do |turn|
      [turn.selected_input_message, turn.selected_output_message].compact
    end
  end

  def hidden_in_projection?(message)
    projection_conversation_chain_for(message)&.any? do |conversation|
      ConversationMessageVisibility.exists?(conversation: conversation, message: message, hidden: true)
    end
  end

  def excluded_from_context_in_projection?(message)
    projection_conversation_chain_for(message)&.any? do |conversation|
      ConversationMessageVisibility.exists?(conversation: conversation, message: message, excluded_from_context: true)
    end
  end

  def projection_conversation_chain_for(message)
    chain = []
    current = self

    while current.present?
      chain << current
      return chain if current.id == message.conversation_id

      current = current.parent_conversation
    end

    nil
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
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

  def automation_rules
    return unless automation?

    errors.add(:kind, "must be root for automation conversations") unless root?
  end

  def parent_workspace_match
    return if parent_conversation.blank?
    return if parent_conversation.workspace_id == workspace_id

    errors.add(:workspace, "must match the parent conversation workspace")
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
end
