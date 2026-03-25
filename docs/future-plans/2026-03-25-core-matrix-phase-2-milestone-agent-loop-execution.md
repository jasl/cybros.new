# Core Matrix Phase 2 Milestone: Agent Loop Execution

## Status

Deferred milestone definition for the next active phase after the completed
substrate batch.

## Purpose

Phase 2 proves that Core Matrix can run a real agent loop end to end under
kernel authority.

## Phase 2 Change Policy

Phase 2 should optimize for architectural correction, not compatibility.

Rules:

- breaking changes are allowed
- no backward-compatibility work is required for pre-phase-two experimental
  state
- no data backfill or legacy-shape migration is required unless it directly
  reduces current implementation risk
- resetting the database is acceptable
- regenerating `schema.rb` is acceptable

Related design and research:

- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)
- [2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-yield-and-intent-batch-design.md)
- [2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-core-matrix-workflow-proof-and-mermaid-export-design.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)
- [2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md)
- [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
- [2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md)
- [2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md)

## Formal Execution Units

Activate and execute Phase 2 through these focused task documents:

1. [2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-structural-gate-and-scope-freeze.md)
2. [2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-substrate-extensions.md)
3. [2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-agent-task-run-and-execution-contract-safety.md)
4. [2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-provider-backed-turn-execution.md)
5. [2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-conversation-feature-policy-and-stale-work-safety.md)
6. [2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-wait-state-human-interaction-and-subagents.md)
7. [2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-unified-capability-governance.md)
8. [2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-runtime-surface-and-execution-hooks.md)
9. [2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-external-fenix-pairing-and-deployment-rotation.md)
10. [2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-streamable-http-mcp-under-governance.md)
11. [2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-fenix-skills-compatibility-and-operational-flows.md)
12. [2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-workflow-proof-export-and-validation-artifacts.md)
13. [2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-25-core-matrix-phase-2-task-run-verification-and-manual-acceptance.md)

## Success Criteria

- a real turn enters the kernel and reaches terminal or waiting state through a
  real execution path
- real provider execution works under workflow control
- at least one real Streamable HTTP MCP-backed tool path works under the same
  governed capability model
- tool invocation works through unified capability governance
- at least one subagent path works in a real run
- at least one human-interaction path works in a real run
- drift, outage, and recovery semantics are validated in a real run
- execution-time budget hints and agent-program lifecycle hooks remain usable
  without moving prompt building back into the kernel
- bundled `Fenix`, independent external `Fenix`, and same-installation
  deployment rotation are all validated in real runs
- agent-program-owned skills are validated through one built-in system skill
  path plus one third-party skill-install-and-use path
- the phase passes automated tests plus real-environment manual validation under
  `bin/dev` with a real LLM API

## Current Validation Baseline

Phase 2 may assume the local development environment has both mock and real
provider paths available:

- a mock LLM path already exists for fast local contract and integration work
- the strengthened provider or model catalog is already in place
- `OPENROUTER_API_KEY` is available through `.env`, and `db:seed` can create
  the matching credential record for real-provider validation

This means Phase 2 development may use:

- mock LLM execution for fast iteration
- real provider execution for targeted manual and integration validation

## Core Matrix Work

- build the real loop executor
- use `simple_inference` as the shared provider-execution substrate unless a
  concrete protocol gap forces a focused extension
- complete unified capability governance for provider, MCP, and agent-program
  tool execution
- add a session-aware Streamable HTTP MCP client path under the same capability
  governance and supervision model
- keep the agent-program public API outbound-friendly so `Core Matrix` does not
  need to call into runtimes behind NAT
- formalize override, whitelist, and reserved-prefix rules
- formalize conversation feature policy and freeze feature snapshots on running
  execution
- preserve execution-time budget and correlation hints for agent-program
  runtime customization
- keep heartbeat as the canonical deployment-health signal even if a WebSocket
  accelerator is added later
- keep any WebSocket accelerator transport optional and implementation-specific
  rather than making it the canonical protocol
- record invocation attempts, failures, retries, waits, and recovery outcomes
- enforce during-generation input policy with stale-work protection such as
  expected-tail guards and safe stale-result rejection
- freeze resolved capability bindings when `AgentTaskRun` is created from the
  current execution snapshot, and retain binding lineage across retries or
  recovery attempts
- use an explicit wait-transition handoff from runtime execution into
  kernel-owned workflow wait state
- use workflow-first yield and resume for kernel-governed intentions rather
  than allowing accepted agent intent to mutate durable state in place
- support `IntentBatch` with ordered `stages[]`
- limit Phase 2 stage semantics to:
  - `dispatch_mode = serial | parallel`
  - `completion_barrier = none | wait_all`
  - `resume_policy = re_enter_agent`
- freeze `WorkflowNode.presentation_policy` when kernel-governed intents
  materialize so later dashboard and conversation surfaces can filter nodes
  without re-deriving visibility from node kind
- allow read-facing redundant fields on workflow-owned rows when they simplify
  dashboard, conversation-adjacent, or operator-inspection queries and avoid
  N+1 traversal
- persist batch request and batch outcome proof through workflow-owned events or
  artifacts
- add workflow-level Mermaid proof export plus proof markdown artifacts for
  real-environment validation, with formal acceptance packages committed under
  `docs/reports/phase-2/`
- provide one reproducible operator-facing export command through
  `core_matrix/script/manual/workflow_proof_export.rb`

## Fenix Validation Slice

`agents/fenix` is the default validation program for this phase.

It should prove:

- bundled default assistant, coding-assistant, and office-assistance flows
- one independently paired external `Fenix` runtime
- one same-installation deployment rotation across release change
- both upgrade and downgrade cutover treated as valid rotation inputs
- one code-driven or mixed code-plus-LLM path using the retained runtime-stage
  hook family
- one built-in system skill that deploys another agent
- one third-party Agent Skills package installed and used successfully
- real tool use, subagent behavior, human interaction, and recovery paths
- workflow-yield scenarios that prove:
  - persistent compaction through workflow materialization
  - conversation title update as a best-effort terminal intent
  - bounded parallel subagent spawn under `wait_all`
  - wait or resume behavior captured in proof artifacts

## Out Of Scope

- Web UI productization
- workspace-owned trigger infrastructure
- IM, PWA, or desktop channels
- extension and plugin packaging
- kernel-owned prompt building
- kernel-owned universal context compaction or summarization
- in-place self-update or plugin-management ecosystems inside `Fenix`
