ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "tmpdir"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    private

    def with_skill_fixture_roots(home_root: nil)
      Dir.mktmpdir("fenix-skill-fixtures-") do |tmpdir|
        effective_home_root = Pathname.new(home_root || tmpdir)
        system_root = effective_home_root.join("project-skills", ".system")
        curated_root = effective_home_root.join("project-skills", ".curated")

        yield(
          home_root: effective_home_root,
          system_root: system_root,
          curated_root: curated_root
        )
      end
    end

    def write_skill(root:, name:, description:, body: nil, dir_name: nil, extra_files: {}, frontmatter: {})
      skill_root = Pathname(root).join(dir_name || name)
      FileUtils.mkdir_p(skill_root)

      resolved_body = body || "# #{name}\n"
      metadata = {
        "name" => name,
        "description" => description,
      }.merge(frontmatter.stringify_keys)

      skill_root.join("SKILL.md").write(
        <<~MARKDOWN
          ---
          #{metadata.to_yaml.sub(/\A---\s*\n/, "").sub(/\.\.\.\s*\n\z/, "")}---

          #{resolved_body}
        MARKDOWN
      )

      extra_files.each do |relative_path, content|
        file_path = skill_root.join(relative_path)
        FileUtils.mkdir_p(file_path.dirname)
        file_path.write(content)
      end

      skill_root
    end
  end
end
