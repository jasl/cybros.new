# Fenix Cowork Roadmap Design

## Goal

Reposition `Fenix` from "default runtime validation product" into the default
adaptive cowork agent on top of `CoreMatrix`, while preserving `CoreMatrix` as a
general agent kernel and using the existing `acceptance/` harness as the main
proof surface for real loop behavior.

## Product Definition

- `CoreMatrix` remains the general agent kernel.
- `Fenix` becomes the default adaptive cowork agent.
- "Coding" is treated as a core computer-use capability, not the product
  category.
- The first strong validation battlefield stays "real work inside an existing
  codebase", but the product definition is broader: research, environment setup,
  software creation, and other real-world tasks.

## External References

We are intentionally borrowing from two mature products for different reasons:

- `Claude Cowork` / `Claude Code`
  - internal organization model
  - coordinator-first task synthesis
  - worker/subagent structuring
  - layered instruction files
  - memory scopes and host isolation
- `OpenClaw`
  - product packaging
  - out-of-box usefulness
  - personal-agent framing
  - user expectation that the default agent is worth using immediately

We do not want a copycat. The target is to land the mature baseline first, then
differentiate through stronger program-level customizability and a cleaner
kernel/program split.

## Core Product Thesis

The default cowork agent should feel like:

- assistant-first on the surface
- operator-first in its execution core

Simple tasks should stay light. Complex tasks should automatically shift into a
structured work mode with planning, execution, verification, supervision, and
delivery.

## Capability Model

The complete capability model for the target product is:

1. `Adaptive interaction`
   - simple tasks handled conversationally
   - complex tasks routed into structured work
2. `Execution harness`
   - shell, files, browser, processes, web access, scripting, and data handling
3. `Multi-agent orchestration`
   - main agent synthesis
   - delegated worker roles
   - controlled parallelism
4. `Persistent personalization`
   - user-specific preferences
   - workspace intelligence
   - programmable roles, skills, and policies
5. `Supervision and delivery`
   - visible progress
   - current focus
   - blockers
   - next-step hints
   - final evidence-backed handoff
6. `Ambient operation`
   - scheduled work
   - triggered work
   - long-running background sessions

## Dual Roadmap

### Fenix roadmap

#### F1: Solo Adaptive Cowork

Ship a default cowork agent that is immediately useful for real tasks.

Primary outcomes:

- `Assistant Mode` for light tasks
- `Work Mode` for structured tasks
- durable delivery summaries
- automatic skill selection
- explicit user/workspace/conversation context layering

#### F2: Directed Cowork

Add main-agent-led delegated execution.

Primary outcomes:

- `Lead Mode`
- formal delegated roles
- work packages
- subagent orchestration
- synthesis-first coordinator behavior

Initial role set:

- `researcher`
- `planner`
- `implementer`
- `reviewer`

#### F3: Programmable Personal Cowork

Make `Fenix` programmable at the agent-program layer without requiring kernel
changes.

Primary outcomes:

- editable layered instruction files
- workspace-scoped shared intelligence
- user-scoped private preferences
- programmable roles
- skills and policy bundles
- controlled self-improvement proposals that modify these files

### CoreMatrix roadmap

#### K1: Agent Loop Kernel

Provide the stable execution substrate:

- workflow state
- mailbox-first control
- runtime registration and capability handshake
- durable tool governance
- resource lifecycle

#### K2: Supervision + Control Plane

Provide the platform substrate for cowork supervision:

- supervision state
- sidechat
- activity feed
- active subagents
- plan/progress projections
- control requests

#### K3: Ambient Runtime

Provide:

- scheduled runs
- external triggers
- background sessions
- resume/recovery behavior

#### K4: Multi-Program Platform

Prove the kernel/program split by supporting multiple agent programs beyond
`Fenix`.

## Current Planning Assumption

For planning purposes, `K1` and `K2` are treated as mostly landed or close to
landed. The next concrete work should therefore:

- keep `F1/F2/F3` as product targets
- treat `K1/K2` as gap-audit and hardening topics
- delay `K3/K4` until after the first cowork benchmark improvements are in place

## Context Model

The intended logical hierarchy is:

- `user`
- `workspace`
- `conversation`

Meaning:

- `user` owns long-lived personal preferences
- `workspace` accumulates shared intelligence for that work domain
- `conversation` carries task-local state and transient execution context

This is more accurate for the target product than the current informal
`root/conversation/daily` memory framing.

## Customization Model

### Code-owned preset layer

Product-owned prompt files should live in source control and load at runtime.

This layer defines:

- core identity
- operator posture
- default work style
- baseline safety and delivery behavior

This should remain code-owned and versioned in the repository, not embedded as
long string constants.

### User layer

Private, cross-workspace instructions for a user.

Examples:

- explanation depth
- communication style
- personal environments
- personal workflow quirks
- private long-lived memory

### Workspace intelligence layer

Shared intelligence for a workspace.

Examples:

- conventions
- recurring workflows
- common gotchas
- team-level task decomposition patterns
- workspace-specific skills and role definitions

### Conversation layer

Task-local state.

Examples:

- conversation summary
- transient memory
- operator state
- current work package state

## Proposed File System Model

### Code-owned presets

- `agents/fenix/prompts/SOUL.md`
- `agents/fenix/prompts/USER.md`
- `agents/fenix/prompts/OPERATOR.md`

### User layer

- `~/.fenix/users/<user_public_id>/FENIX.md`
- `~/.fenix/users/<user_public_id>/rules/*.md`
- `~/.fenix/users/<user_public_id>/agents/*.md`
- `~/.fenix/users/<user_public_id>/skills/*`
- `~/.fenix/users/<user_public_id>/policies/*.yml`

### Workspace layer

- `<workspace>/.fenix/workspace/FENIX.md`
- `<workspace>/.fenix/workspace/rules/*.md`
- `<workspace>/.fenix/workspace/agents/*.md`
- `<workspace>/.fenix/workspace/skills/*`
- `<workspace>/.fenix/workspace/policies/*.yml`
- `<workspace>/.fenix/workspace/memory/*.md`

### Conversation layer

- `<workspace>/.fenix/conversations/<conversation_public_id>/summary.md`
- `<workspace>/.fenix/conversations/<conversation_public_id>/memory.md`
- `<workspace>/.fenix/conversations/<conversation_public_id>/operator_state.json`

## Acceptance Model

The `acceptance/` harness is not a secondary demo harness. It is the main
manual benchmark surface for validating real agent-loop behavior.

The benchmark suite should have two classes of scenarios:

### Primitive validations

Small contract-oriented scenarios, including:

- skills loading
- subagent wait-all
- governed tool and governed MCP flows
- human interaction pause/resume
- process lifecycle closure

### Cowork capstones

Real workload scenarios that activate multiple capabilities at once.

Target capstones:

- `2048 build capstone`
- `repo research capstone`
- `environment bootstrap capstone`
- `bugfix with subagents capstone`

## Acceptance Philosophy

The benchmark should not score only "did the task succeed?"

The primary acceptance questions are:

1. Did the expected capabilities activate?
2. Did the loop behave correctly?
3. If failure occurred, is the failure explainable?
4. Are the durable records and exported artifacts correct?

## Capability-first Scoring

Each capstone should produce:

- `run-summary.json`
- `capability-activation.json`
- `failure-classification.json`

### Capability activation

Required and optional capabilities are declared by scenario contract and are
evaluated using evidence in this order:

1. durable DB/workflow state
2. exported artifacts
3. workspace or host artifacts
4. transcript and supervision text
5. model self-report only as supporting context

### Failure classification

Failures should be classified into:

- `model_variance`
- `environment_defect`
- `agent_design_gap`
- `kernel_gap`
- `harness_gap`
- `user_input_gap`
- `unknown`

Outcome states should distinguish:

- `pass_clean`
- `pass_recovered`
- `pass_diagnostic`
- `fail_model`
- `fail_system`
- `fail_harness`

This allows environment defects surfaced by `Fenix` to count as useful runs
even when the workload itself is not completed cleanly.

## 2048 as the Benchmark Mother Scenario

The existing `2048` capstone should remain in place and become the benchmark
mother scenario.

Why:

- it already spans coding, build, test, browser verification, supervision,
  transcript export, debug export, and workspace artifacts
- it already produces the richest evidence set
- it is the best first place to land capability-first scoring before adding new
  capstones

For `2048`, initial required capabilities should be:

- `workspace_editing`
- `command_execution`
- `browser_verification`
- `supervision`
- `export_roundtrip`

Initial optional capabilities:

- `skills`
- `subagents`

## Gap Audit Method

After this design is recorded, the next planning step should be a structured
gap audit against the current codebase.

Use this matrix:

| Capability | Target Layer | Current State | Evidence | Next Action |
| --- | --- | --- | --- | --- |

Each capability should be marked:

- `done`
- `partial`
- `missing`
- `misplaced`

The evidence column must prefer acceptance proof over code existence.

## Immediate Next Move

The immediate implementation focus should be:

1. upgrade the `2048` capstone into a capability-first benchmark template
2. add shared acceptance helpers for capability activation and failure
   classification
3. then use that template for later cowork capstones
