class ExecutionContextSnapshot < ApplicationRecord
  include HasPublicId

  belongs_to :installation

  validates :fingerprint, presence: true, uniqueness: { scope: :installation_id }
  validates :projection_fingerprint, presence: true
  validate :message_refs_must_be_array
  validate :import_refs_must_be_array
  validate :attachment_refs_must_be_array

  def message_refs_list
    Array(message_refs).map { |entry| entry.deep_stringify_keys }
  end

  def import_refs_list
    Array(import_refs).map { |entry| entry.deep_stringify_keys }
  end

  def attachment_refs_list
    Array(attachment_refs).map { |entry| entry.deep_stringify_keys }
  end

  private

  def message_refs_must_be_array
    errors.add(:message_refs, "must be an array") unless message_refs.is_a?(Array)
  end

  def import_refs_must_be_array
    errors.add(:import_refs, "must be an array") unless import_refs.is_a?(Array)
  end

  def attachment_refs_must_be_array
    errors.add(:attachment_refs, "must be an array") unless attachment_refs.is_a?(Array)
  end
end
