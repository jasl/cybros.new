require "test_helper"

class Prompts::ProfileCatalogTest < ActiveSupport::TestCase
  test "discovers builtin main and specialists profile trees" do
    with_prompt_fixture_roots do |builtin_root:, override_root:, shared_soul_path:|
      write_profile(
        builtin_root,
        group: "main",
        key: "pragmatic",
        meta: default_meta(label: "Pragmatic", description: "Default interactive profile"),
        files: {
          "USER.md" => "Builtin pragmatic interactive overlay",
        }
      )
      write_profile(
        builtin_root,
        group: "specialists",
        key: "researcher",
        meta: default_meta(label: "Researcher", description: "Default specialist profile"),
        files: {
          "WORKER.md" => "Builtin researcher specialist overlay",
        }
      )

      catalog = Prompts::ProfileCatalogLoader.call(
        builtin_root: builtin_root,
        override_root: override_root,
        shared_soul_path: shared_soul_path
      )

      assert_equal %w[pragmatic], catalog.keys_for("main")
      assert_equal %w[researcher], catalog.keys_for("specialists")
      assert_equal "Builtin pragmatic interactive overlay", catalog.fetch(group: "main", key: "pragmatic").prompt_for(mode: :interactive).strip
      assert_equal "Builtin researcher specialist overlay", catalog.fetch(group: "specialists", key: "researcher").prompt_for(mode: :subagent).strip
    end
  end

  test "same-key override replaces the whole profile directory" do
    with_prompt_fixture_roots do |builtin_root:, override_root:, shared_soul_path:|
      write_profile(
        builtin_root,
        group: "main",
        key: "friendly",
        meta: default_meta(label: "Friendly", description: "Builtin interactive profile"),
        files: {
          "USER.md" => "Builtin friendly interactive overlay",
        }
      )
      write_profile(
        override_root,
        group: "main",
        key: "friendly",
        meta: default_meta(label: "Friendly Override", description: "Override interactive profile"),
        files: {
          "WORKER.md" => "Override friendly fallback overlay",
        }
      )

      catalog = Prompts::ProfileCatalogLoader.call(
        builtin_root: builtin_root,
        override_root: override_root,
        shared_soul_path: shared_soul_path
      )
      bundle = catalog.fetch(group: "main", key: "friendly")

      assert_equal "Override friendly fallback overlay", bundle.prompt_for(mode: :interactive).strip
      assert_equal "Override friendly fallback overlay", bundle.prompt_for(mode: :subagent).strip
      refute_includes bundle.prompt_for(mode: :interactive), "Builtin friendly interactive overlay"
    end
  end

  test "specialist resolution does not fall back to the main catalog" do
    with_prompt_fixture_roots do |builtin_root:, override_root:, shared_soul_path:|
      write_profile(
        builtin_root,
        group: "main",
        key: "friendly",
        meta: default_meta(label: "Friendly", description: "Builtin interactive profile"),
        files: {
          "USER.md" => "Builtin friendly interactive overlay",
        }
      )

      catalog = Prompts::ProfileCatalogLoader.call(
        builtin_root: builtin_root,
        override_root: override_root,
        shared_soul_path: shared_soul_path
      )

      assert_raises(KeyError) do
        catalog.resolve(profile_key: "friendly", is_subagent: true)
      end
    end
  end

  test "hidden default profile is excluded from visible keys and used as terminal fallback" do
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
        meta: default_meta(label: "Friendly", description: "Builtin interactive profile"),
        files: {
          "USER.md" => "Builtin friendly interactive overlay",
        }
      )

      catalog = Prompts::ProfileCatalogLoader.call(
        builtin_root: builtin_root,
        override_root: override_root,
        shared_soul_path: shared_soul_path
      )

      assert_equal %w[friendly], catalog.keys_for("main")
      assert_equal "Hidden default interactive overlay", catalog.resolve_with_fallback(profile_key: "missing", is_subagent: false).prompt_for(mode: :interactive).strip
      assert_equal "Hidden default worker overlay", catalog.resolve_with_fallback(profile_key: "missing", is_subagent: true).prompt_for(mode: :subagent).strip
    end
  end

  test "default loader auto reloads prompt directories without reset" do
    with_prompt_fixture_roots do |builtin_root:, override_root:, shared_soul_path:|
      write_profile(
        builtin_root,
        group: "main",
        key: "pragmatic",
        meta: default_meta(label: "Pragmatic", description: "Builtin interactive profile"),
        files: {
          "USER.md" => "Builtin pragmatic interactive overlay",
        }
      )

      original_builtin_root = Prompts::ProfileCatalogLoader.default_builtin_root
      original_override_root = Prompts::ProfileCatalogLoader.default_override_root
      original_shared_soul_path = Prompts::ProfileCatalogLoader.default_shared_soul_path
      original_auto_reload = Prompts::ProfileCatalogLoader.default_auto_reload?

      begin
        Prompts::ProfileCatalogLoader.default_builtin_root = builtin_root
        Prompts::ProfileCatalogLoader.default_override_root = override_root
        Prompts::ProfileCatalogLoader.default_shared_soul_path = shared_soul_path
        Prompts::ProfileCatalogLoader.default_auto_reload = true
        Prompts::ProfileCatalogLoader.reset_default!

        assert_equal %w[pragmatic], Prompts::ProfileCatalogLoader.default.keys_for("main")

        write_profile(
          builtin_root,
          group: "main",
          key: "friendly",
          meta: default_meta(label: "Friendly", description: "Added after first load"),
          files: {
            "USER.md" => "Builtin friendly interactive overlay",
          }
        )

        assert_equal %w[friendly pragmatic], Prompts::ProfileCatalogLoader.default.keys_for("main")
      ensure
        Prompts::ProfileCatalogLoader.default_builtin_root = original_builtin_root
        Prompts::ProfileCatalogLoader.default_override_root = original_override_root
        Prompts::ProfileCatalogLoader.default_shared_soul_path = original_shared_soul_path
        Prompts::ProfileCatalogLoader.default_auto_reload = original_auto_reload
        Prompts::ProfileCatalogLoader.reset_default!
      end
    end
  end

  test "default loader prefers prompts.d shared soul fallback when present" do
    with_prompt_fixture_roots do |builtin_root:, override_root:, shared_soul_path:|
      write_profile(
        builtin_root,
        group: "main",
        key: "friendly",
        meta: default_meta(label: "Friendly", description: "Builtin interactive profile"),
        files: {
          "USER.md" => "Builtin friendly interactive overlay",
        }
      )
      override_shared_soul_path = override_root.join("SOUL.md")
      override_shared_soul_path.write("Override shared soul fallback\n")

      original_builtin_root = Prompts::ProfileCatalogLoader.default_builtin_root
      original_override_root = Prompts::ProfileCatalogLoader.default_override_root
      original_shared_soul_path = Prompts::ProfileCatalogLoader.default_shared_soul_path
      original_auto_reload = Prompts::ProfileCatalogLoader.default_auto_reload?

      begin
        Prompts::ProfileCatalogLoader.default_builtin_root = builtin_root
        Prompts::ProfileCatalogLoader.default_override_root = override_root
        Prompts::ProfileCatalogLoader.default_shared_soul_path = nil
        Prompts::ProfileCatalogLoader.default_auto_reload = true
        Prompts::ProfileCatalogLoader.reset_default!

        bundle = Prompts::ProfileCatalogLoader.default.fetch(group: "main", key: "friendly")

        assert_equal override_shared_soul_path, Prompts::ProfileCatalogLoader.default_shared_soul_path
        assert_equal "Override shared soul fallback", bundle.soul_prompt.strip
      ensure
        Prompts::ProfileCatalogLoader.default_builtin_root = original_builtin_root
        Prompts::ProfileCatalogLoader.default_override_root = original_override_root
        Prompts::ProfileCatalogLoader.default_shared_soul_path = original_shared_soul_path
        Prompts::ProfileCatalogLoader.default_auto_reload = original_auto_reload
        Prompts::ProfileCatalogLoader.reset_default!
      end
    end
  end

  private

  def with_prompt_fixture_roots
    Dir.mktmpdir("fenix-profile-catalog-") do |tmpdir|
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
