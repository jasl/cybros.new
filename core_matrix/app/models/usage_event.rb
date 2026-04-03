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
  belongs_to :agent_program, optional: true
  belongs_to :agent_program_version, optional: true

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
  validate :agent_program_installation_match
  validate :agent_program_version_installation_match

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
