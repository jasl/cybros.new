module Fenix
  module Runtime
    class SelectRoundSkills
      MARKDOWN_SKILL_REFERENCE = /\[\$([A-Za-z0-9._-]+)\]\([^)]+\)/.freeze
      INLINE_SKILL_REFERENCE = /(?<![\w\/])\$([A-Za-z0-9._-]+)/.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(messages:, repository: Fenix::Skills::Repository.default)
        @messages = Array(messages).map(&:deep_stringify_keys)
        @repository = repository
      end

      def call
        {
          "active_catalog" => active_catalog,
          "requested_skill_names" => requested_skill_names,
          "selected_skills" => selected_skills,
        }
      end

      private

      def active_catalog
        @active_catalog ||= Array(@repository.catalog_list).select { |entry| entry["active"] == true }
      end

      def active_skill_names
        @active_skill_names ||= active_catalog.map { |entry| entry.fetch("name") }
      end

      def requested_skill_names
        @requested_skill_names ||= begin
          extracted_names = @messages.flat_map do |message|
            content = message["content"].to_s
            content.scan(MARKDOWN_SKILL_REFERENCE).flatten +
              content.scan(INLINE_SKILL_REFERENCE).flatten
          end

          extracted_names.map(&:to_s).uniq.select { |name| active_skill_names.include?(name) }
        end
      end

      def selected_skills
        @selected_skills ||= requested_skill_names.filter_map do |skill_name|
          @repository.load(skill_name:)
        rescue Fenix::Skills::Repository::SkillNotFound, Fenix::Skills::Repository::InvalidSkillPackage
          nil
        end
      end
    end
  end
end
