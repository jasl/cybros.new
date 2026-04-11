class UsageEvent < ApplicationRecord
  include DataLifecycle

  enum :prompt_cache_status,
    {
      available: "available",
      unknown: "unknown",
      unsupported: "unsupported",
    },
    validate: true
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
  belongs_to :agent, optional: true
  belongs_to :agent_snapshot, optional: true

  validates :provider_handle, presence: true
  validates :model_ref, presence: true
  validates :occurred_at, presence: true
  validates :input_tokens, :output_tokens, :media_units, :latency_ms, :cached_input_tokens,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
  validates :estimated_cost,
    numericality: { greater_than_or_equal_to: 0 },
    allow_nil: true
  validate :cached_input_tokens_match_prompt_cache_status
  validate :user_installation_match
  validate :workspace_installation_match
  validate :agent_installation_match
  validate :agent_snapshot_installation_match

  data_lifecycle_kind! :bounded_audit

  def total_tokens
    return nil if input_tokens.nil? && output_tokens.nil?

    input_tokens.to_i + output_tokens.to_i
  end

  private

  def cached_input_tokens_match_prompt_cache_status
    if available?
      if cached_input_tokens.nil?
        errors.add(:cached_input_tokens, "must be present when prompt cache status is available")
      end
      return
    end

    return if cached_input_tokens.nil?

    errors.add(:cached_input_tokens, "must be blank unless prompt cache status is available")
  end

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

  def agent_installation_match
    return if agent.blank?
    return if agent.installation_id == installation_id

    errors.add(:agent, "must belong to the same installation")
  end

  def agent_snapshot_installation_match
    return if agent_snapshot.blank?
    return if agent_snapshot.installation_id == installation_id

    errors.add(:agent_snapshot, "must belong to the same installation")
  end
end
