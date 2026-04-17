# CoreMatrix Operator CLI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Thor-based operator CLI that can bootstrap a fresh CoreMatrix deployment, log in automatically, reuse bundled bootstrap state when present, authorize Codex Subscription, and configure Telegram or Weixin for real integration testing.

**Architecture:** Extend CoreMatrix with a minimal operator-facing HTTP API for bootstrap, session management, workspace creation, and ingress connector updates, then add a new top-level `core_matrix_cli/` Ruby project that talks only to those APIs. Keep human auth on `Session`, keep machine/runtime pairing on `OnboardingSession`, and make `cmctl init` a state-driven resumable orchestrator rather than a one-shot script.

**Tech Stack:** Ruby, Thor, Net::HTTP, RQRCode, Minitest, Rails request tests, Active Record, existing CoreMatrix provider authorization and ingress binding flows.

---

**Execution notes:**

- Follow `@test-driven-development` for every behavior change.
- If a request/CLI contract test fails for an unexpected reason, stop and use
  `@systematic-debugging` before changing production code.
- Do not stage unrelated dirty worktree files. This repo already has in-flight
  changes outside this feature.

### Task 1: Add CoreMatrix bootstrap and session API contracts

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/bootstrap_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/sessions_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/bootstrap_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/sessions_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/actions/bootstrap/issue_first_admin.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/actions/sessions/create.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/authenticated_session_presenter.rb`

**Step 1: Write the failing bootstrap request tests**

Create tests that lock this contract:

```ruby
test "bootstrap status reports unbootstrapped before any installation exists" do
  get "/app_api/bootstrap/status"

  assert_response :success
  assert_equal "bootstrap_status", response.parsed_body.fetch("method_id")
  assert_equal "unbootstrapped", response.parsed_body.fetch("bootstrap_state")
end

test "bootstrap creates first admin, returns session token, and surfaces bundled defaults" do
  post "/app_api/bootstrap",
    params: {
      name: "Primary Installation",
      email: "admin@example.com",
      password: "Password123!",
      password_confirmation: "Password123!",
      display_name: "Primary Admin",
    },
    as: :json

  assert_response :created
  assert response.parsed_body.fetch("session_token").present?
  assert_equal "bootstrapped", response.parsed_body.dig("installation", "bootstrap_state")
end
```

**Step 2: Write the failing session request tests**

Create tests that lock this contract:

```ruby
test "login issues a session token for a valid identity" do
  identity = create_identity!(email: "admin@example.com", password: "Password123!")
  user = create_user!(identity: identity, role: "admin")

  post "/app_api/session",
    params: { email: "admin@example.com", password: "Password123!" },
    as: :json

  assert_response :created
  assert response.parsed_body.fetch("session_token").present?
  assert_equal user.public_id, response.parsed_body.dig("user", "user_id")
end

test "logout revokes the current session" do
  session = create_session!(user: create_user!(role: "admin"))

  delete "/app_api/session", headers: app_api_headers(session.plaintext_token)

  assert_response :success
  assert_predicate session.reload, :revoked?
end
```

**Step 3: Run the request tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/bootstrap_test.rb test/requests/app_api/sessions_test.rb
```

Expected: FAIL because the routes/controllers/actions do not exist yet.

**Step 4: Implement the minimal bootstrap/session API**

Implement:

- public bootstrap status and bootstrap create endpoints
- `POST /app_api/session`, `GET /app_api/session`, `DELETE /app_api/session`
- keep `GET /app_api/bootstrap/status`, `POST /app_api/bootstrap`, and
  `POST /app_api/session` callable without an existing app session by explicitly
  bypassing `authenticate_session!`
- ensure those unauthenticated JSON endpoints do not trip cookie-backed CSRF
  checks for CLI callers
- `IssueFirstAdmin` should call `Installations::BootstrapFirstAdmin`, then issue
  a normal `Session` and return the plaintext token once
- `Sessions::Create` should authenticate an enabled `Identity` via
  `identity.authenticate(password)`
- use `AuthenticatedSessionPresenter` so the CLI gets a stable payload shape

Minimal presenter shape:

```ruby
{
  "user" => {
    "user_id" => user.public_id,
    "display_name" => user.display_name,
    "role" => user.role,
    "email" => user.identity.email,
  },
  "installation" => {
    "installation_id" => installation.public_id,
    "name" => installation.name,
    "bootstrap_state" => installation.bootstrap_state,
  },
  "session" => {
    "session_id" => session.public_id,
    "expires_at" => session.expires_at.iso8601(6),
  },
  "session_token" => plaintext_token,
}
```

**Step 5: Re-run the request tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/bootstrap_test.rb test/requests/app_api/sessions_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/bootstrap_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/sessions_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/bootstrap_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/sessions_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/actions/bootstrap/issue_first_admin.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/actions/sessions/create.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/presenters/authenticated_session_presenter.rb
git commit -m "feat: add bootstrap and session operator apis"
```

### Task 2: Add workspace creation to the app API

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/actions/workspaces/create_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspaces_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/actions/workspaces/create.rb`

**Step 1: Write the failing workspace create tests**

Add request and service tests for:

```ruby
test "creates a private workspace for the current user" do
  session = create_session!(user: create_user!(role: "admin"))

  post "/app_api/workspaces",
    params: { name: "Integration Lab", privacy: "private" },
    headers: app_api_headers(session.plaintext_token),
    as: :json

  assert_response :created
  assert_equal "Integration Lab", response.parsed_body.dig("workspace", "name")
end

test "enforces one default workspace per user" do
  user = create_user!(role: "admin")
  create_workspace!(user: user, is_default: true)

  assert_raises(ActiveRecord::RecordInvalid) do
    AppSurface::Actions::Workspaces::Create.call(user: user, name: "Another", is_default: true)
  end
end
```

**Step 2: Run the workspace tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/workspaces_test.rb test/services/app_surface/actions/workspaces/create_test.rb
```

Expected: FAIL because `POST /app_api/workspaces` is not implemented.

**Step 3: Implement the minimal workspace create action**

Implement:

- `POST /app_api/workspaces`
- a dedicated app-surface action that:
  - creates a workspace for `current_user`
  - defaults privacy to `private`
  - optionally supports `is_default`
  - leaves agent mount creation to the existing `workspace_agents#create` path

Minimal action shape:

```ruby
Workspace.create!(
  installation: user.installation,
  user: user,
  name: name,
  privacy: privacy.presence || "private",
  is_default: is_default
)
```

**Step 4: Re-run the workspace tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/workspaces_test.rb test/services/app_surface/actions/workspaces/create_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspaces_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/app_surface/actions/workspaces/create_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspaces_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/app_surface/actions/workspaces/create.rb
git commit -m "feat: add app api workspace creation"
```

### Task 3: Extend ingress operator flows for Telegram configuration and Weixin QR contract

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_bindings/update_connector_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_bindings/update_connector.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/lib/claw_bot_sdk/weixin/qr_login.rb`

**Step 1: Write the failing ingress update tests**

Lock this request contract:

```ruby
test "updates telegram connector credentials and config through the binding" do
  context = create_workspace_context!
  session = create_session!(user: context[:user])
  ingress_binding = create_ingress_binding!(context, platform: "telegram")

  patch "/app_api/workspace_agents/#{context[:workspace_agent].public_id}/ingress_bindings/#{ingress_binding.public_id}",
    params: {
      channel_connector: {
        credential_ref_payload: { bot_token: "123:abc" },
        config_payload: { webhook_base_url: "https://bot.example.com" },
      },
    },
    headers: app_api_headers(session.plaintext_token),
    as: :json

  assert_response :success
  assert_equal "123:abc", ingress_binding.reload.channel_connectors.last.credential_ref_payload["bot_token"]
end
```

Also add service tests for:

- rejecting blank Telegram bot token
- rejecting invalid webhook base URL
- allowing label-only updates
- exposing a plaintext Telegram webhook secret token when a binding is created
  or when the operator explicitly rotates it
- preserving Weixin QR material when present in runtime state
- returning `qr_text` from `weixin/start_login` and `weixin/login_status` when
  the connector runtime state has it
- falling back to `qr_code_url` only when raw QR text is unavailable

**Step 2: Run the ingress tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb test/services/ingress_bindings/update_connector_test.rb
```

Expected: FAIL because nested connector update handling does not exist and the
real Weixin QR contract still exposes too little data for a terminal-first CLI.

**Step 3: Implement the connector update service**

Implement:

- nested `channel_connector` params on binding update
- a service that updates the binding's single connector
- Telegram validation rules:
  - `bot_token` present when writing credential payload
  - `webhook_base_url` must be an `http` or `https` URL when present
- Telegram setup contract updates:
  - include a plaintext webhook secret token in the create response, or add an
    explicit rotate operation that returns a newly issued plaintext secret
  - do not rely on the existing `ingress_secret_digest` alone; the digest is not
    operator-usable
- Weixin QR contract updates:
  - `ClawBotSDK::Weixin::QrLogin.start` should continue marking the connector as
    pending, but must also surface any available QR material
  - `ClawBotSDK::Weixin::QrLogin.status` should expose `login_state`,
    `login_started_at`, `account_id`, `base_url`, plus `qr_text` or
    `qr_code_url` when available in runtime state
  - prefer `qr_text` as the primary contract because the CLI can render it
    locally with `rqrcode`

Minimal controller pattern:

```ruby
if params.key?(:channel_connector)
  IngressBindings::UpdateConnector.call(
    channel_connector: @ingress_binding.channel_connectors.order(:id).last,
    attributes: params.require(:channel_connector).permit(:label, :lifecycle_state, credential_ref_payload: {}, config_payload: {}).to_h
  )
end
```

**Step 4: Re-run the ingress tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb test/services/ingress_bindings/update_connector_test.rb
```

Expected: PASS.

For Weixin, the minimal runtime-state contract should be:

```ruby
channel_connector.runtime_state_payload.deep_stringify_keys.slice(
  "login_state",
  "login_started_at",
  "account_id",
  "base_url",
  "qr_text",
  "qr_code_url"
)
```

For Telegram, the operator-visible setup payload should include:

```ruby
{
  "platform" => "telegram",
  "webhook_path" => "/ingress_api/telegram/bindings/#{ingress_binding.public_ingress_id}/updates",
  "webhook_secret_token" => plaintext_secret_token
}
```

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/ingress_bindings/update_connector_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/app_api/workspace_agents/ingress_bindings_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/ingress_bindings/update_connector.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/lib/claw_bot_sdk/weixin/qr_login.rb
git commit -m "feat: add operator ingress updates and weixin qr contract"
```

### Task 4: Scaffold the `core_matrix_cli` project

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.ruby-version`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Rakefile`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/cmctl`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/version.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/cli_smoke_test.rb`

**Step 1: Write the failing CLI smoke test**

Create a boot test:

```ruby
def test_cli_exposes_root_commands
  cli = CoreMatrixCLI::CLI.new
  assert_includes CoreMatrixCLI::CLI.all_commands.keys, "init"
  assert_includes CoreMatrixCLI::CLI.all_commands.keys, "auth"
  assert_includes CoreMatrixCLI::CLI.all_commands.keys, "status"
end
```

**Step 2: Run the smoke test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/cli_smoke_test.rb
```

Expected: FAIL because the project does not exist yet.

**Step 3: Create the minimal project skeleton**

Implement:

- Thor entrypoint in `bin/cmctl`
- root command class with placeholders for:
  - `init`
  - `auth`
  - `status`
  - `providers`
  - `workspace`
  - `agent`
  - `ingress`

Minimal CLI shell:

```ruby
module CoreMatrixCLI
  class CLI < Thor
    desc "init", "Bootstrap or continue operator setup"
    def init; end

    desc "status", "Show installation readiness"
    def status; end
  end
end
```

**Step 4: Re-run the smoke test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/cli_smoke_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
git commit -m "feat: scaffold core matrix operator cli"
```

### Task 5: Add CLI config, credential storage, and HTTP client primitives

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/config_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/file_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/macos_keychain_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/http_client.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/config_store_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/credential_store_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/http_client_test.rb`

**Step 1: Write the failing storage and HTTP tests**

Cover:

```ruby
def test_file_store_writes_with_0600_permissions
  store = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path)
  store.write("session_token" => "secret")
  assert_equal "600", sprintf("%o", File.stat(tmp_path).mode & 0o777)
end

def test_http_client_sends_bearer_token_when_present
  client = CoreMatrixCLI::HTTPClient.new(base_url: "http://example.test", session_token: "sess_123")
  request = client.build_request(:get, "/app_api/session")
  assert_equal "Token token=\"sess_123\"", request["Authorization"]
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/config_store_test.rb test/credential_store_test.rb test/http_client_test.rb
```

Expected: FAIL because the storage/client primitives do not exist.

**Step 3: Implement the minimal storage and client layer**

Implement:

- JSON-backed config store for non-secret defaults
- credential-store abstraction:
  - prefer macOS keychain via `security` CLI when available
  - otherwise use a `0600` file fallback
- `HTTPClient` built on `Net::HTTP`
  - JSON encode/decode
  - stable error wrapper for `401`, `404`, `422`, and transport failures
  - bearer token helper using the same token auth format as CoreMatrix tests

**Step 4: Re-run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/config_store_test.rb test/credential_store_test.rb test/http_client_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/config_store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/file_store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/macos_keychain_store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/http_client.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/config_store_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/credential_store_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/http_client_test.rb
git commit -m "feat: add operator cli config and http primitives"
```

### Task 6: Implement CLI auth, init, and status orchestration

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/runtime.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/setup_orchestrator.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/auth_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/init_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/status_command_test.rb`

**Step 1: Write the failing auth/init/status tests**

Cover:

```ruby
def test_init_bootstraps_and_persists_session_token
  fake_client.stub(:bootstrap_status, { "bootstrap_state" => "unbootstrapped" }) do
    fake_client.stub(:bootstrap, { "session_token" => "sess_123", "installation" => { "name" => "Primary" } }) do
      run_cli("init", input: "http://127.0.0.1:3000\nPrimary Installation\nadmin@example.com\nPassword123!\nPassword123!\nPrimary Admin\n")
      assert_equal "sess_123", credential_store.read.fetch("session_token")
    end
  end
end

def test_status_reads_server_state_instead_of_local_progress
  fake_client.stub(:installation_status, readiness_payload) do
    output = run_cli("status")
    assert_includes output, "codex subscription: authorized"
  end
end
```

**Step 2: Run the command tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/auth_command_test.rb test/init_command_test.rb test/status_command_test.rb
```

Expected: FAIL because the command implementations and runtime wiring do not exist.

**Step 3: Implement auth/init/status**

Implement:

- `auth login`, `auth whoami`, `auth logout`
- automatic session persistence after bootstrap or login
- `init` orchestration:
  - check bootstrap status
  - bootstrap when needed
  - otherwise login when needed
  - re-read installation/workspace/provider state after successful auth
  - reuse bundled default workspace/workspace agent if already present
- `status` output derived from live server responses

Minimal init orchestration shape:

```ruby
status = client.get("/app_api/bootstrap/status")
auth_payload =
  if status.fetch("bootstrap_state") == "unbootstrapped"
    client.post("/app_api/bootstrap", bootstrap_params)
  else
    ensure_logged_in!
  end
persist_session!(auth_payload.fetch("session_token"))
readiness = orchestrator.readiness_snapshot
```

**Step 4: Re-run the command tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/auth_command_test.rb test/init_command_test.rb test/status_command_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/runtime.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/setup_orchestrator.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/auth_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/init_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/status_command_test.rb
git commit -m "feat: add operator cli auth and init orchestration"
```

### Task 7: Add CLI workspace and agent attachment commands

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/readiness_snapshot.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/workspace_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/agent_command_test.rb`

**Step 1: Write the failing workspace/agent tests**

Cover:

```ruby
def test_workspace_create_persists_selected_workspace
  fake_client.stub(:create_workspace, { "workspace" => { "workspace_id" => "ws_123", "name" => "Integration Lab" } }) do
    run_cli("workspace", "create", "--name", "Integration Lab")
    assert_equal "ws_123", config_store.read.fetch("workspace_id")
  end
end

def test_agent_attach_persists_workspace_agent_selection
  fake_client.stub(:attach_workspace_agent, { "workspace_agent" => { "workspace_agent_id" => "wa_123" } }) do
    run_cli("agent", "attach", "--workspace-id", "ws_123", "--agent-id", "agt_123")
    assert_equal "wa_123", config_store.read.fetch("workspace_agent_id")
  end
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/workspace_command_test.rb test/agent_command_test.rb
```

Expected: FAIL because these commands do not exist yet.

**Step 3: Implement workspace and agent commands**

Implement:

- `workspace list`
- `workspace create`
- `workspace use`
- `agent attach`

Behavior:

- save the selected `workspace_id`
- save the selected `workspace_agent_id`
- let `init` reuse these selections when appropriate

**Step 4: Re-run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/workspace_command_test.rb test/agent_command_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/readiness_snapshot.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/workspace_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/agent_command_test.rb
git commit -m "feat: add operator cli workspace selection"
```

### Task 8: Implement Codex provider authorization in the CLI

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/browser_launcher.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/polling.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/provider_codex_command_test.rb`

**Step 1: Write the failing Codex command tests**

Cover:

```ruby
def test_codex_login_opens_authorization_url_and_polls_until_authorized
  fake_client.stub(:start_codex_authorization, { "authorization" => { "authorization_url" => "https://auth.example.test" } }) do
    fake_client.stub(:codex_authorization_statuses, [%w[pending], %w[authorized]]) do
      output = run_cli("providers", "codex", "login")
      assert_includes output, "authorized"
    end
  end
end
```

**Step 2: Run the Codex tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/provider_codex_command_test.rb
```

Expected: FAIL because provider commands and polling do not exist.

**Step 3: Implement the provider command**

Implement:

- `providers codex login`
- `providers codex status`
- `providers codex logout`
- browser open on macOS/Linux when possible; otherwise print URL
- poll the existing CoreMatrix authorization endpoint until:
  - `authorized`
  - `reauthorization_required`
  - timeout

**Step 4: Re-run the Codex tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/provider_codex_command_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/browser_launcher.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/polling.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/provider_codex_command_test.rb
git commit -m "feat: add codex provider authorization to operator cli"
```

### Task 9: Implement Telegram and Weixin setup commands in the CLI

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/ansi_qr_renderer.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ingress_telegram_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ingress_weixin_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ansi_qr_renderer_test.rb`

**Step 1: Write the failing ingress command tests**

Cover:

```ruby
def test_telegram_setup_creates_binding_when_missing_and_prints_webhook_url
  output = run_cli("ingress", "telegram", "setup", input: "123:abc\nhttps://bot.example.com\n")
  assert_includes output, "https://bot.example.com/ingress_api/telegram/bindings/"
  assert_includes output, "X-Telegram-Bot-Api-Secret-Token"
end

def test_weixin_setup_renders_ansi_qr_when_qr_text_becomes_available_and_polls_until_connected
  output = run_cli("ingress", "weixin", "setup")
  assert_includes output, "\e["
  assert_includes output, "connected"
end
```

**Step 2: Run the ingress command tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/ingress_telegram_command_test.rb test/ingress_weixin_command_test.rb
```

Expected: FAIL because the ingress commands do not exist yet.

**Step 3: Implement the ingress commands**

Implement:

- `ingress telegram setup`
  - create binding when absent
  - update connector bot token and webhook base URL
  - print final webhook URL
  - print the plaintext webhook secret token, rotating it if the operator asks
    to reissue credentials
- `ingress weixin setup`
  - create binding when absent
  - check status first when binding exists
  - start login only when not already connected
  - render ANSI QR with `rqrcode` when `qr_text` becomes available
  - print `qr_code_url` only as a fallback when the server cannot expose raw QR
    text
  - poll until connected or timeout

Also implement:

- `CoreMatrixCLI::AnsiQRRenderer`
  - wraps `RQRCode::QRCode.new(qr_text).as_ansi`
  - keeps rendering isolated and unit-testable
- `rqrcode` gem dependency in `core_matrix_cli/Gemfile`
- command help as a first-class operator surface:
  - `cmctl ingress telegram setup --help` must explain prerequisites, prompted
    values, printed outputs, and the v1 verification boundary
  - `cmctl ingress weixin setup --help` must explain prerequisites, QR behavior,
    prompted values if any, and the v1 verification boundary

Use Thor help primitives deliberately rather than leaving these commands with
one-line descriptions only. `long_desc` or equivalent custom help output should
be treated as required behavior for these two commands.

Telegram setup output should be explicit, for example:

```text
Webhook URL: https://bot.example.com/ingress_api/telegram/bindings/ing_xxx/updates
Webhook Secret Header: X-Telegram-Bot-Api-Secret-Token
Webhook Secret Token: <plaintext secret>
```

The Telegram help text should cover, at minimum:

```text
Preparation:
  - Create a bot in BotFather
  - Copy the bot token
  - Prepare a public HTTPS base URL for CoreMatrix

This command will ask for:
  - bot token
  - webhook base URL

This command will print:
  - webhook URL
  - webhook secret header name
  - webhook secret token
```

The Weixin help text should cover, at minimum:

```text
Preparation:
  - Ensure you are logged in
  - Ensure a workspace and workspace agent are selected
  - Use a terminal that can render ANSI QR output if possible

This command will:
  - create or reuse the binding
  - start login when needed
  - poll status
  - render ANSI QR from qr_text when available
  - print qr_code_url only as a fallback
```

**Step 4: Re-run the ingress command tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/ingress_telegram_command_test.rb test/ingress_weixin_command_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/ansi_qr_renderer.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ingress_telegram_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ingress_weixin_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/ansi_qr_renderer_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile
git commit -m "feat: add ingress setup flows to operator cli"
```

### Task 10: Add unattended CLI contract tests against a fake CoreMatrix server

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_core_matrix_server.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/full_setup_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/http_client.rb`

**Step 1: Write the failing contract tests**

Cover the unattended happy path with a fake HTTP server that speaks the planned
CoreMatrix API:

```ruby
def test_full_setup_contract_bootstraps_reuses_bundled_workspace_and_configures_im_paths
  server = FakeCoreMatrixServer.new do |state|
    state.bootstrap_state = "unbootstrapped"
    state.codex_status_sequence = %w[pending authorized]
    state.weixin_status_sequence = [
      { "login_state" => "pending" },
      { "login_state" => "pending", "qr_text" => "weixin://qr-login-token" },
      { "login_state" => "connected", "account_id" => "wx-123" }
    ]
  end

  output = run_cli_against_server(server) do
    invoke "init"
    invoke "providers", "codex", "login"
    invoke "ingress", "telegram", "setup", input: "123:abc\nhttps://bot.example.com\n"
    invoke "ingress", "weixin", "setup"
    invoke "status"
  end

  assert_includes output, "authorized"
  assert_includes output, "connected"
end
```

The fake server must be stateful enough to verify:

- bootstrap response returns a session token
- later authenticated requests reuse that token
- bundled bootstrap can pre-populate workspace and workspace agent state
- Telegram connector writes hit the expected endpoint and payload shape
- Telegram setup output exposes a plaintext webhook secret token
- Weixin QR/status polling works without a real remote account

**Step 2: Run the contract tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/full_setup_contract_test.rb
```

Expected: FAIL because the fake-server harness and end-to-end wiring do not
exist yet.

**Step 3: Implement the fake-server harness**

Implement:

- a lightweight WEBrick or Rack-based fake server under `test/support/`
- helpers for sequencing provider and Weixin status transitions
- one top-level contract test that runs the real CLI commands against the fake
  server over HTTP
- stable HTTP client behavior for timeout and JSON parse failures so the e2e
  test covers realistic error surfaces

This suite is the key enabler for unattended development and self-verification:
it lets the agent prove the CLI works end-to-end without depending on a live
CoreMatrix deployment or a real Telegram/Weixin account.

**Step 4: Re-run the contract tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/full_setup_contract_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_core_matrix_server.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/full_setup_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/http_client.rb
git commit -m "test: add operator cli full setup contract coverage"
```

### Task 11: Wire the new subproject into monorepo CI and docs

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-16-core-matrix-operator-cli-design.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INTEGRATIONS.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md`

**Step 1: Write the failing CI/documentation expectations**

Add a small smoke check in the CLI README or root README examples and verify the
CI workflow includes a path rule/job for `core_matrix_cli/**` per monorepo
rules.

Concrete requirement to satisfy:

- `core_matrix_cli` has its own local toolchain files
- root CI references `core_matrix_cli/**`
- the README documents `cmctl init` and `cmctl status`

**Step 2: Update the workflow and docs**

Implement:

- a CI job or path-aware job inclusion for the new subproject
- extend the root `changes` detector so `core_matrix_cli/**` can trigger its own
  checks without falsely routing everything through `core_matrix`
- root README note pointing operators at `core_matrix_cli`
- CLI README quickstart:
  - `cmctl init`
  - `cmctl providers codex login`
  - `cmctl ingress telegram setup`
  - `cmctl ingress weixin setup`
- operator-facing IM preparation guide with:
  - Telegram prerequisites and exact values the CLI will ask for
  - Weixin prerequisites and the QR login expectations
  - explicit note that v1 self-verification is API-contract only, with real
    webhook delivery and human QR scan reserved for later joint validation

**Step 3: Run focused verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/bootstrap_test.rb test/requests/app_api/sessions_test.rb test/requests/app_api/workspaces_test.rb test/requests/app_api/workspace_agents/ingress_bindings_controller_test.rb test/services/ingress_bindings/update_connector_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/cli_smoke_test.rb test/config_store_test.rb test/credential_store_test.rb test/http_client_test.rb test/auth_command_test.rb test/init_command_test.rb test/status_command_test.rb test/workspace_command_test.rb test/agent_command_test.rb test/provider_codex_command_test.rb test/ingress_telegram_command_test.rb test/ingress_weixin_command_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/full_setup_contract_test.rb
```

Expected: PASS.

**Step 4: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml \
  /Users/jasl/Workspaces/Ruby/cybros/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-16-core-matrix-operator-cli-design.md \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/INTEGRATIONS.md \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md
git commit -m "docs: wire operator cli into monorepo docs and ci"
```
