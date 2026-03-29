require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "time"

module Fenix
  module Skills
    class Repository
      SkillNotFound = Class.new(StandardError)
      InvalidSkillPackage = Class.new(StandardError)
      ReservedSkillNameError = Class.new(StandardError)
      InvalidFileReference = Class.new(StandardError)

      Entry = Struct.new(:name, :description, :source_kind, :active, :root, :provenance, keyword_init: true) do
        def payload
          {
            "name" => name,
            "description" => description,
            "source_kind" => source_kind,
            "active" => active,
            "root_path" => root.to_s,
            "provenance" => provenance,
          }.compact
        end
      end

      SOURCE_PRECEDENCE = {
        "system" => 0,
        "live" => 1,
        "curated" => 2,
      }.freeze
      PROVENANCE_FILENAME = ".fenix-skill-provenance.json".freeze

      def self.default
        new
      end

      def initialize(system_root: default_system_root, curated_root: default_curated_root, live_root: default_live_root, staging_root: default_staging_root, backup_root: default_backup_root)
        @system_root = Pathname(system_root).expand_path
        @curated_root = Pathname(curated_root).expand_path
        @live_root = Pathname(live_root).expand_path
        @staging_root = Pathname(staging_root).expand_path
        @backup_root = Pathname(backup_root).expand_path

        [@system_root, @curated_root, @live_root, @staging_root, @backup_root].each { |path| FileUtils.mkdir_p(path) }
      end

      def catalog_list
        catalog_entries
          .sort_by { |entry| [SOURCE_PRECEDENCE.fetch(entry.source_kind), entry.name] }
          .map(&:payload)
      end

      def load(skill_name:)
        entry = active_entry(skill_name:)
        skill_md = read_skill_md(entry.root)

        entry.payload.merge(
          "skill_md" => skill_md,
          "files" => relative_files(entry.root)
        )
      end

      def read_file(skill_name:, relative_path:)
        entry = active_entry(skill_name:)
        target = resolved_file_path(entry.root, relative_path)

        raise InvalidFileReference, "#{relative_path} is not a readable file for #{skill_name}" unless target.file?

        {
          "name" => entry.name,
          "relative_path" => relative_path,
          "content" => File.read(target),
        }
      end

      def install(source_path:)
        source_root = Pathname(source_path).expand_path
        raise InvalidSkillPackage, "#{source_path} does not exist" unless source_root.directory?

        stage_parent = @staging_root.join(SecureRandom.hex(8))
        FileUtils.mkdir_p(stage_parent)
        staged_root = stage_parent.join(source_root.basename)
        FileUtils.cp_r(source_root, staged_root)

        metadata = skill_metadata(staged_root)
        skill_name = metadata.fetch("name").presence || staged_root.basename.to_s
        raise InvalidSkillPackage, "SKILL.md is required for installation" unless staged_root.join("SKILL.md").file?
        raise ReservedSkillNameError, "#{skill_name} is reserved by a system skill" if system_skill_names.include?(skill_name)

        destination = @live_root.join(skill_name)
        backup_destination = nil

        if destination.directory?
          backup_destination = @backup_root.join("#{Time.current.utc.strftime("%Y%m%d%H%M%S")}-#{skill_name}")
          FileUtils.cp_r(destination, backup_destination)
          FileUtils.rm_rf(destination)
        end

        FileUtils.cp_r(staged_root, destination)

        provenance_path = destination.join(PROVENANCE_FILENAME)
        File.write(
          provenance_path,
          JSON.pretty_generate(
            {
              "source_path" => source_root.to_s,
              "installed_at" => Time.current.utc.iso8601,
            }
          )
        )

        {
          "name" => skill_name,
          "activation_state" => "next_top_level_turn",
          "live_root" => destination.to_s,
          "backup_root" => backup_destination&.to_s,
          "provenance_path" => provenance_path.to_s,
        }.compact
      ensure
        FileUtils.rm_rf(stage_parent) if defined?(stage_parent) && stage_parent.present?
      end

      private

      def default_system_root
        Pathname(ENV["FENIX_SYSTEM_SKILLS_ROOT"].presence || Rails.root.join("skills", ".system"))
      end

      def default_curated_root
        Pathname(ENV["FENIX_CURATED_SKILLS_ROOT"].presence || Rails.root.join("skills", ".curated"))
      end

      def default_live_root
        Pathname(ENV["FENIX_LIVE_SKILLS_ROOT"].presence || Rails.root.join("skills"))
      end

      def default_staging_root
        Pathname(ENV["FENIX_STAGING_SKILLS_ROOT"].presence || Rails.root.join("tmp", "skills-staging"))
      end

      def default_backup_root
        Pathname(ENV["FENIX_BACKUP_SKILLS_ROOT"].presence || Rails.root.join("tmp", "skills-backups"))
      end

      def catalog_entries
        system_entries + live_entries + curated_entries
      end

      def system_entries
        entries_for_root(root: @system_root, source_kind: "system", active: true)
      end

      def live_entries
        entries_for_root(root: @live_root, source_kind: "live", active: true)
      end

      def curated_entries
        entries_for_root(root: @curated_root, source_kind: "curated", active: false)
      end

      def entries_for_root(root:, source_kind:, active:)
        return [] unless root.directory?

        root.children.select(&:directory?).reject { |skill_root| skill_root.basename.to_s.start_with?(".") }.map do |skill_root|
          metadata = skill_metadata(skill_root)
          Entry.new(
            name: metadata.fetch("name").presence || skill_root.basename.to_s,
            description: metadata.fetch("description"),
            source_kind: source_kind,
            active: active,
            root: skill_root,
            provenance: read_provenance(skill_root)
          )
        end
      end

      def active_entry(skill_name:)
        system_entries.find { |entry| entry.name == skill_name } ||
          live_entries.find { |entry| entry.name == skill_name } ||
          raise(SkillNotFound, "#{skill_name} is not active")
      end

      def system_skill_names
        system_entries.map(&:name)
      end

      def read_skill_md(root)
        skill_md_path = root.join("SKILL.md")
        raise InvalidSkillPackage, "#{root} is missing SKILL.md" unless skill_md_path.file?

        File.read(skill_md_path)
      end

      def skill_metadata(root)
        parsed = Frontmatter.parse(read_skill_md(root))

        {
          "name" => parsed.fetch("name"),
          "description" => parsed.fetch("description"),
        }
      rescue InvalidSkillPackage
        raise
      rescue StandardError => error
        raise InvalidSkillPackage, error.message
      end

      def relative_files(root)
        Dir.glob(root.join("**", "*"), File::FNM_DOTMATCH).filter_map do |path|
          pathname = Pathname(path)
          next if pathname.directory?

          relative = pathname.relative_path_from(root).to_s
          next if relative == "SKILL.md"
          next if relative == PROVENANCE_FILENAME

          relative
        end.sort
      end

      def resolved_file_path(root, relative_path)
        raise InvalidFileReference, "relative_path is required" if relative_path.to_s.blank?

        target = root.join(relative_path).expand_path
        root_path = root.expand_path.to_s
        target_path = target.to_s

        unless target_path == root_path || target_path.start_with?("#{root_path}/")
          raise InvalidFileReference, "#{relative_path} escapes the skill root"
        end

        target
      end

      def read_provenance(root)
        provenance_path = root.join(PROVENANCE_FILENAME)
        return unless provenance_path.file?

        JSON.parse(File.read(provenance_path))
      end
    end
  end
end
