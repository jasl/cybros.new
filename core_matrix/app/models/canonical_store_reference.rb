class CanonicalStoreReference < ApplicationRecord
  belongs_to :canonical_store_snapshot
  belongs_to :owner, polymorphic: true

  validates :owner_id, uniqueness: { scope: :owner_type }
end
