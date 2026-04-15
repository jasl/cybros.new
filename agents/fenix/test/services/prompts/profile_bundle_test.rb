require "test_helper"

class Prompts::ProfileBundleTest < ActiveSupport::TestCase
  test "profile without user and worker prompts is invalid" do
    with_prompt_fixture_roots do |builtin_root:, shared_soul_path:|
      profile_dir = write_profile(
        builtin_root,
        group: "main",
        key: "empty",
        meta: default_meta(label: "Empty", description: "Invalid profile")
      )

      error = assert_raises(ArgumentError) do
        Prompts::ProfileBundle.from_directory(
          group: "main",
          key: "empty",
          directory: profile_dir,
          shared_soul_path: shared_soul_path
        )
      end

      assert_includes error.message, "must define USER.md or WORKER.md"
    end
  end

  test "profile-local soul falls back to shared prompts soul" do
    with_prompt_fixture_roots do |builtin_root:, shared_soul_path:|
      profile_dir = write_profile(
        builtin_root,
        group: "main",
        key: "friendly",
        meta: default_meta(label: "Friendly", description: "Friendly interactive profile"),
        files: {
          "USER.md" => "Friendly interactive overlay",
        }
      )

      bundle = Prompts::ProfileBundle.from_directory(
        group: "main",
        key: "friendly",
        directory: profile_dir,
        shared_soul_path: shared_soul_path
      )

      assert_equal "Shared soul fallback", bundle.soul_prompt.strip
      assert_equal "Friendly interactive overlay", bundle.prompt_for(mode: :interactive).strip
      assert_equal "Friendly interactive overlay", bundle.prompt_for(mode: :subagent).strip
    end
  end

  private

  def with_prompt_fixture_roots
    Dir.mktmpdir("fenix-profile-bundle-") do |tmpdir|
      root = Pathname.new(tmpdir)
      builtin_root = root.join("prompts")
      shared_soul_path = builtin_root.join("SOUL.md")
      FileUtils.mkdir_p(builtin_root)
      shared_soul_path.write("Shared soul fallback\n")

      yield(builtin_root:, shared_soul_path:)
    end
  end

  def write_profile(root, group:, key:, meta:, files: {})
    profile_dir = root.join(group, key)
    FileUtils.mkdir_p(profile_dir)
    profile_dir.join("meta.yml").write(meta.to_yaml)

    files.each do |filename, content|
      profile_dir.join(filename).write(content)
    end

    profile_dir
  end

  def default_meta(label:, description:)
    {
      "label" => label,
      "description" => description,
      "when_to_use" => ["Test fixture"],
      "avoid_when" => ["Never"],
      "example_tasks" => ["Example"],
      "model_hints" => {
        "preferred_roles" => ["coding"],
      },
      "skill_hints" => ["layered-rails"],
    }
  end
end
