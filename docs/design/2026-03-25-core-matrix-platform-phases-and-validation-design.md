# Core Matrix Platform Phases And Validation Design

## Status

Approved follow-up design for the post-substrate platform direction.

This document does not replace the current frozen phase-one execution documents.
It defines the next platform phases, the durable product boundaries, and the
validation strategy that should govern work after the current substrate batch.

## Purpose

Use this document to:

- define the product-level meaning of `Core Matrix` and `Fenix`
- normalize terminology such as `capability`, `tool`, `feature`, and `policy`
- define the future phase model after the substrate batch
- make `Fenix` a first-class validation program rather than an informal default
- keep future-phase planning aligned with the kernel's orthogonal boundaries

## Product Definitions

### Core Matrix

Core Matrix is a single-installation, single-tenant agent kernel for personal,
household, and small-team use.

It owns:

- agent-loop execution
- conversation and workflow state
- human-interaction primitives
- trigger and runtime supervision
- platform-level auditability and governance

It does not try to be:

- the business agent itself
- the built-in home for every memory, knowledge, or web capability
- an enterprise multi-tenant control plane
- an early plugin ecosystem

### Fenix

Fenix is the default out-of-the-box agent program for Core Matrix.

It has two roles:

- ship as a usable default assistant
- serve as the first technical validation program for the Core Matrix loop

Fenix is not the long-term home for every product shape. Future products such as
an `OpenAlice`-style system should be validated through separate agent programs.

## Terminology And Disambiguation

### Capability

A `capability` is a kernel-supervised functional surface known to Core Matrix.
It may be provided by the kernel itself or by an external system.

Examples:

- a tool implementation exposed by an agent program
- an MCP-backed external integration
- a platform-owned execution primitive

### Tool

A `tool` is a callable capability surfaced through the runtime contract. Tools
participate in capability snapshots, invocation history, governance, and audit.
Tools are not the same thing as composer completions or per-conversation
feature gates.

### Feature

A `feature` is a conversation-scoped permission to use a class of kernel
behavior.

Examples:

- `human_interaction`
- `tool_invocation`
- `message_attachments`
- `conversation_branching`
- `conversation_archival`

### Policy

A `policy` is a kernel-owned rule that permits, denies, constrains, or shapes
use of a capability or feature.

Examples:

- timeout and retry rules
- override and whitelist rules
- per-conversation feature gating
- approval requirements

In short:

- `capability` answers what functional surface exists
- `feature` answers what this conversation may use
- `policy` answers whether and how the kernel permits that use

### Composer Completion

A `composer completion` is an agent-defined input-surface affordance such as a
slash command, mention completion, or symbol-triggered reference completion. It
belongs to the client and channel surface, not to loop-core tool execution.

### Decision Source

`Decision source` keeps the existing design meaning and records where a runtime
decision came from:

- `llm`
- `agent_program`
- `system`
- `user`

## Design Goals

- keep the kernel small, orthogonal, and authoritative
- prove real loop execution before widening ecosystem scope
- let external agent programs own domain behavior and experimental capability
  implementations
- use `Fenix` as the first validation program without turning it into a
  universal product shell
- keep future product validation possible through additional agent programs
- make destructive correction acceptable while the platform shape is still being
  validated

## Non-Goals

- compatibility guarantees during the current rewrite
- enterprise security, ACL, and audit scope
- a built-in plugin marketplace
- forcing all future product shapes into `Fenix`
- forcing all agent behavior through an LLM when deterministic programmatic
  paths are more appropriate

## Change Strategy

The current rewrite is allowed to make destructive corrections.

Rules:

- no compatibility work is required while the platform shape is still being
  validated
- database resets and data-file cleanup are acceptable when a corrected design
  conflicts with earlier experimental state
- design clarity takes priority over preserving temporary data

## Phase Model

### Phase 2: Agent Loop Execution

The platform must prove one real end-to-end loop through Core Matrix.

Success means:

- a real turn enters the kernel
- context assembly, execution snapshots, and workflow progression are real
- a real provider or execution path is invoked
- tools, subagents, and human interaction can participate in the loop
- drift, waiting, and recovery semantics work in real environments
- `bin/dev` plus a real LLM API pass the manual checklist

### Phase 3: Web UI Productization

Make the product usable through a real Web UI without changing the kernel's
loop authority.

This phase should expose:

- conversation and workspace product surfaces
- human-interaction handling
- runtime status and recovery affordances
- Fenix as a real user-facing default product

### Phase 4: Product-Shape Exploration

Validate that Core Matrix is not overfit to `Fenix`.

This phase should add one or more new agent programs to test materially
different product shapes, such as an `OpenAlice`-style system.

### Phase 5: Trigger And Delivery

Add workspace-owned automation and trigger infrastructure only after the loop
and Web product surface are validated.

### Phase 6: Client And Channel Surfaces

Extend the product through IM, PWA, desktop, and other client or channel
surfaces.

### Phase 7: Extension And Plugin

Only after the kernel and multiple agent programs are stable should Core Matrix
consider extension and plugin packaging.

## Phase 2 Success Criteria

Phase 2 is complete only when all of the following are true:

- Core Matrix runs a real agent loop end to end
- tool invocation works through the kernel's governed path
- at least one subagent path works in a real run
- at least one human-interaction path works in a real run
- drift and recovery behavior are verified in real runs
- the done gate includes unit tests, integration tests, and manual
  `bin/dev + real LLM API` validation

## Capability Boundary

Core Matrix owns:

- loop progression and workflow scheduling
- conversation, workflow, and runtime-resource state
- human interaction, waiting, retry, recovery, and audit semantics
- capability governance and invocation supervision
- feature gating and policy enforcement
- transport-neutral public contract semantics for agent communication

Agent programs may own:

- domain behavior
- prompt building and model-input composition
- context compaction, summarization, and tool-result projection strategies
- experimental tool implementations
- memory, knowledge, fetch, search, and other unstable capability
  implementations
- execution-time lifecycle hooks and token-estimation helpers
- skills, skill loaders, and skill installers
- composer completions and other client-facing affordances

The kernel remains the final authority for durable side effects whether the
agent behavior came from an LLM or deterministic code.

Agent communication transport may vary by implementation. The public protocol
should not be defined in ActionCable-specific, Rails-specific, or any other
framework-specific terms.

## Conversation Feature Policy

Core Matrix should formalize per-conversation feature gating.

Recommended fields:

- `Conversation.enabled_feature_ids`
- `Turn.feature_policy_snapshot`
- `WorkflowRun.feature_policy_snapshot`

Rules:

- feature defaults depend on conversation purpose, trigger source, and channel
  shape
- automation-triggered conversations disable `human_interaction` by default
- requests for disabled features return a structured policy rejection such as
  `feature_not_enabled`
- the kernel must not create a blocking runtime resource for a disabled feature
- feature snapshots freeze execution meaning for a running turn or workflow

## Unified Capability Governance

Phase 2 should lock in one shared capability model.

Recommended conceptual objects:

- `ToolDefinition`
- `ToolImplementation`
- `ImplementationSource`
- `ToolBinding`
- `ToolInvocation`

The model should supervise at least:

- kernel-owned tool surfaces
- Streamable HTTP MCP capability implementations
- agent-program-exposed tool implementations

## Override, Whitelist, And Reserved Prefix Policy

Tool-governance rules must be explicit.

Core Matrix should support three governance modes:

- `replaceable`
- `whitelist_only`
- `reserved`

Rules:

- reserved prefixes are platform-owned and may not be overridden
- whitelist-only definitions may bind only approved implementation sources or
  refs
- replaceable definitions may be rebound by an agent program when policy allows
- every binding decision must be visible in capability snapshots and audit
  history

## External Capability Supervision

All external capability execution must be supervised by the kernel.

Minimum supervision requirements:

- readiness and availability state
- timeout, retry, and degraded behavior policy
- attempt-level invocation history
- failure classification for transport, protocol, and semantic faults
- deterministic routing into retry, wait, or manual recovery

## Automation And Trigger Ownership

Automation and trigger control-plane records belong to `Workspace`.

Recommended conceptual split:

- `AutomationDefinition`
- `TriggerRegistration`
- `TriggerEvent`
- execution records under normal conversation and workflow roots

This keeps long-lived automation intent separate from one concrete run while
avoiding installation-global overreach.

## Validation Strategy

Future phases must not treat automated tests as the only completion gate.

Loop-related work requires:

- unit coverage
- integration coverage
- maintained manual validation checklists
- `bin/dev`
- real LLM API execution
- real tool calls and failure handling

When a phase claims subagent, human interaction, trigger, or recovery support,
the manual checklist must include reproducible real-environment validation for
that behavior.

## Fenix Validation Role

Fenix is the first consumer and validator of platform capability.

### Phase 2

Fenix proves the real loop through:

- general-assistant conversation behavior
- coding-assistant behavior inspired by Codex-like workflows
- everyday office-assistance behavior inspired by `accomplish` and `maxclaw`
- tool use, subagents, human interaction, and recovery paths
- external pairing plus same-installation deployment rotation
- Agent Skills-compatible third-party skill use plus private system-skill flows

### Phase 3

Fenix is the first full Web product surface on top of the validated kernel.

### Phase 4

Fenix remains one product, but the platform must also validate separate agent
programs so the kernel does not collapse into Fenix-specific assumptions.

## Future Product Validation Strategy

Do not force all future references into a single agent program.

The platform should instead validate different shapes through additional agent
programs, for example:

- a default assistant through `Fenix`
- an `OpenAlice`-style product through a separate Alice-focused program

The success criterion is a reusable kernel, not a universal agent shell.

See the focused `Fenix` document for the concrete Phase 2 validation shape:

- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)

## Document Lifecycle Rules

Documentation moves through this order:

1. `docs/proposed-designs`
2. `docs/proposed-plans`
3. `docs/future-plans`
4. `docs/plans`
5. `docs/finished-plans`
6. `docs/archived-plans`

Rules:

- `docs/design` holds approved, durable baselines
- `docs/future-plans` holds accepted later-phase work that is intentionally not
  active yet
- `docs/plans` holds only the active execution queue
- destructive correction is acceptable in proposed, future, and early active
  work until the platform shape is proven

## Final Direction

Finish the current substrate batch without widening it.

Then:

1. make `Phase 2` the real loop-execution proof phase
2. make `Phase 3` the first user-facing Web product phase
3. validate alternative product shapes before widening triggers, channels, or
   plugins

Keep the kernel authoritative, keep agent programs flexible, and keep product
shape validation ahead of ecosystem expansion.
