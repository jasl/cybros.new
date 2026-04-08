# Fenix Operator Surface Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn the current `agents/fenix` runtime appliance into a coherent operator surface organized around `workspace`, `memory`, `command_run`, `process_run`, and `browser_session` instead of a flat tool catalog.

**Architecture:** Keep Core Matrix as the durable truth for `ToolInvocation`, `CommandRun`, and `ProcessRun`, and implement the operator experience entirely on the Fenix side. Extend the existing plugin-registry-backed manifest with additive operator metadata, add missing operator helper tools, and generate a runtime-local operator snapshot under `.fenix` for prompt/context assembly.

**Tech Stack:** Ruby on Rails, existing Fenix plugin registry, `.fenix` workspace bootstrap, `CommandRun` and `ProcessRun` runtime contracts, Playwright, Caddy, Rails integration tests, operator smoke scripts.

---

## Preconditions

- Execute this plan from the current post-appliance baseline, not from the
  older runtime-appliance design assumptions.
- The following are already landed and should be treated as baseline:
  - registry-backed manifest composition
  - `.fenix` workspace bootstrap
  - `exec_command`, `write_stdin`, and `process_exec`
  - browser, web, workspace, and memory plugins
  - Docker distribution contract and public base URL publication
- The following are intentionally out of scope and should remain deferred:
  - third-party plugin ecosystem expansion
  - approval/governance policy work
- Re-read before implementation:
  - `app/services/fenix/runtime/pairing_manifest.rb`
  - `app/services/fenix/context/build_execution_context.rb`
  - `app/services/fenix/prompts/assembler.rb`
  - `app/services/fenix/runtime/command_run_registry.rb`
  - `app/services/fenix/processes/manager.rb`
  - `app/services/fenix/browser/session_manager.rb`
  - `app/services/fenix/plugins/system/*/runtime.rb`
  - `test/integration/external_runtime_pairing_test.rb`
  - `test/integration/runtime_flow_test.rb`
  - `test/integration/workspace_flow_test.rb`
  - `test/integration/memory_flow_test.rb`
  - `test/integration/process_tools_flow_test.rb`
  - `test/integration/browser_tools_flow_test.rb`
- If the runtime contract changed materially, update this plan before writing
  implementation code.

### Task 1: Add operator grouping metadata to the manifest and plugin registry

**Files:**
- Create: `app/services/fenix/operator/catalog.rb`
- Modify: `app/services/fenix/plugins/manifest.rb`
- Modify: `app/services/fenix/plugins/catalog.rb`
- Modify: `app/services/fenix/runtime/pairing_manifest.rb`
- Modify: `app/services/fenix/plugins/system/*/plugin.yml`
- Test: `test/services/fenix/operator/catalog_test.rb`
- Test: `test/integration/external_runtime_pairing_test.rb`

**Step 1: Write the failing tests**

Add tests that assert the manifest exposes additive operator metadata, for
example:

```ruby
test "pairing manifest exposes operator groups for execution tools" do
  get "/runtime/manifest"

  body = JSON.parse(response.body)
  groups = body.fetch("operator_groups")

  assert_includes groups.keys, "workspace"
  assert_includes groups.keys, "command_run"
  assert body.fetch("executor_tool_catalog").any? { |entry| entry["operator_group"] == "workspace" }
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/operator/catalog_test.rb test/integration/external_runtime_pairing_test.rb`
Expected: FAIL because operator grouping metadata does not yet exist.

**Step 3: Write minimal implementation**

- Add an operator catalog service that maps tool names to operator groups.
- Extend plugin-manifest parsing to retain additive fields such as:
  - `operator_group`
  - `resource_identity_kind`
  - `mutates_state`
  - `supports_streaming_output`
- Publish `operator_groups` from the pairing manifest without breaking the
  existing `tool_catalog` contract.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/operator/catalog_test.rb test/integration/external_runtime_pairing_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/operator/catalog.rb app/services/fenix/plugins/manifest.rb app/services/fenix/plugins/catalog.rb app/services/fenix/runtime/pairing_manifest.rb app/services/fenix/plugins/system test/services/fenix/operator/catalog_test.rb test/integration/external_runtime_pairing_test.rb
git commit -m "plan: add fenix operator catalog metadata"
```

### Task 2: Expand workspace and memory into discoverable operator families

**Files:**
- Modify: `app/services/fenix/plugins/system/workspace/plugin.yml`
- Modify: `app/services/fenix/plugins/system/workspace/runtime.rb`
- Modify: `app/services/fenix/plugins/system/memory/plugin.yml`
- Modify: `app/services/fenix/plugins/system/memory/runtime.rb`
- Modify: `app/services/fenix/workspace/layout.rb`
- Modify: `app/services/fenix/memory/store.rb`
- Test: `test/integration/workspace_flow_test.rb`
- Test: `test/integration/memory_flow_test.rb`

**Step 1: Write the failing tests**

Add coverage for the missing operator helpers:

- `workspace_tree`
- `workspace_find`
- `workspace_stat`
- `memory_list`
- `memory_append_daily`
- `memory_compact_summary`

Example:

```ruby
test "workspace_tree returns a bounded directory summary rooted under workspace" do
  result = invoke_runtime_tool("workspace_tree", "path" => ".")

  assert_equal true, result.fetch("ok")
  assert_includes result.fetch("payload").keys, "entries"
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/workspace_flow_test.rb test/integration/memory_flow_test.rb`
Expected: FAIL because the new operator helper tools do not yet exist.

**Step 3: Write minimal implementation**

- Extend the workspace runtime with tree/find/stat helpers.
- Extend the memory runtime with memory inventory, daily append, and summary
  writeback helpers.
- Keep all writes rooted under the existing `.fenix` layout and conversation
  directories.
- Keep output bounded and operator-readable instead of dumping large blobs.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/integration/workspace_flow_test.rb test/integration/memory_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/plugins/system/workspace/plugin.yml app/services/fenix/plugins/system/workspace/runtime.rb app/services/fenix/plugins/system/memory/plugin.yml app/services/fenix/plugins/system/memory/runtime.rb app/services/fenix/workspace/layout.rb app/services/fenix/memory/store.rb test/integration/workspace_flow_test.rb test/integration/memory_flow_test.rb
git commit -m "plan: expand fenix workspace and memory operator tools"
```

### Task 3: Add lifecycle helpers for attached CommandRun sessions

**Files:**
- Modify: `app/services/fenix/plugins/system/exec_command/plugin.yml`
- Modify: `app/services/fenix/plugins/system/exec_command/runtime.rb`
- Modify: `app/services/fenix/runtime/command_run_registry.rb`
- Test: `test/services/fenix/runtime/command_run_registry_test.rb`
- Test: `test/integration/runtime_flow_test.rb`

**Step 1: Write the failing tests**

Cover new operator helpers:

- `command_run_wait`
- `command_run_read_output`
- `command_run_terminate`
- `command_run_list`

Include one test that starts a PTY-backed command and terminates it explicitly.

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/runtime/command_run_registry_test.rb test/integration/runtime_flow_test.rb`
Expected: FAIL because the attached-command operator helpers do not yet exist.

**Step 3: Write minimal implementation**

- Extend the exec-command runtime to route the new helper tool names.
- Teach the command-run registry to enumerate active sessions and expose
  buffered output summaries.
- Keep streamed output ephemeral and terminal payloads compact.
- Ensure terminate semantics still reconcile with the existing `CommandRun` and
  `ToolInvocation` contract.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/runtime/command_run_registry_test.rb test/integration/runtime_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/plugins/system/exec_command/plugin.yml app/services/fenix/plugins/system/exec_command/runtime.rb app/services/fenix/runtime/command_run_registry.rb test/services/fenix/runtime/command_run_registry_test.rb test/integration/runtime_flow_test.rb
git commit -m "plan: add command run operator helpers"
```

### Task 4: Add inspection helpers for ProcessRun and browser sessions

**Files:**
- Modify: `app/services/fenix/plugins/system/process/plugin.yml`
- Modify: `app/services/fenix/plugins/system/process/runtime.rb`
- Modify: `app/services/fenix/processes/manager.rb`
- Modify: `app/services/fenix/processes/proxy_registry.rb`
- Modify: `app/services/fenix/plugins/system/browser/plugin.yml`
- Modify: `app/services/fenix/plugins/system/browser/runtime.rb`
- Modify: `app/services/fenix/browser/session_manager.rb`
- Test: `test/integration/process_tools_flow_test.rb`
- Test: `test/integration/browser_tools_flow_test.rb`

**Step 1: Write the failing tests**

Cover:

- `process_list`
- `process_read_output`
- `process_proxy_info`
- `browser_list`
- `browser_session_info`

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/process_tools_flow_test.rb test/integration/browser_tools_flow_test.rb`
Expected: FAIL because these inspection helpers do not yet exist.

**Step 3: Write minimal implementation**

- Extend detached-process runtime support with read-only inspection helpers.
- Keep detached-process close kernel-driven; do not add a competing local close
  tool in this plan.
- Extend the browser runtime and session manager with session listing and info
  helpers.
- Keep browser screenshots and content reads as separate explicit operations.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/integration/process_tools_flow_test.rb test/integration/browser_tools_flow_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/plugins/system/process/plugin.yml app/services/fenix/plugins/system/process/runtime.rb app/services/fenix/processes/manager.rb app/services/fenix/processes/proxy_registry.rb app/services/fenix/plugins/system/browser/plugin.yml app/services/fenix/plugins/system/browser/runtime.rb app/services/fenix/browser/session_manager.rb test/integration/process_tools_flow_test.rb test/integration/browser_tools_flow_test.rb
git commit -m "plan: add process and browser operator inspection tools"
```

### Task 5: Add operator prompt and `.fenix` snapshot assembly

**Files:**
- Create: `app/services/fenix/operator/snapshot.rb`
- Create: `prompts/OPERATOR.md`
- Modify: `app/services/fenix/context/build_execution_context.rb`
- Modify: `app/services/fenix/prompts/assembler.rb`
- Modify: `app/services/fenix/workspace/bootstrap.rb`
- Test: `test/services/fenix/operator/snapshot_test.rb`
- Test: `test/services/fenix/prompts/assembler_test.rb`

**Step 1: Write the failing tests**

Cover:

- operator snapshot file generation under
  `.fenix/conversations/<public_id>/context/operator_state.json`
- prompt assembly includes the operator guidance fragment for the main profile
- prompt assembly does not inline raw process output or huge workspace dumps

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/fenix/operator/snapshot_test.rb test/services/fenix/prompts/assembler_test.rb`
Expected: FAIL because the operator snapshot and prompt fragment do not yet
exist.

**Step 3: Write minimal implementation**

- Build an operator snapshot service that summarizes active command runs,
  process runs, browser sessions, memory inventory, and workspace highlights.
- Write the snapshot into the existing `.fenix` conversation context tree.
- Add a short built-in operator guidance prompt fragment.
- Include the operator snapshot in context assembly for the main operator path.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/fenix/operator/snapshot_test.rb test/services/fenix/prompts/assembler_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add app/services/fenix/operator/snapshot.rb prompts/OPERATOR.md app/services/fenix/context/build_execution_context.rb app/services/fenix/prompts/assembler.rb app/services/fenix/workspace/bootstrap.rb test/services/fenix/operator/snapshot_test.rb test/services/fenix/prompts/assembler_test.rb
git commit -m "plan: add fenix operator snapshot and prompt layer"
```

### Task 6: Add real operator smoke scenarios and documentation

**Files:**
- Create: `script/manual/operator_surface_smoke.rb`
- Modify: `README.md`
- Modify: `test/integration/distribution_contract_test.rb`
- Test: `test/integration/distribution_contract_test.rb`

**Step 1: Write the failing tests**

Add or extend contract coverage so the README and runtime surface both describe
the operator families and the explicit smoke path.

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/integration/distribution_contract_test.rb`
Expected: FAIL because the current docs do not yet describe the operator smoke
surface.

**Step 3: Write minimal implementation**

- Add one manual smoke script that exercises:
  - workspace discovery
  - memory inventory
  - interactive command lifecycle
  - detached process inspection
  - browser session inspection
- Update the README to describe the operator object families and the smoke
  workflow.

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/integration/distribution_contract_test.rb`
Expected: PASS

**Step 5: Commit**

```bash
git add script/manual/operator_surface_smoke.rb README.md test/integration/distribution_contract_test.rb
git commit -m "plan: add fenix operator surface smoke coverage"
```

## Final Verification Sweep

Run from `agents/fenix`:

```bash
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare test
bin/ci
```

Then run real smoke validation:

```bash
docker compose -f docker-compose.fenix.yml up --build -d
bin/rails runner script/manual/operator_surface_smoke.rb
docker compose -f docker-compose.fenix.yml down -v
```

Expected results:

- all automated checks pass
- the manifest publishes operator grouping metadata
- operator helper tools behave consistently across workspace, memory, command,
  process, and browser families
- Docker smoke validation proves the surface works in the shipped appliance

## Execution Note

The runtime appliance plan is now finished. This follow-up should be treated as
the next Fenix-focused execution plan, not as part of the already-closed
runtime-appliance batch.
