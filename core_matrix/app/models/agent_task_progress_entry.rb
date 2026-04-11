class AgentTaskProgressEntry < ApplicationRecord
  include HasPublicId
  include DataLifecycle

  INTERNAL_RUNTIME_TOKEN_PATTERN = %r{
    \bprovider_round_\d+_tool_\d+\b|
    \bruntime\.[a-z0-9_.]+\b|
    \bsubagent_barrier\b|
    \bworkflow_node_[a-z0-9_]+\b
  }ix

  data_lifecycle_kind! :owner_bound

  belongs_to :installation
  belongs_to :agent_task_run
  belongs_to :subagent_connection, optional: true

  validates :entry_kind, :summary, :occurred_at, presence: true
  validates :sequence, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :agent_task_run_id }
  validate :details_payload_must_be_hash
  validate :installation_alignment
  validate :summary_must_not_expose_internal_tokens

  private

  def details_payload_must_be_hash
    errors.add(:details_payload, "must be a hash") unless details_payload.is_a?(Hash)
  end

  def installation_alignment
    if agent_task_run.present? && agent_task_run.installation_id != installation_id
      errors.add(:agent_task_run, "must belong to the same installation")
    end

    if subagent_connection.present? && subagent_connection.installation_id != installation_id
      errors.add(:subagent_connection, "must belong to the same installation")
    end

    if subagent_connection.present? &&
        agent_task_run.present? &&
        subagent_connection.owner_conversation_id != agent_task_run.conversation_id
      errors.add(:subagent_connection, "must be owned by the task conversation")
    end
  end

  def summary_must_not_expose_internal_tokens
    return unless summary.present?
    return unless INTERNAL_RUNTIME_TOKEN_PATTERN.match?(summary)

    errors.add(:summary, "must not expose internal runtime tokens")
  end
end
