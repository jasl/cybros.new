require "fileutils"
require "json"
require "securerandom"
require "time"

module CybrosNexus
  module Skills
    class Repository
      SkillNotFound = Class.new(StandardError)
      InvalidSkillPackage = PackageValidator::InvalidSkillPackage
      MissingScopeError = Class.new(StandardError)
      ReservedSkillNameError = Class.new(StandardError)
      InvalidFileReference = Class.new(StandardError)

      PROVENANCE_FILENAME = ".nexus-skill-provenance.json".freeze
      SOURCE_PRECEDENCE = {
        "system" => 0,
        "live" => 1,
        "curated" => 2,
      }.freeze

      Entry = Struct.new(:name, :description, :source_kind, :active, :root, :provenance, keyword_init: true) do
        def payload
          {
            "name" => name,
            "description" => description,
            "source_kind" => source_kind,
            "active" => active,
            "root_path" => root,
            "provenance" => provenance,
          }.reject { |_key, value| value.nil? }
        end
      end

      def self.from_runtime_context!(runtime_context:, skills_root: default_skills_root, validator: PackageValidator)
        context = stringify_hash(runtime_context)
        agent_id = context.fetch("agent_id", "").to_s
        user_id = context.fetch("user_id", "").to_s

        if agent_id.empty? || user_id.empty?
          raise MissingScopeError, "runtime_context must include non-blank agent_id and user_id"
        end

        new(
          agent_id: agent_id,
          user_id: user_id,
          skills_root: skills_root,
          validator: validator
        )
      end

      def self.default_skills_root
        File.join(ENV["NEXUS_HOME_ROOT"] || File.join(Dir.home, ".nexus"), "skills")
      end

      def self.stringify_hash(value)
        value.to_h.each_with_object({}) do |(key, entry), result|
          result[key.to_s] = entry
        end
      end

      attr_reader :skills_root, :system_root, :curated_root, :live_root, :staging_root, :backup_root

      def initialize(agent_id:, user_id:, skills_root:, validator: PackageValidator)
        @agent_id = agent_id.to_s
        @user_id = user_id.to_s
        @skills_root = File.expand_path(skills_root.to_s)
        @validator = validator

        validate_scope_component!("agent_id", @agent_id)
        validate_scope_component!("user_id", @user_id)

        @system_root = File.join(@skills_root, ".system")
        @curated_root = File.join(@skills_root, ".curated")
        scope_root = File.join(@skills_root, "scopes", @agent_id, @user_id)
        @live_root = File.join(scope_root, "live")
        @staging_root = File.join(scope_root, "staging")
        @backup_root = File.join(scope_root, "backups")

        [@system_root, @curated_root, @live_root, @staging_root, @backup_root].each do |path|
          FileUtils.mkdir_p(path)
        end
      end

      def catalog_list
        catalog_entries
          .sort_by { |entry| [SOURCE_PRECEDENCE.fetch(entry.source_kind), entry.name] }
          .map(&:payload)
      end

      def load(skill_name:)
        entry = active_entry(skill_name: skill_name.to_s)

        entry.payload.merge(
          "skill_md" => File.read(File.join(entry.root, "SKILL.md")),
          "files" => relative_files(entry.root)
        )
      end

      def read_file(skill_name:, relative_path:)
        entry = active_entry(skill_name: skill_name.to_s)
        target = resolve_file_path(root: entry.root, relative_path: relative_path)
        raise InvalidFileReference, "#{relative_path} is not a readable file for #{skill_name}" unless File.file?(target)

        {
          "name" => entry.name,
          "relative_path" => relative_path,
          "content" => File.read(target),
        }
      end

      def install(source_path:)
        source_root = File.expand_path(source_path.to_s)
        raise InvalidSkillPackage, "#{source_path} does not exist" unless File.directory?(source_root)

        stage_parent = File.join(@staging_root, SecureRandom.hex(8))
        FileUtils.mkdir_p(stage_parent)
        staged_root = File.join(stage_parent, File.basename(source_root))
        FileUtils.cp_r(source_root, staged_root)

        metadata = @validator.call(skill_root: staged_root)
        skill_name = metadata.fetch("name")
        raise ReservedSkillNameError, "#{skill_name} is reserved by a system skill" if system_skill_names.include?(skill_name)

        destination = File.join(@live_root, skill_name)
        backup_destination = nil

        if File.directory?(destination)
          backup_destination = File.join(@backup_root, "#{Time.now.utc.strftime("%Y%m%d%H%M%S")}-#{skill_name}")
          FileUtils.cp_r(destination, backup_destination)
          FileUtils.rm_rf(destination)
        end

        FileUtils.cp_r(staged_root, destination)
        provenance_path = File.join(destination, PROVENANCE_FILENAME)
        File.write(
          provenance_path,
          JSON.pretty_generate(
            {
              "source_path" => source_root,
              "installed_at" => Time.now.utc.iso8601,
            }
          )
        )

        {
          "name" => skill_name,
          "activation_state" => "next_top_level_turn",
          "live_root" => destination,
          "backup_root" => backup_destination,
          "provenance_path" => provenance_path,
        }.reject { |_key, value| value.nil? }
      ensure
        FileUtils.rm_rf(stage_parent) if stage_parent && File.exist?(stage_parent)
      end

      private

      def catalog_entries
        system_entries + live_entries + curated_entries
      end

      def system_entries
        @system_entries ||= entries_for_root(root: @system_root, source_kind: "system", active: true)
      end

      def live_entries
        entries_for_root(root: @live_root, source_kind: "live", active: true)
      end

      def curated_entries
        @curated_entries ||= entries_for_root(root: @curated_root, source_kind: "curated", active: false)
      end

      def entries_for_root(root:, source_kind:, active:)
        return [] unless File.directory?(root)

        Dir.children(root).sort.filter_map do |entry|
          next if entry.start_with?(".")

          skill_root = File.join(root, entry)
          next unless File.directory?(skill_root)

          metadata = @validator.call(skill_root: skill_root)
          Entry.new(
            name: metadata.fetch("name"),
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

      def relative_files(root)
        Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).filter_map do |path|
          next if File.directory?(path)

          relative_path = path.delete_prefix("#{root}/")
          next if relative_path == "SKILL.md"
          next if relative_path == PROVENANCE_FILENAME

          relative_path
        end.sort
      end

      def resolve_file_path(root:, relative_path:)
        path = relative_path.to_s
        raise InvalidFileReference, "relative_path is required" if path.empty?

        root_path = File.expand_path(root)
        target_path = File.expand_path(path, root_path)
        unless target_path == root_path || target_path.start_with?("#{root_path}/")
          raise InvalidFileReference, "#{relative_path} escapes the skill root"
        end

        raise InvalidFileReference, "#{relative_path} is not a readable file" unless File.exist?(target_path)

        resolved_root_path = File.realpath(root_path)
        resolved_target_path = File.realpath(target_path)
        unless resolved_target_path == resolved_root_path || resolved_target_path.start_with?("#{resolved_root_path}/")
          raise InvalidFileReference, "#{relative_path} escapes the skill root"
        end

        target_path
      rescue Errno::ENOENT
        raise InvalidFileReference, "#{relative_path} is not a readable file"
      end

      def read_provenance(root)
        provenance_path = File.join(root, PROVENANCE_FILENAME)
        return unless File.file?(provenance_path)

        JSON.parse(File.read(provenance_path))
      rescue JSON::ParserError
        nil
      end

      def validate_scope_component!(name, value)
        raise ArgumentError, "#{name} is required" if value.empty?
        raise ArgumentError, "#{name} must not contain path separators" if value.include?(File::SEPARATOR)
        raise ArgumentError, "#{name} must not contain path separators" if File::ALT_SEPARATOR && value.include?(File::ALT_SEPARATOR)
        raise ArgumentError, "#{name} must not be '.' or '..'" if value == "." || value == ".."
      end
    end
  end
end
