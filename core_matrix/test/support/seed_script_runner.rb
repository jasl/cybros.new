module SeedScriptRunner
  def run_seed_script!(installation:, bundled_agent_configuration:, env: {}, catalog: build_test_provider_catalog)
    assert_seed_installation_scope!(installation)

    stdout, stderr = capture_io do
      with_seed_runtime_overrides(
        bundled_agent_configuration: bundled_agent_configuration,
        env: env,
        catalog: catalog
      ) do
        load Rails.root.join("db/seeds.rb")
      end
    end

    { stdout: stdout, stderr: stderr }
  end

  private

  def with_seed_runtime_overrides(bundled_agent_configuration:, env:, catalog:)
    original_configuration = Rails.configuration.x.bundled_agent
    Rails.configuration.x.bundled_agent = bundled_agent_configuration

    with_stubbed_provider_catalog(catalog) do
      with_modified_env(env) { yield }
    end
  ensure
    Rails.configuration.x.bundled_agent = original_configuration
  end

  def assert_seed_installation_scope!(installation)
    installations = Installation.order(:id).to_a

    unless installations.one? && installations.first == installation
      raise ArgumentError, "expected exactly one installation matching the requested seed target before loading db seeds"
    end
  end
end

class ActiveSupport::TestCase
  include SeedScriptRunner
end
