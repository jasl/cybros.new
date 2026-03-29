class ImplementationSource < ApplicationRecord
  include HasPublicId

  enum :source_kind,
    {
      core_matrix: "core_matrix",
      execution_environment: "execution_environment",
      agent: "agent",
      kernel: "kernel",
      mcp: "mcp",
    },
    validate: true

  belongs_to :installation

  has_many :tool_implementations, dependent: :restrict_with_exception

  validates :source_ref, presence: true
  validate :metadata_must_be_hash

  private

  def metadata_must_be_hash
    errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
  end
end
