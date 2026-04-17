require "test_helper"

class InitCommandTest < CoreMatrixCLITestCase
  def test_init_bootstraps_and_persists_session_and_workspace_context
    api = FakeCoreMatrixAPI.new
    api.bootstrap_status_payload = { "bootstrap_state" => "unbootstrapped" }
    api.bootstrap_response = {
      "session_token" => "sess_123",
      "installation" => { "name" => "Primary Installation" },
      "user" => { "email" => "admin@example.com" },
      "workspace" => { "workspace_id" => "ws_123", "name" => "Primary Workspace" },
      "workspace_agent" => { "workspace_agent_id" => "wa_123" },
    }
    api.session_response = { "user" => { "email" => "admin@example.com" } }
    api.workspaces_response = {
      "workspaces" => [
        {
          "workspace_id" => "ws_123",
          "name" => "Primary Workspace",
          "is_default" => true,
          "workspace_agents" => [
            {
              "workspace_agent_id" => "wa_123",
              "lifecycle_state" => "active",
            },
          ],
        },
      ],
    }
    api.provider_status_responses["codex_subscription"] = {
      "llm_provider" => { "configured" => false, "usable" => false },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))

    output = run_cli(
      "init",
      input: "https://core.example.com\nPrimary Installation\nadmin@example.com\nPassword123!\nPassword123!\nPrimary Admin\n",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    assert_equal "sess_123", credential_repository.read.fetch("session_token")
    assert_equal "ws_123", config_repository.read.fetch("workspace_id")
    assert_equal "wa_123", config_repository.read.fetch("workspace_agent_id")
    assert_includes output, "Primary Installation"
  end

  def test_init_reuses_existing_session_when_bootstrapped
    api = FakeCoreMatrixAPI.new
    api.bootstrap_status_payload = {
      "bootstrap_state" => "bootstrapped",
      "installation" => { "name" => "Primary Installation" },
    }
    api.session_response = {
      "user" => { "email" => "admin@example.com" },
      "installation" => { "name" => "Primary Installation" },
    }
    api.workspaces_response = {
      "workspaces" => [
        {
          "workspace_id" => "ws_123",
          "name" => "Primary Workspace",
          "is_default" => true,
          "workspace_agents" => [
            {
              "workspace_agent_id" => "wa_123",
              "lifecycle_state" => "active",
            },
          ],
        },
      ],
    }
    api.provider_status_responses["codex_subscription"] = {
      "llm_provider" => { "configured" => true, "usable" => true },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    config_repository.merge("base_url" => "https://core.example.com")
    credential_repository.write("session_token" => "sess_123")

    output = run_cli(
      "init",
      input: "https://core.example.com\n",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    refute api.calls.any? { |call| call.first == :bootstrap }
    assert_includes api.calls, [:current_session]
    assert_includes output, "Primary Installation"
  end

  def test_init_reuses_stored_base_url_when_bootstrapped
    api = FakeCoreMatrixAPI.new
    api.bootstrap_status_payload = {
      "bootstrap_state" => "bootstrapped",
      "installation" => { "name" => "Primary Installation" },
    }
    api.session_response = {
      "user" => { "email" => "admin@example.com" },
      "installation" => { "name" => "Primary Installation" },
    }
    api.workspaces_response = {
      "workspaces" => [],
    }
    api.provider_status_responses["codex_subscription"] = {
      "llm_provider" => { "configured" => false, "usable" => false },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    config_repository.merge("base_url" => "https://core.example.com")
    credential_repository.write("session_token" => "sess_123")

    run_cli(
      "init",
      input: "",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    assert_equal "https://core.example.com", config_repository.read.fetch("base_url")
    assert_includes api.calls, [:bootstrap_status]
    assert_includes api.calls, [:current_session]
    refute api.calls.any? { |call| call.first == :bootstrap }
  end
end
