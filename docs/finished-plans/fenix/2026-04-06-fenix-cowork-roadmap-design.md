# Fenix Cowork Roadmap Design

## Goal

Reposition `Fenix` as the default cowork agent on top of `CoreMatrix`, while
rewriting this roadmap around the current codebase instead of treating the
product as a greenfield design.

## What This Document Is

This document is a status-aware roadmap and calibration pass.

It does three things:

- preserve the stable product thesis
- record which parts of the cowork stack are already landed, partially landed,
  or still missing
- remove planning assumptions that no longer match the current runtime,
  supervision, and acceptance contracts

Status labels in this document mean:

- `landed`: the capability exists as a real product or platform surface
- `partial`: the capability exists, but the product contract is still soft or
  incomplete
- `missing`: the capability is still largely future work
- `stale assumption`: an older planning statement that should no longer be
  treated as current truth

This document is not a fresh architecture proposal. Current code, current
acceptance flows, and later finished plans take precedence over older
exploration notes.

## Stable Product Thesis

The parts of the April 6 thesis that still hold are:

- `CoreMatrix` should remain the kernel and platform substrate.
- `Fenix` should remain the default bundled cowork agent.
- simple requests should stay conversational and lightweight
- complex requests should move into a structured work loop with planning,
  execution, supervision, and evidence-backed delivery
- the strongest validation surface should remain real work inside an existing
  workspace, not synthetic demos
- the default agent should be useful out of the box, while still allowing
  deeper customization over time

## Current State Snapshot

The current codebase is materially further along than the original roadmap
assumed.

- code-owned prompt layers already exist at
  `agents/fenix/prompts/SOUL.md`, `USER.md`, and `OPERATOR.md`
- workspace bootstrapping and `.fenix` runtime state already exist, including
  root memory, daily memory, conversation context files, operator state, and
  per-conversation attachments/artifacts/runs
- skill loading, skill installation, plugin catalogs, and round-time skill
  selection already exist in `Fenix`
- subagent tools and subagent identity projection already exist in the runtime
  contract
- the top-level `acceptance/` harness already owns the main benchmark surface,
  including the `2048` capstone bundle, replay inputs, and capability-oriented
  evidence
- supervision has already moved into a plan-first direction in `CoreMatrix`
- automation turns, schedule/webhook origins, auto-resume paths, and heartbeat
  infrastructure already exist as part of the platform substrate

The main roadmap question is therefore no longer "how do we invent the cowork
stack?" It is "which parts are stable platform, which parts are stable product,
and which parts still need a clearer contract?"

## Capability Roadmap By Area

### Adaptive Interaction: `partial`

Current state:

- `Fenix` already assembles a layered round prompt from code-owned instructions,
  workspace overrides, root memory, conversation summary, and selected skills
- the runtime already distinguishes between main-agent and subagent context
- current supervision work already assumes a structured task model with active
  plan items and recent progress summaries

What is still missing:

- a stable product contract for when the default experience stays lightweight
  versus when it shifts into structured cowork
- durable semantics for `Assistant Mode`, `Work Mode`, and `Lead Mode`
- a clear rule for when those names are user-facing product concepts versus
  internal implementation language

Roadmap implication:

The next interaction work should build on the existing plan, skill, and
operator-state surfaces rather than inventing a second mode system.

### Execution Harness: `landed`

Current state:

- `Fenix` already exposes the core execution families needed for cowork work:
  workspace, memory, shell command execution, long-running processes, browser
  sessions, and web access
- the mailbox-first runtime contract is already in place
- the acceptance harness already treats real execution evidence as the primary
  proof surface

What is still missing:

- continued hardening and cleanup
- sharper product-level wording around what is visible to the user versus what
  stays as debug/runtime detail

Roadmap implication:

This area is no longer greenfield roadmap scope. It is mostly platform
hardening, acceptance hardening, and UI/wording cleanup.

### Multi-Agent Orchestration: `partial`

Current state:

- subagent tools already exist: spawn, send, wait, close, and list
- runtime payloads already carry `is_subagent`, `subagent_connection_id`,
  `parent_subagent_connection_id`, `subagent_depth`, and allowed tool surfaces
- `CoreMatrix` already tracks subagent connections and exposes subagent activity
  into supervision surfaces

What is still missing:

- a stable product contract for delegated roles
- explicit work-package semantics beyond low-level subagent control
- a polished "lead agent" behavior model that feels intentional to the user

Roadmap implication:

The next step is not to prove that subagents are technically possible. The next
step is to turn the existing substrate into a real delegated cowork product
surface with roles, handoff rules, and summary contracts.

### Memory And Customization: `partial`

Current state:

- code-owned prompt layers already exist
- workspace overrides already exist for `SOUL.md` and `USER.md`
- workspace-level memory already exists through `MEMORY.md` and
  `.fenix/.../memory`
- plugin catalogs already compose from bundled system plugins, curated plugins,
  and workspace plugins
- skills already compose from bundled system skills, curated skills, and live
  installed skills
- environment overlays already exist across workspace, program-version, and
  conversation scopes

What is still missing:

- a settled user-scoped private customization model
- a documented authoring model for workspace intelligence as a product feature,
  not just as scattered runtime files
- a final decision on which surfaces are durable public product surfaces versus
  implementation details

Roadmap implication:

Customization work should start from the surfaces that already exist today and
only promote additional layers once they have a real owner and a clear
lifecycle.

### Supervision And Delivery: `landed`

Current state:

- `CoreMatrix` already owns supervision state, turn todo plans, current focus,
  recent progress, and app-facing supervision contracts
- later plans already re-centered supervision around plan-first semantics
- the acceptance harness already produces replayable supervision evidence,
  capability activation outputs, failure classification outputs, and artifact
  bundles
- cowork-facing UI work is already framed around one runtime story plus one
  semantic supervision view

What is still missing:

- continued cleanup of semantic boundaries so platform-owned supervision stays
  generic and agent-owned task semantics stay in the agent
- continued convergence between cowork wording, verbose wording, and acceptance
  replay surfaces

Roadmap implication:

This area should no longer be described as future roadmap aspiration. It is an
active product surface that is already landed and still being refined.

### Ambient Operation: `partial`

Current state:

- automation conversations and automation turns already exist
- turn origin kinds already include schedule and webhook forms
- heartbeat and auto-resume substrate already exist
- background service execution is already part of the runtime control surface

What is still missing:

- a clean user-facing product model for "ambient cowork"
- one shared understanding of when work is interactive, background, scheduled,
  or resume-driven
- a durable contract for how ambient work appears in supervision and final
  delivery

Roadmap implication:

The platform substrate is already partially present. The remaining work is
mostly product-modeling and supervision-modeling, not raw scheduler invention.

## Kernel / Program Split Status

### CoreMatrix: `landed as kernel/platform, still refining semantics`

`CoreMatrix` already owns most of the substrate that the original roadmap
described as `K1` and `K2`, plus part of `K3`.

That includes:

- `Agent`, `AgentSnapshot`, `ExecutionRuntime`, `AgentConnection`, and
  `ExecutionRuntimeConnection`
- turn-scoped runtime binding and capability freezing
- automation turn entry
- supervision state and turn todo plans
- acceptance-harness integration and replay-oriented evidence

The main remaining kernel question is not whether the kernel exists. It is
whether the kernel is still carrying product semantics that should move outward
to the agent boundary.

### Fenix: `landed as bundled default agent, still maturing as product`

`Fenix` already owns:

- code-owned prompts
- workspace bootstrap and runtime state seeding
- prompt assembly
- workspace environment overlays
- skills flow
- plugin catalogs
- operator snapshots
- runtime-side execution helpers

The main remaining product question is not whether `Fenix` is real. It is
which of its current capabilities should become stable cowork UX contracts.

### Split Quality: `stronger than the original roadmap assumed`

The current split is materially clearer than the April 6 document assumed, but
it is not finished.

The strongest remaining boundary work is around:

- supervision semantics
- role/delegation packaging
- customization ownership
- ambient cowork product behavior

## Stale Assumptions To Remove

The following statements from the original roadmap should no longer be treated
as current truth.

### `K1` and `K2` are "mostly landed or close to landed": `stale assumption`

That statement is now too weak.

The better current summary is:

- `K1`: landed
- `K2`: landed and still being refined
- `K3`: partially landed
- `K4`: still future-facing

### The context model is already `user / workspace / conversation`: `stale assumption`

That hierarchy is still a useful product intention, but it is not the current
runtime file-system fact.

Current runtime state is actually organized around:

- `.fenix/agent_snapshots/<id>/memory/...`
- `.fenix/agent_snapshots/<id>/conversations/<id>/context/...`

Any future `user / workspace / conversation` model should be introduced as an
explicit design decision, not treated as if it already exists.

### The proposed file-system model is current truth: `stale assumption`

The original doc described:

- `~/.fenix/users/<user_public_id>/...`
- `<workspace>/.fenix/workspace/...`
- `<workspace>/.fenix/conversations/<conversation_public_id>/...`

That is not the current implementation.

Current facts are:

- `SOUL.md` and `USER.md` can already be overridden from the workspace root
- `OPERATOR.md` currently remains code-owned in the bundled prompt set
- workspace plugins live under `.fenix/plugins`
- workspace and conversation state live under the program-version-scoped
  `.fenix` layout
- a user-scoped private home directory model is not yet implemented as a real
  contract

### `OPERATOR` belongs to the same editable preset layer as `SOUL` and `USER`: `stale assumption`

Today, `SOUL.md` and `USER.md` are part of the workspace override surface.
`OPERATOR.md` is still bundled from the repository and only injected for the
main non-subagent profile.

If `OPERATOR` should become editable later, that needs its own design pass.

### Acceptance is mainly a future benchmark plan: `stale assumption`

The acceptance model is already much more real than the original roadmap
described.

The current harness already has:

- primitive validation scenarios
- the `2048` capstone bundle
- capability activation reporting
- failure classification reporting
- replayable supervision evaluation inputs

Future roadmap work should extend that evidence model, not describe it as if it
is still hypothetical.

### `F1 / F2 / F3` and `K1 / K2 / K3 / K4` are the right next planning frame: `stale assumption`

Those labels were useful while the architecture was still less settled.

They are now too linear for the current state of the repo. The next planning
work should follow product seams and ownership seams, not the original phase
labels.

## Next Planning Focus

The most useful next planning threads are now the following.

### 1. Interaction Contract

Define:

- when the default experience stays lightweight
- when it enters structured cowork behavior
- whether `Assistant Mode`, `Work Mode`, and `Lead Mode` are real product
  surfaces or only internal shorthand

This should build on the existing prompt, plan, and supervision stack.

### 2. Customization And Memory Ownership

Define:

- which customization surfaces are already durable
- which ones are still implementation details
- whether a user-scoped private layer should exist at all
- how workspace intelligence should be authored, shared, and versioned

This work should start from the existing prompt, memory, plugin, skill, and env
overlay surfaces rather than from the old speculative file layout.

### 3. Delegated Cowork Productization

Define:

- the role model for delegated workers
- the contract for work packages and handoff summaries
- what the user should see when the main agent delegates work
- how much of the current subagent surface remains low-level runtime detail

The technical substrate already exists. The missing work is product shaping.

### 4. Ambient Cowork Model

Define:

- how scheduled, webhook-driven, resume-driven, and background work fit into one
  product story
- how ambient work appears in supervision and final delivery
- how the default bundled agent should behave when work continues without active
  foreground interaction

This is the main roadmap topic that sits on top of the already-partial
automation and runtime-recovery substrate.

## Summary

`Fenix` is no longer a mostly hypothetical cowork roadmap. It is already a real
bundled agent with meaningful runtime, supervision, customization, and
acceptance surfaces.

The next stage of planning should therefore stop treating the project as a
greenfield build. The right job now is to clarify product contracts, tighten
the kernel/program boundary, and turn already-landed technical capabilities
into a cleaner cowork product.
