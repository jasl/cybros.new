require "test_helper"

class RuntimeManifestDefinitionPackageTest < ActiveSupport::TestCase
  test "definition package derives reflected surface and canonical defaults from the catalog" do
    with_prompt_fixture_roots do |builtin_root:, override_root:, shared_soul_path:|
      write_profile(
        builtin_root,
        group: "main",
        key: "default",
        meta: default_meta(label: "Default", description: "Hidden fallback profile").merge("hidden" => true),
        files: {
          "USER.md" => "Hidden default interactive overlay",
          "WORKER.md" => "Hidden default worker overlay",
        }
      )
      write_profile(
        builtin_root,
        group: "main",
        key: "friendly",
        meta: default_meta(label: "Friendly", description: "Friendly interactive profile"),
        files: {
          "USER.md" => "Builtin friendly interactive overlay",
        }
      )
      write_profile(
        builtin_root,
        group: "specialists",
        key: "critic",
        meta: default_meta(label: "Critic", description: "Critique specialist profile"),
        files: {
          "WORKER.md" => "Builtin critic worker overlay",
        }
      )

      catalog = Prompts::ProfileCatalogLoader.call(
        builtin_root: builtin_root,
        override_root: override_root,
        shared_soul_path: shared_soul_path
      )

      package = Runtime::Manifest::DefinitionPackage.new(
        catalog: catalog,
        prompt_roots: [builtin_root, override_root]
      ).call

      assert_equal "default", package.dig("default_canonical_config", "interactive", "default_profile_key")
      assert_equal(
        {
          "default" => { "role_slot" => "main" },
          "friendly" => { "role_slot" => "main" },
          "critic" => { "role_slot" => "main" },
        },
        package.dig("default_canonical_config", "profile_runtime_overrides")
      )
      assert_equal(
        {
          "friendly" => { "label" => "Friendly", "description" => "Friendly interactive profile" },
          "critic" => { "label" => "Critic", "description" => "Critique specialist profile" },
        },
        package.dig("reflected_surface", "profiles")
      )
      refute package.dig("reflected_surface", "profiles").key?("default")
    end
  end

  private

  def with_prompt_fixture_roots
    Dir.mktmpdir("fenix-definition-package-") do |tmpdir|
      root = Pathname.new(tmpdir)
      builtin_root = root.join("prompts")
      override_root = root.join("prompts.d")
      shared_soul_path = builtin_root.join("SOUL.md")

      FileUtils.mkdir_p(builtin_root)
      FileUtils.mkdir_p(override_root)
      shared_soul_path.write("Shared soul fallback\n")

      yield(builtin_root:, override_root:, shared_soul_path:)
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
