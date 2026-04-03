require "digest"

class UsageRollup < ApplicationRecord
  DIMENSION_KEYS = %i[
    user_id
    workspace_id
    conversation_id
    turn_id
    workflow_node_key
    agent_program_id
    agent_program_version_id
    provider_handle
    model_ref
    operation_kind
  ].freeze

  enum :bucket_kind,
    {
      hour: "hour",
      day: "day",
      rolling_window: "rolling_window",
    },
    validate: true

  belongs_to :installation
  belongs_to :user, optional: true
  belongs_to :workspace, optional: true
  belongs_to :agent_program, optional: true
  belongs_to :agent_program_version, optional: true

  validates :provider_handle, :model_ref, :bucket_key, :dimension_digest, presence: true
  validates :dimension_digest, uniqueness: { scope: [:installation_id, :bucket_kind, :bucket_key] }
  validates :event_count, :success_count, :failure_count, :input_tokens_total,
    :output_tokens_total, :media_units_total, :total_latency_ms,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :estimated_cost_total,
    numericality: { greater_than_or_equal_to: 0 }
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_program_installation_match
  validate :agent_program_version_installation_match

  def self.dimension_digest_for(attributes)
    values = DIMENSION_KEYS.to_h do |key|
      [key.to_s, attributes[key]]
    end

    Digest::SHA256.hexdigest(values.to_json)
  end

  private

  def user_installation_match
    return if user.blank?
    return if user.installation_id == installation_id

    errors.add(:user, "must belong to the same installation")
  end

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def agent_program_installation_match
    return if agent_program.blank?
    return if agent_program.installation_id == installation_id

    errors.add(:agent_program, "must belong to the same installation")
  end

  def agent_program_version_installation_match
    return if agent_program_version.blank?
    return if agent_program_version.installation_id == installation_id

    errors.add(:agent_program_version, "must belong to the same installation")
  end
end
