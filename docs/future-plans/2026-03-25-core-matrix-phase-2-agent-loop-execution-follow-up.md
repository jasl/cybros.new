# Core Matrix Phase 2 Agent Loop Execution Follow-Up

## Status

Deferred future plan for the next active phase after the completed substrate
batch.

## Purpose

Phase 2 proves that Core Matrix can run a real agent loop end to end under
kernel authority.

Related design and research:

- [2026-03-25-fenix-phase-2-validation-and-skills-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-25-fenix-phase-2-validation-and-skills-design.md)
- [2026-03-25-agent-program-public-api-and-transport-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-agent-program-public-api-and-transport-research-note.md)
- [2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-core-matrix-phase-2-runtime-loop-and-mcp-research-note.md)
- [2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-skills-and-agent-skills-spec-research-note.md)
- [2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md](/Users/jasl/Workspaces/Ruby/cybros/docs/research-notes/2026-03-25-fenix-deployment-rotation-and-discourse-operations-research-note.md)

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

## Out Of Scope

- Web UI productization
- workspace-owned trigger infrastructure
- IM, PWA, or desktop channels
- extension and plugin packaging
- kernel-owned prompt building
- kernel-owned universal context compaction or summarization
- in-place self-update or plugin-management ecosystems inside `Fenix`
