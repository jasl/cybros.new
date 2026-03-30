# Fenix Provider-Backed Agent Loop Design

## Status

- Date: 2026-03-31
- Status: approved draft
- Baseline tag: `phase2`
- Validation target: [2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md)

## Goal

Add a real provider-backed agent loop to `Fenix` so `Core Matrix + Fenix` can
complete a real coding task through the normal conversation and turn workflow,
with tool use, skills, subagents, streaming, and browser-visible output.

This design is intentionally staged:

1. prove the loop in `Fenix` against the capstone `2048` workload
2. only after the proof succeeds, extract the stable generic parts into an
   agent-program SDK or gem

## Why Now

The current product has already proved several important layers:

- `Core Matrix` owns conversation, turn, workflow DAG, mailbox control, durable
  truth, and runtime-side effect identities
- `Fenix` owns a strong runtime appliance with workspace, memory, browser,
  command, process, and skill surfaces
- websocket-first mailbox control, streaming surfaces, and runtime-owned side
  effect reporting are all working

But `Fenix` is still not a real agent loop. Today it executes deterministic
runtime flows instead of making its own provider-backed decisions. That is the
main blocker between "strong runtime substrate" and "usable coworker/coding
agent".

## Architectural Position

This work chooses a **Fenix-first runtime-loop** model.

### Core Matrix remains the collaboration kernel

`Core Matrix` continues to own:

- conversations
- turns
- workflow DAG and wait semantics
- mailbox assignment and runtime control
- durable truth for:
  - `ToolInvocation`
  - `CommandRun`
  - `ProcessRun`
- publication and audit
- governance and future approval surfaces

### Fenix becomes a real runtime-loop agent program

`Fenix` should own:

- provider-backed turn execution
- model-directed tool loop
- skill discovery and skill loading policy
- subagent delegation policy
- coding/coworker prompt and completion behavior
- operator workspace behavior

This is not the same as moving the whole product brain into `Fenix`. The
kernel remains in `Core Matrix`; `Fenix` becomes one concrete agent program
running on that kernel.

## Why Not Move The Top Loop Into Core Matrix

Doing the whole agent loop in `Core Matrix` would make future agent families
too expensive to evolve.

The near-term roadmap already includes agent types beyond `Fenix`, such as:

- investment assistance
- roleplay or companion chat
- translation
- other coworker-like task agents

If the top-level reasoning loop lives primarily in `Core Matrix`, then every
agent-specific memory rule, tool style, skill strategy, and subagent behavior
would keep leaking back into the kernel. That would turn `Core Matrix` into a
monolithic general-purpose agent instead of a collaboration kernel.

The better split is:

- kernel-owned collaboration infrastructure in `Core Matrix`
- agent-program-owned cognition in `Fenix`
- later extraction of the generic agent-program wheel into a reusable SDK

## Two-Phase Strategy

### Phase A: Fenix-first proof

The first phase is intentionally product-specific.

`Fenix` gets a real provider-backed loop that can:

- interpret the assignment context
- select skills
- call tools repeatedly
- decide when to delegate to subagents
- stream final output
- produce a real application in a mounted workspace

Success is measured only by the capstone checklist. In particular:

- Dockerized `Fenix`
- mounted `tmp/fenix`
- installed `superpowers` and `find-skills`
- real conversation and turn flow
- playable React `2048`
- per-turn DAG proof
- real collaboration transcript

### Phase B: post-capstone extraction

Only after the capstone passes should the team extract a reusable SDK or gem.

The extraction target is not a fully generic framework from day one. It is the
set of boundaries proven useful by the working `Fenix` implementation, likely
including:

- provider session and model transport
- tool loop controller
- skill resolver and prompt injection
- subagent client
- context assembly contract
- completion policy hooks
- streaming and runtime reporting hooks

The desired end-state is that `Fenix` can be rewritten on top of that SDK with
mostly business logic remaining in the app layer.

## Execution Model

The assignment lifecycle remains mailbox-driven.

1. `Core Matrix` creates a workflow-owned agent assignment.
2. `Fenix` receives the assignment over realtime mailbox or poll fallback.
3. `Fenix` builds runtime context and prompt state.
4. `Fenix` enters a provider-backed loop:
   - call model
   - inspect assistant output
   - execute tool calls
   - append tool results
   - optionally spawn or wait on subagents
   - repeat until completion
5. `Fenix` emits incremental runtime reports and streaming output.
6. `Core Matrix` persists durable state and advances the workflow DAG.

The key point is that `Core Matrix` does not choose the next tool call for
`Fenix`. It only records, governs, and orchestrates the durable consequences.

## Runtime Loop Components

The implementation should create explicit seams inside `Fenix`, even before any
SDK extraction:

- `Fenix::AgentLoop::TurnRunner`
  - owns one top-level provider-backed assignment execution
- `Fenix::AgentLoop::ProviderSession`
  - wraps provider transport, streaming, response normalization, and model
    choice
- `Fenix::AgentLoop::ToolDispatcher`
  - validates and executes visible tools, provisions kernel-side identities,
    and captures streaming output
- `Fenix::AgentLoop::SkillResolver`
  - decides which installed or bundled skills to surface and how to inject them
- `Fenix::AgentLoop::SubagentClient`
  - turns `subagent_*` decisions into kernel-reserved tool usage and child
    coordination
- `Fenix::AgentLoop::CompletionPolicy`
  - decides when the turn is done and how to assemble final user-facing output

These seams are not yet the SDK; they are the future extraction points.

## Provider Loop

The provider loop should stay inside `Fenix`.

Requirements:

- use the existing `model_context` and `provider_execution` hints from mailbox
  assignments
- support streaming final output for user-visible text
- keep tool-loop internal state in the runtime layer rather than reifying every
  intermediate token in the kernel
- normalize tool-call and final-output results into the existing runtime report
  shape

The loop should allow more than one provider roundtrip per assignment. A single
tool call is not sufficient for realistic coding work.

## Tool Loop

The tool loop should use the existing runtime-first surfaces rather than create
new one-off pathways.

Requirements:

- all tool execution still respects `allowed_tool_names`
- tool-owned side effects still materialize first-class kernel identities:
  - `ToolInvocation`
  - `CommandRun`
  - `ProcessRun`
- streaming tool output remains ephemeral and user-facing
- terminal summaries remain compact and durable
- deterministic tools can remain as a testing mode, but they must no longer be
  the only real execution mode

`exec_command` and `process_exec` stay distinct:

- `exec_command` always creates `CommandRun`
- `process_exec` always creates `ProcessRun`

## Skill Loop

The current skill surface is enough to install, list, load, and read skills,
but not enough to make skill use part of the agent cognition.

The new loop should treat skills as runtime-owned instructional overlays:

- discover candidate skills
- decide whether a task warrants a skill
- load only the skills needed for the current turn
- allow reading additional skill-relative files on demand
- treat installed third-party skills as available on the next top-level turn,
  preserving the existing activation rule

This should follow the broad shape seen in OpenClaw and Codex:

- skills are directories with instructions and optional supporting files
- skill loading is selective, not "load everything"
- skill presence should affect agent planning, not just passive file browsing

## Subagent Loop

Subagent support is already advertised in the pairing manifest but is not yet
runtime-executable. This design makes it real.

Requirements:

- `Fenix` may decide to spawn a subagent when the task warrants bounded
  delegation
- subagents remain kernel-reserved tools at the protocol level
- `Fenix` should coordinate them through a dedicated `SubagentClient` instead
  of treating them as ordinary environment tools
- child work must appear in workflow proof and turn transcripts
- final capstone proof should show real subagent activity when the workload
  naturally justifies it

Subagent work should resemble a true orchestration path, not a fake trace.

## Context, Prompt, And Memory

The existing `.fenix` and operator-surface work stays in place, but it becomes
input to a real loop instead of a deterministic runtime shell.

The prompt stack should combine:

- built-in `Fenix` system prompt
- workspace and conversation overlays
- selected skill instructions
- operator state summaries
- memory summaries and relevant daily memory slices

The context system must support:

- repeated provider rounds without rebuilding the whole world every time
- compaction between rounds
- writing summaries back into `.fenix`
- narrower subagent contexts for child work

## Streaming

Streaming remains split into two layers:

- final assistant output streams as user-visible delta text
- tool, command, process, and subagent progress stream as structured events

This keeps the runtime interactive without exposing every internal reasoning
token.

## Core Matrix Changes Allowed

The main implementation lives in `Fenix`, but `Core Matrix` remains in scope
for necessary product-level changes under the same destructive-change allowance
used through the phase-2 work.

Permitted kernel-side adjustments include:

- mailbox payload changes needed for richer provider-backed `Fenix` turns
- workflow/DAG adjustments needed to represent real subagent work
- new runtime report handling required for provider or subagent loops
- publication and proof export changes required for capstone recording

Compatibility with old phase-2 intermediate shapes is not required.

## Out Of Scope

This design does not attempt to finish everything at once.

Still out of scope for this phase:

- a full generic agent-program SDK or gem
- a universal agent framework for every future agent type
- final approval-stage product surfaces
- full crash-reattach semantics for local runtime handles

Those can be extracted or widened after the capstone proves the real loop.

## Success Criteria

This work succeeds only when the capstone checklist passes:

- full stack deployed
- Dockerized `Fenix`
- mounted `tmp/fenix`
- installed `superpowers` and `find-skills`
- real provider-backed `Fenix` loop
- real tool and subagent usage
- playable React `2048`
- full per-turn DAG/state proof
- transcript and collaboration notes

Anything less means the loop is still not product-grade.
