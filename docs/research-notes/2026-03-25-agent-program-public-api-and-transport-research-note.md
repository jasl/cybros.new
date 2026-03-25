# Agent Program Public API And Transport Research Note

## Status

Recorded research for future `Core Matrix` and `Fenix` Phase 2 planning.

This note captures durable transport and public-API conclusions for
`agent-program <-> Core Matrix` communication. It should remain useful even if
local reference code changes later.

## Decision Summary

- `Core Matrix` should not depend on long synchronous RPC calls into agent
  programs for long-running work.
- Canonical execution semantics should be durable `claim -> lease -> heartbeat
  -> report`, not request-held RPC.
- `agent programs` should initiate outbound connections to `Core Matrix`; the
  kernel should not need to call back into runtimes behind NAT or home-network
  environments.
- The public protocol should remain language- and framework-agnostic.
- Short HTTP requests should remain the canonical transport for the public API
  in Phase 2.
- An outbound WebSocket connection may exist as an optional accelerator for
  notifications and wakeups, but it should not become the only execution path.
- `ActionCable`, `SolidCable`, and `AnyCable` are implementation choices for
  the Rails side, not public protocol standards.

## Stable Findings From The Current Core Matrix Contract

The current `Core Matrix` machine-facing contract is already strongest when it
stays short and synchronous.

Durable patterns already present in the local contract:

- registration, heartbeat, health, and capability refresh are short request or
  response operations
- transcript, variable, and human-interaction APIs are runtime-resource reads
  or mutation intents, not long-held sessions
- recovery, waiting, and lease semantics are already modeled as durable kernel
  state rather than as transport-local assumptions

That makes the existing contract a good fit for a future durable
lease-and-report execution model.

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

### Canonical Public API

Keep a transport-neutral, short-request public API for:

- registration and handshake
- capability refresh
- runtime resource reads and mutation intents
- execution claim
- lease heartbeat
- progress report
- completion report
- failure report

The kernel should persist the durable execution state. Transport only moves
claims and reports.

### Optional WebSocket Accelerator

An outbound WebSocket session from the agent program to `Core Matrix` may be
used for low-latency hints such as:

- `work_available`
- `cancel_requested`
- `refresh_capabilities_requested`
- optional operator or recovery hints

Rules:

- the accelerator is additive, not canonical
- all durable execution state must still survive without the WebSocket session
- disconnect must degrade cleanly back to short HTTP polling
- the accelerator protocol must use the platform's own message envelope rather
  than leaking ActionCable-specific semantics

## Why This Is Better Than A Pure ActionCable Protocol

Using ActionCable directly as the public standard would create avoidable
coupling:

- non-Rails runtimes would need ActionCable-specific client behavior
- reconnect and session semantics would be defined by a Rails framework choice
  instead of by the platform contract
- replacing ActionCable with `AnyCable` or another WebSocket stack later would
  become harder than it needs to be

By contrast, a custom envelope over WebSocket keeps the future transport
replaceable while still letting Rails use ActionCable today if it is the
fastest implementation path.

## Execution Consequences

This transport model reinforces another important Phase 2 rule:

- prompt building should be treated as part of asynchronous agent execution,
  not as a short synchronous API
- agent-owned memory assembly, preflight intent or risk triage, local small
  model checks, LLM calls, and agent-owned tool use all fit better inside a
  claimed execution lease
- `Core Matrix` should observe structured progress and results, not wait on a
  single held request

## Registration And Session Consequences

If the platform adopts this model, registration and pairing should evolve
toward:

- one-time enrollment token issued by `Core Matrix`
- outbound registration or session bootstrap initiated by the agent
- durable machine credential issued after successful registration
- optional accelerator-session identity separate from the durable deployment
  credential
- no assumption that the kernel can ever directly reach the agent's local
  network address

## Re-Evaluation Triggers

Re-open this note when one of these becomes true:

- Phase 2 decides to require the WebSocket accelerator instead of keeping it
  optional
- multiple non-Ruby agent programs need first-class client libraries
- the platform wants server-to-agent push semantics that must survive polling
  gaps without an active WebSocket
- real scale pressure makes HTTP polling too wasteful even for single-tenant
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
