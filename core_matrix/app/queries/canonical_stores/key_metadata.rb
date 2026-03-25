module CanonicalStores
  KeyMetadata = Struct.new(
    :key,
    :entry_kind,
    :value_type,
    :value_bytesize,
    :created_at,
    :updated_at,
    keyword_init: true
  )
end
