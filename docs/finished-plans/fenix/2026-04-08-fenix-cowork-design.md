# Fenix Cowork Design

> `agents/fenix` is now the only cowork implementation in this repository.
> References to `agents/fenix.old` in this document are historical notes from
> the migration period; the legacy app has been removed.

## Goal

Build `agents/fenix` as a cowork-first agent that fits the
`CoreMatrix` agent loop, mirrors the proven cowork behavior of
`references/claude-code-sourcemap/restored-src`, and reaches the `2048`
acceptance capstone through native plan, delegation, and delivery behavior.

## Repo Reality

- `agents/fenix`
  - the new cowork-first Rails app
- `agents/fenix.old`
  - historical migration-era reference only
  - no longer present in the live repository
- `core_matrix`
  - the neutral orchestration kernel
- `references/claude-code-sourcemap/restored-src`
  - the behavioral reference for cowork semantics
- `references/original/references/codex-universal`
  - a structure and environment-design reference only
  - not the version source of truth

## Product Target

The target is not generic "agent capability". The target is cowork behavior
close to the reference implementation:

- structured task shaping
- durable plan-driven execution
- delegated child work
- evidence-backed delivery
- layered prompt composition that supports those behaviors reliably

Innovation comes after the baseline cowork behavior is proven.

## Deployment Model

`agents/fenix` supports two intentionally different deployment paths.

### Bare-Metal

For advanced users, `fenix` may run on a host-controlled environment.

Properties:

- the user owns the trust and security boundary
- the user controls software and hardware directly
- platform-native capabilities remain available
- macOS-specific automation such as AppleScript remains possible

Bare-metal is not expected to look like Docker. It should validate required
host capabilities rather than pretending the host is a container.

For `v1`, bare-metal support means:

- document the host contract clearly
- provide a lightweight host-capability validator
- preserve room for platform-native integrations such as AppleScript

It does not mean bare-metal becomes part of the 2048 acceptance gate in this
phase.

### Docker With `images/nexus`

For default out-of-the-box use, `fenix` runs in Docker on top of
`images/nexus`.

Properties:

- cowork starts with a ready toolchain instead of spending turns finding tools
- the runtime gets a stable, reproducible development-machine baseline
- long-tail development tasks have broad coverage without per-task bootstrap

`images/nexus` is therefore part of `v1`, not a later optimization.

## `images/nexus`

`images/nexus` is a monorepo subproject that provides the Docker-only runtime
base image for `agents/fenix`.

It is:

- the default Docker deployment base for the agent runtime
- a prebuilt cowork-friendly toolchain image
- a reusable runtime base for future agent runtimes if needed

It is not:

- a CI image
- a devcontainer base
- a generic monorepo base image
- a place for prompt logic, memory logic, or product behavior

### `images/nexus` V1 Contents

`images/nexus` should include only durable, cross-task capabilities that
materially improve cowork success:

- Ubuntu 24.04 LTS
- common CLI/build tools such as `bash`, `curl`, `git`, `jq`, `unzip`, `zip`,
  `ripgrep`, `fd`, `sqlite3`, `build-essential`, `pkg-config`
- Node LTS plus `npm`, `corepack`, `pnpm`
- `vite` and `create-vite`
- Playwright plus Chromium
- Python plus `uv`
- Ruby runtime and native extension build prerequisites
- Go stable
- Rust stable
- an image-local `verify.sh` that proves the image is usable

The image should borrow good structural ideas from `codex-universal`, but it
should remain much narrower. We want a cowork runtime base, not a clone of a
multi-language universal development workstation.

## Boundary And Ownership

### `CoreMatrix` Owns

`CoreMatrix` remains the neutral kernel and orchestration platform. It owns:

- turn, workflow, and runtime durability
- agent communication contracts
- tool visibility and routing
- subagent connection durability
- supervision state and turn feeds
- app-facing read models and future UI/API surfaces
- acceptance-harness execution entry points

All platform changes for this work must remain:

- agent-neutral
- semantically generic
- capability-optional

`CoreMatrix` must not absorb cowork-specific product semantics that belong to
`fenix`.

### `agents/fenix` Owns

`fenix` owns the cowork product semantics:

- deciding when to enter structured cowork behavior
- forming and updating plans
- deciding when to delegate
- defining delegation packages and result synthesis
- building final delivery responses
- prompt layout and prompt assembly
- agent-side `Memory`
- agent-side `Skills`

Those remain inside the agent even if `CoreMatrix` later exposes richer
neutral runtime surfaces.

### No Second Truth

`fenix` may keep its own prompts, memory files, skill packages, and prompt
assembly state.

`fenix` must not keep its own durable truth for:

- turn lifecycle
- active plan truth
- subagent lifecycle
- supervision truth

Whenever that state needs to be durable, inspectable, or UI-consumable, it must
flow through `CoreMatrix`.

## Allowed Platform Changes

This phase may make breaking changes to `CoreMatrix` contracts and surfaces.

Rules:

- no compatibility shims are required
- no old development data needs to be preserved
- no backfill path is required
- `fenix.old` and `fenix` should still be treated as sibling consumers of a
  neutral platform

Breaking changes are acceptable only when they improve multi-agent
platform quality rather than embedding `fenix` product logic in the kernel.

## Reference Strategy

This design uses three reference sources for different purposes.

### Claude Cowork Reference

Use `references/claude-code-sourcemap/restored-src` for:

- cowork interaction model
- coordinator and worker behavior expectations
- layered prompt layout
- dynamic prompt build pipeline
- plan-centric work style
- delegation behavior and result synthesis

Do not use it to copy file layout, UI/CLI implementation, or non-CoreMatrix
transport assumptions.

### `fenix.old`

Use `agents/fenix.old` for:

- runtime-control patterns
- bundled runtime registration and mailbox execution
- execution-runtime-plane tool execution
- browser/process/command runtime patterns
- previous acceptance integration lessons

Do not treat it as the target product or target architecture.

### `codex-universal`

Use `references/original/references/codex-universal` for:

- base image project shape
- image verification patterns
- layering ideas between base environment and app image

Do not treat its pinned versions or language matrix as our truth.

## Prompt Layout And Prompt Build Pipeline

`fenix` should explicitly copy the style of the reference prompt system: layered
layout, deterministic assembly, lazy context expansion, and clear separation
between durable platform facts and agent semantics.

### Prompt Layout

The prompt layout should contain these ordered layers:

1. `Code-owned base`
2. `Role or mode overlay`
3. `Workspace and project instructions`
4. `Skill overlay`
5. `CoreMatrix durable state`
6. `Execution-local fenix context`
7. `Transcript layer`

### Prompt Build Pipeline

The build pipeline should follow a fixed sequence:

1. validate the `CoreMatrix` request payload
2. choose the prompt profile for main or child execution
3. load project instructions and memory
4. resolve active skills lazily
5. attach neutral durable state from `CoreMatrix`
6. assemble prompt sections deterministically
7. emit prepared round messages and visible tool surface

### Prompt Ownership Rule

`CoreMatrix` provides durable facts. `fenix` provides semantic prompt
composition.

That is the critical split. `CoreMatrix` should not manufacture cowork prompt
language. `fenix` should not create a second durable task state.

## Internal Architecture For `agents/fenix`

The new app should use a hard internal separation so cowork logic does not get
mixed with Rails transport or local infrastructure details.

### 1. Program Boundary

Owns:

- `prepare_round`
- `execute_tool`
- mailbox payload validation
- response serialization

It should not contain product decisions.

### 2. Runtime Boundary

Owns:

- runtime manifest and registration metadata
- mailbox polling and realtime delivery
- persistent runtime worker entrypoints
- execution-runtime-plane tool execution
- runtime-local resource registries

This layer is where `fenix` becomes a real bundled runtime rather than only an
agent prompt adapter.

### 3. Application Layer

Owns cowork use cases such as:

- preparing a round
- deciding work mode
- building or updating a plan
- deciding delegation
- synthesizing child results
- assembling final delivery

### 4. Domain Layer

Models `fenix` concepts rather than Rails or mailbox details. Examples:

- `WorkIntent`
- `WorkModeDecision`
- `PlanDraft`
- `DelegationPackage`
- `DelegationResult`
- `DeliveryBundle`

### 5. Infrastructure Layer

Owns local implementations such as:

- prompt assembly
- memory storage
- skills loading
- `CoreMatrix` contract adapters
- runtime tool adapters
- reference-analysis helpers if needed

`Memory` and `Skills` remain in `fenix`, but still belong in infrastructure
rather than leaking into application policy.

## CoreMatrix Contract Requirements

`fenix` should be designed against `CoreMatrix` as it exists today, but it also
needs platform refinements.

### Already Strong Enough For V1

The following platform surfaces are already a strong basis for v1:

- versioned mailbox-first agent exchange
- runtime capability contracts and visible tool surfaces
- durable turn todo plan write path
- turn todo plan read models
- durable subagent connection substrate
- supervision state and snapshot read models
- acceptance execution through `CoreMatrix`

### Needs To Be Strengthened

The following areas still need platform work:

- neutral `work_context_view` in `prepare_round`
- structured delegation package durability
- structured child result envelope durability
- read models that are stable enough for future UI/API consumers

These surfaces must stay generic. They are not allowed to say "cowork mode" or
otherwise encode `fenix` product language.

## V1 Scope

`v1` is not "all of old `fenix` plus cowork". It is the smallest complete slice
that proves the new architecture can deliver the 2048 capstone.

`v1` must include:

- `images/nexus`
- bundled runtime registration with both agent and execution-runtime planes
- mailbox runtime worker and control loop
- enough execution-runtime-plane tools to build, run, and browser-verify the 2048 app
- layered prompt assembly
- agent-side memory and skills support
- neutral `CoreMatrix` work-context and delegation/result contracts
- a `fenix`-specific 2048 acceptance path with no `using-superpowers`
  dependency
- a documented bare-metal host contract plus a lightweight validator script

`v1` explicitly does not include:

- GHCR publishing
- CI or devcontainer reuse of `images/nexus`
- broad parity with all `fenix.old` capabilities
- a wide language/runtime matrix in the base image
- a UI/client product surface
- ambient/background cowork productization
- bare-metal parity with the Docker acceptance environment

## Acceptance Target

The `v1` proof target is the 2048 capstone run through `CoreMatrix` and the
acceptance harness.

That gate is Docker-first and runs on top of `images/nexus`.

The executable scripts, scenario text, generated artifacts, and written
acceptance checklist must describe the same gate. `v1` is not complete if those
surfaces drift.

Bare-metal remains a supported deployment shape, but its `v1` proof obligation
is limited to a clear host contract and capability validation rather than full
2048 acceptance parity.

The important property is not only that the game gets produced, but that it is
produced through:

- the real mailbox/runtime path
- the real plan and delegation path
- the real execution-runtime-plane tool surface
- a `fenix` runtime that starts with the necessary toolchain already available

That is the minimum proof that the new architecture is better, not merely
different.
