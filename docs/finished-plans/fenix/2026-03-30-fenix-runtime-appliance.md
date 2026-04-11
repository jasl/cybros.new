# Fenix Runtime Appliance Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn `agents/fenix` from the current validated runtime into a distributable Ubuntu 24.04 runtime appliance with pluggable environment tools, `.fenix` workspace state, Firecrawl-backed web capabilities, browser automation, and `ProcessRun`-aligned long-lived service support.

**Architecture:** Keep the shipped product as one default Fenix runtime service while separating agent-plane logic from execution-plane logic inside the implementation. Replace the current hardcoded tool catalog with a registry-backed composition model, keep Core Matrix reserved tools outside the plugin collision domain, and split attached command execution from long-lived process execution.

**Tech Stack:** Ruby on Rails, Ubuntu 24.04, Ruby 4.0.x, Node.js LTS, npm, pnpm, Python, uv, Chromium, Playwright, Caddy, Firecrawl, Core Matrix runtime capability contract, Rails integration tests.

---

## Preconditions

- This plan has been revalidated against the current validated runtime baseline.
  Execute it from the current runtime-control/resource-contract shape instead
  of the older minimal-runtime assumptions.
- The following are already landed and should be treated as baseline, not
  greenfield work:
  - websocket-first mailbox control
  - `runtime:control_loop_forever`
  - `ToolInvocation` / `CommandRun` / `ProcessRun` create APIs
  - `exec_command`, `write_stdin`, and `process_exec`
  - skill loading and install flows
- The following still need implementation and remain in scope for this plan:
  - runtime foundation metadata and packaging
  - plugin-registry-backed manifest composition
  - `.fenix` workspace bootstrap and OpenClaw-style memory overlay
  - local web/browser/proxy surfaces
- Re-read the current versions of:
  - `app/services/fenix/runtime/pairing_manifest.rb`
  - `app/services/fenix/runtime/control_loop.rb`
  - `app/services/fenix/runtime/control_worker.rb`
  - `app/services/fenix/runtime/execute_assignment.rb`
  - `app/services/fenix/processes/manager.rb`
  - `app/services/fenix/runtime_surface/report_collector.rb`
  - `test/integration/external_runtime_pairing_test.rb`
  - `test/integration/runtime_flow_test.rb`
  - `../core_matrix/docs/behavior/agent-runtime-resource-apis.md`
  - `../core_matrix/docs/behavior/workflow-artifacts-node-events-and-process-runs.md`
- If the runtime contract changed materially, update this plan before writing
  implementation code.

### Task 1: Establish runtime bootstrap and package layout

**Files:**
- Modify: `Dockerfile`
- Modify: `README.md`
- Create: `scripts/bootstrap-runtime-deps.sh`
- Create: `scripts/bootstrap-runtime-deps-darwin.sh`
- Create: `.node-version`
- Create: `.python-version`
- Test: `test/integration/runtime_foundation_test.rb`

**Step 1: Write the failing test**

Add an integration test that asserts the runtime foundation surface exposes the
expected bootstrap metadata, for example:

```ruby
test "runtime foundation metadata exposes supported local toolchains" do
  get "/runtime/manifest"

  body = JSON.parse(response.body)
  foundation = body.fetch("executor_capability_payload").fetch("runtime_foundation")

  assert_equal "ubuntu-24.04", foundation.fetch("base_image")
  assert_includes foundation.fetch("toolchains"), "ruby"
  assert_includes foundation.fetch("toolchains"), "node"
  assert_includes foundation.fetch("toolchains"), "python"
end
```

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/runtime_foundation_test.rb`
Expected: FAIL because the manifest does not yet expose runtime foundation data.

**Step 3: Write minimal implementation**

- Switch `Dockerfile` to an Ubuntu 24.04 base.
- Add `scripts/bootstrap-runtime-deps.sh` as the shared package install entry.
- Add minimal version pin files for Node and Python.
- Extend runtime capability payload with bootstrap/toolchain metadata.

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/integration/runtime_foundation_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add Dockerfile README.md scripts/bootstrap-runtime-deps.sh scripts/bootstrap-runtime-deps-darwin.sh .node-version .python-version test/integration/runtime_foundation_test.rb
git commit -m "plan: establish fenix runtime foundation"
```

### Task 2: Introduce registry-backed tool and plugin composition

**Files:**
- Create: `app/services/fenix/plugins/manifest.rb`
- Create: `app/services/fenix/plugins/registry.rb`
- Create: `app/services/fenix/plugins/catalog.rb`
- Create: `app/services/fenix/plugins/system/exec_command/plugin.yml`
- Create: `app/services/fenix/plugins/system/workspace/plugin.yml`
- Create: `app/services/fenix/plugins/system/memory/plugin.yml`
- Modify: `app/services/fenix/runtime/pairing_manifest.rb`
- Test: `test/services/fenix/plugins/registry_test.rb`
- Test: `test/integration/external_runtime_pairing_test.rb`

**Step 1: Write the failing tests**

Add unit and integration coverage for registry-backed manifest composition:

```ruby
test "registry composes agent and environment catalogs from plugin manifests" do
  registry = Fenix::Plugins::Registry.default
  catalog = registry.catalog

  assert catalog.execution_tool_names.include?("exec_command")
  assert catalog.execution_tool_names.include?("write_stdin")
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/plugins/registry_test.rb test/integration/external_runtime_pairing_test.rb`
Expected: FAIL because the plugin registry does not yet exist.

**Step 3: Write minimal implementation**

- Add plugin manifest parsing and registry loading.
- Move ordinary tool declarations out of static manifest constants.
- Accept the broader manifest schema even when some surfaces remain stub/no-op
  in the first cut.
- Keep Core Matrix reserved tools and built-in hook tools outside the normal
  plugin collision path.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/plugins/registry_test.rb test/integration/external_runtime_pairing_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/plugins app/services/fenix/runtime/pairing_manifest.rb test/services/fenix/plugins/registry_test.rb test/integration/external_runtime_pairing_test.rb
git commit -m "plan: compose fenix tools from plugin registry"
```

### Task 3: Add `.fenix` workspace bootstrap and prompt/memory overlay

**Files:**
- Create: `app/services/fenix/workspace/bootstrap.rb`
- Create: `app/services/fenix/workspace/env_overlay.rb`
- Create: `app/services/fenix/workspace/layout.rb`
- Create: `app/services/fenix/memory/store.rb`
- Create: `app/services/fenix/prompts/assembler.rb`
- Create: `prompts/SOUL.md`
- Create: `prompts/USER.md`
- Modify: `app/services/fenix/context/build_execution_context.rb`
- Test: `test/services/fenix/workspace/bootstrap_test.rb`
- Test: `test/services/fenix/workspace/env_overlay_test.rb`
- Test: `test/services/fenix/prompts/assembler_test.rb`

**Step 1: Write the failing tests**

Cover:

- `.fenix` bootstrap layout creation
- workspace root `.env` / `.env.agent` overlays
- conversation-scoped overlays
- prompt precedence without workspace `AGENTS.md`

Example:

```ruby
test "bootstrap seeds .fenix memory and conversation directories without workspace agents file" do
  root = Pathname.new(Dir.mktmpdir)

  Fenix::Workspace::Bootstrap.call(workspace_root: root, conversation_id: "conversation_123")

  assert root.join(".fenix/memory/root.md").exist?
  assert root.join(".fenix/conversations/conversation_123/meta.json").exist?
  refute root.join("AGENTS.md").exist?
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/workspace/bootstrap_test.rb test/services/fenix/workspace/env_overlay_test.rb test/services/fenix/prompts/assembler_test.rb`
Expected: FAIL because the workspace bootstrap and overlay services do not yet exist.

**Step 3: Write minimal implementation**

- Create `.fenix` bootstrap services.
- Keep `AGENTS.md` code-owned.
- Allow `SOUL.md`, `USER.md`, and `MEMORY.md` root overrides.
- Follow the OpenClaw memory split:
  - concise root bootstrap files
  - curated long-term `MEMORY.md`
  - non-injected daily memory files under `.fenix/memory/daily/`
- Add conversation metadata caching in `.fenix/conversations/<public_id>/meta.json`.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/workspace/bootstrap_test.rb test/services/fenix/workspace/env_overlay_test.rb test/services/fenix/prompts/assembler_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/workspace app/services/fenix/memory/store.rb app/services/fenix/prompts/assembler.rb prompts/SOUL.md prompts/USER.md test/services/fenix/workspace/bootstrap_test.rb test/services/fenix/workspace/env_overlay_test.rb test/services/fenix/prompts/assembler_test.rb
git commit -m "plan: add fenix workspace bootstrap and prompt overlay"
```

### Task 4: Refactor attached command tools behind pluggable runtimes

**Files:**
- Create: `app/services/fenix/plugins/system/exec_command/runtime.rb`
- Modify: `app/services/fenix/runtime/execute_assignment.rb`
- Modify: `app/services/fenix/hooks/project_tool_result.rb`
- Modify: `app/services/fenix/hooks/review_tool_call.rb`
- Test: `test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `test/integration/runtime_flow_test.rb`

**Step 1: Write the failing tests**

Cover:

- `exec_command` command execution
- streamed stdout/stderr progress
- PTY command handoff via durable `command_run_id`
- `write_stdin` polling and write behavior

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/runtime/execute_assignment_test.rb test/integration/runtime_flow_test.rb`
Expected: FAIL because the attached command path is still wired directly inside
`ExecuteAssignment` rather than through plugin runtime composition.

**Step 3: Write minimal implementation**

- Preserve the existing external tool names and the `CommandRun` contract.
- Move command execution out of the direct `ExecuteAssignment` branch logic into
  the `exec_command` plugin runtime.
- Keep streamed output on the `runtime.tool_invocation.output` path.
- Support `write_stdin` only for PTY-backed attached sessions.
- Keep terminal tool payloads summary-only.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/runtime/execute_assignment_test.rb test/integration/runtime_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/plugins/system/exec_command/runtime.rb app/services/fenix/runtime/execute_assignment.rb app/services/fenix/hooks/project_tool_result.rb app/services/fenix/hooks/review_tool_call.rb test/services/fenix/runtime/execute_assignment_test.rb test/integration/runtime_flow_test.rb
git commit -m "plan: pluginize exec command tools"
```

### Task 5: Add workspace and memory tool plugins

**Files:**
- Create: `app/services/fenix/plugins/system/workspace/runtime.rb`
- Create: `app/services/fenix/plugins/system/memory/runtime.rb`
- Modify: `app/services/fenix/runtime/execute_assignment.rb`
- Test: `test/integration/workspace_flow_test.rb`
- Test: `test/integration/memory_flow_test.rb`

**Step 1: Write the failing tests**

Add coverage for:

- workspace file reads/writes inside the mounted root
- path rejection outside the allowed workspace
- `memory_get`
- `memory_search`
- `memory_store`

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/workspace_flow_test.rb test/integration/memory_flow_test.rb`
Expected: FAIL because the workspace and memory plugins do not yet exist.

**Step 3: Write minimal implementation**

- Back workspace tools with the `.fenix` layout and explicit path policy.
- Back memory tools with workspace root and conversation-local files.
- Ensure the plugin runtime integrates with the same tool invocation and error
  reporting path as attached commands.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/integration/workspace_flow_test.rb test/integration/memory_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/plugins/system/workspace/runtime.rb app/services/fenix/plugins/system/memory/runtime.rb app/services/fenix/runtime/execute_assignment.rb test/integration/workspace_flow_test.rb test/integration/memory_flow_test.rb
git commit -m "plan: add workspace and memory plugins"
```

### Task 6: Add local `web_fetch` and Firecrawl-backed `web_search`

**Files:**
- Create: `app/services/fenix/web/fetch.rb`
- Create: `app/services/fenix/web/search.rb`
- Create: `app/services/fenix/web/firecrawl_client.rb`
- Create: `app/services/fenix/plugins/system/web/plugin.yml`
- Create: `app/services/fenix/plugins/system/web/runtime.rb`
- Modify: `README.md`
- Test: `test/services/fenix/web/fetch_test.rb`
- Test: `test/services/fenix/web/search_test.rb`
- Test: `test/integration/web_tools_flow_test.rb`

**Step 1: Write the failing tests**

Cover:

- local `web_fetch` extraction
- SSRF/private address rejection
- redirect policy
- Firecrawl-backed `web_search`
- explicit `firecrawl_search` and `firecrawl_scrape` tool behavior

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/web/fetch_test.rb test/services/fenix/web/search_test.rb test/integration/web_tools_flow_test.rb`
Expected: FAIL because no web service layer or plugin exists.

**Step 3: Write minimal implementation**

- Implement local `web_fetch`.
- Implement provider-backed `web_search` with Firecrawl as the first provider.
- Add Firecrawl-specific explicit tools.
- Document required env vars and config.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/web/fetch_test.rb test/services/fenix/web/search_test.rb test/integration/web_tools_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/web app/services/fenix/plugins/system/web README.md test/services/fenix/web/fetch_test.rb test/services/fenix/web/search_test.rb test/integration/web_tools_flow_test.rb
git commit -m "plan: add web fetch and firecrawl search plugins"
```

### Task 7: Add browser and Playwright plugin support

**Files:**
- Create: `app/services/fenix/browser/session_manager.rb`
- Create: `app/services/fenix/plugins/system/browser/plugin.yml`
- Create: `app/services/fenix/plugins/system/browser/runtime.rb`
- Modify: `Dockerfile`
- Modify: `README.md`
- Test: `test/services/fenix/browser/session_manager_test.rb`
- Test: `test/integration/browser_tools_flow_test.rb`

**Step 1: Write the failing tests**

Cover:

- browser session creation
- screenshot/page content interactions
- Playwright-backed navigation/action flows
- runtime manifest exposure for browser tools

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/browser/session_manager_test.rb test/integration/browser_tools_flow_test.rb`
Expected: FAIL because browser tooling is not yet implemented.

**Step 3: Write minimal implementation**

- Install Chromium and Playwright runtime support.
- Expose browser tools through a dedicated plugin.
- Keep browser automation separate from `web_fetch`.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/browser/session_manager_test.rb test/integration/browser_tools_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/browser app/services/fenix/plugins/system/browser Dockerfile README.md test/services/fenix/browser/session_manager_test.rb test/integration/browser_tools_flow_test.rb
git commit -m "plan: add browser and playwright plugin"
```

### Task 8: Refactor long-lived process tools and add fixed-port dev proxy

**Files:**
- Create: `app/services/fenix/processes/launcher.rb`
- Create: `app/services/fenix/processes/proxy_registry.rb`
- Create: `app/services/fenix/plugins/system/process/plugin.yml`
- Create: `app/services/fenix/plugins/system/process/runtime.rb`
- Create: `config/caddy/Caddyfile`
- Create: `bin/fenix-dev-proxy`
- Modify: `app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `README.md`
- Test: `test/services/fenix/processes/launcher_test.rb`
- Test: `test/services/fenix/processes/proxy_registry_test.rb`
- Test: `test/integration/process_tools_flow_test.rb`

**Step 1: Write the failing tests**

Cover:

- long-lived process launch registration
- `ProcessRun`-aligned identifiers and metadata
- proxy path registration
- close request compatibility expectations

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/processes/launcher_test.rb test/services/fenix/processes/proxy_registry_test.rb test/integration/process_tools_flow_test.rb`
Expected: FAIL because the long-lived process path is not yet expressed as a
plugin/runtime family and no proxy registry exists.

**Step 3: Write minimal implementation**

- Preserve the current `process_exec` name and `ProcessRun`-first contract.
- Introduce a distinct long-lived process plugin/runtime family.
- Keep attached command tools separate.
- Wire process-backed routes into a fixed-port Caddy proxy.
- Ensure the tool payloads carry enough metadata to reconcile with Core Matrix
  `ProcessRun` and close flows.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/processes/launcher_test.rb test/services/fenix/processes/proxy_registry_test.rb test/integration/process_tools_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/processes app/services/fenix/plugins/system/process config/caddy/Caddyfile bin/fenix-dev-proxy app/services/fenix/runtime/pairing_manifest.rb README.md test/services/fenix/processes/launcher_test.rb test/services/fenix/processes/proxy_registry_test.rb test/integration/process_tools_flow_test.rb
git commit -m "plan: add process tools and fixed-port dev proxy"
```

### Task 9: Finish distribution and verification

**Files:**
- Modify: `README.md`
- Modify: `Dockerfile`
- Create: `docker-compose.fenix.yml`
- Create: `test/integration/distribution_contract_test.rb`

**Step 1: Write the failing test**

Add a contract-style integration test that checks the runtime manifest and docs
agree on the supported deployment shape and required capabilities.

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/distribution_contract_test.rb`
Expected: FAIL because the final distribution contract does not yet exist.

**Step 3: Write minimal implementation**

- Document Compose deployment.
- Document Ubuntu 24.04 bare-metal requirements.
- Document macOS development caveats.
- Add a Compose sample for the default runtime service.

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/integration/distribution_contract_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add README.md Dockerfile docker-compose.fenix.yml test/integration/distribution_contract_test.rb
git commit -m "plan: document fenix distribution contract"
```

## Final Verification Sweep

Run from `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix`:

```bash
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
```

Expected:

- all tests pass
- manifest integration tests pass
- no regression in skill flow or runtime flow
- docs and manifest describe the same runtime/tool boundaries

## Execution Note

This plan intentionally assumes the repository shape visible on 2026-03-30.
Before implementation starts, regenerate or amend the plan if parallel refactors
changed:

- tool naming
- execution report structure
- plugin registry surfaces
- `ProcessRun` integration points
- workspace bootstrap paths
