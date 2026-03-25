# Agent Program Public API And Transport Research Note

## Status

Recorded research for future `Core Matrix` and `Fenix` Phase 2 planning.

This note captures durable transport and public-API conclusions for
`agent-program <-> Core Matrix` communication. It should remain useful even if
local reference code changes later.

## Decision Summary

- `Core Matrix` should not depend on long synchronous RPC calls into agent
  programs for long-running work.
- Canonical control semantics should be a durable mailbox model with leases and
  deadlines.
- `agent programs` should initiate outbound connections to `Core Matrix`; the
  kernel should not need to call back into runtimes behind NAT or home-network
  environments.
- The public protocol should remain language- and framework-agnostic.
- `poll` must remain a complete fallback path even when `WebSocket` is
  unavailable.
- `WebSocket` should be preferred for low-latency delivery and presence, but it
  must not become the only execution path.
- `ActionCable`, `SolidCable`, and `AnyCable` are implementation choices for
  the Rails side, not public protocol standards.

## Stable Findings From The Current Core Matrix Contract

The current `Core Matrix` machine-facing contract already separates stateless
resource APIs from runtime coordination:

- registration is a short request
- transcript, variable, and human-interaction APIs are resource APIs
- recovery, waiting, and lease semantics already live in durable kernel state

That supports a mailbox-first control plane without moving resource APIs onto
the persistent control session.

## Stable Findings From Old Claw RPC

The local old `claw` reference is useful mainly as a warning.

Useful conclusions:

- synchronous `tool.execute` is acceptable for short local operations
- `callback_session` is useful for sidecar reads or helper callbacks such as
  tool-surface manifests and memory access
- `callback_session` is not a strong main transport model for long-running
  execution

For long-running prompt building, memory assembly, or agent-owned tool use,
`Core Matrix` should not sit in a synchronous request waiting for the agent
runtime to finish.

## Stable Findings From The Nostr Cable Example

The local `nostr_cable` reference shows that ActionCable can host a custom
protocol without exposing ActionCable channel semantics directly.

Durable conclusions:

- ActionCable can maintain an outbound client-initiated WebSocket session
- the application can define its own session ids, command envelope, heartbeat,
  timeout, and dispatch layer
- the protocol value comes from the custom envelope, not from the ActionCable
  channel API itself

This makes ActionCable a plausible Rails implementation option for an optional
accelerator connection, but not a reason to define the public agent protocol in
ActionCable terms.

## Recommended Transport Split

### Resource Plane

Keep short HTTP APIs for:

- registration and enrollment
- transcript reads
- conversation and workspace variable APIs
- human-interaction APIs
- artifact upload or download when needed

### Control Plane

Use a mailbox-shaped control plane for:

- execution delivery
- execution progress and terminal reporting
- close requests
- capability refresh requests
- recovery notices

Rules:

- `WebSocket` is the preferred low-latency transport for control-plane items
- `agent_poll` must remain a complete fallback path
- agent responses may piggyback pending mailbox items when helpful
- the mailbox envelope must be the same across `WebSocket` and `poll`
- the transport value comes from durable mailbox semantics, not from the
  framework-specific session layer

## Connectivity And Liveness Model

If `Core Matrix` cannot dial back into runtimes, liveness should depend on
recent control-plane activity rather than on one transport alone.

Recommended split:

- `realtime_link_state`
  - `connected`
  - `disconnected`
- `control_activity_state`
  - `active`
  - `stale`
  - `offline`

Rules:

- `WebSocket` disconnect is a warning, not an immediate hard failure
- successful poll, progress, terminal reports, and health reports all refresh
  control activity
- `offline` should mean "no recent control activity", not merely "no realtime
  link"

## Why This Is Better Than A Pure ActionCable Protocol

Using ActionCable directly as the public standard would create avoidable
coupling:

- non-Rails runtimes would need ActionCable-specific client behavior
- reconnect and session semantics would be defined by a Rails framework choice
  instead of by the platform contract
- replacing ActionCable with `AnyCable` or another WebSocket stack later would
  become harder than it needs to be

By contrast, a custom mailbox envelope over `WebSocket` and `poll` keeps the
future transport replaceable while still letting Rails use ActionCable today if
it is the fastest implementation path.

## Execution Consequences

This transport model reinforces another important Phase 2 rule:

- prompt building should be treated as part of asynchronous agent execution,
  not as a short synchronous API
- agent-owned memory assembly, preflight intent or risk triage, local small
  model checks, LLM calls, and agent-owned tool use all fit better inside a
  mailbox-delivered execution
- `Core Matrix` should observe structured progress, close acknowledgements, and
  terminal outcomes, not wait on one held request

## Registration And Session Consequences

If the platform adopts this model, registration and pairing should evolve
toward:

- one-time enrollment token issued by `Core Matrix`
- outbound registration or session bootstrap initiated by the agent
- durable machine credential issued after successful registration
- optional session identity separate from the durable deployment credential
- the deployment should remain usable through poll even when no realtime link
  exists
- no assumption that the kernel can ever directly reach the agent's local
  network address

## Re-Evaluation Triggers

Re-open this note when one of these becomes true:

- Phase 2 decides to remove polling fallback or to require realtime presence
- multiple non-Ruby agent programs need first-class client libraries
- real scale pressure makes durable polling too wasteful even for single-tenant
  deployments
- ActionCable is no longer the likely Rails-side implementation option

## Reference Index

These references informed the note, but they are not the source of truth.

Local monorepo references:

- [/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/agent-runtime-resource-apis.md)
- [/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/deployment-bootstrap-and-recovery-flows.md)
- [/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/design/2026-03-24-core-matrix-agent-protocol-and-tool-surface-design.md)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/lib/cybros/agents/claw/tool_executor.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/lib/cybros/agents/claw/tool_executor.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/lib/cybros/agents/claw/hooks/before_agent_step.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/agents/claw/lib/cybros/agents/claw/hooks/before_agent_step.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/dephy-relay/app/channels/nostr_cable/connection.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/dephy-relay/app/channels/nostr_cable/connection.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/dephy-relay/app/channels/nostr_cable/relay_handler.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/dephy-relay/app/channels/nostr_cable/relay_handler.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/dephy-relay/app/channels/nostr_cable/session.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/dephy-relay/app/channels/nostr_cable/session.rb)
