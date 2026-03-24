require "digest"

class UsageRollup < ApplicationRecord
  DIMENSION_KEYS = %i[
    user_id
    workspace_id
    conversation_id
    turn_id
    workflow_node_key
    agent_installation_id
    agent_deployment_id
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
  belongs_to :agent_installation, optional: true
  belongs_to :agent_deployment, optional: true

  validates :provider_handle, :model_ref, :bucket_key, :dimension_digest, presence: true
  validates :dimension_digest, uniqueness: { scope: [:installation_id, :bucket_kind, :bucket_key] }
  validates :event_count, :success_count, :failure_count, :input_tokens_total,
    :output_tokens_total, :media_units_total, :total_latency_ms,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :estimated_cost_total,
    numericality: { greater_than_or_equal_to: 0 }
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_installation_match
  validate :agent_deployment_installation_match

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

  def agent_installation_installation_match
    return if agent_installation.blank?
    return if agent_installation.installation_id == installation_id

    errors.add(:agent_installation, "must belong to the same installation")
  end

  def agent_deployment_installation_match
    return if agent_deployment.blank?
    return if agent_deployment.installation_id == installation_id

    errors.add(:agent_deployment, "must belong to the same installation")
  end
end
