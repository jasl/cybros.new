# CoreMatrix CLI Gem Rebuild Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild `core_matrix_cli` into a complete standalone gem with `bundle exec exe/cmctl` as the only supported entrypoint, preserve the existing operator setup behavior, adapt acceptance to the new executable layout, update licensing so only `core_matrix` remains O'Saasy, and delete the legacy `core_matrix_cli.old` tree once parity is proven.

**Architecture:** Treat `core_matrix_cli.old` as specification input only, then rebuild the CLI around explicit command, use-case, API, state, and support layers inside `core_matrix_cli/`. Keep transport on `Net::HTTP`, move all operator-required documentation inside the gem project, adapt acceptance helpers to invoke `bundle exec ./exe/cmctl` from the stable repo-root-relative `core_matrix_cli/` path, and clean up root-only convenience code that does not warrant its own abstraction.

**Tech Stack:** Ruby 4.0.2, Bundler gem layout, Thor, Net::HTTP, RQRCode, Minitest, Open3, repo-root acceptance harness, MIT/O'Saasy licensing files, existing monorepo CI.

---

**Execution notes:**

- Follow `@test-driven-development` for each behavior change.
- If an old `core_matrix_cli.old` test is useful, rewrite its intent into the
  new test layout instead of copying the file unchanged.
- Do not stage unrelated dirty worktree files. This repository already has
  in-flight user changes under `core_matrix_cli/`.
- Keep `core_matrix` application code untouched unless a verification step
  proves the rebuilt CLI cannot reach parity without a server-side change.
- Use the approved design at
  `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-17-core-matrix-cli-gem-rebuild-design.md`
  as the architecture baseline.
- Treat the current `core_matrix_cli/` tree as a partially generated scaffold
  plus user in-flight churn. Normalize it deliberately; do not assume it is a
  clean Bundler fresh-start.

**Verified reference anchors:**

- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/README.md:5-72`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/lib/core_matrix_cli.rb:1-33`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/lib/core_matrix_cli/http_client.rb:1-152`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/test/test_helper.rb:1-260`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/test/full_setup_contract_test.rb:3-59`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/test/support/fake_core_matrix_server.rb:1-258`
- `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/cli_support.rb:13-65`
- `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb:18-125`
- `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/active_suite.rb:9-37`
- `/Users/jasl/Workspaces/Ruby/cybros/README.md:47-92`
- `/Users/jasl/Workspaces/Ruby/cybros/lib/monorepo_dev_environment.rb:3-20`
- `/Users/jasl/Workspaces/Ruby/cybros/test/monorepo_dev_environment_test.rb:1-29`
- `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml:382-418`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile:1-12`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md:1-39`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/core_matrix_cli.gemspec:1-35`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb:1-5`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb:1-4`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.rubocop.yml:1-47`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/console:1-10`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/setup:1-8`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/sig/core_matrix_cli.rbs:1-4`

When a task below says "Modify" for one of these existing files without
repeating a line range, use the anchor list above as the verified current-file
starting point before editing.

### Task 1: Re-establish a clean gem boundary and executable contract

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.ruby-version`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.gitignore`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.rubocop.yml`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/console`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/setup`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/exe/cmctl`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/executable_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/core_matrix_cli.gemspec`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/version.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_core_matrix_cli.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/sig/core_matrix_cli.rbs`
- Delete (manual workspace cleanup): `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.git`
- Delete (manual workspace cleanup): `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.github/workflows/main.yml`

**Step 1: Write the failing executable contract test**

Create `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/executable_contract_test.rb` with assertions like:

```ruby
require "test_helper"
require "open3"

class ExecutableContractTest < Minitest::Test
  def test_exe_cmctl_exists_and_is_executable
    path = File.expand_path("../exe/cmctl", __dir__)

    assert File.exist?(path), "expected #{path} to exist"
    assert File.executable?(path), "expected #{path} to be executable"
  end

  def test_exe_cmctl_boots_the_cli
    stdout, stderr, status = Open3.capture3(
      { "BUNDLE_GEMFILE" => File.expand_path("../Gemfile", __dir__) },
      "bundle", "exec", "./exe/cmctl", "--help",
      chdir: File.expand_path("..", __dir__)
    )

    assert status.success?, "expected help command to pass, stderr=#{stderr}"
    assert_includes stdout, "cmctl"
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/executable_contract_test.rb
```

Expected: FAIL because `exe/cmctl` does not exist and the current root file at
`/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb:1-5`
still exposes only placeholder content.

**Step 3: Implement the minimal executable and root module contract**

Implement the minimum needed to make the test pass:

- restore `.ruby-version` to `4.0.2`
- keep `.gitignore`, `.rubocop.yml`, `bin/console`, and `bin/setup` as tracked
  project files, but strip or replace any template-only comments that no longer
  describe the project
- delete `sig/core_matrix_cli.rbs` unless you are prepared to maintain real RBS
  for the rebuilt codebase
- replace the placeholder content in `lib/core_matrix_cli.rb` with a real root
  boot path that exposes `CoreMatrixCLI::CLI`
- create `exe/cmctl` with the standard Bundler boot shim:

```ruby
#!/usr/bin/env ruby

require "bundler/setup"
require "core_matrix_cli"

CoreMatrixCLI::CLI.start(ARGV)
```

- update the gemspec so the executable name is `cmctl`

**Step 4: Remove nested gem-template repository scaffolding**

Clean the workspace-only nested repo artifacts that should never survive in the
monorepo:

```bash
rm -rf /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.git
rm -f /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.github/workflows/main.yml
rm -f /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_core_matrix_cli.rb
rm -f /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/sig/core_matrix_cli.rbs
```

**Step 5: Re-run the test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/executable_contract_test.rb
```

Expected: PASS.

**Step 6: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.ruby-version \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.gitignore \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/.rubocop.yml \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/console \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/bin/setup \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/exe/cmctl \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/core_matrix_cli.gemspec \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/version.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/executable_contract_test.rb
git commit -m "build: restore clean core matrix cli gem boundary"
```

### Task 2: Rebuild local config and credential persistence

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/state/config_repository.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/state/credential_repository.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/file_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/mac_os_keychain_store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/state/config_repository_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/state/credential_repository_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_shell_runner.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb`

**Step 1: Write the failing persistence tests**

Create tests that lock the intended behavior:

```ruby
class ConfigRepositoryTest < Minitest::Test
  def test_merge_round_trips_stringified_json_keys
    repo = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))

    repo.merge(workspace_id: "ws_123", nested: { current_agent_id: "wa_123" })

    assert_equal(
      { "workspace_id" => "ws_123", "nested" => { "current_agent_id" => "wa_123" } },
      repo.read
    )
  end
end

class CredentialRepositoryTest < Minitest::Test
  def test_file_store_writes_with_0600_permissions
    store = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))

    store.write("session_token" => "secret")

    assert_equal "600", format("%o", File.stat(tmp_path("credentials.json")).mode & 0o777)
    assert_equal({ "session_token" => "secret" }, store.read)
  end
end
```

Add one test for environment overrides and one for the macOS keychain runner
contract using `FakeShellRunner`.

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/state/config_repository_test.rb test/state/credential_repository_test.rb
```

Expected: FAIL because the state and credential classes do not exist yet.

**Step 3: Implement the state and credential layers**

Implement:

- `State::ConfigRepository` as JSON-backed non-secret state with `read`, `write`,
  `merge`, and `clear`
- `State::CredentialRepository` as a strategy wrapper that picks file or macOS
  keychain storage
- `CredentialStores::FileStore` with `0600` permission writes
- `CredentialStores::MacOSKeychainStore` using `security`
- environment overrides:
  - `CORE_MATRIX_CLI_CONFIG_PATH`
  - `CORE_MATRIX_CLI_CREDENTIAL_STORE`
  - `CORE_MATRIX_CLI_CREDENTIAL_PATH`

Keep default storage paths under `~/.config/core_matrix_cli`.

**Step 4: Re-run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/state/config_repository_test.rb test/state/credential_repository_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/state/config_repository.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/state/credential_repository.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/file_store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/credential_stores/mac_os_keychain_store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/state/config_repository_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/state/credential_repository_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_shell_runner.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb
git commit -m "feat: rebuild cli local state persistence"
```

### Task 3: Rebuild the API client and technical support utilities

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/errors.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/support/polling.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/support/browser_launcher.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/support/ansi_qr_renderer.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/core_matrix_api_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/polling_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/browser_launcher_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/ansi_qr_renderer_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb`

**Step 1: Write the failing transport and support tests**

Create tests that cover:

- request building and JSON parsing
- `401`, `404`, `422`, and `5xx` error mapping
- transport failures wrapping into a dedicated transport error
- polling timeout and stop condition behavior
- browser launching being skipped when `CORE_MATRIX_CLI_DISABLE_BROWSER=1`
- QR renderer returning terminal-safe text

Use an injected transport lambda for the API test:

```ruby
transport = lambda do |_uri, request, _options|
  FakeResponse.new(code: "200", body: "{\"method_id\":\"session_show\"}", message: "OK")
end
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest \
  test/core_matrix_api_test.rb \
  test/support/polling_test.rb \
  test/support/browser_launcher_test.rb \
  test/support/ansi_qr_renderer_test.rb
```

Expected: FAIL because the new API and support classes do not exist yet.

**Step 3: Implement the API and support layers**

Implement:

- `CoreMatrixAPI` as the CLI-local Net::HTTP adapter
- typed errors under `Errors`
- JSON request/response handling
- the old endpoint surface:
  - bootstrap
  - session
  - installation/workspace/agent
  - Codex provider authorization
  - ingress binding and Weixin login
- `Support::Polling.until`
- `Support::BrowserLauncher#open`
- `Support::AnsiQrRenderer#render`

Keep the public API Ruby-shaped, for example:

```ruby
api.login(email:, password:)
api.list_workspaces
api.start_codex_authorization
api.update_ingress_binding(...)
```

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/errors.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/core_matrix_api.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/support/polling.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/support/browser_launcher.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/support/ansi_qr_renderer.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/core_matrix_api_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/polling_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/browser_launcher_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/ansi_qr_renderer_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb
git commit -m "feat: rebuild cli api and support layers"
```

### Task 4: Rebuild auth, status, and provider command flows

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/auth.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/providers.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/login_operator.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/show_current_session.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/logout_operator.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/authorize_codex_subscription.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/show_codex_status.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/revoke_codex_authorization.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/auth_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/status_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/provider_codex_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/cli_smoke_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb`

**Step 1: Write the failing command tests**

Rewrite the old auth/status/provider expectations against the new command
layout. Cover:

- `auth login` persisting session token and operator email
- `auth logout` clearing credentials
- `auth whoami` printing current session
- `status` printing readiness snapshot fields
- `providers codex login` opening or suppressing browser launch, printing code,
  and polling until non-pending
- `providers codex status|logout`

Use a CLI runner helper that executes `CoreMatrixCLI::CLI.start(...)` and
captures stdout/stderr.

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest \
  test/commands/auth_command_test.rb \
  test/commands/status_command_test.rb \
  test/commands/provider_codex_command_test.rb \
  test/cli_smoke_test.rb
```

Expected: FAIL because the new command groups and use cases do not exist yet.

**Step 3: Implement the command and use-case flow**

Implement:

- the root Thor CLI
- `auth` command group
- `providers codex` command group
- session persistence side effects through the new state repositories
- `status` output using real snapshot data from `CoreMatrixAPI`
- unauthorized-path behavior that clears local session state before printing the
  re-login hint

Keep command objects thin and business logic in `UseCases`.

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/auth.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/providers.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/login_operator.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/show_current_session.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/logout_operator.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/show_status.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/authorize_codex_subscription.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/show_codex_status.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/revoke_codex_authorization.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/auth_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/status_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/provider_codex_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/cli_smoke_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/test_helper.rb
git commit -m "feat: rebuild cli auth status and codex flows"
```

### Task 5: Rebuild workspace and agent workflows

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/workspace.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/agent.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/list_workspaces.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/create_workspace.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/use_workspace.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/attach_agent.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/workspace_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/agent_command_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`

**Step 1: Write the failing workspace and agent tests**

Cover:

- `workspace list` printing available workspaces
- `workspace create --name ...` creating and selecting the workspace
- `workspace use <workspace_id>` changing the saved workspace id
- `agent attach --workspace-id ... --agent-id ...` persisting the selected
  workspace agent id and clearing stale ingress-binding ids when the mount
  changes

Use assertions similar to:

```ruby
assert_match(/CLI Smoke Workspace/, output)
assert_equal "ws_123", config_repo.read.fetch("workspace_id")
assert_equal "wa_123", config_repo.read.fetch("workspace_agent_id")
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/commands/workspace_command_test.rb test/commands/agent_command_test.rb
```

Expected: FAIL because the workspace and agent command flow is not implemented.

**Step 3: Implement the workspace and agent use cases**

Implement:

- workspace listing and creation
- workspace selection persistence
- agent attachment flow
- workspace / workspace-agent side effects in local config
- ingress-binding cleanup when workspace context changes

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/workspace.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/agent.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/list_workspaces.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/create_workspace.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/use_workspace.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/attach_agent.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/workspace_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/agent_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb
git commit -m "feat: rebuild cli workspace and agent flows"
```

### Task 6: Rebuild ingress setup and `init` orchestration

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/ingress.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/run_init.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_orchestrator.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/init_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/ingress_telegram_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/ingress_telegram_webhook_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/ingress_weixin_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/full_setup_contract_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_core_matrix_server.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile.lock`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb`

**Step 1: Write the failing ingress and init tests**

Port the old ingress and end-to-end setup intent into the new test layout.
Cover:

- `init` bootstrapping when unbootstrapped
- `init` reusing existing server state when already bootstrapped
- Telegram polling setup
- Telegram webhook setup
- Weixin QR login start and status polling
- full setup contract against a fake server

The fake-server contract should still validate a flow like:

```ruby
server = FakeCoreMatrixServer.start!
stdout, stderr, status = Open3.capture3(
  env_for_fake_server(server),
  "bundle", "exec", "./exe/cmctl", "init",
  stdin_data: fake_server_bootstrap_input,
  chdir: cli_root
)
assert status.success?, stderr
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest \
  test/commands/init_command_test.rb \
  test/commands/ingress_telegram_command_test.rb \
  test/commands/ingress_telegram_webhook_command_test.rb \
  test/commands/ingress_weixin_command_test.rb \
  test/full_setup_contract_test.rb
```

Expected: FAIL because the ingress and orchestration layers do not exist yet.

**Step 3: Implement the orchestration and ingress layers**

Implement:

- `RunInit` as the resumable top-level setup flow
- `SetupOrchestrator` for shared setup-state decisions
- Telegram polling setup
- Telegram webhook setup
- Weixin QR login flow
- ingress binding id persistence per platform
- add `webrick` back to the CLI development dependencies because the fake-server
  contract from
  `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old/test/support/fake_core_matrix_server.rb:1-258`
  requires it outside the Ruby standard library bundle
- run `bundle install` in `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli`
  after changing `Gemfile` so `Gemfile.lock` is refreshed before re-running the
  contract tests

Preserve the old product behavior but keep orchestration logic out of Thor.

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/commands/ingress.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/run_init.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_polling.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_telegram_webhook.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_weixin.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/use_cases/setup_orchestrator.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/init_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/ingress_telegram_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/ingress_telegram_webhook_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/commands/ingress_weixin_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/full_setup_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/support/fake_core_matrix_server.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/Gemfile.lock \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/lib/core_matrix_cli/cli.rb
git commit -m "feat: rebuild cli init and ingress flows"
```

### Task 7: Make gem metadata and CLI documentation self-contained

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/docs/integrations.md`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/metadata_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/core_matrix_cli.gemspec`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/LICENSE.txt`

**Step 1: Write the failing metadata contract test**

Create a test that prevents placeholder gem metadata and legacy executable docs
from surviving:

```ruby
class MetadataContractTest < Minitest::Test
  def test_gemspec_and_readme_are_real_product_metadata
    readme = File.read(File.expand_path("../README.md", __dir__))
    gemspec = Gem::Specification.load(File.expand_path("../core_matrix_cli.gemspec", __dir__))

    refute_includes readme, "TODO:"
    refute_includes readme, "bin/cmctl"
    assert_includes readme, "bundle exec exe/cmctl"
    assert_equal "MIT", gemspec.license
    assert_equal ["cmctl"], gemspec.executables
    refute_match(/TODO/i, gemspec.summary)
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec ruby -Itest test/metadata_contract_test.rb
```

Expected: FAIL because the README and gemspec still contain Bundler template
content and do not document `exe/cmctl`.

**Step 3: Replace placeholder metadata and write local docs**

Implement:

- real gemspec summary, description, source URLs, and executable list
- a real README with:
  - installation
  - quickstart
  - command groups
  - local development
  - verification
  - MIT license statement
- `docs/integrations.md` with the operator guidance that currently lives
  outside the gem project

Keep docs self-contained inside `core_matrix_cli/`.

**Step 4: Re-run the test to verify it passes**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/docs/integrations.md \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/test/metadata_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/core_matrix_cli.gemspec \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli/LICENSE.txt
git commit -m "docs: make core matrix cli gem self contained"
```

### Task 8: Update monorepo CI for the rebuilt CLI

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/core_matrix_cli_ci_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml`

**Step 1: Write the failing CI contract test**

Create a small file-reading test that locks the new automation contract:

```ruby
require "minitest/autorun"

class CoreMatrixCliCiContractTest < Minitest::Test
  def test_root_ci_uses_maintainable_cli_commands
    workflow = File.read("/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml")

    assert_includes workflow, "bundle exec rake test"
    assert_includes workflow, "bundle exec rubocop --no-server"
    refute_includes workflow, "test/config_store_test.rb"
    refute_includes workflow, "test/http_client_test.rb"
    refute_includes workflow, "test/init_command_test.rb"
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
BUNDLE_GEMFILE=/Users/jasl/Workspaces/Ruby/cybros/acceptance/Gemfile \
  bundle exec ruby acceptance/test/core_matrix_cli_ci_contract_test.rb
```

Expected: FAIL because the root workflow at
`/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml:382-418` still
lists legacy test files explicitly.

**Step 3: Update the root workflow**

Change the `core_matrix_cli_test` job to use maintainable CLI-local commands,
for example:

```yaml
- name: Run CLI test suite
  run: bundle exec rake test

- name: Run CLI lint
  run: bundle exec rubocop --no-server
```

Do not retain hard-coded references to deleted legacy test filenames.

**Step 4: Re-run the test to verify it passes**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/acceptance/test/core_matrix_cli_ci_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml
git commit -m "ci: update core matrix cli workflow for rebuilt test layout"
```

### Task 9: Adapt acceptance helpers and repo docs to `exe/cmctl`

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/cli_support_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/cli_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/README.md`

**Step 1: Write the failing acceptance helper contract test**

Create a small acceptance-harness test that locks the helper invocation
contract:

```ruby
require "minitest/autorun"
require_relative "../lib/cli_support"

class CliSupportTest < Minitest::Test
  def test_run_uses_bundle_exec_and_exe_cmctl_from_core_matrix_cli
    calls = []
    runner = lambda do |env, *command, **kwargs|
      calls << { env:, command:, kwargs: }
      ["", "", Struct.new(:success?).new(true)]
    end

    Acceptance::CliSupport.run!(
      artifact_dir: "/tmp/core-matrix-cli-acceptance",
      label: "status",
      args: ["status"],
      runner: runner
    )

    assert_equal ["bundle", "exec", "./exe/cmctl", "status"], calls.fetch(0).fetch(:command)
    assert_equal "/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli", calls.fetch(0).fetch(:kwargs).fetch(:chdir)
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
BUNDLE_GEMFILE=/Users/jasl/Workspaces/Ruby/cybros/acceptance/Gemfile \
  bundle exec ruby acceptance/test/cli_support_test.rb
```

Expected: FAIL because the helper still invokes `./bin/cmctl`.

**Step 3: Update the acceptance helper and documentation**

Implement:

- `Acceptance::CliSupport.run!` invoking `bundle exec ./exe/cmctl`
- any needed scenario adjustments for the new command entrypoint
- acceptance README snippets that mention the operator CLI path
- root README quickstart commands switched from `bin/cmctl` to `exe/cmctl`

Keep repo-root-relative `core_matrix_cli/` and `acceptance/` path assumptions
explicit.

**Step 4: Re-run the helper test to verify it passes**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Run the targeted acceptance scenario**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails runner ../acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb
```

Expected: PASS with fresh CLI artifacts under
`/Users/jasl/Workspaces/Ruby/cybros/acceptance/artifacts/...`.

**Step 6: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/acceptance/test/cli_support_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/acceptance/lib/cli_support.rb \
  /Users/jasl/Workspaces/Ruby/cybros/acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb \
  /Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/README.md
git commit -m "test: adapt acceptance to rebuilt cli executable"
```

### Task 10: Update licensing to MIT outside `core_matrix`

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/LICENSE.txt`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/images/nexus/LICENSE.txt`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/repo_licensing_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/LICENSE.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/images/nexus/README.md`

**Step 1: Write the failing repository licensing contract test**

Create `/Users/jasl/Workspaces/Ruby/cybros/acceptance/test/repo_licensing_contract_test.rb` with assertions like:

```ruby
require "minitest/autorun"

class RepoLicensingContractTest < Minitest::Test
  def test_only_core_matrix_remains_osaasy
    root_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/LICENSE.md")
    fenix_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/LICENSE.txt")
    nexus_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/images/nexus/LICENSE.txt")
    core_matrix_license = File.read("/Users/jasl/Workspaces/Ruby/cybros/core_matrix/LICENSE.md")

    assert_includes root_license, "The MIT License (MIT)"
    assert_includes fenix_license, "The MIT License (MIT)"
    assert_includes nexus_license, "The MIT License (MIT)"
    assert_includes core_matrix_license, "O'Saasy License Agreement"
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
BUNDLE_GEMFILE=/Users/jasl/Workspaces/Ruby/cybros/acceptance/Gemfile \
  bundle exec ruby acceptance/test/repo_licensing_contract_test.rb
```

Expected: FAIL because the root license is still O'Saasy and the Fenix/Nexus
license files do not exist.

**Step 3: Apply the licensing update**

Implement:

- rewrite the root `LICENSE.md` to MIT text
- add MIT `LICENSE.txt` files to `agents/fenix/` and `images/nexus/`
- update README sections so they clearly state:
  - `core_matrix/` remains O'Saasy
  - `core_matrix_cli/`, `agents/fenix/`, `images/nexus/`, and root repo
    materials are MIT unless a more specific project file says otherwise

Do not change `core_matrix/LICENSE.md`.

**Step 4: Re-run the test to verify it passes**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/LICENSE.txt \
  /Users/jasl/Workspaces/Ruby/cybros/images/nexus/LICENSE.txt \
  /Users/jasl/Workspaces/Ruby/cybros/acceptance/test/repo_licensing_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/LICENSE.md \
  /Users/jasl/Workspaces/Ruby/cybros/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/images/nexus/README.md
git commit -m "docs: align repository licensing around core matrix boundary"
```

### Task 11: Remove root-only dev helper abstraction, verify parity, and delete `core_matrix_cli.old`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/bin/dev`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/lib/monorepo_dev_environment.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/test/monorepo_dev_environment_test.rb`
- Delete (manual workspace cleanup): `/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old`

**Step 1: Inline the helper logic into `bin/dev`**

Move the environment-default logic from
`/Users/jasl/Workspaces/Ruby/cybros/lib/monorepo_dev_environment.rb` directly
into `/Users/jasl/Workspaces/Ruby/cybros/bin/dev`.

Keep the resulting script small and literal, for example:

```ruby
core_matrix_port = ENV.fetch("CORE_MATRIX_PORT", ENV.fetch("PORT", "3000"))
agent_fenix_port = ENV.fetch("AGENT_FENIX_PORT", "36173")

ENV["PORT"] ||= core_matrix_port
ENV["CORE_MATRIX_PORT"] ||= core_matrix_port
ENV["AGENT_FENIX_PORT"] ||= agent_fenix_port
ENV["AGENT_FENIX_BASE_URL"] ||= "http://127.0.0.1:#{agent_fenix_port}"
```

Then delete the helper module and its dedicated test.

**Step 2: Run the rebuilt CLI test suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rake test
```

Expected: PASS.

**Step 3: Run the rebuilt CLI lint and packaging checks**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli
bundle exec rubocop --no-server
bundle exec rake build
```

Expected: PASS.

**Step 4: Re-run the targeted CLI acceptance proof**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails runner ../acceptance/scenarios/core_matrix_cli_operator_smoke_validation.rb
```

Expected: PASS.

**Step 5: Remove the legacy CLI tree**

After Steps 2-4 are green, delete the legacy workspace tree:

```bash
rm -rf /Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli.old
```

**Step 6: Confirm the legacy path is gone and no operational docs or helpers still point at `bin/cmctl`**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
test ! -e core_matrix_cli.old
rg -n "bin/cmctl" README.md acceptance/README.md acceptance/lib/cli_support.rb core_matrix_cli/README.md core_matrix_cli/docs .github/workflows/ci.yml -S
rg -n "core_matrix_cli.old" README.md acceptance core_matrix_cli agents/fenix images/nexus .github -S
```

Expected: `test` exits `0`, and both `rg` commands return no matches.

**Step 7: Run the full active acceptance suite**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/run_active_suite.sh
```

Expected: PASS, including the operator CLI smoke scenario under the active
acceptance matrix.

**Step 8: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/bin/dev
git rm /Users/jasl/Workspaces/Ruby/cybros/lib/monorepo_dev_environment.rb \
  /Users/jasl/Workspaces/Ruby/cybros/test/monorepo_dev_environment_test.rb
git commit -m "refactor: finish core matrix cli gem rebuild"
```
