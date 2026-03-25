class UsageEvent < ApplicationRecord
  enum :operation_kind,
    {
      text_generation: "text_generation",
      image_generation: "image_generation",
      video_generation: "video_generation",
      embeddings: "embeddings",
      speech: "speech",
      transcription: "transcription",
      media_analysis: "media_analysis",
    },
    validate: true

  belongs_to :installation
  belongs_to :user, optional: true
  belongs_to :workspace, optional: true
  belongs_to :agent_installation, optional: true
  belongs_to :agent_deployment, optional: true

  validates :provider_handle, presence: true
  validates :model_ref, presence: true
  validates :occurred_at, presence: true
  validates :input_tokens, :output_tokens, :media_units, :latency_ms,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :estimated_cost,
    numericality: { greater_than_or_equal_to: 0 },
    allow_nil: true
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_installation_match
  validate :agent_deployment_installation_match

  def total_tokens
    return nil if input_tokens.nil? && output_tokens.nil?

    input_tokens.to_i + output_tokens.to_i
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
