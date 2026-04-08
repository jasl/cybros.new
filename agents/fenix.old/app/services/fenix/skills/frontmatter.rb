require "yaml"

module Fenix
  module Skills
    class Frontmatter
      def self.parse(skill_md)
        new(skill_md).parse
      end

      def initialize(skill_md)
        @skill_md = skill_md.to_s
      end

      def parse
        return default_payload unless @skill_md.start_with?("---\n")

        _opening, frontmatter, body = @skill_md.split(/^---\s*$\n?/, 3)
        payload = YAML.safe_load(frontmatter.to_s, permitted_classes: [], aliases: false)

        {
          "name" => payload.is_a?(Hash) ? payload["name"].to_s.presence : nil,
          "description" => payload.is_a?(Hash) ? payload["description"].to_s.presence : nil,
          "body" => body.to_s.lstrip,
        }
      rescue Psych::SyntaxError
        default_payload
      end

      private

      def default_payload
        {
          "name" => nil,
          "description" => nil,
          "body" => @skill_md,
        }
      end
    end
  end
end
