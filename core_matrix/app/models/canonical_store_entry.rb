class CanonicalStoreEntry < ApplicationRecord
  ENTRY_KINDS = %w[set tombstone].freeze

  belongs_to :canonical_store_snapshot
  belongs_to :canonical_store_value, optional: true

  validates :key, presence: true, uniqueness: { scope: :canonical_store_snapshot_id }
  validates :entry_kind, presence: true, inclusion: { in: ENTRY_KINDS }

  validate :key_bytesize_limit
  validate :entry_value_rules

  private

  def key_bytesize_limit
    return if key.blank?
    return if key.bytesize.between?(1, 128)

    errors.add(:key, "must be between 1 and 128 bytes")
  end

  def entry_value_rules
    if entry_kind == "set"
      errors.add(:canonical_store_value, "must exist for set entries") if canonical_store_value.blank?
      errors.add(:value_type, "must exist for set entries") if value_type.blank?
      errors.add(:value_bytesize, "must exist for set entries") if value_bytesize.blank?
      return
    end

    return unless entry_kind == "tombstone"

    errors.add(:canonical_store_value, "must be blank for tombstone entries") if canonical_store_value.present?
    errors.add(:value_type, "must be blank for tombstone entries") if value_type.present?
    errors.add(:value_bytesize, "must be blank for tombstone entries") if value_bytesize.present?
  end
end
