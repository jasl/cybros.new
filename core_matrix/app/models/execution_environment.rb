class ExecutionEnvironment < ApplicationRecord
  enum :kind, { local: "local", container: "container", remote: "remote" }, validate: true
  enum :lifecycle_state, { active: "active", retired: "retired" }, validate: true

  belongs_to :installation

  has_many :agent_deployments, dependent: :restrict_with_exception

  validate :connection_metadata_must_be_hash

  private

  def connection_metadata_must_be_hash
    errors.add(:connection_metadata, "must be a Hash") unless connection_metadata.is_a?(Hash)
  end
end
