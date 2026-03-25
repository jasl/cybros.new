class WorkflowNode < ApplicationRecord
  include HasPublicId

  enum :decision_source,
    {
      llm: "llm",
      agent_program: "agent_program",
      system: "system",
      user: "user",
    },
    validate: true

  belongs_to :installation
  belongs_to :workflow_run

  has_many :outgoing_edges,
    class_name: "WorkflowEdge",
    foreign_key: :from_node_id,
    dependent: :restrict_with_exception,
    inverse_of: :from_node
  has_many :incoming_edges,
    class_name: "WorkflowEdge",
    foreign_key: :to_node_id,
    dependent: :restrict_with_exception,
    inverse_of: :to_node
  has_many :workflow_artifacts, dependent: :restrict_with_exception
  has_many :workflow_node_events, dependent: :restrict_with_exception
  has_many :human_interaction_requests, dependent: :restrict_with_exception
  has_many :process_runs, dependent: :restrict_with_exception
  has_many :subagent_runs, dependent: :restrict_with_exception
  has_many :execution_leases, dependent: :restrict_with_exception

  validates :node_key, presence: true, uniqueness: { scope: :workflow_run_id }
  validates :node_type, presence: true
  validates :ordinal,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :workflow_run_id }
  validate :workflow_run_installation_match
  validate :metadata_must_be_hash

  private

  def workflow_run_installation_match
    return if workflow_run.blank?
    return if workflow_run.installation_id == installation_id

    errors.add(:workflow_run, "must belong to the same installation")
  end

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end
end
