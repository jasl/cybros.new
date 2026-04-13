class Conversation < ApplicationRecord
  include HasPublicId
  include DataLifecycle
  include DetailBackedJsonFields

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
  enum :title_source,
    {
      none: "none",
      bootstrap: "bootstrap",
      generated: "generated",
      agent: "agent",
      user: "user",
    },
    validate: true,
    prefix: :title_source
  enum :summary_source,
    {
      none: "none",
      bootstrap: "bootstrap",
      generated: "generated",
      agent: "agent",
      user: "user",
    },
    validate: true,
    prefix: :summary_source
  enum :title_lock_state,
    {
      unlocked: "unlocked",
      user_locked: "user_locked",
    },
    validate: true,
    prefix: :title_lock_state
  enum :summary_lock_state,
    {
      unlocked: "unlocked",
      user_locked: "user_locked",
    },
    validate: true,
    prefix: :summary_lock_state
  enum :interactive_selector_mode,
    {
      auto: "auto",
      explicit_candidate: "explicit_candidate",
    },
    validate: true
  enum :execution_continuity_state,
    {
      not_started: "not_started",
      ready: "ready",
      handoff_pending: "handoff_pending",
      handoff_blocked: "handoff_blocked",
    },
    validate: true

  data_lifecycle_kind! :owner_bound

  belongs_to :installation
  belongs_to :user, optional: true
  belongs_to :workspace
  belongs_to :agent
  belongs_to :current_execution_epoch, class_name: "ConversationExecutionEpoch", optional: true
  belongs_to :current_execution_runtime, class_name: "ExecutionRuntime", optional: true
  belongs_to :latest_active_turn, class_name: "Turn", optional: true
  belongs_to :latest_turn, class_name: "Turn", optional: true
  belongs_to :latest_active_workflow_run, class_name: "WorkflowRun", optional: true
  belongs_to :latest_message, class_name: "Message", optional: true
  belongs_to :parent_conversation, class_name: "Conversation", optional: true
  belongs_to :historical_anchor_message, class_name: "Message", optional: true

  has_many :messages, dependent: :restrict_with_exception
  has_many :conversation_imports, dependent: :restrict_with_exception
  has_many :turns, dependent: :restrict_with_exception
  has_many :execution_epochs,
    class_name: "ConversationExecutionEpoch",
    dependent: :restrict_with_exception,
    inverse_of: :conversation
  has_many :conversation_message_visibilities, dependent: :restrict_with_exception
  has_many :conversation_summary_segments, dependent: :restrict_with_exception
  has_many :conversation_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :workflow_runs, dependent: :restrict_with_exception
  has_one :conversation_detail, dependent: :destroy, autosave: true, inverse_of: :conversation
  has_one :conversation_supervision_state,
    foreign_key: :target_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :target_conversation
  has_many :conversation_supervision_feed_entries,
    foreign_key: :target_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :target_conversation
  has_many :conversation_supervision_sessions,
    foreign_key: :target_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :target_conversation
  has_many :conversation_control_requests,
    foreign_key: :target_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :target_conversation
  has_many :conversation_capability_grants,
    foreign_key: :target_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :target_conversation
  has_many :conversation_close_operations, dependent: :restrict_with_exception
  has_many :owned_subagent_connections,
    class_name: "SubagentConnection",
    foreign_key: :owner_conversation_id,
    dependent: :restrict_with_exception,
    inverse_of: :owner_conversation
  has_one :publication, dependent: :restrict_with_exception
  has_one :subagent_connection,
    dependent: :restrict_with_exception,
    inverse_of: :conversation
  has_one :lineage_store_reference, as: :owner, dependent: :restrict_with_exception
  has_one :root_lineage_store,
    class_name: "LineageStore",
    foreign_key: :owner_conversation_id,
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

  detail_backed_json_fields :conversation_detail, :override_payload, :override_reconciliation_report

  def self.accessible_to_user(user)
    return none if user.blank?

    where(
      installation_id: user.installation_id,
      deletion_state: "retained"
    )
      .where(workspace_id: Workspace.accessible_to_user(user).select(:id))
      .where(agent_id: Agent.visible_to_user(user).select(:id))
  end

  validate :workspace_installation_match
  validate :user_installation_match
  validate :agent_installation_match
  validate :workspace_user_match
  validate :workspace_agent_match
  validate :parent_lineage_rules
  validate :parent_workspace_match
  validate :parent_agent_match
  validate :historical_anchor_membership
  validate :current_execution_epoch_installation_match
  validate :current_execution_epoch_conversation_match
  validate :current_execution_runtime_installation_match
  validate :current_execution_cache_matches_epoch
  validate :execution_continuity_state_matches_epoch_presence
  validate :automation_rules
  validate :override_payload_must_be_hash
  validate :override_reconciliation_report_must_be_hash
  validate :interactive_selector_rules
  validate :deleted_at_consistency
  validate :enabled_feature_ids_supported
  validate :during_generation_input_policy_supported

  after_initialize :apply_default_feature_policy, if: :new_record?
  before_validation :normalize_enabled_feature_ids
  before_validation :normalize_capability_authority
  before_validation :default_execution_continuity_state
  before_validation :default_current_execution_runtime

  def deleting?
    pending_delete? || deleted?
  end

  def title_locked?
    title_lock_state_user_locked?
  end

  def summary_locked?
    summary_lock_state_user_locked?
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

  def capability_authority_snapshot
    {
      "supervision_enabled" => supervision_enabled?,
      "detailed_progress_enabled" => detailed_progress_enabled?,
      "side_chat_enabled" => side_chat_enabled?,
      "control_enabled" => control_enabled?,
    }
  end

  def feed_anchor_turn
    return latest_active_turn if latest_active_turn&.active?

    latest_turn
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

  def normalize_capability_authority
    self.detailed_progress_enabled = false unless supervision_enabled?
    self.side_chat_enabled = false unless supervision_enabled?
    self.control_enabled = false unless side_chat_enabled?
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

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def workspace_user_match
    return if workspace.blank? || user.blank?
    return if workspace.user_id == user_id

    errors.add(:user, "must match the workspace owner")
  end

  def workspace_agent_match
    return if workspace.blank? || agent.blank?
    return if workspace.agent_id == agent_id

    errors.add(:agent, "must match the workspace agent")
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

  def parent_agent_match
    return if parent_conversation.blank?
    return if parent_conversation.agent_id == agent_id

    errors.add(:agent, "must match the parent conversation agent")
  end

  def override_payload_must_be_hash
    errors.add(:override_payload, "must be a hash") unless override_payload.is_a?(Hash)
  end

  def override_reconciliation_report_must_be_hash
    errors.add(:override_reconciliation_report, "must be a hash") unless override_reconciliation_report.is_a?(Hash)
  end

  def interactive_selector_rules
    return unless explicit_candidate?

    errors.add(:interactive_selector_provider_handle, "must be present when explicit candidate mode is selected") if interactive_selector_provider_handle.blank?
    errors.add(:interactive_selector_model_ref, "must be present when explicit candidate mode is selected") if interactive_selector_model_ref.blank?
  end

  def deleted_at_consistency
    if retained?
      errors.add(:deleted_at, "must be blank when deletion state is retained") if deleted_at.present?
      return
    end

    errors.add(:deleted_at, "must be present when deletion state is pending_delete or deleted") if deleted_at.blank?
  end

  def current_execution_epoch_installation_match
    return if current_execution_epoch.blank?
    return if current_execution_epoch.installation_id == installation_id

    errors.add(:current_execution_epoch, "must belong to the same installation")
  end

  def current_execution_epoch_conversation_match
    return if current_execution_epoch.blank?
    return if current_execution_epoch.conversation_id == id
    return if new_record? && current_execution_epoch.conversation.equal?(self)

    errors.add(:current_execution_epoch, "must belong to the same conversation")
  end

  def current_execution_runtime_installation_match
    return if current_execution_runtime.blank?
    return if current_execution_runtime.installation_id == installation_id

    errors.add(:current_execution_runtime, "must belong to the same installation")
  end

  def current_execution_cache_matches_epoch
    return if current_execution_epoch.blank? || current_execution_runtime.blank?
    return if current_execution_epoch.execution_runtime_id == current_execution_runtime_id

    errors.add(:current_execution_runtime, "must match the current execution epoch runtime")
  end

  def execution_continuity_state_matches_epoch_presence
    if current_execution_epoch.blank?
      return if not_started?

      errors.add(:execution_continuity_state, "must be not_started when no current execution epoch exists")
      return
    end

    return unless not_started?

    errors.add(:execution_continuity_state, "must not remain not_started after execution continuity is materialized")
  end

  def default_execution_continuity_state
    return unless execution_continuity_state.blank? ||
      (new_record? && current_execution_epoch.blank? && execution_continuity_state == "ready")

    self.execution_continuity_state = current_execution_epoch.present? ? "ready" : "not_started"
  end

  def default_current_execution_runtime
    return if current_execution_runtime.present?

    self.current_execution_runtime =
      parent_conversation&.current_execution_runtime ||
      workspace&.default_execution_runtime ||
      agent&.default_execution_runtime
  end
end
