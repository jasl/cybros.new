# Fenix Cowork V1 Implementation Plan

> `agents/fenix` is now the only cowork implementation in this repository.
> References to `agents/fenix.old` in this document are historical notes from
> the migration period; the legacy app has been removed.

## Goal

Build `agents/fenix` into a cowork-first bundled runtime that can complete the
`2048` acceptance capstone through `CoreMatrix` using native plan, delegation,
and delivery behavior rather than extra superpower-style workflow boosts.

## Architecture

Start by creating `images/nexus`, the Docker-only cowork runtime base image.
Then rebuild `agents/fenix` as a real bundled runtime with both program and
executor planes, persistent mailbox execution, and a minimal but sufficient
executor tool surface. After that, strengthen `CoreMatrix` with neutral work
context and delegation/result contracts. Finish by wiring a `fenix`-specific
2048 acceptance path that does not depend on `using-superpowers`, and then
register the new projects in root docs and CI.

## Tech Stack

- Ruby on Rails 8 API app: `agents/fenix`
- reference runtime source: `agents/fenix.old`
- runtime base image project: `images/nexus`
- Ruby on Rails 8 platform app: `core_matrix`
- Ubuntu 24.04 LTS Docker base
- Minitest
- JSON mailbox contracts
- acceptance harness Ruby scripts
- GitHub Actions monorepo CI

## V1 Definition Of Done

`v1` is complete only when all of the following are true:

- `images/nexus` exists as an independent monorepo project with its own
  `Dockerfile`, version manifest, `verify.sh`, and README
- `agents/fenix` builds on top of `images/nexus` for Docker deployment
- `agents/fenix` publishes a bundled runtime manifest with both program and
  executor planes
- `agents/fenix` can receive and settle real mailbox work through a persistent
  runtime worker
- the executor-plane tool surface is sufficient to build, test, run, and
  browser-verify the 2048 app
- `fenix` uses layered prompt assembly, plan-first instructions, and optional
  app-local skills/memory
- `CoreMatrix` exposes neutral `work_context_view` and neutral delegation/result
  envelopes
- the dedicated 2048 acceptance path runs without `using-superpowers`
- root docs and CI know about both `agents/fenix` and `images/nexus`

## Known Constraints

- `CoreMatrix` must remain neutral across `fenix.old` and the new `fenix`
- capability additions must stay optional
- `Memory` and `Skills` remain on the agent-program side
- no compatibility shim or development-data backfill is required
- Docker and bare-metal are both supported, but `images/nexus` is Docker-only
- `codex-universal` is a structure reference, not our version source of truth

## Dependency Order

The tasks below are intentionally ordered. Do not start prompt or acceptance
work before the runtime base, bundled runtime identity, runtime worker, and
executor tool slice exist.

1. `images/nexus`
2. `agents/fenix` Docker layering on top of `nexus`
3. bundled runtime manifest and identity
4. mailbox worker and control loop
5. executor tool slice for `2048`
6. prompt assembly and cowork instruction builder
7. `CoreMatrix` neutral contracts
8. acceptance bootstrap and scenario
9. root docs, CI, and full verification

## Task 1: Create `images/nexus` as the Docker cowork runtime base

**Files:**

- Create: `images/nexus/Dockerfile`
- Create: `images/nexus/README.md`
- Create: `images/nexus/verify.sh`
- Create: `images/nexus/versions.env`
- Create: `images/nexus/.dockerignore`

**Requirements:**

- use `ubuntu:24.04`
- install only one default version line for each language/runtime
- include:
  - Node LTS plus `npm`, `corepack`, `pnpm`
  - `vite`, `create-vite`
  - Playwright plus Chromium
  - Python plus `uv`
  - Ruby runtime prerequisites and native extension build prerequisites
  - Go stable
  - Rust stable
  - common CLI/build tools such as `git`, `curl`, `jq`, `unzip`, `zip`,
    `ripgrep`, `fd`, `sqlite3`, `build-essential`, `pkg-config`
- keep all version truth in `images/nexus/versions.env`
- add `verify.sh` checks for command existence, version selection, and browser
  availability

**Reference sources:**

- borrow project shape and image verification ideas from
  `references/original/references/codex-universal`
- borrow currently useful runtime dependencies from `agents/fenix.old`
- do not copy the full language/version matrix from `codex-universal`

**Acceptance for this task:**

- `docker build -f images/nexus/Dockerfile -t nexus-local .` succeeds
- `docker run --rm -v /Users/jasl/Workspaces/Ruby/cybros:/workspace nexus-local /workspace/images/nexus/verify.sh` succeeds

## Task 2: Switch `agents/fenix` Docker deployment to consume `images/nexus`

**Files:**

- Modify: `agents/fenix/Dockerfile`
- Create any app-local Docker helper scripts under `agents/fenix/bin/` that the
  final image requires
- Create: `agents/fenix/bin/check-runtime-host`
- Modify: `agents/fenix/README.md`
- Modify: `agents/fenix/env.sample`

**Requirements:**

- make the Docker app image `FROM` the locally built `images/nexus` base
- keep app responsibilities limited to:
  - copying source
  - bundle install
  - app-local asset or npm installation if still needed
  - entrypoint and runtime worker boot
- remove old "bootstrap inside the app image at runtime" assumptions from the
  new `fenix` Docker path
- document the split:
  - Docker deployment uses `images/nexus`
  - bare-metal deployment validates host requirements separately
- provide a lightweight bare-metal host validator that checks the documented
  prerequisites without trying to recreate Docker parity

**Acceptance for this task:**

- `agents/fenix` builds successfully when `images/nexus` has been built locally
- the new app image no longer owns the broad toolchain baseline
- `agents/fenix/bin/check-runtime-host` reports missing prerequisites clearly and
  passes when the documented host contract is satisfied

## Task 3: Re-establish bundled runtime identity for the new `agents/fenix`

**Files:**

- Modify: `agents/fenix/config/routes.rb`
- Create: `agents/fenix/app/controllers/runtime/manifests_controller.rb`
- Create: `agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Create: `agents/fenix/test/integration/runtime_manifest_test.rb`

**Requirements:**

- the manifest must reflect the new cowork runtime, not `fenix.old`
- publish both:
  - `program_plane`
  - `executor_plane`
- include:
  - `agent_key`
  - `display_name`
  - `includes_executor_program`
  - `executor_kind`
  - `executor_fingerprint`
  - `executor_connection_metadata`
  - `protocol_version`
  - `sdk_version`
  - `endpoint_metadata`
  - `program_contract`
  - `protocol_methods`
  - `executor_capability_payload`
  - `executor_tool_catalog`
  - `tool_catalog`
  - `profile_catalog`
  - `effective_tool_catalog`
  - `config_schema_snapshot`
  - `conversation_override_schema_snapshot`
  - `default_config_snapshot`

**Important note:**

This task is not complete if the manifest only exposes `prepare_round` and
`execute_program_tool`. The current acceptance and registration flow expects a
bundled runtime with an executor-plane contract and the current registration
fields used by `RegisterBundledAgentRuntime` and the acceptance harness.

**Acceptance for this task:**

- `GET /runtime/manifest` returns a valid bundled-runtime shape
- the payload is suitable for `CoreMatrix` bundled runtime registration

## Task 4: Implement the persistent mailbox runtime path

**Files:**

- Modify: `agents/fenix/Gemfile`
- Modify: `agents/fenix/Gemfile.lock`
- Create: `agents/fenix/app/services/fenix/runtime/control_client.rb`
- Create: `agents/fenix/app/services/fenix/runtime/control_plane.rb`
- Create: `agents/fenix/app/services/fenix/runtime/realtime_session.rb`
- Create: `agents/fenix/app/services/fenix/runtime/mailbox_pump.rb`
- Create: `agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Create: `agents/fenix/app/services/fenix/runtime/control_loop.rb`
- Create: `agents/fenix/app/services/fenix/runtime/control_worker.rb`
- Create: `agents/fenix/bin/runtime-worker`
- Create: `agents/fenix/lib/tasks/runtime.rake`
- Create: corresponding tests under `agents/fenix/test/services/fenix/runtime/`

**Implementation source:**

- use `agents/fenix.old` as the direct reference for runtime worker shape and
  report flow

**Requirements:**

- support websocket-first delivery with poll fallback
- support both program-plane and executor-plane mailbox items
- support incremental report delivery back to `CoreMatrix`
- provide a persistent runtime worker entrypoint
- make `bin/runtime-worker` boot the mailbox control path together with whatever
  queue-processing arrangement the runtime needs for real turn execution
- declare any additional runtime gems needed for realtime delivery and worker
  boot in the app bundle
- preserve runtime-local handles for long-lived resources such as commands or
  browser sessions

**Acceptance for this task:**

- mailbox items can be received and settled end-to-end
- a persistent runtime worker can run in Docker with the same machine
  credentials returned by registration
- the runtime-worker boot path covers both mailbox control and active queue
  processing

## Task 5: Implement the minimum executor tool slice required for the 2048 capstone

**Files:**

- Modify: `agents/fenix/Gemfile` if browser/runtime gems are required
- Modify: `agents/fenix/Gemfile.lock` if gem dependencies change
- Create: `agents/fenix/package.json`
- Create: `agents/fenix/pnpm-lock.yaml`
- Create: `agents/fenix/scripts/browser/session_host.mjs`
- Create: `agents/fenix/app/services/fenix/runtime/system_tool_registry.rb`
- Create: `agents/fenix/app/services/fenix/runtime/program_tool_executor.rb`
- Create: `agents/fenix/app/services/fenix/runtime/command_run_registry.rb`
- Create: `agents/fenix/app/services/fenix/browser/session_manager.rb`
- Create: the concrete executor tool classes and result projectors needed to back
  the required tool families
- Create: tests covering the chosen tool families

**Minimum required tool families:**

- shell and command execution
  - `exec_command`
  - `write_stdin`
  - `command_run_list`
  - `command_run_read_output`
  - `command_run_wait`
  - `command_run_terminate`
- browser validation
  - `browser_open`
  - `browser_navigate`
  - `browser_get_content`
  - `browser_screenshot`
  - `browser_list`
  - `browser_close`
  - `browser_session_info`

**Optional in v1 unless acceptance friction proves they are necessary:**

- workspace file tools
- memory executor tools
- web fetch/search tools
- process proxy tools

**Requirements:**

- the tool catalog must be declared through the executor plane
- the tool implementations must run in the Docker runtime, not through host-side
  shortcuts
- the browser slice must include the Node-side browser host and package-managed
  Playwright dependency it needs to boot reliably
- use `pnpm` as the committed Node package manager for the browser host slice
- the browser slice must be able to verify the 2048 app on the live local port

**Acceptance for this task:**

- the runtime can scaffold, install, test, build, start, and browser-check the
  2048 app using only declared runtime tools

## Task 6: Build the layered prompt pipeline and cowork instruction builder

**Files:**

- Create: `agents/fenix/prompts/SOUL.md`
- Create: `agents/fenix/prompts/USER.md`
- Create: `agents/fenix/prompts/WORKER.md`
- Create: `agents/fenix/app/services/fenix/prompts/assembler.rb`
- Create: `agents/fenix/app/services/fenix/prompts/workspace_instruction_loader.rb`
- Create: `agents/fenix/app/services/fenix/memory/store.rb`
- Create: `agents/fenix/app/services/fenix/skills/catalog.rb`
- Create: `agents/fenix/app/services/fenix/application/build_round_instructions.rb`
- Create: `agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- Create: `agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
- Create: `agents/fenix/app/services/fenix/runtime/payload_context.rb`
- Create: prompt/runtime tests under `agents/fenix/test/services/fenix/`

**Requirements:**

- implement the approved prompt layer order:
  - code-owned base
  - role overlay
  - workspace instructions
  - skill overlay
  - `CoreMatrix` durable state
  - execution-local memory/context
  - transcript
- skills must remain optional and lazy
- memory and skills remain agent-program-side
- `prepare_round` must use neutral `CoreMatrix` facts, not infer durable state
  from transcript alone
- cowork instructions must explicitly require:
  - plan updates
  - evidence-backed delivery
  - subagent use only when genuinely helpful

**Non-goal:**

Do not make `using-superpowers` or any comparable workflow skill a hard
dependency of the base cowork behavior.

## Task 7: Strengthen `CoreMatrix` with neutral work-context and delegation contracts

**Files:**

- Create: `core_matrix/app/services/provider_execution/build_work_context_view.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_program_round.rb`
- Modify: `core_matrix/app/services/subagent_sessions/spawn.rb`
- Modify: `core_matrix/app/services/subagent_sessions/wait.rb`
- Modify: related tests under `core_matrix/test/services/provider_execution/`
  and `core_matrix/test/services/subagent_sessions/`

**Requirements:**

- add neutral `work_context_view` to `prepare_round`
- include:
  - conversation and turn public ids
  - primary turn todo plan summary/view
  - active child-state projection built from current turn-todo read models and
    subagent session summaries
  - current supervision snapshot
- do not expose internal numeric ids at this agent-facing boundary
- preserve generic naming
- serialize neutral delegation packages into child workflow payloads
- serialize neutral result envelopes out of child completion state

**Implementation note:**

Use existing plan builders correctly. The current basis is
`ConversationSupervision::BuildCurrentTurnTodo` and the existing turn todo plan
read models, not a made-up `TurnTodoPlans::BuildCompactView.call(turn: ...)`
entrypoint.

**Acceptance for this task:**

- `fenix` can build cowork instructions from durable platform state without
  product-specific platform naming

## Task 8: Genericize acceptance bootstrap and add the `fenix` 2048 capstone path

**Files:**

- Create: `acceptance/bin/activate_agent_docker_runtime.sh`
- Modify: `acceptance/bin/activate_fenix_docker_runtime.sh` into a thin
  fenix-specific wrapper around the generic activator for v1
- Modify: `acceptance/bin/fresh_start_stack.sh`
- Modify: `acceptance/bin/run_with_fresh_start.sh`
- Modify: `acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh`
- Modify: `core_matrix/script/manual/manual_acceptance_support.rb`
- Create: `acceptance/lib/capstone_app_api_roundtrip.rb`
- Modify: `acceptance/lib/review_artifacts.rb`
- Modify: `acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb`
- Modify: `acceptance/README.md`
- Modify: `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Modify: `core_matrix/test/lib/fresh_start_stack_contract_test.rb`
- Modify: `core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Requirements:**

- stop hardcoding old `fenix` runtime registration metadata into the helper
  layer
- support the current `agents/fenix` Docker runtime path
- support building `images/nexus` first, then the `fenix` app image
- update the wrapper layer that still assumes:
  - direct image build from `agents/fenix`
  - old wrapper names as the only public entrypoints
  - old activation/report wording in acceptance artifacts
- remove the old in-container `scripts/bootstrap-runtime-deps.sh` expectation from
  activation and contract tests
- extract shared capstone mechanics into a helper if that reduces duplication
- remove the hard dependency on:
  - `Use $using-superpowers`
  - GitHub-sourced skill staging
- keep subagent use optional and behavior-driven
- keep browser verification mandatory
- make the written checklist match the executable acceptance path so the scripts,
  scenario, and checklist do not describe different products

**Acceptance for this task:**

- the 2048 capstone can run through the new `fenix` stack without
  `using-superpowers`
- produced artifacts still include supervision and portability evidence
- contract tests cover the genericized wrapper flow and current public
  entrypoints

## Task 9: Register the new project layout in root docs and CI, then run full verification

**Files:**

- Modify: `AGENTS.md`
- Modify: `.github/workflows/ci.yml`
- Modify: `agents/fenix/README.md`
- Modify: `images/nexus/README.md`

**Requirements:**

- `AGENTS.md` must reflect:
  - `agents/fenix`
  - `agents/fenix.old`
  - `images/nexus`
- root CI must add explicit path detection and a job for `images/nexus`
- root CI must run `agents/fenix` checks as the active cowork app
- verification commands for `agents/fenix` must be documented

**Minimum verification set:**

For `agents/fenix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

For `core_matrix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

For `images/nexus`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
docker build -f images/nexus/Dockerfile -t nexus-local .
docker run --rm -v /Users/jasl/Workspaces/Ruby/cybros:/workspace nexus-local /workspace/images/nexus/verify.sh
```

For acceptance:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
bash acceptance/bin/fenix_capstone_app_api_roundtrip_validation.sh
```

## Potential Blockers

These are real blockers, not optional cleanup:

- `images/nexus` version selection may need a short calibration pass if one of
  the newest stable tool releases breaks Ubuntu 24.04 packaging or Playwright
  browser support
- the current `agents/fenix` skeleton has almost none of the bundled runtime
  machinery yet
- the existing acceptance bootstrap path is hardcoded around the previous Fenix
  runtime
- provider-backed capstone runs still include normal model variability, so the
  implementation goal is a stable, repeatable acceptance path rather than a
  claim of guaranteed first-run success

## Execution Guidance

- use `agents/fenix.old` aggressively as a reference for runtime/executor
  mechanics
- use `references/claude-code-sourcemap/restored-src` aggressively as a
  reference for cowork behavior and prompt discipline
- use `references/original/references/codex-universal` selectively for image
  project structure and verification ideas
- do not re-import `fenix.old` architecture wholesale
- do not let `CoreMatrix` absorb `fenix` product semantics
