# Core Matrix Phase 2 Agent Loop Execution Initial Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans only after this plan is promoted into `docs/plans` and refreshed against the post-phase-one codebase.

**Goal:** Turn the phase-one substrate into a real Core Matrix agent loop that works with `Fenix`, real providers, real tools, real recovery behavior, deployment rotation, and real manual validation.

**Architecture:** Phase 2 keeps the kernel authoritative. Core Matrix owns loop progression, workflow execution, feature gating, capability governance, and recovery semantics; `Fenix` and other agent programs may supply domain behavior, external capability implementations, and agent-program-owned skills, but durable side effects still flow back through kernel workflows. This initial plan remains pre-activation until a refreshed activation pass confirms the post-phase-one codebase and real validation environment.

**Tech Stack:** Rails 8.2, PostgreSQL, Active Storage, Minitest, request and integration tests, `bin/dev`, real LLM provider APIs, Streamable HTTP MCP, bundled `agents/fenix`.

---

## Status

This is a future-phase initial plan, not an active execution plan.

Keep it in `docs/future-plans` until:

- the completed phase-one substrate batch has been re-read against the current
  codebase
- the structural-gate review is closed
- the actual post-phase-one file layout is known

When those conditions are true, rewrite this plan into `docs/plans` with exact
task ordering and file paths.

Before promotion, run:

- [2026-03-25-core-matrix-phase-2-activation-checklist.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-checklist.md)
- [2026-03-25-core-matrix-phase-2-activation-ready-outline.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-activation-ready-outline.md)
- [2026-03-25-core-matrix-phase-2-kernel-first-sequencing-follow-up.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-kernel-first-sequencing-follow-up.md)
- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-agent-execution-delivery-contract-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-agent-execution-delivery-contract-design.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)

## Preconditions

Before activation, confirm all of the following:

1. phase one has landed the workflow, runtime-resource, protocol, and recovery
   substrate it promised
2. the phase-one structural gate has either closed cleanly or produced explicit
   design corrections
3. `Fenix` is still the default bundled validation program for the next phase
4. at least one independently started external `Fenix` deployment path remains
   available for pairing validation
5. at least one real provider path and one real external capability path remain
   available for manual validation
6. a third-party skill source is available for manual validation, ideally
   [obra/superpowers](https://github.com/obra/superpowers)

## Workstream 1: Re-run The Structural Gate Against The Real Substrate

**Why first:** Phase 2 should not start by layering executors on top of a wrong
ownership or schema shape.

**Expected inputs:**

- `docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
- `docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md`
- `docs/design/2026-03-25-core-matrix-platform-phases-and-validation-design.md`
- the final post-phase-one behavior docs under `core_matrix/docs/behavior/`

**Output:**

- one refreshed go/no-go note for Phase 2 activation
- any last substrate fixes called out explicitly as activation blockers instead
  of leaking silently into Phase 2

## Workstream 2: Build The Real Loop Executor

**Problem:** The substrate has workflows, snapshots, and protocol surfaces, but
Phase 2 must make them drive a real run.

**Scope:**

- turn intake into executable workflow progression
- real provider invocation under workflow control
- provider execution routed through `simple_inference` or a focused extension of
  it rather than through ad hoc HTTP client code
- keep the public agent-facing execution path outbound-only from the runtime
  side whenever possible
- result ingestion back into workflow state and events
- terminal, waiting, failure, and retry transitions
- carry forward during-generation input policy semantics including `reject`,
  `restart`, `queue`, expected-tail guards, and safe stale-result rejection
- preserve execution-time budget hints such as context-window, reserved-output,
  and request-correlation guidance without moving prompt building into the
  kernel
- expose the likely model or model-profile hint when known so the agent program
  can run model-aware prompt sizing before provider execution
- keep a clear split between hard kernel or provider ceilings and advisory
  runtime hints such as recommended compaction thresholds
- persist authoritative provider usage for post-run context-budget advice and
  authoritative supervised-capability usage for accounting or audit rather than
  relying only on estimates
- preserve heartbeat as the canonical liveness signal even if an optional
  WebSocket accelerator is later introduced
- define one claimable agent-execution runtime resource plus the
  `execution_claim / execution_lease_heartbeat / execution_progress /
  execution_complete / execution_fail` method family
- treat accepted kernel-governed intent as workflow-yield boundaries rather
  than letting the current `AgentTaskRun` continue under an in-place mutation
- support `IntentBatch` as ordered `stages[]` with Phase 2-limited stage
  semantics:
  - `dispatch_mode = serial | parallel`
  - `completion_barrier = none | wait_all`
  - `resume_policy = re_enter_agent`
- freeze `WorkflowNode.presentation_policy` when kernel-governed intent
  materializes so future dashboard and conversation projections can filter
  nodes without guessing from node kind
- allow redundant read-facing fields on `WorkflowNode` or related runtime
  resources when they make dashboard or conversation-adjacent queries simple,
  direct, and non-N+1
- support a bounded fast terminal path for short tasks through
  `execution_claim` followed by an immediate `execution_complete` or
  `execution_fail`, not through a separate claimless API
- define explicit stale-lease rejection, duplicate-report idempotency, and
  progress ordering rules for the `execution_*` family
- keep `execution_claim` aligned with `ExecutionLease` single-owner acquisition
  semantics under competing claims

**Likely code areas to revisit:**

- `core_matrix/app/services/workflows/`
- likely create `core_matrix/app/services/provider_execution/`
- likely create `core_matrix/app/models/agent_task_run.rb`
- `core_matrix/app/models/workflow_run.rb`
- `core_matrix/app/models/workflow_node*.rb`
- likely create or extend `core_matrix/app/queries/` for workflow read paths
- `core_matrix/app/services/turns/`
- `core_matrix/vendor/simple_inference/lib/simple_inference/`
- `core_matrix/vendor/simple_inference/test/`
- `core_matrix/test/services/workflows/`
- `core_matrix/test/integration/`

## Workstream 3: Complete Unified Capability Governance

**Problem:** Phase 2 must not let provider tools, MCP tools, and agent-program
tools fork into separate execution models.

**Scope:**

- finalize `ToolDefinition`, `ToolImplementation`, `ToolBinding`, and
  `ToolInvocation`
- bind Streamable HTTP MCP into the same governance model through a
  session-aware client transport
- bind agent-program-exposed tools into the same governance model
- keep invocation history and supervision consistent across all sources
- keep the public agent API transport-neutral even when Rails later uses
  ActionCable or another WebSocket implementation as an optional accelerator
- define the shared envelope used by HTTP claim/report and any optional
  accelerator notifications
- freeze resolved tool bindings when `AgentTaskRun` is created from the current
  execution snapshot, and reopen binding decisions only through explicit
  recovery-time attempts

**Required policy work:**

- replaceable versus whitelist-only versus reserved definitions
- reserved-prefix handling
- snapshotting of resolved bindings into execution history
- session and transport-failure handling for Streamable HTTP MCP invocations

## Workstream 4: Add Conversation Feature Policy Enforcement

**Problem:** Per-conversation feature gating must become real runtime behavior,
not just a design note.

**Scope:**

- persist the conversation feature policy
- persist the per-conversation during-generation input policy
- freeze feature snapshots on turn and workflow execution
- reject disallowed kernel behaviors deterministically
- prevent dead-end automation runs caused by impossible human-interaction
  requests

**Initial feature set to prove:**

- `human_interaction`
- `tool_invocation`
- `message_attachments`
- `conversation_branching`
- `conversation_archival`

## Workstream 5: Prove Real Human Interaction And Subagent Paths

**Problem:** The substrate models for human interaction and subagents must be
proven in real execution, not just table-backed.

**Scope:**

- one real `HumanFormRequest` or `HumanTaskRequest` path
- one real `SubagentRun` path
- correct wait-state and recovery handling for both
- one explicit wait-transition handoff from runtime progress into a
  kernel-owned workflow wait state
- decision-source tracking for LLM-driven versus deterministic agent-program
  behavior

## Workstream 6: Prove External Pairing And Deployment Rotation

**Problem:** Phase 2 should not only prove the bundled runtime. It must also
prove that `Core Matrix` can supervise `Fenix` as an external deployment and
rotate across release changes.

**Scope:**

- start and pair one independent external `Fenix` deployment
- prove enrollment, registration, heartbeat, health, handshake, and bootstrap
- prove one same-installation cutover between two `Fenix` deployments
- treat upgrade and downgrade as the same deployment-rotation shape
- verify manual resume or manual retry behavior across a release change

**Release rule:**

- do not build an in-place updater
- use deployment rotation instead
- if a changed `Fenix` release cannot boot, treat that as an agent-program
  release failure rather than a kernel recovery obligation
- do not require `Core Matrix` to dial back into the runtime as part of normal
  pairing or execution delivery

## Workstream 7: Build The Fenix Runtime Surface And Retain Execution Hooks

**Problem:** `Fenix` must be a real agent program in Phase 2, not only a
handshake target or skills shell.

**Scope:**

- build the minimal runtime endpoints and services `Fenix` needs to participate
  in the loop as an external deployment
- keep prompt building and context shaping on the agent-program side
- preserve a stage-shaped runtime hook family equivalent to:
  - `prepare_turn`
  - `compact_context`
  - `review_tool_call`
  - `project_tool_result`
  - `finalize_output`
  - `handle_error`
- preserve the helper family:
  - `estimate_tokens`
  - `estimate_messages`
- allow `Fenix` to use likely-model hints plus local estimation to decide when
  to call `compact_context` proactively before provider execution
- preserve post-run authoritative usage visibility so later adaptive behavior
  can rely on real usage facts instead of only preflight estimates
- prove at least one deterministic or mixed code-plus-LLM execution path, not
  only a pure LLM path

## Workstream 8: Add Fenix Skills Compatibility And Operational Skills

**Problem:** `Fenix` needs a real skill surface both to match the reference
product direction and to validate code-driven agent-program behavior.

**Scope:**

- keep skills agent-program-owned rather than kernel-owned
- support standard third-party Agent Skills installation and activation
- separate bundled `.system` skills from bundled `.curated` catalog entries
- keep live installed third-party skills under the normal workspace skill root
- expose a minimal real skill surface:
  - `skills_catalog_list`
  - `skills_load`
  - `skills_read_file`
  - `skills_install`
- add one built-in system skill that deploys another agent
- validate third-party install and use with
  [obra/superpowers](https://github.com/obra/superpowers)

**Operational rules:**

- reserved system skill names may not be overridden
- skill installs should stage, validate, and promote instead of writing live
- refreshed skills should become effective on the next top-level turn

## Workstream 9: Fenix Validation And Manual Acceptance

**Problem:** Phase 2 is not done until `Fenix` proves the loop in a real
environment.

**Validation slices:**

- default assistant conversation
- coding-assistant flow
- office-assistance flow
- independent external `Fenix` pairing flow
- same-installation deployment rotation flow
- one explicit downgrade flow
- one code-driven or mixed code-plus-LLM flow using the retained runtime-stage
  hook surface
- one workflow-yield path where persistent compaction materializes as workflow
  execution instead of an in-place mutation
- one best-effort title-update intent that terminals without blocking workflow
- one bounded parallel subagent stage under `wait_all`
- one proof that `presentation_policy` distinguishes internal-only metadata
  mutation from ops-trackable or user-projectable workflow work
- one proof that the chosen dashboard or workflow inspection read path works
  without N+1 traversal or graph-reconstruction SQL
- one built-in system-skill deployment flow
- one third-party skill installation and usage flow
- at least one real tool call
- at least one fast terminal execution path with no intermediate progress or
  heartbeat report
- at least one path where `Fenix` uses local estimation and likely-model hints
  to compact context proactively before the provider call
- at least one path where authoritative post-run provider usage crosses an
  advisory threshold and the kernel records or surfaces follow-up compaction
  advice
- at least one real Streamable HTTP MCP-backed tool call
- at least one real subagent flow
- at least one real human-interaction flow
- at least one stale-work scenario where new input supersedes or queues older
  work and the older result is safely rejected
- at least one outage or drift recovery flow

**Required artifacts:**

- updated manual checklist under `docs/checklists/`
- reproducible `bin/dev` validation steps
- workflow-level Mermaid proof artifacts for the key Phase 2 yield, wait, and
  recovery scenarios
- clear notes on which flows are intentionally agent-program-defined rather than
  kernel-owned
- clear notes on which skill behaviors are standard third-party compatible
  versus `Fenix`-private

## Out Of Scope

Do not widen this phase into:

- Web UI productization
- workspace-owned trigger and delivery infrastructure
- IM, PWA, or desktop surfaces
- extension and plugin packaging
- kernel-owned prompt building
- kernel-owned universal compaction or summarization
- a `Fenix` self-update daemon or plugin marketplace

## Promotion Rule

Before promotion, the next planning pass should:

1. refresh this document against the actual codebase
2. split it into execution tasks with exact file paths
3. move the execution-ready version into `docs/plans`
