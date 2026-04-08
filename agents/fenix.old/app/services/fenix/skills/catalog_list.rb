module Fenix
  module Skills
    class CatalogList
      def self.call(repository: Repository.default)
        repository.catalog_list
      end
    end
  end
end
