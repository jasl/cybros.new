module Fenix
  module Agent
    module Skills
      class Install
        def self.call(source_path:, repository:)
          repository.install(source_path: source_path)
        end
      end
    end
  end
end
