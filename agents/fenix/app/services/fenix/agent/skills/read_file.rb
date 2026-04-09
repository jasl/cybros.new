module Fenix
  module Agent
    module Skills
      class ReadFile
        def self.call(skill_name:, relative_path:, repository:)
          repository.read_file(skill_name: skill_name, relative_path: relative_path)
        end
      end
    end
  end
end
