# Fenix Skills Scope Isolation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
>
> Historical references to `agents/fenix.old` in this document come from the
> migration period and may no longer resolve now that the legacy app has been
> removed.

**Goal:** Make installed Fenix skills durable and isolated by `agent public_id + user public_id`, shared across that user's conversations for the same agent, while keeping CoreMatrix agent-neutral and keeping the 2048 cowork capstone free of `superpowers` and staged-skill dependencies.

**Architecture:** CoreMatrix only forwards neutral scope identifiers that Fenix already needs at the runtime boundary: `agent_id` and `user_id`, both as `public_id`. Fenix owns all filesystem layout, install/load/read behavior, and activation rules through a scoped skills repository rooted at `~/.fenix/skills-scopes/<agent_public_id>/<user_public_id>/...`; conversations never become the storage boundary.

**Tech Stack:** Ruby on Rails 8, Minitest, filesystem-backed skill packages, acceptance Ruby scenarios, Docker/local runtime pairing, public-id-only runtime payload contracts.

---

## Execution Rules

- Use `@test-driven-development` before every implementation step.
- If a test fails unexpectedly or behavior conflicts with the plan, stop and use `@systematic-debugging` before changing code.
- After every task, run `@requesting-code-review`, repair findings, then run `@verification-before-completion` before moving on.
- Prefer breaking cleanup over compatibility shims; this refactor removes obsolete roots, env vars, and fallback behavior.
- Do not introduce `agent_snapshot_id`, conversation ids, or bigint ids as the durable skills scope key.
- Do not reintroduce `using-superpowers`, `find-skills`, or GitHub-staged skills into the Cowork Fenix capstone flow.
- Keep memory and skills in `agents/fenix`; CoreMatrix only transports neutral identifiers.

## Scope Contract

The implementation is correct only if all of these are true:

1. Installing a skill in conversation A makes it available in conversation B for the same user and the same agent.
2. The same installed skill is not visible from a different agent, even for the same user.
3. All agent-facing/runtime-facing ids remain `public_id` values.
4. The default writable root is `~/.fenix/skills-scopes/<agent_public_id>/<user_public_id>/`.
5. `skills/.system` and `skills/.curated` remain checked-in, read-only catalog roots inside `agents/fenix`.
6. The standalone 2048 cowork acceptance path stays independent from skill installation and from `superpowers`.
7. `skills_install` remains the simple runtime install entry point for third-party skills; this refactor must not remove or hide it behind a different API.
8. Scope is keyed only by `agent_id + user_id`; conversation id, workspace id, and agent-snapshot id are never part of the durable skills root.
9. Docker deployments must keep the effective `FENIX_HOME_ROOT` on persistent storage; installed skills must not disappear just because the runtime container is replaced.

## Task 1: Add neutral skills-scope identifiers to CoreMatrix runtime payloads

**Files:**
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/app/models/turn_execution_snapshot.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `core_matrix/app/services/provider_execution/tool_call_runners/agent_mediated.rb`
- Modify: `core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `core_matrix/app/services/agent_control/create_agent_request.rb`
- Test: `core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Test: `core_matrix/test/models/turn_execution_snapshot_test.rb`
- Test: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Test: `core_matrix/test/services/provider_execution/tool_call_runners/agent_mediated_test.rb`
- Test: `core_matrix/test/services/agent_control/serialize_mailbox_item_test.rb`
- Test: `core_matrix/test/services/agent_control/create_agent_request_test.rb`

**Step 1: Write failing tests for public scope ids**

Add assertions that runtime-facing payloads include:

```ruby
{
  "agent_id" => turn.agent_snapshot.agent.public_id,
  "user_id" => turn.conversation.workspace.user.public_id
}
```

Required coverage:

- `AgentControlMailboxItem#materialized_payload` for persisted request documents
- `TurnExecutionSnapshot#runtime_context`
- `ProviderExecution::PrepareAgentRound` request payloads
- `ProviderExecution::ToolCallRunners::AgentMediated` request payloads
- `AgentControl::SerializeMailboxItem.serialized_payload` for execution assignments
- `AgentControl::CreateAgentRequest` payload document compaction and reconstruction

**Step 2: Run the targeted CoreMatrix tests and confirm red**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_control_mailbox_item_test.rb test/models/turn_execution_snapshot_test.rb test/services/provider_execution/prepare_agent_round_test.rb test/services/provider_execution/tool_call_runners/agent_mediated_test.rb test/services/agent_control/serialize_mailbox_item_test.rb test/services/agent_control/create_agent_request_test.rb
```

Expected: FAIL because `agent_id` and `user_id` are missing from at least one runtime payload.

**Step 3: Implement minimal neutral propagation**

Implementation rules:

- use `turn.agent_snapshot.agent.public_id`, not `agent_snapshot.public_id`, as the durable program scope key
- use `turn.conversation.workspace.user.public_id`, not any bigint id
- keep field names neutral: `agent_id`, `user_id`
- update payload compaction in `CreateAgentRequest` so those keys survive when agent requests are persisted and replayed
- do not keep a compatibility branch that tolerates missing skills-scope ids in new runtime payloads; downstream Fenix code treats these fields as required

**Step 4: Re-run the targeted CoreMatrix tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Run a focused CoreMatrix style gate**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rubocop app/models/agent_control_mailbox_item.rb app/models/turn_execution_snapshot.rb app/services/provider_execution/prepare_agent_round.rb app/services/provider_execution/tool_call_runners/agent_mediated.rb app/services/agent_control/serialize_mailbox_item.rb app/services/agent_control/create_agent_request.rb test/models/agent_control_mailbox_item_test.rb test/models/turn_execution_snapshot_test.rb test/services/provider_execution/prepare_agent_round_test.rb test/services/provider_execution/tool_call_runners/agent_mediated_test.rb test/services/agent_control/serialize_mailbox_item_test.rb test/services/agent_control/create_agent_request_test.rb
```

Expected: PASS.

**Step 6: Review / repair / verify gate**

- Run `@requesting-code-review` on the CoreMatrix diff for this task.
- Fix findings before proceeding.
- Run `@verification-before-completion` using the test and RuboCop commands above.

## Task 2: Replace global live-skill roots with a scoped Fenix repository

**Files:**
- Create: `agents/fenix/app/services/fenix/skills/repository.rb`
- Create: `agents/fenix/app/services/fenix/skills/scope_roots.rb`
- Create: `agents/fenix/app/services/fenix/skills/package_validator.rb`
- Modify: `agents/fenix/app/services/fenix/skills/catalog.rb`
- Test: `agents/fenix/test/services/fenix/skills/catalog_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/repository_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/package_validator_test.rb`

**Reference sources:**

- Skills format spec: `references/original/references/agentskills/docs/specification.mdx`
- Old repository semantics: `agents/fenix.old/app/services/fenix/skills/repository.rb`
- Old install tests: `agents/fenix.old/test/services/fenix/skills/install_test.rb`

**Step 1: Write failing repository and catalog tests**

Add tests that prove:

- default writable roots resolve to:

```ruby
Pathname(Dir.home).join(
  ".fenix",
  "skills-scopes",
  agent_id,
  user_id,
  "live"
)
```

and sibling `staging` / `backups` roots

- two repositories with the same `agent_id` and `user_id` share the same live skill installation
- changing only `agent_id` isolates the installation
- `.system` skills remain reserved and cannot be overridden
- `Catalog#active_for_messages` only sees active system/live skills from the current scope
- installed or loaded skill packages must satisfy the Agent Skills spec subset that Fenix accepts:
  - `SKILL.md` exists
  - YAML frontmatter includes non-empty `name` and `description`
  - `name` is at most 64 characters
  - `description` is at most 1024 characters
  - `name` matches the parent directory name
  - `name` only uses lowercase letters, numbers, and single hyphens
  - `name` does not start/end with a hyphen and does not contain `--`
  - Fenix v1 intentionally validates the ASCII subset `[a-z0-9-]` for determinism; it does not attempt broader unicode name acceptance
  - install does not auto-rename or normalize mismatched packages; invalid packages fail fast

Use explicit constructor arguments in the tests:

```ruby
Fenix::Skills::Repository.new(
  agent_id: "agent-1",
  user_id: "user-1",
  home_root: tmp_root
)
```

**Step 2: Run the targeted Fenix skills tests and confirm red**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/skills/catalog_test.rb test/services/fenix/skills/repository_test.rb test/services/fenix/skills/package_validator_test.rb
```

Expected: FAIL because the repository abstraction and scoped roots do not exist yet.

**Step 3: Implement the scoped repository**

Implementation rules:

- keep checked-in roots:
  - `skills/.system/<name>/`
  - `skills/.curated/<name>/`
- move writable state to:
  - `~/.fenix/skills-scopes/<agent_public_id>/<user_public_id>/live/<skill_name>/`
  - `~/.fenix/skills-scopes/<agent_public_id>/<user_public_id>/staging/<nonce>/<skill_name>/`
  - `~/.fenix/skills-scopes/<agent_public_id>/<user_public_id>/backups/<timestamp>-<skill_name>/`
- keep provenance in `.fenix-skill-provenance.json`
- prefer a small `ScopeRoots` value object for path math and keep filesystem mutation in `Repository`
- tests override the home base through constructor injection; app runtime and acceptance override it only through `FENIX_HOME_ROOT`
- default host-runtime root remains `Pathname(Dir.home).join(".fenix")`
- Docker/runtime docs and bootstrap code must point `FENIX_HOME_ROOT` at a persistent, volume-backed path instead of relying on the container layer home directory
- remove legacy writable-root env vars such as `FENIX_LIVE_SKILLS_ROOT`, `FENIX_STAGING_SKILLS_ROOT`, and `FENIX_BACKUP_SKILLS_ROOT` instead of keeping alias behavior
- implement a local Ruby package validator instead of adding `skills-ref` as a runtime dependency, but match the relevant `agentskills` spec rules above
- optional spec fields such as `license`, `compatibility`, `metadata`, and `allowed-tools` remain parse-tolerant even if Fenix v1 does not act on them yet
- install promotion is stage -> validate -> backup current live copy if present -> replace within the same scope; no cross-scope writes are allowed

**Step 4: Re-run the targeted Fenix skills tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Run a focused Fenix style gate**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rubocop app/services/fenix/skills/catalog.rb app/services/fenix/skills/repository.rb app/services/fenix/skills/scope_roots.rb app/services/fenix/skills/package_validator.rb test/services/fenix/skills/catalog_test.rb test/services/fenix/skills/repository_test.rb test/services/fenix/skills/package_validator_test.rb
```

Expected: PASS.

**Step 6: Review / repair / verify gate**

- Run `@requesting-code-review` on the Fenix skills repository diff.
- Fix findings before proceeding.
- Run `@verification-before-completion` using the test and RuboCop commands above.

## Task 3: Bind runtime skill lookup to the scoped repository

**Files:**
- Modify: `agents/fenix/app/services/fenix/runtime/payload_context.rb`
- Modify: `agents/fenix/app/services/fenix/runtime/execute_mailbox_item.rb`
- Create: `agents/fenix/app/services/fenix/runtime/assignments/dispatch_mode.rb`
- Create: `agents/fenix/app/services/fenix/skills/catalog_list.rb`
- Create: `agents/fenix/app/services/fenix/skills/load.rb`
- Create: `agents/fenix/app/services/fenix/skills/read_file.rb`
- Create: `agents/fenix/app/services/fenix/skills/install.rb`
- Test: `agents/fenix/test/services/fenix/runtime/payload_context_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/execute_mailbox_item_test.rb`
- Test: `agents/fenix/test/services/fenix/runtime/assignments/dispatch_mode_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/catalog_list_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/load_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/read_file_test.rb`
- Test: `agents/fenix/test/services/fenix/skills/install_test.rb`
- Test: `agents/fenix/test/integration/skills_flow_test.rb`

**Reference sources:**

- Old mailbox dispatch: `agents/fenix.old/app/services/fenix/runtime/assignments/dispatch_mode.rb`
- Old runtime coverage: `agents/fenix.old/test/services/fenix/runtime/assignments/dispatch_mode_test.rb`
- Old end-to-end skills flow: `agents/fenix.old/test/integration/skills_flow_test.rb`
- Old thin service wrappers:
  - `agents/fenix.old/app/services/fenix/skills/catalog_list.rb`
  - `agents/fenix.old/app/services/fenix/skills/load.rb`
  - `agents/fenix.old/app/services/fenix/skills/read_file.rb`
  - `agents/fenix.old/app/services/fenix/skills/install.rb`

**Step 1: Write failing tests for payload-bound scope selection**

Add tests that prove:

- `PayloadContext` builds its default skills catalog from `runtime_context["agent_id"]` and `runtime_context["user_id"]`
- `PayloadContext` raises a deterministic configuration/runtime error when a skills operation is attempted without both `agent_id` and `user_id`
- the same transcript message activates an installed live skill for one scope and not for another
- install/load/read service wrappers delegate through the scoped repository instead of hard-coded global roots
- `execution_assignment` mailbox items with `task_payload["mode"]` equal to `skills_catalog_list`, `skills_load`, `skills_read_file`, or `skills_install` dispatch through the scoped skill wrappers instead of the current unconditional executor-slice failure
- the app-local mailbox worker integration path can install a skill in one top-level turn and load/read it in the next top-level turn within the same scope

Use a payload like:

```ruby
"runtime_context" => {
  "agent_id" => "agent-1",
  "user_id" => "user-1",
  "agent_snapshot_id" => "agent-snapshot-1"
}
```

**Step 2: Run the targeted Fenix runtime/skills tests and confirm red**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/runtime/payload_context_test.rb test/services/fenix/runtime/execute_mailbox_item_test.rb test/services/fenix/runtime/assignments/dispatch_mode_test.rb test/services/fenix/skills/catalog_list_test.rb test/services/fenix/skills/load_test.rb test/services/fenix/skills/read_file_test.rb test/services/fenix/skills/install_test.rb test/integration/skills_flow_test.rb
```

Expected: FAIL because payload-bound repository wiring does not exist yet.

**Step 3: Implement the runtime binding**

Implementation rules:

- `PayloadContext` must require `agent_id` and `user_id` for default skills resolution; missing scope ids are a hard error, not a fallback case
- keep skill activation transcript-driven; only the active catalog source changes
- make the small service wrappers the public app-local entry points so the rest of Fenix does not know about filesystem layout details
- restore the minimal `skills_*` mailbox flow by dispatching those `execution_assignment` modes through `Runtime::Assignments::DispatchMode`
- keep the broader executor tool slice untouched; only the explicit `skills_*` modes become runnable in this refactor
- port the old `CatalogList` / `Load` / `ReadFile` / `Install` service boundary and dispatch semantics into the new runtime rather than re-inventing a different public API name such as `install_skills`
- use deterministic failure codes for missing scope ids and invalid packages so acceptance and tests can assert the right failure mode rather than a generic runtime exception

**Step 4: Re-run the targeted Fenix runtime/skills tests**

Run the same command from Step 2.

Expected: PASS.

**Step 5: Run a focused Fenix style gate**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rubocop app/services/fenix/runtime/payload_context.rb app/services/fenix/runtime/execute_mailbox_item.rb app/services/fenix/runtime/assignments/dispatch_mode.rb app/services/fenix/skills/catalog_list.rb app/services/fenix/skills/load.rb app/services/fenix/skills/read_file.rb app/services/fenix/skills/install.rb test/services/fenix/runtime/payload_context_test.rb test/services/fenix/runtime/execute_mailbox_item_test.rb test/services/fenix/runtime/assignments/dispatch_mode_test.rb test/services/fenix/skills/catalog_list_test.rb test/services/fenix/skills/load_test.rb test/services/fenix/skills/read_file_test.rb test/services/fenix/skills/install_test.rb test/integration/skills_flow_test.rb
```

Expected: PASS.

**Step 6: Review / repair / verify gate**

- Run `@requesting-code-review` on the runtime binding diff.
- Fix findings before proceeding.
- Run `@verification-before-completion` using the test and RuboCop commands above.

## Task 4: Rewrite the dedicated skills acceptance to prove cross-conversation sharing and cross-program isolation

**Files:**
- Modify: `acceptance/bin/fresh_start_stack.sh`
- Modify: `acceptance/bin/activate_fenix_docker_runtime.sh`
- Modify: `acceptance/scenarios/fenix_skills_validation.rb`
- Modify: `agents/fenix/README.md`
- Test: `core_matrix/test/lib/fenix_capstone_acceptance_contract_test.rb`

**Step 1: Write failing acceptance-contract assertions**

Add or update contract assertions so the repo clearly documents:

- the 2048 capstone still does not install or depend on staged skills
- the dedicated skills validation remains separate from the capstone
- the skills validation scenario covers:
  - conversation A install
  - conversation B same user + same program load/read success
  - conversation C same user + different program load failure

**Step 2: Update the acceptance scenario to a three-run proof**

Implementation requirements:

- create two external agents for the same seeded user
- register the same runtime base URL once per external agent enrollment; do not introduce a second runtime process just to prove scope
- install the third-party skill through conversation A on program 1 via `skills_install`
- load and read that skill through conversation B on program 1
- attempt to load the same skill through conversation C on program 2 and assert a semantic skill-not-found failure rather than a generic runtime crash
- stop clearing global `live/staging/backup` roots directly; clear only a dedicated temp `FENIX_HOME_ROOT`
- ensure the started Fenix runtime process actually receives that `FENIX_HOME_ROOT` in both host and docker acceptance modes
- in docker acceptance mode, pass `FENIX_HOME_ROOT` to a persistent, mounted path instead of an ephemeral in-container home directory
- keep output evidence explicit:
  - install scope root
  - shared-conversation success proof
  - different-program failure proof

**Step 3: Update the README**

Replace the old documentation that says live skills default to `tmp/skills-live` with the new scoped layout rooted under `~/.fenix/skills-scopes/...`, and document both:

- host runtime default: `~/.fenix`
- docker/runtime requirement: set `FENIX_HOME_ROOT` to a persistent volume-backed path

**Step 4: Run the contract and scenario verification**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/fenix_capstone_acceptance_contract_test.rb
```

Then run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
FENIX_HOME_ROOT=/tmp/acceptance-fenix-home bash acceptance/bin/fresh_start_stack.sh
bash -n acceptance/bin/fresh_start_stack.sh acceptance/bin/activate_fenix_docker_runtime.sh
ruby acceptance/scenarios/fenix_skills_validation.rb
```

Expected:

- contract test PASS
- acceptance JSON shows install success, same-program cross-conversation success, and different-program semantic failure

**Step 5: Run final targeted regression suites**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test
```

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/agent_control_mailbox_item_test.rb test/models/turn_execution_snapshot_test.rb test/services/provider_execution/prepare_agent_round_test.rb test/services/provider_execution/tool_call_runners/agent_mediated_test.rb test/services/agent_control/serialize_mailbox_item_test.rb test/services/agent_control/create_agent_request_test.rb test/lib/fenix_capstone_acceptance_contract_test.rb
```

Expected: PASS.

**Step 6: Review / repair / verify gate**

- Run `@requesting-code-review` on the acceptance/docs diff.
- Fix findings before proceeding.
- Run `@verification-before-completion` using the contract, scenario, and regression commands above.

## Final Verification Checklist

Before claiming the refactor complete, verify all of these explicitly:

- `agent_id` and `user_id` appear in agent-facing runtime payloads as `public_id`
- Fenix defaults to `~/.fenix/skills-scopes/...` for writable skill state
- invalid skill packages that violate the accepted `agentskills` spec subset are rejected deterministically
- conversation A install is visible in conversation B for the same user/program
- the same installed skill is not visible from a different agent
- the different-program failure is a skill-scope miss, not a generic runtime exception
- the legacy `skills_catalog_list` / `skills_load` / `skills_read_file` / `skills_install` runtime flow is runnable again in the new Fenix
- `skills_install` remains the simplest supported install path for user-installed third-party skills
- acceptance bootstrap and docker activation pass `FENIX_HOME_ROOT` through to the actual runtime process
- docker runtime docs and acceptance wiring keep `FENIX_HOME_ROOT` on persistent storage
- the 2048 capstone acceptance still avoids `superpowers`, `find-skills`, and staged-skill dependencies
- legacy writable-root env vars are gone rather than silently aliased
- no README or acceptance docs still describe `tmp/skills-live` as the default live root
