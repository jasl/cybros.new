class Conversation < ApplicationRecord
  include HasPublicId

  FEATURE_IDS = %w[
    human_interaction
    tool_invocation
    message_attachments
    conversation_branching
    conversation_archival
  ].freeze
  DURING_GENERATION_INPUT_POLICIES = %w[reject restart queue].freeze

  enum :kind,
    {
      root: "root",
      branch: "branch",
      fork: "fork",
      checkpoint: "checkpoint",
    },
    validate: true
  enum :purpose,
    {
      interactive: "interactive",
      automation: "automation",
    },
    validate: true
  enum :addressability,
    {
      owner_addressable: "owner_addressable",
      agent_addressable: "agent_addressable",
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
  has_many :owned_subagent_sessions,
    class_name: "SubagentSession",
    foreign_key: :owner_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :owner_conversation
  has_one :publication, dependent: :restrict_with_exception
  has_one :subagent_session,
    dependent: :restrict_with_exception,
    inverse_of: :conversation
  has_one :lineage_store_reference, as: :owner, dependent: :restrict_with_exception
  has_one :root_lineage_store,
    class_name: "LineageStore",
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
  validate :enabled_feature_ids_supported
  validate :during_generation_input_policy_supported

  after_initialize :apply_default_feature_policy, if: :new_record?
  before_validation :normalize_enabled_feature_ids

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

  def feature_enabled?(feature_id)
    enabled_feature_ids.include?(feature_id.to_s)
  end

  def feature_policy_snapshot
    {
      "enabled_feature_ids" => enabled_feature_ids.dup,
      "during_generation_input_policy" => during_generation_input_policy,
    }
  end

  private

  def apply_default_feature_policy
    return if purpose.blank?
    return if will_save_change_to_enabled_feature_ids?

    self.enabled_feature_ids = default_enabled_feature_ids
  end

  def normalize_enabled_feature_ids
    self.enabled_feature_ids = normalize_feature_ids(enabled_feature_ids)
  end

  def normalize_feature_ids(values)
    Array(values).map(&:to_s).select(&:present?).uniq
  end

  def default_enabled_feature_ids
    default_ids = FEATURE_IDS.dup
    default_ids -= ["human_interaction"] if automation?
    default_ids
  end

  def enabled_feature_ids_supported
    requested_ids = Array(enabled_feature_ids).map(&:to_s).uniq
    unsupported_ids = requested_ids - FEATURE_IDS
    return if unsupported_ids.empty?

    errors.add(:enabled_feature_ids, "must only contain supported feature ids")
  end

  def during_generation_input_policy_supported
    return if DURING_GENERATION_INPUT_POLICIES.include?(during_generation_input_policy)

    errors.add(:during_generation_input_policy, "must be reject, restart, or queue")
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
  end

  def deleted_at_consistency
    if retained?
      errors.add(:deleted_at, "must be blank while conversation is retained") if deleted_at.present?
      return
    end

    errors.add(:deleted_at, "must exist once deletion is requested") if deleted_at.blank?
  end
end
