# Nexus Runtime Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild `execution_runtimes/nexus` into the only active Nexus runtime as a distributable Ruby 4.0 gem with a single `nexus run` entrypoint, full functional parity with `nexus.old`, websocket-first runtime delivery, durable local recovery, and a cleaned-up CoreMatrix execution-runtime protocol.

**Architecture:** Treat `execution_runtimes/nexus.old` as the capability source only, then rebuild Nexus around a monorepo-owned gem, a supervised runtime kernel, durable SQLite-backed local state, a websocket-first mailbox control plane, and explicit resource hosts for command, process, browser, skill, and memory surfaces. In parallel, collapse the CoreMatrix runtime protocol from the current registration/capabilities/poll/report/resource-controller mix into a smaller `session`, `mailbox`, `events`, and attachment surface while keeping CoreMatrix as the sole owner of public identifiers and orchestration state.

**Tech Stack:** Ruby 4.0.2, Bundler gem layout, Thor, SQLite3, Action Cable websocket protocol, Net::HTTP or async HTTP client adapters, Minitest, existing CoreMatrix Rails app, existing verification harness, filesystem-backed skills and memory.

---

**Execution notes:**

- Follow `@test-driven-development` for each behavior change.
- Execute this plan from an isolated execution workspace. As of
  `2026-04-18`, the rewrite was started from a dedicated branch
  `codex/nexus-runtime-rewrite` in the main checkout rather than a separate
  worktree, so all commits must continue to use explicit path-based staging.
- Use the approved design at
  `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-18-nexus-runtime-redesign-design.md`
  as the architecture baseline.
- Do not stage unrelated worktree files. Even when the checkout starts clean,
  all commits for this rewrite must continue to stage only the intended target
  paths.
- At execution start, `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.git`
  was already absent, so Task 1 should treat monorepo ownership of the rebuilt
  gem tree as an invariant rather than a pending cleanup step.
- Keep Action Cable as the primary low-latency path. Poll remains fallback and
  recovery infrastructure and should never become the only happy-path design.
- Final delivery must not keep compatibility shims, but the implementation
  sequence may temporarily keep old and new CoreMatrix runtime endpoints alive
  until all callers, harnesses, and tests have moved. Do not delete the legacy
  surface before the new surface is exercised end-to-end.
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
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb:6-24`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/create_execution_assignment_test.rb:54-258`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/fake_agent_runtime_harness.rb:91-168`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/registrations_test.rb:3-116`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/capabilities_test.rb:3-65`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/control_poll_test.rb:3-113`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/command_runs_controller_test.rb:3-220`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runs_controller_test.rb:3-150`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/resource_close_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runtime_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_registration_contract_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_runtime_resource_api_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtime_versions/register_test.rb`
- `/Users/jasl/Workspaces/Ruby/cybros/shared/fixtures/contracts/core_matrix_nexus_execution_assignment.json`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/cybros_nexus.gemspec:1-32`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Gemfile:1-10`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus.rb:1-6`
- `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/test_helper.rb:1-4`

When a task below says "Modify" for one of these files without repeating a line
range, use the anchor list above as the verified current-file starting point
before editing.

### Task 0: Normalize the rewrite starting point and isolate the execution workspace

**Goal:** Make the current `nexus.old` + new `nexus/` layout reproducible and
execute the rewrite from a clean isolated branch boundary instead of from a
mixed checkout.

**Step 1: Verify the expected starting layout exists**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
test -d execution_runtimes/nexus.old
test -d execution_runtimes/nexus
test -f execution_runtimes/nexus.old/README.md
test -f execution_runtimes/nexus/cybros_nexus.gemspec
git status --short
```

Expected: the old Rails runtime is present at `execution_runtimes/nexus.old/`,
the new gem stub is present at `execution_runtimes/nexus/`, and the current
checkout state is understood before any implementation commits are made.

**Step 2: Create an isolated execution workspace**

- If the current checkout already contains unrelated staged or unstaged work,
  isolate the rewrite before Task 1 by switching to a dedicated branch or by
  otherwise ensuring commits can be staged by explicit target path only.
- If the selected execution workspace does not yet contain the `nexus.old`
  rename and the new `nexus/` gem stub, recreate that starting layout
  intentionally before continuing.
- Do not begin Task 1 until the selected workspace contains both directories
  and no unrelated staged changes that would leak into the task commits.

**Step 3: Record the starting assumption**

Before Task 1, note in the execution log or task journal which workspace will
carry the rewrite and whether `execution_runtimes/nexus/.git` is still present.
For the `2026-04-18` execution, the selected workspace is branch
`codex/nexus-runtime-rewrite` in the main checkout, and
`execution_runtimes/nexus/.git` is already absent.

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

**Step 3: Confirm monorepo ownership and implement the minimal boot path**

- confirm `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/.git`
  is absent before continuing
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
- add a minimal CLI that preserves the user-facing `nexus run` contract while
  using Thor-compatible internal command naming where needed, plus a root
  `version` command
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
bundle exec ruby -Itest -e 'ARGV.each { |file| require File.expand_path(file) }' \
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

### Task 3: Add the new CoreMatrix `session`, `mailbox`, and `events` protocol surface without deleting the old one yet

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

Do not delete the old controllers in this task. The legacy surface stays
temporarily so the next task can migrate all callers, support harnesses, and
request/integration coverage onto the new protocol cleanly.

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
git commit -m "feat: add the new runtime session mailbox and events api"
```

### Task 4: Migrate CoreMatrix callers, support harnesses, and legacy request coverage to the new protocol, then delete the old surface

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/fake_agent_runtime_harness.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/registrations_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/capabilities_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/control_poll_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/command_runs_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runs_controller_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/resource_close_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/execution_delivery_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_registration_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_runtime_resource_api_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtime_versions/register_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/poll_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/serialize_mailbox_items_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/retry_semantics_e2e_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/runtime_capability_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/capabilities_controller.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/control_controller.rb`

**Step 1: Write the failing migration and cleanup tests**

Update the existing harness and request tests so they now expect:

- `session/open` and `session/refresh` instead of `registrations` and
  `capabilities`
- `mailbox/pull` instead of `control/poll`
- `events/batch` instead of `control/report`
- no remaining `command_runs` or `process_runs` provisioning requests from the
  runtime side
- no remaining `capabilities_refresh_request` mailbox item type usage

Add at least one route-level contract assertion that fails if these old
runtime-only paths remain:

```ruby
assert_raises(ActionController::RoutingError) do
  Rails.application.routes.recognize_path("/execution_runtime_api/control/poll", method: :post)
end

assert_raises(ActionController::RoutingError) do
  Rails.application.routes.recognize_path("/execution_runtime_api/registrations", method: :post)
end
```

Also add an explicit runtime-protocol sweep step to the migration task notes:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
rg -n "execution_runtime_api/(registrations|capabilities|control|command_runs|process_runs)|command_run_create|process_run_create|execution_runtime_registration|capabilities_refresh_request" \
  core_matrix/app/controllers/execution_runtime_api \
  core_matrix/config/routes.rb \
  core_matrix/test/requests/execution_runtime_api \
  core_matrix/test/requests/agent_api \
  core_matrix/test/support/fake_agent_runtime_harness.rb \
  core_matrix/test/integration/agent_registration_contract_test.rb \
  core_matrix/test/integration/agent_runtime_resource_api_test.rb
```

Do not use repo-wide `capabilities_handshake` or `capabilities_refresh` greps
as deletion signals. Agent-side protocol methods under `agent_api`,
`AgentDefinitionVersions`, and generic helper defaults remain valid unless they
are explicitly brought into this runtime-protocol migration.

The task is not done until every remaining runtime-protocol hit is either
rewritten for the new runtime protocol or deleted.

**Step 2: Run the tests to verify they fail**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/requests/execution_runtime_api/registrations_test.rb \
  test/requests/execution_runtime_api/capabilities_test.rb \
  test/requests/execution_runtime_api/control_poll_test.rb \
  test/requests/agent_api/command_runs_controller_test.rb \
  test/requests/agent_api/process_runs_controller_test.rb \
  test/requests/agent_api/resource_close_test.rb \
  test/requests/agent_api/process_runtime_test.rb \
  test/requests/agent_api/execution_delivery_test.rb \
  test/integration/agent_registration_contract_test.rb \
  test/integration/agent_runtime_resource_api_test.rb \
  test/services/installations/register_bundled_agent_runtime_test.rb \
  test/services/execution_runtime_versions/register_test.rb \
  test/services/agent_control/poll_test.rb \
  test/services/agent_control/report_test.rb \
  test/services/agent_control/serialize_mailbox_items_test.rb \
  test/e2e/protocol/mailbox_delivery_e2e_test.rb \
  test/e2e/protocol/retry_semantics_e2e_test.rb \
  test/e2e/protocol/conversation_close_e2e_test.rb \
  test/e2e/protocol/process_close_escalation_e2e_test.rb
```

Expected: FAIL because the support harnesses and request tests still target the
old protocol.

**Step 3: Migrate callers and remove the legacy protocol**

- update the fake runtime harness and any CoreMatrix-side test helpers to speak
  the new `session`, `mailbox`, and `events` API
- update the service and e2e suites that rely on the fake runtime harness or
  serialized mailbox envelopes so they prove the new runtime protocol rather
  than only the old controller names
- rewrite or delete request tests that only existed to prove runtime-side
  `command_runs#create` and `process_runs#create`
- remove `capabilities_refresh_request` from mailbox item types if it is no
  longer part of the redesigned runtime protocol
- delete the old registration, capabilities, and control controllers only after
  the harnesses and tests are already green on the new paths

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/fake_agent_runtime_harness.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/registrations_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/capabilities_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/control_poll_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/command_runs_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runs_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/resource_close_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/process_runtime_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/agent_api/execution_delivery_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_registration_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/agent_runtime_resource_api_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/execution_runtime_versions/register_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/poll_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/serialize_mailbox_items_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/mailbox_delivery_e2e_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/retry_semantics_e2e_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/conversation_close_e2e_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/e2e/protocol/process_close_escalation_e2e_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/runtime_capability_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb
git add -u /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/capabilities_controller.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/controllers/execution_runtime_api/control_controller.rb
git commit -m "refactor: migrate runtime callers and drop the old protocol"
```

### Task 5: Implement the websocket-first control role and poll fallback in the new gem

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
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/channels/control_plane_channel.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/publish_pending.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/publish_mailbox_lease_event.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/channels/control_plane_channel_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/publish_pending_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/publish_mailbox_lease_event_test.rb`

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
bundle exec ruby -Itest -e 'ARGV.each { |file| require File.expand_path(file) }' \
  test/session/client_test.rb \
  test/transport/action_cable_client_test.rb \
  test/mailbox/control_loop_test.rb \
  test/events/outbox_test.rb \
  test/http/server_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test \
  test/channels/control_plane_channel_test.rb \
  test/services/agent_control/publish_pending_test.rb \
  test/services/agent_control/publish_mailbox_lease_event_test.rb
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
- if protocol or payload details change the realtime happy path, update
  `ControlPlaneChannel`, `PublishPending`, and
  `PublishMailboxLeaseEvent` so CoreMatrix continues to publish runtime
  mailbox availability over Action Cable while poll remains the fallback

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
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/supervisor.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/channels/control_plane_channel.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/publish_pending.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/publish_mailbox_lease_event.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/channels/control_plane_channel_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/publish_pending_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/publish_mailbox_lease_event_test.rb
git commit -m "feat: add websocket-first nexus control role"
```

### Task 6: Standardize the command and process infrastructure contract and implement the resource host

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
bundle exec ruby -Itest -e 'ARGV.each { |file| require File.expand_path(file) }' \
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

### Task 7: Port execution assignment dispatch, close handling, and attachments to the new protocol

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
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/serialize_mailbox_items_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/attachments_controller_test.rb`
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
bin/rails test \
  test/services/agent_control/create_execution_assignment_test.rb \
  test/services/agent_control/serialize_mailbox_items_test.rb \
  test/requests/execution_runtime_api/attachments_controller_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec ruby -Itest -e 'ARGV.each { |file| require File.expand_path(file) }' \
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
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/serialize_mailbox_items_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/execution_runtime_api/attachments_controller_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/shared/fixtures/contracts/core_matrix_nexus_execution_assignment.json
git commit -m "feat: port runtime assignment and attachment execution flow"
```

### Task 8: Port filesystem memory, skills, and browser hosting into the new runtime kernel

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/memory/store.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/catalog.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/package_validator.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/repository.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/install.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/host.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/session_registry.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/scripts/browser/session_host.mjs`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/memory/store_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/catalog_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/install_test.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/browser/host_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/assignment_executor.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/cli.rb`
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
bundle exec ruby -Itest -e 'ARGV.each { |file| require File.expand_path(file) }' \
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
- wire skills and browser surfaces into the active runtime execution path so
  advertised capability is backed by live mailbox execution behavior
- make the runtime manifest advertise capability flags directly from the new
  implementation

**Step 4: Re-run the tests to verify they pass**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/memory/store.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/catalog.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/package_validator.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/repository.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/skills/install.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/host.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/browser/session_registry.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/scripts/browser/session_host.mjs \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/memory/store_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/catalog_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/skills/install_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/test/browser/host_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/mailbox/assignment_executor.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/cli.rb \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/lib/cybros_nexus/session/runtime_manifest.rb
git commit -m "feat: port nexus memory skills and browser surfaces"
```

### Task 9: Remove the legacy Rails runtime, update docs and CI, and run the destructive cutover verification

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/AGENTS.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/root_layout_contract_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/fake_agent_runtime_harness.rb`
- Delete: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old/`

**Step 1: Write the failing contract and layout tests**

Add or update tests that assert:

- the monorepo points to `execution_runtimes/nexus` as the active runtime gem
- CI runs the new Nexus verification command instead of Rails-app-specific
  checks
- active operator-facing docs, CI, and contract tests no longer point to
  `nexus.old` as a supported product path
- README and AGENTS verification commands match the rebuilt gem
- packaged-gem smoke instructions are documented with the installed `nexus`
  executable, not only `bundle exec ./exe/nexus`

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
- keep historical planning documents intact; the cleanup requirement only
  applies to active operator-facing docs, CI, and active contract tests
- delete `execution_runtimes/nexus.old/`
- make the new Nexus README document:
  - `nexus run` for installed-gem operators
  - `bundle exec ./exe/nexus run` only as the development workflow
  - required env
  - state root
  - verification command
  - packaged-gem smoke check from a clean temporary `GEM_HOME`

**Step 4: Run the project and monorepo verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus
bundle exec rake test
bundle exec rubocop
rm -rf tmp/package_smoke
mkdir -p tmp/package_smoke/gems tmp/package_smoke/home
rm -f cybros_nexus-*.gem
bundle exec gem build cybros_nexus.gemspec
GEM_HOME="$PWD/tmp/package_smoke/gems" \
GEM_PATH="$PWD/tmp/package_smoke/gems" \
gem install --no-document --install-dir "$PWD/tmp/package_smoke/gems" ./cybros_nexus-*.gem
HOME="$PWD/tmp/package_smoke/home" \
GEM_HOME="$PWD/tmp/package_smoke/gems" \
GEM_PATH="$PWD/tmp/package_smoke/gems" \
PATH="$PWD/tmp/package_smoke/gems/bin:$PATH" \
nexus --help
HOME="$PWD/tmp/package_smoke/home" \
GEM_HOME="$PWD/tmp/package_smoke/gems" \
GEM_PATH="$PWD/tmp/package_smoke/gems" \
PATH="$PWD/tmp/package_smoke/gems/bin:$PATH" \
nexus run --help

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system

cd /Users/jasl/Workspaces/Ruby/cybros
bash verification/bin/test_all.sh
ACTIVE_VERIFICATION_ENABLE_2048_CAPSTONE=1 bash verification/bin/run_active_suite.sh
```

Expected: PASS, with artifacts and resulting database state manually inspected
before calling the cutover complete. The packaged-gem smoke step must prove
that a clean `GEM_HOME` exposes the installed `nexus` executable successfully.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/AGENTS.md \
  /Users/jasl/Workspaces/Ruby/cybros/.github/workflows/ci.yml \
  /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/root_layout_contract_test.rb \
  /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/support/fake_agent_runtime_harness.rb
git add -u /Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus.old
git commit -m "refactor: cut over to the rebuilt nexus runtime"
```

Plan complete and saved to `docs/plans/2026-04-18-nexus-runtime-redesign-implementation.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

Which approach?
