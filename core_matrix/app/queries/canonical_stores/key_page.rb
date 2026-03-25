module CanonicalStores
  KeyPage = Struct.new(:items, :next_cursor, keyword_init: true)
end
