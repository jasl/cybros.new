require "find"
require "yaml"

module Fenix
  module Agent
    module Skills
      class PackageValidator
        InvalidSkillPackage = Class.new(StandardError)

        NAME_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/.freeze
        MAX_NAME_LENGTH = 64
        MAX_DESCRIPTION_LENGTH = 1024

        def self.call(...)
          new(...).call
        end

        def initialize(skill_root:)
          @skill_root = Pathname(skill_root).expand_path
        end

        def call
          metadata = frontmatter
          validate_file_tree!
          name = metadata["name"].to_s
          description = metadata["description"].to_s

          validate_name!(name)
          validate_description!(description)

          {
            "name" => name,
            "description" => description,
          }
        end

        private

        def validate_name!(name)
          raise InvalidSkillPackage, "skill name is required" if name.blank?
          raise InvalidSkillPackage, "skill name exceeds #{MAX_NAME_LENGTH} characters" if name.length > MAX_NAME_LENGTH
          raise InvalidSkillPackage, "skill name must match the directory name" unless name == @skill_root.basename.to_s
          raise InvalidSkillPackage, "skill name must use only lowercase letters, numbers, and single hyphens" unless name.match?(NAME_PATTERN)
        end

        def validate_description!(description)
          raise InvalidSkillPackage, "skill description is required" if description.blank?
          raise InvalidSkillPackage, "skill description exceeds #{MAX_DESCRIPTION_LENGTH} characters" if description.length > MAX_DESCRIPTION_LENGTH
        end

        def frontmatter
          match = read_skill_md.match(/\A---\s*\n(.*?)\n---\s*(?:\n|\z)/m)
          raise InvalidSkillPackage, "#{@skill_root} is missing YAML frontmatter" unless match

          parsed = YAML.safe_load(match[1], permitted_classes: [], aliases: false)
          raise InvalidSkillPackage, "#{@skill_root} frontmatter must be a mapping" unless parsed.is_a?(Hash)

          parsed.stringify_keys
        rescue Psych::SyntaxError => error
          raise InvalidSkillPackage, error.message
        end

        def read_skill_md
          skill_md_path = @skill_root.join("SKILL.md")
          raise InvalidSkillPackage, "#{@skill_root} is missing SKILL.md" unless skill_md_path.file?

          skill_md_path.read
        end

        def validate_file_tree!
          raise InvalidSkillPackage, "#{@skill_root} must not be a symlink" if File.lstat(@skill_root).symlink?

          Find.find(@skill_root.to_s) do |path|
            next if path == @skill_root.to_s
            next unless File.lstat(path).symlink?

            relative_path = Pathname(path).relative_path_from(@skill_root).to_s
            raise InvalidSkillPackage, "#{relative_path} must not be a symlink"
          end
        end
      end
    end
  end
end
