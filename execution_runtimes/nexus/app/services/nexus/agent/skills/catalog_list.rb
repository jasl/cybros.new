module Nexus
  module Agent
    module Skills
      class CatalogList
        def self.call(repository:)
          repository.catalog_list
        end
      end
    end
  end
end
