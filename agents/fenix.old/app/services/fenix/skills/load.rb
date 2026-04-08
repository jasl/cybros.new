module Fenix
  module Skills
    class Load
      def self.call(skill_name:, repository: Repository.default)
        repository.load(skill_name: skill_name)
      end
    end
  end
end
