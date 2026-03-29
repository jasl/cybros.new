class LineageStoreReference < ApplicationRecord
  belongs_to :lineage_store_snapshot
  belongs_to :owner, polymorphic: true

  validates :owner_id, uniqueness: { scope: :owner_type }
end
