class CanonicalStoreSnapshot < ApplicationRecord
  SNAPSHOT_KINDS = %w[root write compaction].freeze

  belongs_to :canonical_store
  belongs_to :base_snapshot,
    class_name: "CanonicalStoreSnapshot",
    optional: true

  has_many :canonical_store_entries, dependent: :restrict_with_exception
  has_many :canonical_store_references, dependent: :restrict_with_exception

  validates :snapshot_kind, presence: true, inclusion: { in: SNAPSHOT_KINDS }
  validates :depth, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  validate :shape_rules
  validate :base_snapshot_store_match

  private

  def shape_rules
    case snapshot_kind
    when "root", "compaction"
      errors.add(:base_snapshot, "must be blank for root and compaction snapshots") if base_snapshot.present?
      errors.add(:depth, "must equal 0 for root and compaction snapshots") unless depth == 0
    when "write"
      if base_snapshot.blank?
        errors.add(:base_snapshot, "must exist for write snapshots")
      elsif depth != base_snapshot.depth + 1
        errors.add(:depth, "must equal base snapshot depth plus one")
      end
    end
  end

  def base_snapshot_store_match
    return if base_snapshot.blank? || canonical_store.blank?
    return if base_snapshot.canonical_store_id == canonical_store_id

    errors.add(:base_snapshot, "must belong to the same canonical store")
  end
end
