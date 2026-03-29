module LineageStores
  VisibleValue = Struct.new(
    :key,
    :typed_value_payload,
    :value_type,
    :value_bytesize,
    :created_at,
    :updated_at,
    keyword_init: true
  )
end
