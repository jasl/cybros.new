require "fileutils"
require "json"
require "pathname"
require "securerandom"

module Nexus
  module Agent
    module Skills
      class Repository
        SkillNotFound = Class.new(StandardError)
        InvalidSkillPackage = PackageValidator::InvalidSkillPackage
        MissingScopeError = Class.new(StandardError)
        ReservedSkillNameError = Class.new(StandardError)
        InvalidFileReference = Class.new(StandardError)

        def self.from_runtime_context!(runtime_context:, **kwargs)
          context = runtime_context.deep_stringify_keys
          agent_id = context["agent_id"].to_s
          user_id = context["user_id"].to_s

          if agent_id.blank? || user_id.blank?
            raise MissingScopeError, "runtime_context must include non-blank agent_id and user_id"
          end

          new(
            agent_id: agent_id,
            user_id: user_id,
            **kwargs
          )
        end

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

        PROVENANCE_FILENAME = ".nexus-skill-provenance.json".freeze
        SOURCE_PRECEDENCE = {
          "system" => 0,
          "live" => 1,
          "curated" => 2,
        }.freeze

        attr_reader :scope_roots, :system_root, :curated_root

        def initialize(agent_id:, user_id:, home_root: default_home_root, system_root: default_system_root, curated_root: default_curated_root, validator: PackageValidator)
          @scope_roots = ScopeRoots.new(
            agent_id: agent_id,
            user_id: user_id,
            home_root: home_root
          )
          @system_root = Pathname(system_root).expand_path
          @curated_root = Pathname(curated_root).expand_path
          @validator = validator

          [@system_root, @curated_root, live_root, staging_root, backup_root].each { |path| FileUtils.mkdir_p(path) }
        end

        def live_root
          scope_roots.live_root
        end

        def staging_root
          scope_roots.staging_root
        end

        def backup_root
          scope_roots.backup_root
        end

        def catalog_list
          catalog_entries
            .sort_by { |entry| [SOURCE_PRECEDENCE.fetch(entry.source_kind), entry.name] }
            .map(&:payload)
        end

        def load(skill_name:)
          entry = active_entry(skill_name: skill_name.to_s)

          entry.payload.merge(
            "skill_md" => read_skill_md(entry.root),
            "files" => relative_files(entry.root)
          )
        end

        def read_file(skill_name:, relative_path:)
          entry = active_entry(skill_name: skill_name.to_s)
          target = resolved_file_path(entry.root, relative_path)

          raise InvalidFileReference, "#{relative_path} is not a readable file for #{skill_name}" unless target.file?

          {
            "name" => entry.name,
            "relative_path" => relative_path,
            "content" => target.read,
          }
        end

        def install(source_path:)
          source_root = Pathname(source_path).expand_path
          raise InvalidSkillPackage, "#{source_path} does not exist" unless source_root.directory?

          stage_parent = staging_root.join(SecureRandom.hex(8))
          FileUtils.mkdir_p(stage_parent)
          staged_root = stage_parent.join(source_root.basename)
          FileUtils.cp_r(source_root, staged_root)

          metadata = skill_metadata(staged_root)
          skill_name = metadata.fetch("name")
          raise ReservedSkillNameError, "#{skill_name} is reserved by a system skill" if system_skill_names.include?(skill_name)

          destination = live_root.join(skill_name)
          backup_destination = nil

          if destination.directory?
            backup_destination = backup_root.join("#{Time.current.utc.strftime("%Y%m%d%H%M%S")}-#{skill_name}")
            FileUtils.cp_r(destination, backup_destination)
            FileUtils.rm_rf(destination)
          end

          FileUtils.cp_r(staged_root, destination)

          provenance_path = destination.join(PROVENANCE_FILENAME)
          provenance_path.write(
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

        def default_home_root
          Pathname.new(ENV["NEXUS_HOME_ROOT"].presence || Pathname.new(Dir.home).join(".nexus"))
        end

        def default_system_root
          Rails.root.join("skills", ".system")
        end

        def default_curated_root
          Rails.root.join("skills", ".curated")
        end

        def catalog_entries
          system_entries + live_entries + curated_entries
        end

        def system_entries
          @system_entries ||= entries_for_root(root: system_root, source_kind: "system", active: true)
        end

        def live_entries
          entries_for_root(root: live_root, source_kind: "live", active: true)
        end

        def curated_entries
          @curated_entries ||= entries_for_root(root: curated_root, source_kind: "curated", active: false)
        end

        def entries_for_root(root:, source_kind:, active:)
          return [] unless root.directory?

          root.children
            .select(&:directory?)
            .reject { |skill_root| skill_root.basename.to_s.start_with?(".") }
            .map do |skill_root|
              metadata = skill_metadata(skill_root)
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

        def skill_metadata(root)
          @validator.call(skill_root: root)
        end

        def read_skill_md(root)
          root.join("SKILL.md").read
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

          return target unless target.exist?

          resolved_target = target.realpath
          resolved_root = root.realpath
          resolved_target_path = resolved_target.to_s
          resolved_root_path = resolved_root.to_s

          unless resolved_target_path == resolved_root_path || resolved_target_path.start_with?("#{resolved_root_path}/")
            raise InvalidFileReference, "#{relative_path} escapes the skill root"
          end

          target
        rescue Errno::ENOENT
          raise InvalidFileReference, "#{relative_path} is not a readable file"
        end

        def read_provenance(root)
          provenance_path = root.join(PROVENANCE_FILENAME)
          return unless provenance_path.file?

          JSON.parse(provenance_path.read)
        rescue JSON::ParserError
          nil
        end
      end
    end
  end
end
