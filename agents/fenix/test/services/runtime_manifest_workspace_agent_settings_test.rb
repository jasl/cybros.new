require "test_helper"

class RuntimeManifestWorkspaceAgentSettingsTest < ActiveSupport::TestCase
  test "schema and defaults follow the visible prompt catalog dynamically" do
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
        group: "main",
        key: "strategist",
        meta: default_meta(label: "Strategist", description: "Added interactive profile"),
        files: {
          "USER.md" => "Builtin strategist interactive overlay",
        }
      )
      write_profile(
        builtin_root,
        group: "specialists",
        key: "critic",
        meta: default_meta(label: "Critic", description: "Added specialist profile"),
        files: {
          "WORKER.md" => "Builtin critic worker overlay",
        }
      )

      catalog = Prompts::ProfileCatalogLoader.call(
        builtin_root: builtin_root,
        override_root: override_root,
        shared_soul_path: shared_soul_path
      )

      contract = Runtime::Manifest::WorkspaceAgentSettings.call(
        catalog: catalog,
        default_canonical_config: {
          "subagents" => {
            "allow_nested" => true,
            "max_depth" => 4,
          },
        }
      )

      assert_equal %w[friendly strategist], contract.dig("schema", "properties", "agent", "properties", "interactive", "properties", "profile_key", "enum")
      refute_includes contract.dig("schema", "properties", "agent", "properties", "interactive", "properties", "profile_key", "enum"), "default"
      assert_equal ["critic"], contract.dig("schema", "properties", "agent", "properties", "subagents", "properties", "default_profile_key", "oneOf", 0, "enum")
      assert_equal "friendly", contract.dig("defaults", "agent", "interactive", "profile_key")
      assert_equal "critic", contract.dig("defaults", "agent", "subagents", "default_profile_key")
      assert_equal ["critic"], contract.dig("defaults", "agent", "subagents", "enabled_profile_keys")
      assert_equal 4, contract.dig("defaults", "core_matrix", "subagents", "max_depth")
      assert_equal true, contract.dig("defaults", "core_matrix", "subagents", "allow_nested")
    end
  end

  private

  def with_prompt_fixture_roots
    Dir.mktmpdir("fenix-workspace-agent-settings-") do |tmpdir|
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
