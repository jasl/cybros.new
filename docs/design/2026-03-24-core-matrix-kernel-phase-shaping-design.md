# Core Matrix Kernel Phase Shaping Design

## Status

Approved design note capturing the review conclusions for the current `docs/plans` set.

This note does not replace the current phase-one task documents. It reframes them so later planning can extend the system without pretending phase one is already the full platform.

## Design Principle For This Rewrite

This rewrite is shape-first, not compatibility-first.

Rules:

- prioritize the cleanest and currently most correct architecture over forward-compatibility promises
- allow destructive correction when a boundary later proves wrong
- if persistent data conflicts with the corrected design, resetting the database is acceptable in this stage
- defer compatibility guarantees until the kernel has been validated against multiple real agent shapes

## Review Conclusion

The current plan set is feasible as a greenfield kernel rebuild, but it should be interpreted as a substrate phase rather than a complete agent platform phase.

What the current plan already does well:

- establishes the root ownership model around installation, identity, user, agent installation, deployment, binding, and workspace
- preserves the strong-kernel rule that durable side effects remain kernel authority
- builds the runtime ledger needed for transcript, workflow, events, resources, policy, audit, and publication
- separates protocol methods from model-visible tool names and keeps the machine contract explicit

What the current plan does not yet do:

- execute a real end-to-end agent loop
- invoke a real provider through a transport adapter
- run a generic external tool bridge
- provide connector, delivery, trigger, or heartbeat infrastructure

The practical implication is:

- phase one should be treated as `kernel substrate`
- phase two should be the first phase that proves the platform can actually run agents

## Phase 1 Positioning

Phase one should be understood as:

`Core Matrix Kernel Substrate`

Its job is to produce a strong kernel with the right core shapes:

- installation, identity, session, and audit roots
- agent installation, deployment, environment, enrollment, and handshake roots
- workspace, conversation, turn, workflow, and runtime-resource roots
- provider governance, selector resolution, accounting, and execution snapshot roots
- machine-facing protocol skeleton
- read-only publication and query surfaces

Phase one should not be judged by whether it already ships a complete product loop. It should be judged by whether it creates the right substrate for later execution, integration, and orchestration work.

Phase one explicitly stops short of:

- provider execution adapters
- workflow node side-effect execution
- generic tool execution bridges
- connector or channel adapters
- delivery and outbox infrastructure
- heartbeat, cron, webhook, or other trigger runners
- built-in memory, search, fetch, or knowledge subsystems

## Phase 1 Structural Gate

Before concluding substrate work, run a structural-gate review.

Its purpose is not to pull all execution work into phase one. Its purpose is to catch the small set of gaps that would otherwise force a later rewrite of the kernel's database roots or core object model.

Absorb a change into phase one when the review shows a need to adjust:

- aggregate roots or foreign-key ownership for installation, user, agent installation, deployment, workspace, conversation, turn, workflow, runtime resource, or publication records
- scheduler-visible state semantics for runnable, waiting, retryable, failed, timed-out, or terminal execution
- durable invocation lineage required for provider or tool attempts, timeouts, failures, repairs, and audit links
- the anchor point for external capability bindings, availability state, or endpoint supervision
- snapshot, usage, and audit lineage required to explain historical execution without reinterpretation

Do not pull a change into phase one when it is only about:

- concrete provider adapters
- concrete tool implementations
- connector or delivery layers
- trigger runners
- plugin or extension packaging systems

Decision rule:

- if the issue requires a root-shape, ownership, or schema correction, fix it in the substrate
- if it only affects concrete execution-layer implementation, defer it to later planning

At this stage, destructive schema correction remains acceptable when the structural gate proves that the current shape is wrong.

## Phase 2 Positioning

Phase two should be understood as:

`Agent Loop Execution`

Its purpose is to turn the phase-one substrate into a real executable loop.

The minimum success condition for phase two is:

1. a turn enters the kernel
2. the kernel creates and schedules workflow work
3. the kernel invokes a real provider or runtime execution path
4. the agent runtime returns observation data and effect intent
5. the kernel materializes governed execution from that intent
6. the workflow continues until terminal state with audit, events, usage, and snapshots intact

Phase two should not try to finish the entire platform surface. It should prove one strong closed loop first.

## Phase 2 Scope

Phase two should include:

- workflow node executor infrastructure
- at least one real provider execution path
- the minimal tool invocation bridge needed for loop execution
- runtime handling for `kernel_primitive`, `agent_observation`, and `effect_intent`
- Streamable HTTP MCP support as the first native external capability bridge
- end-to-end contract tests and manual validation for the closed loop

Phase two should not include:

- connector framework
- delivery or outbox infrastructure
- heartbeat or recurring trigger systems
- built-in implementations for experimental capabilities such as `web_search`, `web_fetch`, or memory
- plugin or extension packaging systems

## Future Plans Layering

Future plans should be organized by platform capability, not by reference product.

Recommended layering:

### 1. Execution Layer

- provider transport adapters
- model invocation executor
- effect executor
- generic tool invocation bridge
- provider-specific repair profiles

### 2. Connector Layer

- CLI, UI, channel, and MCP-facing connector contracts
- inbound normalization
- outbound delivery contract

### 3. Trigger Layer

- heartbeat
- cron and schedule runners
- webhook ingress
- automation trigger registration

### 4. Delivery And Eventing Layer

- outbox
- delivery receipts
- retry and dedupe
- event subscription model

### 5. Orchestration Layer

- ticketing and delegation
- manager and worker coordination
- organization and hierarchy abstractions
- multi-agent supervisory flows

Ordering recommendation:

- phase two should focus on the execution layer first
- connector and delivery should come after the loop works
- triggers should come after execution and delivery
- orchestration should remain last because it is the most product-specific and easiest to overfit early

## Tool And Capability Boundary

The kernel owns the loop and governance. External systems may own concrete capability implementations.

Core Matrix should own:

- all agent-loop progression and user-facing interaction mediation
- when a tool call happens
- which implementation is chosen
- timeout, retry, approval, audit, and usage semantics
- durable invocation history
- workflow continuation after success, repair, retry, wait, or failure

Agent programs or external services may own:

- experimental tool implementations
- memory systems
- search and fetch implementations
- knowledge integrations
- other domain-specific capabilities

This allows unstable capabilities to be developed externally first and only promoted into substrate later when they are proven.

Recommended conceptual objects:

- `ToolDefinition`
- `ToolImplementation`
- `ImplementationSource`
- `ToolBinding`
- `ToolInvocation`

Recommended `ImplementationSource` values for the next phase:

- `kernel_builtin`
- `mcp_streamable_http`

Design rule:

- stabilize tool definitions earlier than tool implementations
- treat tool implementations as replaceable during the experimental stage
- do not build a full plugin system yet
- if a future plugin system is added, it should register definitions and implementations into this registry model instead of inventing a parallel tool architecture

## External Capability Supervision

Because many capabilities will come from outside the kernel, Core Matrix must act as an execution supervisor rather than a naive request forwarder.

Minimum supervision requirements:

- registration-time validation
- readiness checks before a capability becomes runnable
- lightweight pre-dispatch availability checks
- post-failure state transitions after timeout, transport failure, or protocol failure

Recommended external capability lifecycle states:

- `registered`
- `ready`
- `degraded`
- `unavailable`
- `retired`

Recommended execution-policy metadata for implementations:

- `timeout_ms`
- `max_retries`
- `retry_backoff_policy`
- `concurrency_limit`
- `availability_check_kind`
- `degraded_behavior`

Recommended conceptual objects:

- `ToolImplementation`
- `ImplementationEndpoint`
- `InvocationAttempt`

Hard rules:

- timeouts are kernel semantics
- a timed-out invocation must become an explicit retryable, failed, or waiting state
- scheduler-visible blocking must surface as explicit workflow wait or failure semantics, not as silent disappearance of runnable work

## Invocation Failure Recovery

Phase two should include a first-class recovery framework for tool and provider invocation failures.

This is not optional hardening. It is part of making the loop real.

Recommended canonical failure classes:

- `transport_failure`
- `protocol_failure`
- `tool_call_shape_failure`
- `execution_semantic_failure`

Recommended recovery rules:

- classify failures before retrying
- repair protocol and shape errors before replaying execution
- record every repair and retry as a new attempt
- never auto-replay ambiguous side effects without explicit idempotency confidence
- hang provider-specific repair logic off a shared repair framework instead of scattering it across adapters

Recommended conceptual objects:

- `InvocationFailure`
- `FailureClassifier`
- `RepairPolicy`
- `RepairAttempt`
- `ProviderRepairProfile`

Minimum recovery features for the next phase:

- safe parameter correction
- tool-call payload normalization into kernel canonical shape
- single safe retry for clearly retryable attempts
- provider-specific repair profiles for common tool-calling failure modes already observed in prior research

## Current Docs Implications

The current phase-one plan documents are still usable, but later planning should interpret them with these caveats:

- phase one is substrate, not the first fully usable platform release
- provider catalog, selector resolution, and context assembly are preparatory surfaces, not proof that provider execution is already solved
- the current omission of connector, delivery, trigger, and built-in experimental capabilities is intentional and should remain explicit
- future plans should extend the substrate through new layers instead of retroactively pretending unstable capability implementations belonged in phase one

## Deferred Notes Worth Keeping

The following topics should be noted as intentionally considered but intentionally deferred:

- built-in memory systems
- built-in `web_search` and `web_fetch`
- alternative implementation sources beyond kernel built-ins and Streamable HTTP MCP
- plugin and extension packaging
- connector and delivery systems
- trigger systems

The reason for documenting them now is to preserve the boundary decision:

- these are recognized platform concerns
- they should not be half-implemented in the current phase
- they may live in agents first and move into substrate later only after validation

## Final Direction

Use the current docs/plans set to build the kernel substrate.

When planning resumes after phase one, the first major planning exercise should target:

`Phase 2: Agent Loop Execution`

That phase should prove one real executable loop before widening the platform into connectors, delivery, triggers, or orchestration.
