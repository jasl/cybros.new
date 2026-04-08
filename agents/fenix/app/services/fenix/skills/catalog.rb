module Fenix
  module Skills
    class Catalog
      SkillNotFound = Class.new(StandardError)
      InvalidSkillPackage = PackageValidator::InvalidSkillPackage

      MARKDOWN_SKILL_REFERENCE = /\[\$([A-Za-z0-9._-]+)\]\([^)]+\)/.freeze
      INLINE_SKILL_REFERENCE = /(?<![\w\/])\$([A-Za-z0-9._-]+)/.freeze

      def self.requested_skill_names(messages:)
        Array(messages).map { |message| message.deep_stringify_keys["content"].to_s }.flat_map do |content|
          content.scan(MARKDOWN_SKILL_REFERENCE).flatten +
            content.scan(INLINE_SKILL_REFERENCE).flatten
        end.uniq
      end

      Entry = Struct.new(:name, :description, :source_kind, :active, :root, keyword_init: true) do
        def payload
          {
            "name" => name,
            "description" => description,
            "source_kind" => source_kind,
            "active" => active,
            "root_path" => root.to_s,
          }
        end
      end

      def initialize(system_root: default_system_root, live_root:, curated_root: default_curated_root, validator: PackageValidator)
        @system_root = Pathname(system_root).expand_path
        @live_root = Pathname(live_root).expand_path
        @curated_root = Pathname(curated_root).expand_path
        @validator = validator

        [@system_root, @live_root, @curated_root].each { |path| FileUtils.mkdir_p(path) }
      end

      def catalog_list
        (active_entries + curated_entries)
          .sort_by { |entry| [entry.fetch("active") ? 0 : 1, entry.fetch("name")] }
      end

      def active_for_messages(messages:)
        self.class.requested_skill_names(messages: messages).filter_map do |skill_name|
          load(skill_name: skill_name)
        rescue SkillNotFound, InvalidSkillPackage
          nil
        end
      end

      def load(skill_name:)
        entry = system_entries.find { |candidate| candidate.name == skill_name.to_s } ||
          live_entries.find { |candidate| candidate.name == skill_name.to_s } ||
          raise(SkillNotFound, "#{skill_name} is not active")

        entry.payload.merge(
          "skill_md" => read_skill_md(entry.root)
        )
      end

      private

      def active_entries
        (system_entries + live_entries).map(&:payload)
      end

      def curated_entries
        entries_for_root(root: @curated_root, source_kind: "curated", active: false).map(&:payload)
      end

      def system_entries
        @system_entries ||= entries_for_root(root: @system_root, source_kind: "system", active: true)
      end

      def live_entries
        @live_entries ||= entries_for_root(root: @live_root, source_kind: "live", active: true)
      end

      def entries_for_root(root:, source_kind:, active:)
        return [] unless root.directory?

        root.children.select(&:directory?).reject { |entry| entry.basename.to_s.start_with?(".") }.map do |skill_root|
          metadata = metadata_for(skill_root)
          Entry.new(
            name: metadata.fetch("name"),
            description: metadata.fetch("description"),
            source_kind: source_kind,
            active: active,
            root: skill_root
          )
        end
      end

      def metadata_for(skill_root)
        @validator.call(skill_root: skill_root)
      end

      def read_skill_md(skill_root)
        skill_md_path = skill_root.join("SKILL.md")
        raise InvalidSkillPackage, "#{skill_root} is missing SKILL.md" unless skill_md_path.file?

        skill_md_path.read
      end

      def default_system_root
        Rails.root.join("skills", ".system")
      end

      def default_curated_root
        Rails.root.join("skills", ".curated")
      end
    end
  end
end
