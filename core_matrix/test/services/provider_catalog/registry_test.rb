require "test_helper"

class ProviderCatalog::RegistryTest < ActiveSupport::TestCase
  self.uses_real_provider_catalog = true

  test "current loads a validated snapshot and exposes its revision" do
    with_catalog_files(test_provider_catalog_definition.deep_stringify_keys.to_yaml) do |path:, override_dir:|
      registry = build_registry(path:, override_dir:)

      snapshot = registry.current

      assert_instance_of ProviderCatalog::Snapshot, snapshot
      assert_equal snapshot.revision, registry.revision
      assert_equal "api_key", snapshot.provider("openai").fetch(:credential_kind)
      assert_equal ["dev/mock-model"], snapshot.role_candidates("mock")
    end
  end

  test "reload replaces the in-process snapshot when the catalog changes" do
    with_catalog_files(test_provider_catalog_definition.deep_stringify_keys.to_yaml) do |path:, override_dir:|
      registry = build_registry(path:, override_dir:)
      original_snapshot = registry.current

      updated_definition = test_provider_catalog_definition.deep_dup
      updated_definition[:providers][:openai][:display_name] = "OpenAI Reloaded"
      File.write(path, updated_definition.deep_stringify_keys.to_yaml)

      reloaded_snapshot = registry.reload!

      assert_equal "OpenAI Reloaded", reloaded_snapshot.provider("openai").fetch(:display_name)
      refute_equal original_snapshot.revision, reloaded_snapshot.revision
      assert_equal reloaded_snapshot.revision, registry.revision
    end
  end

  test "reload failure preserves the previous snapshot and revision" do
    with_catalog_files(test_provider_catalog_definition.deep_stringify_keys.to_yaml) do |path:, override_dir:|
      registry = build_registry(path:, override_dir:)
      original_snapshot = registry.current
      original_revision = registry.revision

      File.write(path, { version: 1, providers: {}, model_roles: { main: ["missing/provider"] } }.to_yaml)

      assert_raises(ProviderCatalog::Validate::InvalidCatalog) do
        registry.reload!
      end

      current_snapshot = registry.current
      assert_equal original_revision, registry.revision
      assert_equal original_snapshot.revision, current_snapshot.revision
      assert_equal "OpenAI", current_snapshot.provider("openai").fetch(:display_name)
    end
  end

  test "current becomes fresh after another registry publishes a newer shared revision" do
    with_catalog_files(test_provider_catalog_definition.deep_stringify_keys.to_yaml) do |path:, override_dir:|
      shared_cache = ActiveSupport::Cache::MemoryStore.new
      shared_cache_key = "test:provider_catalog:shared"
      registry_a = build_registry(path:, override_dir:, cache: shared_cache, cache_key: shared_cache_key)
      registry_b = build_registry(path:, override_dir:, cache: shared_cache, cache_key: shared_cache_key)

      original_revision = registry_b.current.revision

      updated_definition = test_provider_catalog_definition.deep_dup
      updated_definition[:providers][:openrouter][:display_name] = "OpenRouter Reloaded"
      File.write(path, updated_definition.deep_stringify_keys.to_yaml)

      published_snapshot = registry_a.reload!
      refreshed_snapshot = registry_b.current

      assert_equal published_snapshot.revision, refreshed_snapshot.revision
      refute_equal original_revision, refreshed_snapshot.revision
      assert_equal "OpenRouter Reloaded", refreshed_snapshot.provider("openrouter").fetch(:display_name)
    end
  end

  test "concurrent readers observe only complete snapshots while reload runs" do
    with_catalog_files(test_provider_catalog_definition.deep_stringify_keys.to_yaml) do |path:, override_dir:|
      registry = build_registry(path:, override_dir:)
      seen_display_names = Queue.new
      failures = Queue.new

      registry.current

      readers = Array.new(4) do
        Thread.new do
          40.times do
            snapshot = registry.current
            seen_display_names << snapshot.provider("openai").fetch(:display_name)
          rescue StandardError => error
            failures << error
          end
        end
      end

      writer = Thread.new do
        definition = test_provider_catalog_definition.deep_dup

        %w[OpenAI-A OpenAI-B OpenAI-A].each do |display_name|
          definition[:providers][:openai][:display_name] = display_name
          File.write(path, definition.deep_stringify_keys.to_yaml)
          registry.reload!
        end
      rescue StandardError => error
        failures << error
      end

      (readers + [writer]).each(&:join)

      assert failures.empty?, failures.size.times.map { failures.pop.message }.join(", ")

      observed = []
      observed << seen_display_names.pop until seen_display_names.empty?
      assert observed.all? { |name| ["OpenAI", "OpenAI-A", "OpenAI-B"].include?(name) }
    end
  end

  private

  def build_registry(path:, override_dir:, cache: ActiveSupport::Cache::MemoryStore.new, cache_key: "test:provider_catalog:#{SecureRandom.hex(4)}")
    ProviderCatalog::Registry.new(
      loader: ProviderCatalog::Load.new(path: path, override_dir: override_dir, env: "test"),
      cache: cache,
      cache_key: cache_key,
      revision_check_interval: 0.seconds
    )
  end

  def with_catalog_files(base_yaml)
    Dir.mktmpdir do |dir|
      config_dir = File.join(dir, "config")
      override_dir = File.join(dir, "config.d")
      FileUtils.mkdir_p(config_dir)
      FileUtils.mkdir_p(override_dir)

      path = File.join(config_dir, "llm_catalog.yml")
      File.write(path, base_yaml)

      yield path:, override_dir:
    end
  end
end
