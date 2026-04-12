class WorkspacePolicy < ApplicationRecord
  belongs_to :installation
  belongs_to :workspace

  validates :workspace, uniqueness: true
  validate :workspace_installation_match
  validate :disabled_capabilities_must_be_array

  private

  def workspace_installation_match
    return if workspace.blank?
    return if workspace.installation_id == installation_id

    errors.add(:workspace, "must belong to the same installation")
  end

  def disabled_capabilities_must_be_array
    errors.add(:disabled_capabilities, "must be an array") unless disabled_capabilities.is_a?(Array)
  end
end
