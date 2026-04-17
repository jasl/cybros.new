# Nexus Runtime Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild `execution_runtimes/nexus` into the only active Nexus runtime as a distributable Ruby 4.0 gem with a single `nexus run` entrypoint, full functional parity with `nexus.old`, websocket-first runtime delivery, durable local recovery, and a cleaned-up CoreMatrix execution-runtime protocol.

**Architecture:** Treat `execution_runtimes/nexus.old` as the capability source only, then rebuild Nexus around a monorepo-owned gem, a supervised runtime kernel, durable SQLite-backed local state, a websocket-first mailbox control plane, and explicit resource hosts for command, process, browser, skill, and memory surfaces. In parallel, collapse the CoreMatrix runtime protocol from the current registration/capabilities/poll/report/resource-controller mix into a smaller `session`, `mailbox`, `events`, and attachment surface while keeping CoreMatrix as the sole owner of public identifiers and orchestration state.

**Tech Stack:** Ruby 4.0.2, Bundler gem layout, Thor, SQLite3, Action Cable websocket protocol, Net::HTTP or async HTTP client adapters, Minitest, existing CoreMatrix Rails app, existing verification harness, filesystem-backed skills and memory.

---

**Execution notes:**

- Follow `@test-driven-development` for each behavior change.
- Use the approved design at
  `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-18-nexus-runtime-redesign-design.md`
  as the architecture baseline.
- Do not stage unrelated dirty worktree files. The current repository already
  contains unrelated staged renames and an untracked `execution_runtimes/nexus/`
  tree.
- Before Task 1 lands, remove the nested git metadata directory at
  `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.git` so the
  monorepo can own the rebuilt gem files directly.
- Keep Action Cable as the primary low-latency path. Poll remains fallback and
  recovery infrastructure and should never become the only happy-path design.
- Preserve `CoreMatrix` ownership of public IDs. Nexus consumes public refs and
  reports lifecycle events; it does not allocate durable IDs itself.
- Keep the process and TTY contract standardized even when capability flags
  disable one or both families on a specific runtime.
- Rewrite or delete legacy tests intentionally. Do not copy the old Rails test
  tree into the gem unchanged.
- End-to-end completion requires the full `core_matrix` verification suite plus
  `ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh`
  from the repo root.

**Verified reference anchors:**

- `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-18-nexus-runtime-redesign-design.md`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old/README.md:3-197`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old/app/services/runtime/control_loop.rb:9-105`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old/app/services/runtime/realtime_connection.rb:1-167`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old/app/services/processes/manager.rb:32-260`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/tool_call_runners/execution_runtime_mediated.rb:15-255`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/control_controller.rb:2-113`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/command_runs_controller.rb:2-29`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/process_runs_controller.rb:2-25`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/attachments_controller.rb:9-75`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_execution_assignment_test.rb:54-258`
- `/Users/jasl/Workspaces/Ruby/cybros/shared/fixtures/contracts/core_matrix_nexus_execution_assignment.json`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/cybros_nexus.gemspec:1-32`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Gemfile:1-10`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus.rb:1-6`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/test_helper.rb:1-4`

When a task below says "Modify" for one of these files without repeating a line
range, use the anchor list above as the verified current-file starting point
before editing.

### Task 1: Re-establish a monorepo-owned gem boundary and `nexus run` entrypoint

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.ruby-version`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/exe/nexus`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/cli.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/executable_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Gemfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/cybros_nexus.gemspec`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/version.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/test_helper.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/test_cybros_nexus.rb`
- Delete (manual workspace cleanup): `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.git`

**Step 1: Write the failing executable contract test**

Create `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/executable_contract_test.rb`:

```ruby
require "test_helper"
require "open3"

class ExecutableContractTest < Minitest::Test
  def test_exe_nexus_exists_and_is_executable
    path = File.expand_path("../exe/nexus", __dir__)

    assert File.exist?(path), "expected #{path} to exist"
    assert File.executable?(path), "expected #{path} to be executable"
  end

  def test_exe_nexus_prints_help
    stdout, stderr, status = Open3.capture3(
      { "BUNDLE_GEMFILE" => File.expand_path("../Gemfile", __dir__) },
      "bundle", "exec", "./exe/nexus", "--help",
      chdir: File.expand_path("..", __dir__)
    )

    assert status.success?, "stderr=#{stderr}"
    assert_includes stdout, "nexus"
    assert_includes stdout, "run"
  end
end
```

**Step 2: Run the test to verify it fails**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest test/executable_contract_test.rb
```

Expected: FAIL because `exe/nexus` and `CybrosNexus::CLI` do not exist yet.

**Step 3: Remove the nested git metadata and implement the minimal boot path**

- delete `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.git`
- restore `.ruby-version` to `4.0.2`
- add `exe/nexus` with a standard Bundler boot shim:

```ruby
#!/usr/bin/env ruby

require "bundler/setup"
require "cybros_nexus"

CybrosNexus::CLI.start(ARGV)
```

- replace placeholder gem metadata with real summary, description, homepage
  paths, and executable registration
- add a minimal Thor CLI with a `run` command stub and a root `version`
  command
- clean README wording so it describes the actual runtime product instead of
  the Bundler gem template

**Step 4: Re-run the test to verify it passes**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.ruby-version \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/exe/nexus \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/version.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Gemfile \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/cybros_nexus.gemspec \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/test_helper.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/executable_contract_test.rb
git add -u /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/test_cybros_nexus.rb
git commit -m "build: restore nexus gem boundary and executable"
```

### Task 2: Build configuration, SQLite state, and supervisor scaffolding

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/config.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/logger.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/supervisor.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/state/store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/state/migrator.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/state/schema.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/config_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/state/store_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/state/migrator_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/supervisor_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Gemfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/cybros_nexus.gemspec`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus.rb`

**Step 1: Write the failing config and state tests**

Create tests that lock the runtime root and SQLite contract:

```ruby
class ConfigTest < Minitest::Test
  def test_defaults_home_root_under_user_home
    config = CybrosNexus::Config.load(env: {})

    assert_match(/\.nexus\z/, config.home_root)
    assert_equal File.join(config.home_root, "state.sqlite3"), config.state_path
  end
end

class StoreTest < Minitest::Test
  def test_bootstrap_creates_required_tables
    store = CybrosNexus::State::Store.open(path: tmp_path("state.sqlite3"))

    assert_includes store.table_names, "runtime_sessions"
    assert_includes store.table_names, "event_outbox"
  end
end
```

Add one supervisor test that asserts a crashing child role is restarted and one
test that asserts `SIGTERM` stops the supervisor cleanly.

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest \
  test/config_test.rb \
  test/state/store_test.rb \
  test/state/migrator_test.rb \
  test/supervisor_test.rb
```

Expected: FAIL because the config, state, and supervisor classes do not exist.

**Step 3: Implement the minimal state and supervision substrate**

- add runtime dependencies for `sqlite3` and any small support libraries needed
  to manage WAL-mode state safely
- implement `Config.load` with:
  - `NEXUS_HOME_ROOT`
  - `CORE_MATRIX_BASE_URL`
  - `NEXUS_PUBLIC_BASE_URL`
  - `NEXUS_HTTP_BIND`
  - `NEXUS_HTTP_PORT`
- implement a small SQLite wrapper that:
  - opens the database
  - sets WAL mode
  - exposes transaction helpers
  - creates the required tables
- implement a supervisor that can start named roles, restart failed roles with
  bounded backoff, and stop them on signal

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/config.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/logger.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/supervisor.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/state/store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/state/migrator.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/state/schema.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/config_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/state/store_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/state/migrator_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/supervisor_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Gemfile \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/cybros_nexus.gemspec \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus.rb
git commit -m "feat: add nexus runtime state and supervisor foundation"
```

### Task 3: Replace CoreMatrix runtime registration and control endpoints with `session`, `mailbox`, and `events`

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/session_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/mailbox_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/events_controller.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/execution_runtime_sessions/open.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/execution_runtime_sessions/refresh.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/pull_mailbox_batch.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/apply_event_batch.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/session_controller_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/mailbox_controller_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/events_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/base_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/capabilities_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/control_controller.rb`

**Step 1: Write the failing request tests**

Create three request specs that assert:

- `session/open` returns a credential, capability snapshot, and transport hints
- `session/refresh` accepts a version package refresh and rotates state without
  a second endpoint family
- `mailbox/pull` returns leased mailbox items
- `events/batch` accepts multiple runtime events and returns per-event results

Start with payload assertions like:

```ruby
post "/execution_runtime_api/session/open", params: {
  onboarding_token: onboarding_session.plaintext_token,
  endpoint_metadata: { base_url: "https://runtime.example.test" },
  version_package: version_package_payload
}

assert_response :created
assert_equal "execution_runtime_session_open", response_body.fetch("method_id")
assert response_body.fetch("transport_hints").fetch("websocket")
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/requests/execution_runtime_api/session_controller_test.rb \
  test/requests/execution_runtime_api/mailbox_controller_test.rb \
  test/requests/execution_runtime_api/events_controller_test.rb
```

Expected: FAIL because the new controllers, services, and routes do not exist.

**Step 3: Implement the new protocol surface**

- add the new routes and controllers
- make `session/open` call the existing registration logic plus capability
  packaging in one place
- make `session/refresh` absorb the current refresh/handshake split
- make `mailbox/pull` the canonical lease endpoint
- make `events/batch` consume an array of runtime events and return per-event
  outcomes

For the first pass, `ApplyEventBatch` can internally delegate to the existing
single-event report services one event at a time; the important step is to make
the public protocol batch-oriented immediately.

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/session_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/mailbox_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/events_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/execution_runtime_sessions/open.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/execution_runtime_sessions/refresh.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/pull_mailbox_batch.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/apply_event_batch.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/session_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/mailbox_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/events_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/config/routes.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/base_controller.rb
git add -u /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/capabilities_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/control_controller.rb
git commit -m "refactor: replace runtime api with session mailbox and events"
```

### Task 4: Implement the websocket-first control role and poll fallback in the new gem

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/client.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/runtime_manifest.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/transport/action_cable_client.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/control_loop.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/events/outbox.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/http/server.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/session/client_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/transport/action_cable_client_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/mailbox/control_loop_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/events/outbox_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/http/server_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/cli.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/supervisor.rb`

**Step 1: Write the failing transport and loop tests**

Create tests that lock the required control-plane semantics:

```ruby
class ActionCableClientTest < Minitest::Test
  def test_subscribes_to_control_plane_and_yields_mailbox_items
    socket = FakeCableSocket.new
    items = []

    client = CybrosNexus::Transport::ActionCableClient.new(
      base_url: "https://core-matrix.example.test",
      credential: "secret",
      socket_factory: ->(*) { socket }
    )

    client.start { |mailbox_item| items << mailbox_item }
    socket.push_welcome!
    socket.push_message!("item_id" => "mbx_123")

    assert_equal ["mbx_123"], items.map { |item| item.fetch("item_id") }
  end
end
```

Add loop tests that verify:

- websocket-first processing
- poll fallback when the websocket drops
- mailbox receipt dedupe
- event outbox replay before new work pull
- local HTTP server exposes `/runtime/manifest`

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest \
  test/session/client_test.rb \
  test/transport/action_cable_client_test.rb \
  test/mailbox/control_loop_test.rb \
  test/events/outbox_test.rb \
  test/http/server_test.rb
```

Expected: FAIL because the new control-plane classes do not exist yet.

**Step 3: Implement the control role**

- implement a session client around the new CoreMatrix endpoints
- implement an Action Cable client that:
  - uses the `/cable` websocket
  - sends the correct `ControlPlaneChannel` subscribe payload
  - treats websocket as the primary path
  - falls back to `mailbox/pull` on disconnect or timeout
- implement `Events::Outbox` on top of the SQLite state store
- implement a tiny local HTTP server for `/runtime/manifest` and health probes
- wire the `run` command so the supervisor starts the `control` and `http`
  roles

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/client.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/runtime_manifest.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/transport/action_cable_client.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/control_loop.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/events/outbox.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/http/server.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/session/client_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/transport/action_cable_client_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/mailbox/control_loop_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/events/outbox_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/http/server_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/supervisor.rb
git commit -m "feat: add websocket-first nexus control role"
```

### Task 5: Standardize the command and process infrastructure contract and implement the resource host

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/resources/command_host.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/resources/process_host.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/resources/process_registry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/tools/exec_command.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/tools/process_tools.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/resources/command_host_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/resources/process_host_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/tools/exec_command_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/tools/process_tools_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_tool_contracts/command_and_process_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/tool_call_runners/execution_runtime_mediated.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/tool_call_runners_test.rb`

**Step 1: Write the failing host and contract tests**

Create tests that assert:

- `exec_command` one-shot calls return exit status plus output summary
- PTY-backed `exec_command` yields a durable `command_run_id`
- `write_stdin`, `command_run_wait`, and `command_run_terminate` behave against
  the same public ID
- `process_exec` starts a detached process and emits `process_started`
- `process_read_output`, `process_list`, and `process_proxy_info` read by
  public ID only
- CoreMatrix continues to provision resource refs before runtime execution

Example command-host assertion:

```ruby
result = command_host.start(
  command_run_id: "cmd_123",
  command_line: "printf hello",
  pty: false
)

assert_equal "cmd_123", result.fetch("command_run_id")
assert_equal 0, result.fetch("exit_status")
assert_equal "hello", result.fetch("stdout_tail")
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest \
  test/resources/command_host_test.rb \
  test/resources/process_host_test.rb \
  test/tools/exec_command_test.rb \
  test/tools/process_tools_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/services/runtime_tool_contracts/command_and_process_contract_test.rb \
  test/services/provider_execution/tool_call_runners_test.rb
```

Expected: FAIL because the resource host and standardized contract assertions
are not implemented yet.

**Step 3: Implement the command and process substrate**

- implement `CommandHost` for one-shot and PTY-backed command sessions
- implement `ProcessHost` plus `ProcessRegistry` for detached processes
- persist command/process handle metadata into `resource_handles`
- report `process_started`, `process_output`, `process_exited`, and close
  events through the outbox
- keep CoreMatrix-side provisioning on public IDs only and remove any need for
  runtime-side `command_runs#create` or `process_runs#create`

**Step 4: Re-run the tests to verify they pass**

Run the same commands from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/resources/command_host.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/resources/process_host.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/resources/process_registry.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/tools/exec_command.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/tools/process_tools.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/resources/command_host_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/resources/process_host_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/tools/exec_command_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/tools/process_tools_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/tool_call_runners/execution_runtime_mediated.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_tool_contracts/command_and_process_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/tool_call_runners_test.rb
git commit -m "feat: standardize runtime command and process contracts"
```

### Task 6: Port execution assignment dispatch, close handling, and attachments to the new protocol

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/assignment_executor.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/close_request_executor.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/attachments/client.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/mailbox/assignment_executor_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/mailbox/close_request_executor_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/attachments/client_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/attachments_controller.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_execution_assignment_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/shared/fixtures/contracts/core_matrix_nexus_execution_assignment.json`

**Step 1: Write the failing assignment and attachment tests**

Lock the new envelope and handler behavior:

```ruby
assert_equal "command-run-public-id",
  serialized.dig("payload", "runtime_resource_refs", "command_run", "command_run_id")
assert_equal "events/batch",
  serialized.dig("payload", "runtime_context", "event_submission_path")
```

Add Nexus-side tests that assert:

- assignment execution sends `execution_started`
- tool progress gets queued into the outbox as `execution_progress`
- terminal outcomes become `execution_complete` or `execution_fail`
- `resource_close_request` reaches the correct local handle and produces the
  right close event sequence
- attachment refresh and upload use public IDs only

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/agent_control/create_execution_assignment_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest \
  test/mailbox/assignment_executor_test.rb \
  test/mailbox/close_request_executor_test.rb \
  test/attachments/client_test.rb
```

Expected: FAIL because the new envelope fields and executors do not exist yet.

**Step 3: Implement the new assignment path**

- update CoreMatrix mailbox serialization so assignments carry:
  - runtime resource refs
  - transport hints
  - event submission hints
  - attachment refresh/upload hints
- implement Nexus mailbox executors for:
  - `execution_assignment`
  - `resource_close_request`
- keep close strictness semantics explicit and durable
- narrow the attachment API surface to refresh and upload instead of general
  runtime-side resource provisioning

**Step 4: Re-run the tests to verify they pass**

Run the same commands from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/assignment_executor.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/close_request_executor.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/attachments/client.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/mailbox/assignment_executor_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/mailbox/close_request_executor_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/attachments/client_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/serialize_mailbox_item.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/attachments_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_execution_assignment_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/shared/fixtures/contracts/core_matrix_nexus_execution_assignment.json
git commit -m "feat: port runtime assignment and attachment execution flow"
```

### Task 7: Port filesystem memory, skills, and browser hosting into the new runtime kernel

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/memory/store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/catalog.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/repository.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/install.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/host.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/session_registry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/memory/store_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/catalog_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/install_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/browser/host_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/runtime_manifest.rb`

**Step 1: Write the failing portability tests**

Cover:

- filesystem-backed memory round-trip under `NEXUS_HOME_ROOT`
- skill discovery and package validation from runtime-local storage
- skill install idempotency
- browser host capability gating and session lifecycle
- manifest capability payload reflecting browser availability and attachment
  support flags

Example:

```ruby
result = CybrosNexus::Memory::Store.new(
  workspace_root: tmp_path("workspace"),
  conversation_id: "conv_123"
).write("summary.md", "hello")

assert_equal "hello", result.fetch("content")
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest \
  test/memory/store_test.rb \
  test/skills/catalog_test.rb \
  test/skills/install_test.rb \
  test/browser/host_test.rb
```

Expected: FAIL because the new memory, skills, and browser classes do not
exist.

**Step 3: Implement the runtime-local surfaces**

- port memory to the new runtime root and workspace context contract
- port skills with explicit repository and install boundaries
- implement browser hosting as a distinct isolated subsystem, optionally under
  a dedicated role if the process boundary proves cleaner
- make the runtime manifest advertise capability flags directly from the new
  implementation

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/memory/store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/catalog.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/repository.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/install.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/host.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/session_registry.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/memory/store_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/catalog_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/install_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/browser/host_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/runtime_manifest.rb
git commit -m "feat: port nexus memory skills and browser surfaces"
```

### Task 8: Remove the legacy Rails runtime, update docs and CI, and run the destructive cutover verification

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/root_layout_contract_test.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old/`

**Step 1: Write the failing contract and layout tests**

Add or update tests that assert:

- the monorepo points to `execution_runtimes/nexus` as the active runtime gem
- CI runs the new Nexus verification command instead of Rails-app-specific
  checks
- no docs or tests still reference `nexus.old`
- README and AGENTS verification commands match the rebuilt gem

Start with assertions like:

```ruby
assert_includes agents_doc, "### `execution_runtimes/nexus`"
assert_includes workflow, "execution_runtimes/nexus/*)"
refute_includes workflow, "bin/rails db:test:prepare"
```

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/root_layout_contract_test.rb
```

Expected: FAIL because the docs and CI still describe the old runtime shape.

**Step 3: Update docs, CI, and remove the old tree**

- update monorepo docs and verification commands to match the rebuilt gem
- update CI path detection and verification commands
- delete `execution_runtimes/nexus.old/`
- make the new Nexus README document:
  - `bundle exec ./exe/nexus run`
  - required env
  - state root
  - verification command

**Step 4: Run the project and monorepo verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest -e 'Dir["test/**/*_test.rb"].sort.each { |f| require File.expand_path(f) }'

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system

cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh
```

Expected: PASS, with artifacts and resulting database state manually inspected
before calling the cutover complete.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/AGENTS.md \
  /Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/root_layout_contract_test.rb
git add -u /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old
git commit -m "refactor: cut over to the rebuilt nexus runtime"
```

Plan complete and saved to `docs/plans/2026-04-18-nexus-runtime-redesign-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
