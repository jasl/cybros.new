module Fenix
  module Skills
    class Install
      def self.call(source_path:, repository: Repository.default)
        repository.install(source_path: source_path)
      end
    end
  end
end
