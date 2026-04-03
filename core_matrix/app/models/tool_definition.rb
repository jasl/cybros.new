class ToolDefinition < ApplicationRecord
  include HasPublicId

  enum :governance_mode,
    {
      reserved: "reserved",
      whitelist_only: "whitelist_only",
      replaceable: "replaceable",
    },
    validate: true

  belongs_to :installation
  belongs_to :agent_program_version

  has_many :tool_implementations, dependent: :restrict_with_exception
  has_many :tool_bindings, dependent: :restrict_with_exception
  has_many :tool_invocations, dependent: :restrict_with_exception

  validates :tool_name, presence: true, format: { with: AgentProgramVersion::METHOD_ID_PATTERN }
  validates :tool_kind, presence: true
  validate :installation_matches_program_version
  validate :policy_payload_must_be_hash

  def default_implementation
    tool_implementations.find_by!(default_for_snapshot: true)
  end

  private

  def installation_matches_program_version
    return if agent_program_version.blank?
    return if agent_program_version.installation_id == installation_id

    errors.add(:installation, "must match the program version installation")
  end

  def policy_payload_must_be_hash
    errors.add(:policy_payload, "must be a hash") unless policy_payload.is_a?(Hash)
  end
end
