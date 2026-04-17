module CybrosNexus
  module Skills
    class Catalog
      MARKDOWN_SKILL_REFERENCE = /\[\$([A-Za-z0-9._-]+)\]\([^)]+\)/.freeze
      INLINE_SKILL_REFERENCE = /(?<![\w\/])\$([A-Za-z0-9._-]+)/.freeze

      def self.requested_skill_names(messages:)
        Array(messages).flat_map do |message|
          content = Repository.stringify_hash(message).fetch("content", "").to_s
          content.scan(MARKDOWN_SKILL_REFERENCE).flatten +
            content.scan(INLINE_SKILL_REFERENCE).flatten
        end.uniq
      end

      def initialize(repository:)
        @repository = repository
      end

      def catalog_list
        @repository.catalog_list
      end

      def active_for_messages(messages:)
        self.class.requested_skill_names(messages: messages).filter_map do |skill_name|
          @repository.load(skill_name: skill_name)
        rescue Repository::SkillNotFound, Repository::InvalidSkillPackage
          nil
        end
      end

      def load(skill_name:)
        @repository.load(skill_name: skill_name)
      end
    end
  end
end
