# Workspace-Agent Profile Catalog Design

## Goal

Introduce a Fenix-owned profile catalog for interactive and delegated work,
keep all prompt/business content local to Fenix, and let `WorkspaceAgent`
carry only small mount-scoped override settings that choose profiles and
constrain delegation behavior.

This round is a follow-up to
[`2026-04-16-workspace-agent-global-instructions-design.md`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-16-workspace-agent-global-instructions-design.md).
`global_instructions` remains a plain mount-scoped text block. The new profile
system adds structured selection and delegation policy on top of that contract
without moving prompt ownership back into CoreMatrix.

## Problem

Today Fenix still has only a coarse profile distinction:

- current interactive work defaults to profile key `main`
- delegated work commonly uses profile key `researcher`
- prompt assembly still effectively chooses between one interactive overlay and
  one delegated overlay

That is too narrow for the next round of `WorkspaceAgent` settings:

- users want to switch the mounted agent's primary working style
- delegated specialists should be explicit and selectable
- mount settings should control delegation depth/concurrency/default specialist
- CoreMatrix must not learn or persist Fenix-owned prompt business data

The design therefore needs a clean split:

- Fenix owns profile catalog content and routing hints
- CoreMatrix owns mount-scoped override state and capability enforcement
- the protocol carries only small resolved facts, not prompt bundles

## Design Principles

1. Prompt/profile content remains agent-owned. CoreMatrix must not persist
   prompt fragments, routing copy, or model-hint catalogs.
2. Mount settings carry only overrides and policy. They choose among agent-owned
   profile keys; they do not define profiles.
3. The wire contract stays small. Cross-service payloads carry only profile
   keys and small resolved selector hints when strictly necessary.
4. Delegation behavior must be auditable. Child turns must freeze the selected
   specialist key and any resolved model-selector hint used for that spawn.
5. Capability authority stays in CoreMatrix. Fenix may bias or describe tool
   usage in prompt text, but it does not declare runtime-visible tools.
6. Built-in external keys should not churn without product value. Existing
   visible keys such as `main` and `researcher` should remain valid unless
   there is a concrete reason to break them.

## Recommended Ownership Split

### Fenix owns the profile catalog

Fenix should own:

- profile labels and descriptions
- prompt fragments
- routing hints such as `when_to_use`
- model hints
- skill hints

These live in the `agents/fenix` repo and are loaded locally by Fenix.

### CoreMatrix owns mount-scoped override state

CoreMatrix should own only small mutable settings on `WorkspaceAgent`, such as:

- which interactive profile key is active for this mount
- which specialist profile key is the default delegation target
- which specialist profile keys are enabled
- delegation depth/concurrency policy
- optional small model-selector override hints

CoreMatrix stores those scalar settings because they are durable per-mount
product state. It must not store the catalog those keys refer to.

## Fenix Profile Catalog

### Directory Contract

Fenix should load profiles from two builtin trees:

- `agents/fenix/prompts/main/<profile_key>/`
- `agents/fenix/prompts/specialists/<profile_key>/`

Each profile directory has the same structure:

- `meta.yml`
- optional `SOUL.md`
- optional `USER.md`
- optional `WORKER.md`

The metadata schema is the same for both trees. The tree location expresses the
catalog group, not a different file format.

Example layout:

```text
agents/fenix/prompts/main/main/meta.yml
agents/fenix/prompts/main/main/SOUL.md
agents/fenix/prompts/main/main/USER.md
agents/fenix/prompts/main/friendly/meta.yml
agents/fenix/prompts/main/friendly/USER.md
agents/fenix/prompts/specialists/researcher/meta.yml
agents/fenix/prompts/specialists/researcher/WORKER.md
```

### Initial Key Strategy

The first round should preserve existing externally visible keys where
possible:

- keep `main` as the default interactive key
- keep `researcher` as the existing delegated specialist key

If product copy wants to describe `main` as "pragmatic", that should be done
through metadata labels, not by renaming the external key in the first round.
That keeps current `profile_key` semantics stable across runtime manifests,
tooling, supervision, and existing tests.

### Initial Builtin Profile Set

The first round should stay intentionally small:

- interactive profiles:
  - `main`
  - `friendly`
- specialist profiles:
  - `researcher`
  - `developer`
  - `tester`

`developer` replaces the vaguer `editor` label. `translator` is intentionally
deferred until there is a stable product need for a language-specialist route.

### `meta.yml`

`meta.yml` should contain only metadata and local hints, for example:

```yaml
label: Pragmatic
description: Default direct cowork style for iterative engineering work.
when_to_use:
  - General implementation and debugging
  - Most interactive coding sessions
avoid_when:
  - The task is clearly a delegated deep-dive best handled by a specialist
example_tasks:
  - Fix the failing Rails test and explain the root cause
model_hints:
  preferred_roles:
    - coding
  preferred_models:
    - gpt-5.4
skill_hints:
  - layered-rails
  - systematic-debugging
```

Allowed hint categories in this round:

- `label`
- `description`
- `when_to_use`
- `avoid_when`
- `example_tasks`
- `model_hints`
- `skill_hints`

This round intentionally does **not** add tool allow/deny metadata. Actual tool
visibility remains a CoreMatrix capability concern.

### Prompt Fragment Fallback Rules

Prompt files should be optional with strict fallback behavior:

- interactive execution:
  - use `USER.md` when present
  - otherwise fall back to `WORKER.md`
- subagent execution:
  - use `WORKER.md` when present
  - otherwise fall back to `USER.md`
- if neither `USER.md` nor `WORKER.md` exists, the profile is invalid
- `SOUL.md` is optional:
  - use the profile-local file when present
  - otherwise fall back to the shared builtin `agents/fenix/prompts/SOUL.md`

This keeps profile directories compact while avoiding forced duplication of
large common prompt text.

### Prompt Authoring Guidance

Profile prompts should explicitly borrow proven patterns from the mature
reference projects already reviewed for this design, while remaining Fenix's
own source of truth.

Use these reference principles:

- Codex:
  - role prompts should describe task semantics and operating boundaries, not
    just speaking style
  - specialist keys should read like roles (`researcher`, `developer`,
    `tester`), not whimsical personas
- Hermes Agent:
  - specialist prompts should clearly state delegation scope, desired evidence
    standard, and when further delegation is or is not appropriate
- Claude Code:
  - focused subagents should have narrow task framing and avoid pretending to
    be general-purpose sessions when they are not
- Paperclip:
  - metadata and prompt packaging should stay structured and lightweight rather
    than becoming an ad hoc prompt pile

Prompt-writing rules for this round:

- each specialist prompt should state what it is for, what it should optimize
  for, and what it should avoid
- `researcher` should bias toward evidence gathering and diagnosis over code
  changes
- `developer` should bias toward bounded implementation and refactoring work
- `tester` should bias toward reproduction, validation, and acceptance proof
- `friendly` may change tone and collaboration style, but should not weaken the
  default engineering rigor expected from `main`

These reference projects inform prompt quality only. They do not define the
runtime contract and do not override Fenix's local catalog.

### `prompts.d` Override Contract

Fenix should support a local override tree modeled after `core_matrix/config.d`,
but with simpler semantics:

- `agents/fenix/prompts.d/main/<profile_key>/...`
- `agents/fenix/prompts.d/specialists/<profile_key>/...`

Rules:

- same catalog group + same profile key replaces the entire builtin profile
  directory
- there is no deep merge inside `meta.yml`
- there is no file-level partial merge
- resolution chooses exactly one source directory for a profile:
  builtin or override

This "whole directory replace" rule keeps prompt/profile provenance legible and
prevents mixed-source half-overrides.

## WorkspaceAgent Mount Overrides

### Storage

Introduce a new mount-scoped JSON field on `WorkspaceAgent`:

- `settings_payload`

This field is authoritative current editable override state for one mounted
agent in one workspace.

Suggested shape for this round:

```json
{
  "interactive_profile_key": "main",
  "default_subagent_profile_key": "researcher",
  "enabled_subagent_profile_keys": ["researcher"],
  "delegation_mode": "allow",
  "max_concurrent_subagents": 3,
  "max_subagent_depth": 2,
  "allow_nested_subagents": true,
  "default_subagent_model_selector_hint": "coding-fast"
}
```

Rules:

- blank or absent means "use agent/runtime defaults"
- only supported keys are accepted
- unknown keys are rejected
- values normalize into a stable JSON shape
- this payload stores only small mount-scoped settings, never prompt bodies

### Scope of Settings

This round supports only override data that is both:

- durable per mount
- independent of prompt business content

That includes:

- active interactive profile key
- enabled/default specialist keys
- delegation policy
- optional default subagent model-selector hint

This round does **not** add:

- prompt fragment overrides
- arbitrary profile definitions in CoreMatrix
- per-profile tool policies

### Precedence And Existing Config Integration

`WorkspaceAgent.settings_payload` is a mount-scoped override layer. It must not
rewrite agent-owned defaults on `AgentDefinitionVersion` or `AgentConfigState`.

Required precedence:

1. agent/runtime-owned defaults from the effective canonical config remain the
   base layer
2. mount-scoped `WorkspaceAgent.settings_payload` overlays that base only for
   conversations running through that mounted agent
3. existing conversation-scoped mutable overrides remain limited to the current
   narrow subagent policy surface; this round does not reopen conversation-level
   interactive profile mutation

Consequences:

- `interactive_profile_key` must affect turn/runtime behavior for the mounted
  workspace without mutating the underlying agent config state
- selector resolution for mounted interactive turns must respect the mount
  override before falling back to the agent-owned default interactive profile
- the implementation must be explicit about how the mount override maps onto
  the existing `interactive.default_profile_key` / normalized `interactive.profile`
  projection already used by current runtime contracts

### App Surface

Expose `settings_payload` through the existing `WorkspaceAgent` app surface:

- create/update through `WorkspaceAgentsController`
- present through `WorkspaceAgentPresenter`
- include in workspace list fan-out payloads

App-facing payloads must continue to use only public ids and small JSON values.

## Runtime And Protocol Contract

### `workspace_agent_context`

Extend the existing `workspace_agent_context` contract with a compact profile
settings view:

```json
{
  "workspace_agent_context": {
    "workspace_agent_id": "wsa_...",
    "global_instructions": "...",
    "profile_settings": {
      "interactive_profile_key": "main",
      "default_subagent_profile_key": "researcher",
      "enabled_subagent_profile_keys": ["researcher"],
      "delegation_mode": "allow",
      "max_concurrent_subagents": 3,
      "max_subagent_depth": 2,
      "allow_nested_subagents": true,
      "default_subagent_model_selector_hint": "coding-fast"
    }
  }
}
```

Rules:

- no profile catalog crosses this boundary
- no prompt text other than `global_instructions` crosses this boundary
- this payload contains only the current mount-scoped override state needed by
  Fenix to route work
- `default_subagent_model_selector_hint` is present when the mount sets one, so
  Fenix can use it as the fallback hint when constructing `subagent_spawn`
  requests that do not choose a more specific specialist hint locally

This shape must remain consistent across:

- `ExecutionContract`
- `TurnExecutionSnapshot`
- direct `prepare_round` payloads
- mailbox compaction/reconstruction

### `subagent_spawn`

`subagent_spawn` should continue to accept `profile_key`, and add only one
optional model-related field:

- `model_selector_hint`

That hint is a small resolved scalar chosen by Fenix when it decides a specific
specialist should use a non-default model preference. It should be optional and
fall back cleanly to normal selector behavior when absent or unsupported.

This is the only new profile-related field that needs to cross the delegation
tool boundary in this round.

The `profile_key` choices exposed in the visible `subagent_spawn` tool schema
must be narrowed to:

- `default`
- explicitly enabled specialist profile keys for the current mount

Interactive-only profiles must not appear in that schema. The main agent should
not be invited to choose disabled or non-specialist profiles and then learn via
runtime rejection.

### Frozen Child State

When CoreMatrix spawns a child turn, it should freeze:

- the resolved specialist `profile_key`
- the optional resolved `model_selector_hint`

Those frozen facts belong in the child turn's execution-visible contract and in
the persisted `delegation_package`, not in mutable live-only state.

## Fenix Routing Behavior

### Main-Agent Routing

The main agent should decide whether to delegate using:

- current task/request context
- `workspace_agent_context.profile_settings`
- its local specialist catalog metadata

Fenix should synthesize a compact internal routing summary from:

- locally loaded specialist metadata
- intersection with the enabled specialist keys from CoreMatrix

That summary can then be rendered into prompt guidance such as:

- available specialist keys
- when each should be used
- default specialist profile
- delegation mode and nesting limits

Because the catalog stays local, this adds no large wire payload.

### Delegation Modes

Recommended initial modes:

- `allow`
  - delegation is available, but not preferred
- `prefer`
  - when an enabled specialist clearly matches the task, delegation should be
    preferred over inline handling

This is intentionally narrow. The goal is to nudge routing behavior without
creating a complex strategy DSL.

### Specialist Selection Safety

To reduce wrong-specialist selection:

- start with a small specialist catalog
- require each specialist to declare `when_to_use`, `avoid_when`, and
  `example_tasks`
- permit `default` alias resolution when Fenix wants delegation but does not
  have strong confidence in a specific specialist key

## Model Hint Semantics

`model_hints` are Fenix-owned advisory metadata. They are not hard model ids
owned by CoreMatrix.

Rules:

- Fenix may use local `model_hints` to resolve a small `model_selector_hint`
  when spawning a child specialist
- when no stronger specialist-local hint is selected, Fenix may fall back to
  `workspace_agent_context.profile_settings.default_subagent_model_selector_hint`
- if the current runtime/provider cannot satisfy that hint, CoreMatrix falls
  back to the ordinary default selection path
- this round does not require CoreMatrix to know the full profile-local model
  hint catalog

This keeps model-routing extensible without teaching CoreMatrix about Fenix
business semantics.

## Capability Authority

Capability authority remains unchanged:

- CoreMatrix decides the visible tool/capability surface
- Fenix may bias behavior through prompt text and routing metadata
- `WorkspaceAgent.settings_payload` may later add coarse capability toggles,
  but that is outside this round unless they map directly onto existing
  CoreMatrix capability policy primitives

No profile-local tool allow/deny lists are introduced in this design.

## Export And Review Artifacts

The current export surfaces are asymmetrical:

- `conversation export` is user-facing and transcript-oriented; it currently does
  not include subagent/specialist data
- `conversation debug export` already includes `subagent_connections.json`, but
  today it only records compact session facts such as `profile_key`

This follow-up should make subagent/specialist usage easier to inspect in both
product-facing and operator-facing outputs.

### Conversation Export

Add a compact delegation summary to the ordinary `conversation export` bundle.

Recommended shape:

```json
{
  "delegation_summary": [
    {
      "subagent_connection_id": "subagent_...",
      "origin_turn_id": "turn_...",
      "profile_key": "researcher",
      "specialist_key": "researcher",
      "profile_group": "specialist",
      "close_outcome_kind": "completed"
    }
  ]
}
```

Rules:

- keep this summary intentionally compact
- include only stable public ids and small classification facts
- do not copy prompt/catalog metadata into the export
- when no subagents were used, emit an empty array rather than omitting the key

### Debug Export

Extend `conversation debug export` so `subagent_connections.json` and related
workflow/task records include the new specialist-facing facts introduced by
this round:

- `profile_group`
- `specialist_key`
- `resolved_model_selector_hint` when present

The debug export should remain the complete internal trace surface, while the
ordinary conversation export should present a compact summary suitable for
artifact review.

### Acceptance Review Directory

Acceptance artifact generation should also emit a Mermaid workflow view into the
scenario's `review/` directory so humans can inspect the internal execution
shape without opening raw debug JSON.

Recommended file:

- `review/workflow-mermaid.md`

Recommended contents:

- a short legend describing node/state labels
- one fenced Mermaid diagram for the conversation's workflow graph
- visible subagent spawn nodes labeled with the selected specialist/profile key
- waiting/barrier states when present

This review artifact is a presentation export only. It should be generated from
existing debug/export evidence rather than becoming a new source of truth.

## Non-Goals

This design intentionally does **not** do the following:

- no prompt/profile catalog stored in CoreMatrix
- no deep merge of prompt/profile overrides
- no file-level partial override inside one profile
- no per-profile tool allow/deny metadata
- no generic arbitrary mount settings bag beyond the documented keys
- no requirement that interactive model selection use profile-local metadata in
  the first request path
- no widening of the protocol to carry full profile descriptors

## Testing And Verification Expectations

### Fenix

Focused tests should lock:

- profile directory discovery and validation
- `prompts.d` whole-directory override resolution
- `SOUL.md` / `USER.md` / `WORKER.md` fallback behavior
- local catalog projection for routing summaries
- prompt assembly using selected interactive/specialist profile bundles

### CoreMatrix

Focused tests should lock:

- `WorkspaceAgent.settings_payload` normalization/validation
- app-surface presentation and update semantics
- workspace list preload behavior
- mount-scoped interactive profile override precedence against the existing
  agent canonical config layer
- execution snapshot freezing of `workspace_agent_context.profile_settings`
- mailbox compaction/reconstruction for the same frozen shape
- `subagent_spawn` schema filtering to enabled specialist keys plus `default`
- `subagent_spawn` validation and persistence of optional
  `model_selector_hint`
- child turn execution state preserving frozen profile/model-selector facts

### End-To-End

At least one acceptance-critical loop should prove:

- the mounted agent sees only compact profile settings over the wire
- Fenix can choose an enabled specialist and spawn it
- child execution receives the frozen specialist key and any resolved selector
  hint
- no prompt catalog content is persisted in CoreMatrix tables
- ordinary conversation export includes compact specialist/subagent summary
- debug export includes specialist-facing subagent facts
- acceptance `review/` output includes a Mermaid workflow view that visibly
  marks specialist/subagent nodes
