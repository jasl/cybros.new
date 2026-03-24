# Core Matrix Model Role Resolution Design

## Status

Approved in chat on 2026-03-24 and absorbed into the main kernel design and planning documents on the same day. Keep this document as focused rationale; use the kernel implementation plan and milestone documents for the canonical execution order.

## Execution Placement

This topic is implemented through the current substrate milestones rather than a separate execution plan:

- **Milestone 2 / Task Group 05**: provider catalog, role catalog, and `provider_handle/model_ref` validation
- **Milestone 3 / Task Group 07**: conversation interactive selector persistence and turn-level resolved-model snapshots
- **Milestone 3 / Task Group 09**: selector normalization, role-local fallback, reservation-time entitlement checks, and snapshot freezing
- **Milestone 4 / Task Group 11**: machine-facing transcript and variable boundaries plus one-time selector override during explicit manual recovery

## Context

Core Matrix already separates:

- config-backed provider and model catalog
- installation-scoped provider credentials, entitlements, and policies
- deployment-level agent config
- conversation-level execution overrides

What is still missing is a stable way to express:

- preferred models for different agent purposes
- explicit fallback order across multiple providers
- entitlement-aware model selection
- the boundary between user-visible conversation model choice and agent-internal model choice

This design closes that gap without making agent configuration heavy or forcing agents to understand provider credential details.

## Goals

- keep user-facing model choice simple
- allow explicit, ordered fallback across providers
- let cheaper or subscription-backed providers win by priority
- keep fallback deterministic and auditable
- allow agents to define internal model slots without forcing kernel-wide fixed role names
- preserve historical correctness by freezing the resolved model choice on execution snapshots

## Non-Goals

- dynamic capability-only model matching with no explicit candidate order
- implicit cross-role fallback
- automatic long-term mutation of conversation or deployment config during recovery
- forcing all agents to use the same fixed set of internal roles beyond the kernel default

## Core Decision

Use provider-qualified ordered candidate lists for model roles.

The role catalog is a kernel configuration surface. Each role resolves to an ordered list of provider-qualified candidates in the form:

`provider_handle/model_ref`

Example:

```yaml
model_roles:
  main:
    - codex_subscription/gpt-5.4
    - openai/gpt-5.3-chat-latest
  coder:
    - codex_subscription/gpt-5.4
    - anthropic/claude-opus-4.1
```

This intentionally avoids inventing a second global model-identity layer such as `gpt5` aliases. The explicit provider-qualified format keeps priority, economics, and auditability obvious.

## Roles

The kernel may ship a default role catalog that includes generic roles such as:

- `main`
- `planner`
- `researcher`
- `speaker`
- `coder`
- `classifier`
- `archivist`

`main` is the only reserved default role. It replaces the earlier `master` terminology.

Rules:

- if no more specific selector is provided, execution defaults to `role:main`
- role names are stable kernel-facing identifiers
- role contents are configuration, not code
- fallback is only allowed inside the ordered candidate list of the selected role

## Conversation Model Selector

The user-visible conversation selector should stay simple.

`Conversation` should support two modes:

- `auto`
- `explicit candidate`

Rules:

- `auto` means "resolve through `role:main`"
- `explicit candidate` means one exact `provider_handle/model_ref`
- the user-facing conversation surface should expose only:
  - `auto`
  - the set of currently available explicit models
- user-facing conversation selection should not expose the full internal role catalog by default

This keeps the common path simple while still allowing advanced users to pin a specific model when they want exact behavior.

## Agent Deployment Model Slots

The kernel should not hardcode a long list of fixed internal slots such as `planner_role` or `research_role`.

Instead:

- the kernel reserves one slot name: `interactive`
- `interactive` defaults to `role:main`
- agent programs may define additional named slots in deployment config schema

Examples:

- `planner`
- `research`
- `subagent_default`
- `title_generator`
- `memory_writer`

Each slot definition should support at least:

- `selector`
- `allowed_selector_kinds`
- `user_visible`
- `conversation_overridable`
- `required_capabilities`

Rules:

- only the reserved `interactive` slot is conversation-overridable by default
- other slots are deployment-level or agent-controlled unless their schema explicitly allows otherwise
- the kernel does not need to know the business meaning of a custom slot name
- the agent may request a slot by name; the kernel validates and resolves it

## Selector Normalization

All execution-time model requests should normalize to one of two internal selector forms:

- `role:<role_name>`
- `candidate:<provider_handle/model_ref>`

Normalization rules:

- `conversation.selector = auto` normalizes to `role:main`
- `conversation.selector = explicit candidate` normalizes to `candidate:...`
- an agent-requested slot first resolves to its configured selector, then normalizes

## Resolution Pipeline

Model resolution should follow a deterministic pipeline.

### 1. Candidate Expansion

- `role:<name>` expands to the ordered candidate list configured for that role
- `candidate:<provider/model>` expands to a single-item candidate list
- unknown role is an immediate error
- empty role list is an immediate error

### 2. Availability Filtering

Candidates are evaluated in order. A candidate is provisionally selectable only if:

- the provider is enabled by policy
- a usable credential or subscription exists
- required capabilities match the current slot or node need
- the candidate is not disabled, deprecated-out, or otherwise blocked for scheduling
- the current entitlement state appears usable

The first passing candidate becomes the provisional selection.

### 3. Execution-Time Reservation

Before the model request actually runs, the kernel must perform an execution-time reservation or atomic entitlement check.

Rules:

- this second check exists to handle concurrent consumption correctly
- if reservation succeeds, execution proceeds
- if reservation fails for a role-based selection, the kernel tries the next candidate in the same ordered role list
- if reservation fails for an explicit candidate, execution fails immediately

This is how subscription-backed providers such as `codex_subscription` can be preferred first, but automatically fall through when their quota window is exhausted.

## Fallback Rules

Fallback behavior must remain explicit and bounded.

Rules:

- fallback is only allowed inside the currently selected role's ordered candidate list
- explicit candidate selection does not fallback to any other candidate
- v1 does not support implicit cross-role fallback
- if a specialized role such as `coder` is requested and its list is exhausted, execution fails instead of silently switching to `main`
- if no selector is specified at all, the kernel falls back to `interactive`, then to `role:main`

## Snapshot Freezing

Once a candidate is actually selected for execution, the kernel must freeze the resolved choice on the turn or workflow snapshot.

Persist at least:

- selector source
- normalized selector
- resolved role name when applicable
- resolved provider handle
- resolved model ref
- resolution reason
- fallback count
- pinned capability snapshot reference
- pinned policy or entitlement snapshot references when needed

This prevents later catalog or policy changes from reinterpreting historical executions.

## Audit And Profiling

Selection should produce both control-plane and runtime facts.

Audit should focus on durable control-plane mutations such as:

- role catalog changes
- deployment slot-config changes
- policy changes that affect availability
- recovery-time temporary override acceptance

Runtime profiling or workflow-node events should capture:

- requested selector
- selector source
- resolved provider and model
- fallback count
- fallback reason
- reservation failure reason
- terminal "no candidate available" reason

This is the data needed to later answer questions such as:

- which roles most often fall through to the second provider
- which subscriptions are most often exhausted
- which models are most often manually pinned by users

## Recovery-Time Override

When execution pauses because no candidate is currently available, recovery may happen through any of these paths:

- restoring provider availability
- changing role, slot, or policy configuration
- supplying a temporary selector for the recovery action

V1 recovery-time override rules:

- a recovery action may provide a one-time selector override
- that override applies only to the current `manual_resume` or `manual_retry`
- it does not mutate `conversation.selector`
- it does not mutate deployment slot configuration
- it must be frozen into the new execution snapshot
- it must be auditable as a temporary recovery override

This keeps recovery flexible without turning recovery actions into hidden configuration editors.

## Failure Semantics

If no candidate can be resolved:

- execution enters an explicit error or paused state
- the system does not guess another role or model
- an administrator or operator must repair availability or configuration, or trigger a recovery action

Accepted repair paths are:

- fix provider availability
- fix role, slot, or policy configuration
- retry with a one-time recovery override

## Recommended Data-Model Impact

This design implies future implementation work in at least these areas:

- provider catalog gains role-catalog configuration support
- deployment config schema gains flexible agent-defined model slots
- conversation state gains `auto | explicit candidate` selector support for the interactive path
- turn or workflow snapshots gain resolved-model selection metadata
- entitlement handling gains reservation-aware fallback behavior
- recovery services gain one-time selector override support
- audit and profiling services gain model-resolution facts

## Summary

The approved v1 behavior is:

- use ordered provider-qualified candidate lists for roles
- reserve `main` as the default role
- let conversations choose only `auto` or an explicit currently available model
- let agents define flexible internal slots in deployment config
- allow fallback only within the current role's ordered list
- require execution-time entitlement reservation before committing a candidate
- freeze the resolved choice on execution snapshots
- allow one-time recovery overrides without mutating long-term conversation or deployment config
