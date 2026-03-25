# Core Matrix Phase 2 Activation-Ready Outline

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans only after this outline is refreshed into `docs/plans` against the activated Phase 2 scope.

**Goal:** Bridge the approved Phase 2 design into an activation-ready execution outline without promoting it early into `docs/plans`.

**Architecture:** `Core Matrix` remains the kernel authority for loop progression, feature gating, capability governance, and recovery. `Fenix` remains the default validation program, including external deployment rotation and agent-program-owned skills, but the final execution-ready task list should still be refreshed after the activation checklist passes.

**Tech Stack:** Rails 8.2, PostgreSQL, Minitest, request and integration tests, `bin/dev`, real LLM provider APIs, Streamable HTTP MCP, `agents/fenix`, real external deployment pairing.

---

## Status

Deferred companion outline for Phase 2.

Use this document to speed up plan promotion later. Do not treat it as the
final active implementation plan.

## Promotion Rule

Before Phase 2 moves into `docs/plans`, refresh this outline against:

- [2026-03-25-core-matrix-phase-2-activation-checklist.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md)
- [2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md)
- [2026-03-25-core-matrix-phase-2-task-group-kernel-first-sequencing.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-group-kernel-first-sequencing.md)
- [2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-agent-execution-delivery-contract-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md)
- [2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)

## Task Group 1: Re-Run The Structural Gate And Freeze Phase 2 Scope

**Purpose:** Confirm the landed Phase 1 code still supports the approved Phase 2
shape without a root-model rewrite.

**Likely files:**

- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-agent-loop-execution-initial-plan.md`
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`
- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Review: `core_matrix/docs/behavior/*.md`

**Verification:**

- produce one short activation note
- confirm any remaining blockers are recorded before promotion

## Task Group 2: Add A Real Loop Executor Path In Core Matrix

**Purpose:** Turn the existing workflow substrate into a real executable loop.

**Likely files:**

- Modify: `core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `core_matrix/app/services/workflows/context_assembler.rb`
- Modify: `core_matrix/app/services/workflows/scheduler.rb`
- Likely create: `core_matrix/app/services/workflows/execute_run.rb`
- Likely create: `core_matrix/app/services/workflows/visualization/*`
- Likely create: `core_matrix/app/services/provider_execution/*`
- Likely create: `core_matrix/app/models/agent_task_run.rb`
- Likely create: `core_matrix/app/queries/workflows/proof_export_query.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Likely create: `core_matrix/script/manual/workflow_proof_export.rb`
- Modify: `core_matrix/vendor/simple_inference/lib/simple_inference/*`
- Test: `core_matrix/vendor/simple_inference/test/*`
- Test: `core_matrix/test/services/workflows/*`
- Likely create: `core_matrix/test/queries/workflows/proof_export_query_test.rb`
- Likely create: `core_matrix/test/services/workflows/visualization/*`
- Test: `core_matrix/test/integration/*`

**Verification:**

- `cd core_matrix/vendor/simple_inference && bundle exec rake`
- `cd core_matrix && bin/rails test test/services/workflows`
- `cd core_matrix && bin/rails test test/integration`
- stale-work guard coverage for `reject`, `restart`, or `queue` paths
- coverage for authoritative provider-usage persistence plus post-run
  advisory-threshold evaluation
- one workflow proof export path that shows yield, successor-agent-step
  resumption, and non-transcript workflow materialization
- one reproducible manual command path through
  `script/manual/workflow_proof_export.rb`

## Task Group 3: Complete Unified Capability Governance

**Purpose:** Prevent provider tools, MCP tools, and agent-program tools from
forking into separate execution models.

**Likely files:**

- Modify: `core_matrix/app/models/capability_snapshot.rb`
- Modify: `core_matrix/app/services/agent_deployments/handshake.rb`
- Modify: `core_matrix/app/services/agent_deployments/reconcile_config.rb`
- Modify: `core_matrix/app/controllers/agent_api/capabilities_controller.rb`
- Likely create: `core_matrix/app/controllers/agent_api/executions_controller.rb`
- Likely create: `core_matrix/app/services/mcp/*`
- Likely create or expand: `core_matrix/app/models/` for tool-governance
  objects
- Likely create or expand: `core_matrix/app/services/` for tool binding and
  invocation recording
- Test: `core_matrix/test/requests/agent_api/*`
- Test: `core_matrix/test/services/agent_deployments/*`

**Verification:**

- `cd core_matrix && bin/rails test test/requests/agent_api`
- `cd core_matrix && bin/rails test test/services/agent_deployments`
- contract coverage for the `execution_*` method family
- contract coverage for the bounded fast terminal path with no intermediate
  progress or heartbeat
- contract coverage for stale-lease rejection, duplicate terminal delivery, and
  out-of-order progress handling
- contract coverage for competing claim attempts and single-owner lease
  acquisition

## Task Group 4: Enforce Conversation Feature Policy At Runtime

**Purpose:** Make feature gating real execution behavior instead of a design
placeholder.

**Likely files:**

- Modify: `core_matrix/app/models/conversation.rb`
- Modify: `core_matrix/app/models/turn.rb`
- Modify: `core_matrix/app/models/workflow_run.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Modify: `core_matrix/app/services/turns/start_automation_turn.rb`
- Modify: `core_matrix/app/services/human_interactions/request.rb`
- Test: `core_matrix/test/services/turns/*`
- Test: `core_matrix/test/services/human_interactions/*`

**Verification:**

- `cd core_matrix && bin/rails test test/services/turns`
- `cd core_matrix && bin/rails test test/services/human_interactions`

## Task Group 5: Prove Human Interaction, Subagents, And Wait-State Recovery

**Purpose:** Move the existing runtime-resource substrate into real execution.

**Likely files:**

- Modify: `core_matrix/app/services/human_interactions/request.rb`
- Modify: `core_matrix/app/services/human_interactions/submit_form.rb`
- Modify: `core_matrix/app/services/human_interactions/complete_task.rb`
- Modify: `core_matrix/app/services/subagents/spawn.rb`
- Modify: `core_matrix/app/services/leases/acquire.rb`
- Modify: `core_matrix/app/services/leases/heartbeat.rb`
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Test: `core_matrix/test/services/human_interactions/*`
- Test: `core_matrix/test/services/subagents/*`
- Test: `core_matrix/test/services/leases/*`

**Verification:**

- `cd core_matrix && bin/rails test test/services/human_interactions test/services/subagents test/services/leases`
- one test path for `wait_transition_requested` or equivalent canonical wait
  handoff payload

## Task Group 6: Prove External Fenix Pairing And Deployment Rotation

**Purpose:** Validate the real external deployment workflow plus same-installation
release rotation.

**Likely files:**

- Modify: `core_matrix/app/services/agent_deployments/register.rb`
- Modify: `core_matrix/app/services/agent_deployments/record_heartbeat.rb`
- Modify: `core_matrix/app/services/agent_deployments/bootstrap.rb`
- Modify: `core_matrix/app/services/agent_deployments/auto_resume_workflows.rb`
- Modify: `core_matrix/app/services/agent_deployments/mark_unavailable.rb`
- Likely create or expand: `core_matrix/app/controllers/agent_api/*` for
  claim/report style execution delivery
- Modify: `core_matrix/app/services/workflows/manual_resume.rb`
- Modify: `core_matrix/app/services/workflows/manual_retry.rb`
- Test: `core_matrix/test/services/agent_deployments/*`
- Test: `core_matrix/test/integration/dummy_agent_runtime_test.rb`

**Verification:**

- `cd core_matrix && bin/rails test test/services/agent_deployments test/integration/dummy_agent_runtime_test.rb`
- real `bin/dev` validation with:
  - bundled `Fenix`
  - one independent external `Fenix`
- one same-installation rotation across upgrade
- one same-installation rotation across downgrade
- no required kernel-initiated callback into the runtime during normal pairing
  or execution delivery

## Task Group 7: Build The Fenix Runtime Surface And Retain Execution Hooks

**Purpose:** Give `Fenix` enough runtime behavior to participate in Phase 2 as a
real agent program.

**Likely files:**

- Modify: `agents/fenix/config/routes.rb`
- Modify: `agents/fenix/README.md`
- Likely create: `agents/fenix/app/controllers/*` for machine-facing runtime
  endpoints
- Likely create: `agents/fenix/app/services/fenix/runtime/*`
- Likely create: `agents/fenix/app/services/fenix/runtime_surface/*`
- Likely create: `agents/fenix/app/services/fenix/tools/*`
- Likely create: `agents/fenix/test/integration/*`
- Likely create: `agents/fenix/test/services/*`

**Verification:**

- `cd agents/fenix && bin/rails test`
- manual registration and pairing from a real `Fenix` runtime into
  `Core Matrix`
- one real code-driven or mixed code-plus-LLM execution path that exercises the
  retained runtime-stage hook family
- one path where `Fenix` uses likely-model hints and local estimation to decide
  proactive compaction before provider execution

## Task Group 8: Add Fenix Skills Compatibility And Operational Skills

**Purpose:** Prove that `Fenix` can use both built-in system skills and standard
third-party Agent Skills.

**Likely files:**

- Modify: `agents/fenix/README.md`
- Likely create: `agents/fenix/app/services/fenix/skills/*`
- Likely create: `agents/fenix/test/integration/skills_*`
- Likely create: `agents/fenix/test/services/fenix/skills/*`
- Likely create: bundled skill roots under `agents/fenix/skills/.system/`
- Likely create: bundled curated catalog roots under
  `agents/fenix/skills/.curated/`

**Required validation slices:**

- one built-in system skill that deploys another agent
- one installed third-party skill package from
  [obra/superpowers](https://github.com/obra/superpowers)
- one proof that installed or replaced skills become active only on the next
  top-level turn

**Verification:**

- `cd agents/fenix && bin/rails test`
- real `bin/dev` validation of:
  - skill install
  - skill activation
  - resource reads from an installed skill
  - system-skill-driven deployment flow

## Task Group 9: Refresh The Manual Checklist And Run Real Acceptance

**Purpose:** Make Phase 2 impossible to declare complete without real operator
evidence.

**Likely files:**

- Modify: `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-milestone-agent-loop-execution.md`
- Modify: `docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md`

**Required real-environment scenarios:**

- bundled `Fenix` loop
- external `Fenix` pairing
- same-installation upgrade rotation
- same-installation downgrade rotation
- one workflow proof record plus raw Mermaid artifact package for the key
  yield, wait, resume, and bounded-parallel scenarios
- those acceptance-proof artifacts committed under `docs/reports/phase-2/`
- tool call
- Streamable HTTP MCP-backed tool call
- subagent path
- human-interaction path
- proactive compaction driven by agent-side estimation
- advisory post-run threshold handling driven by authoritative provider usage
- recovery path
- code-driven or mixed code-plus-LLM runtime-stage-hook path
- built-in deployment skill path
- third-party skill install-and-use path
- stale-work rejection after new input supersedes older execution

**Verification:**

- `cd core_matrix && bin/rails db:test:prepare test`
- `cd core_matrix && bin/rails db:test:prepare test:system`
- `cd core_matrix && bun run lint:js`
- `cd core_matrix && bin/rubocop -f github`
- `cd core_matrix && bin/brakeman --no-pager`
- `cd core_matrix && bin/bundler-audit`
- `cd agents/fenix && bin/rubocop -f github`
- `cd agents/fenix && bin/brakeman --no-pager`
- `cd agents/fenix && bin/bundler-audit`
- `cd agents/fenix && bin/rails db:test:prepare test`

## Final Promotion Check

Do not promote this outline into `docs/plans` until:

- the activation checklist passes cleanly
- real provider credentials are ready
- the retained execution-budget and runtime-hook boundary is still accepted
- the chosen `Fenix` runtime shape is concrete
- the third-party skill validation source is confirmed
