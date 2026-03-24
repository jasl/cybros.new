# Core Matrix Kernel Greenfield Design

## Status

Approved greenfield design for restarting `core_matrix` as a fresh implementation.

This document supersedes the earlier 2026-03-23 planning set. Those documents were useful exploration material, but they were anchored on the wrong aggregate roots for the product that Core Matrix is actually becoming.

## Executive Summary

Core Matrix is a single-installation, single-tenant agent platform kernel for personal, household, and small-team use. It is the user-facing control plane, runtime governor, audit authority, and execution orchestrator. It is not the business agent itself, not an enterprise ACL platform, and not the long-term memory or knowledge-base system.

The platform must support:

- one installation
- many users
- personal and global resource scopes only
- multiple admins
- agent programs deployed as independent services
- a stable public contract between Core Matrix and external agents
- user-private workspaces
- live read-only publication of conversations
- global shared AI credentials and subscriptions with per-user accounting
- auditable, observable execution where the kernel, not the agent process, is the final side-effect authority

The implementation should start fresh. The current `core_matrix` code should be treated as archived prototype material, not as the migration base.

The current delivery phase is backend-first:

- domain models
- application services
- machine-to-machine contract boundaries required for agent enrollment and health flows
- unit and integration tests
- manual real-environment validation

Human-facing UI should be tracked separately as a follow-up document and should not expand the current phase scope.

## Product Definition

Core Matrix is a general-purpose agent kernel in the same sense that a JVM is a general-purpose program runtime. It hosts shared infrastructure that many agent programs can rely on, while leaving business behavior to the agent programs themselves.

The bundled `agents/fenix` service is the default reference agent. It is not the defining shape of the kernel, and the kernel must not hardcode Fenix-specific behavior into its domain model.

The product assumptions are:

- single installation, not multi-tenant SaaS
- trust boundary is the installation, not a zero-trust enterprise environment
- expected deployments are personal, family, or small-team environments with baseline trust
- expected deployment modes include local development, bare-metal advanced-user installs, and bundled docker-compose style distribution
- v1 commonly colocates the agent runtime and code execution environment inside the same trusted environment; this reduces complexity but is not a hard security boundary
- users may deploy separate installations when they need stronger isolation
- Core Matrix is the user-facing product surface
- agents operate behind the scenes through a stable machine-to-machine contract
- agent implementations are protocol-facing and language-agnostic from the kernel's perspective

## Kernel Versus Agent Responsibilities

Core Matrix owns shared infrastructure and control-plane behavior. Agents own business behavior.

Core Matrix should own:

- UI and user-facing control surfaces
- conversation runtime orchestration
- workflow materialization and execution
- approvals, policy gates, and auditing
- provider governance and usage accounting
- foundational shared tool surfaces such as subagent orchestration and protocol adapters
- publication and installation health surfaces

Agent programs should own:

- prompt building
- business-specific tools
- skills and domain heuristics
- persona and output shaping
- optional external memory or knowledge integrations

Core Matrix may provide adapter points for external services such as knowledge stores, memory systems, and protocol transports like MCP or Streamable HTTP, but those are integration surfaces rather than built-in business subsystems.

## Goals

- keep the kernel generic and agent-agnostic
- make the user model, ownership model, and runtime model orthogonal
- make agent upgrades and deployment replacement safe and auditable
- keep workspaces private to users
- keep global shared AI resources simple to govern
- preserve detailed execution and usage telemetry
- support future separation of kernel, agent service, and execution environment

## Non-Goals

- enterprise ACLs, groups, departments, or projects
- multi-tenant account hierarchy
- built-in long-term memory, knowledge base, or RAG subsystem
- shared editable workspaces
- collaborative multi-user conversations in v1
- full OAuth authorization server machinery for agent registration
- sophisticated sandbox scheduling in v1

## Design Principles

1. Use only two resource scopes: `personal` and `global`.
2. Keep admins focused on installation-level control, not access to personal user content.
3. Keep workspaces private and durable.
4. Treat the logical agent identity separately from the currently active deployment.
5. Freeze runtime snapshots for history; never reinterpret history from current config.
6. Require the kernel to materialize and execute all side effects that affect user resources, system state, or external systems.
7. Prefer best-effort forward compatibility for agent config schema evolution.

## Normalized Domain Boundaries

Core Matrix should be split into six bounded contexts.

### 1. Installation And Identity

This context defines the installation itself and who can enter it.

Primary objects:

- `Installation`
- `Identity`
- `User`
- `Invitation`
- `Session`

Responsibilities:

- bootstrap the first admin user
- bootstrap the bundled default agent binding when present
- password-based authentication
- future-friendly separation between authentication identity and product user entity
- invitation-based user join flow
- admin role assignment and revocation

Admin safety rule:

- the installation must always retain at least one active admin user
- revoking the last active admin is forbidden

Naming note:

- use `Installation`, not `Account`
- `Identity` handles authentication concerns
- `User` handles product-level ownership, role, and preferences

### 2. Agent Registry And Connectivity

This context defines what an agent is, how it connects, and which runtime instance is currently online.

Primary objects:

- `AgentInstallation`
- `AgentDeployment`
- `ExecutionEnvironment`
- `AgentEnrollment`
- `CapabilitySnapshot`

Responsibilities:

- represent the stable logical identity of an agent program
- represent a concrete deployed runtime instance
- support agent-driven registration
- store machine credentials and rotation metadata
- store health and heartbeat state
- negotiate runtime identity, supported methods, capability snapshots, and config schemas

Kernel rule:

- Core Matrix does not couple agent identity to implementation language, repository layout, or deployment toolchain
- prompt, skill, code, and behavior changes on a user-owned agent are modeled as deployment evolution behind the same logical agent identity when appropriate
- using one agent to build, modify, or deploy another agent is a normal workload, not a special-case aggregate

### 3. User Agent Surface

This context defines how a user uses a logical agent inside the installation.

Primary objects:

- `UserAgentBinding`
- `Workspace`
- user-level agent preferences

Responsibilities:

- decide which agent installations are available to which users
- create a default workspace for each binding
- keep every workspace user-private
- preserve the user-facing rule:
  `a user has many agents, an agent has many workspaces, a workspace has many conversations`

### 4. Conversation Runtime

This context owns the actual interaction and execution history.

Primary objects:

- `Conversation`
- `ConversationBranch` or equivalent tree edges
- `Turn`
- `Message`
- `ConversationEvent`
- `ConversationMessageVisibility`
- `MessageAttachment`
- `ConversationImport`
- `ConversationSummarySegment`
- `WorkflowRun`
- `WorkflowNode`
- `WorkflowNodeEvent`
- `WorkflowArtifact`
- `ProcessRun`
- `HumanInteractionRequest`
- `SubagentRun`
- `ApprovalRequest`
- `ExecutionLease`
- `CanonicalVariable`
- execution telemetry facts

Responsibilities:

- maintain conversation tree navigation
- preserve an append-only transcript
- preserve immutable message variants with selected input and output pointers
- project non-transcript runtime state into visible conversation events without polluting transcript rows
- support queued turns and pre-side-effect input steering
- materialize reusable attachments and attachment ancestry
- project eligible attachments into runtime manifests and model input blocks according to the turn's pinned capability snapshot
- model read-only imports for branch prefixes, merge summaries, and quoted context
- support compaction through summary segments instead of transcript rewrites
- materialize per-turn workflows
- run tools, processes, human-interaction requests, approvals, subagents, and explicit process-control resources
- store canonical variables at workspace and conversation scope with auditable version history
- preserve live execution event streams, timeout semantics, stop semantics, and lease ownership
- pin each turn to a specific deployment and runtime snapshot

### 5. Provider Governance And Usage

This context governs shared AI resources and accounting.

Primary objects:

- config-backed provider catalog
- `ProviderCredential`
- `ProviderEntitlement`
- `ProviderPolicy`
- `UsageEvent`
- `UsageRollup`
- retention and archival policies

Responsibilities:

- maintain shared provider credentials and subscriptions
- enforce global hard limits
- collect detailed per-user usage
- support rollups and long-term storage control

### 6. Publication And Audit

This context defines read-only exposure and global traceability.

Primary objects:

- `Publication`
- `AuditLog`

Responsibilities:

- expose live read-only conversation pages
- log sensitive control-plane and runtime actions
- keep publication separate from conversation ownership

## Ownership Model

The ownership chain should be:

`Installation -> User -> UserAgentBinding -> Workspace -> Conversation -> Turn -> WorkflowRun`

Rules:

- `Installation` owns all global resources
- `User` owns personal resources
- `Workspace` is always personal
- `Conversation` belongs to a workspace
- `Publication` does not change ownership
- admins manage installation-level objects but do not read personal conversation content

## Identity Model

Use separate `Identity` and `User` records.

`Identity` should own:

- email
- password digest
- password reset state
- session relationships
- future authentication methods such as passkeys

`User` should own:

- display name
- admin flag or admin role
- personal preferences
- ownership of workspaces, conversations, and publications
- actor identity for auditing

Rationale:

- authentication lifecycle and product ownership lifecycle should not be fused
- login method changes should not force product-resource rewrites
- future auth expansion stays localized

## Invitation Model

`Invitation` is not a login method. It is the installation join mechanism.

Rules:

- invitation tokens are one-time, expiring, and auditable
- invitation consumption creates or activates the installation relationship
- new invitees create `Identity + User`
- existing identities can consume an invitation through a controlled join flow

## Agent Model

### AgentInstallation

`AgentInstallation` is the stable logical identity of an agent program.

It should include:

- key
- display name
- visibility: `personal | global`
- owner user when visibility is personal
- lifecycle state
- default binding policy

This is the object users conceptually choose.

### AgentDeployment

`AgentDeployment` is a concrete online runtime for one `AgentInstallation`.

It should include:

- deployment fingerprint
- endpoint and transport details
- machine credential metadata
- health state
- heartbeat timestamps
- protocol and SDK version
- active capability snapshot reference
- active config schema snapshot reference
- bootstrap state

V1 rule:

- one deployment serves one logical agent
- one agent installation may have historical deployments
- only one deployment is active for a given `AgentInstallation` at a time in v1

### ExecutionEnvironment

`ExecutionEnvironment` should exist as a thin object now, even if it is usually one-to-one with a deployment.

It should represent:

- local machine, container, or future remote execution target
- environment identity and connection metadata
- future split point for separating agent runtime from code execution runtime

This is a deliberate placeholder for future refactoring, not a full scheduling system.

## Agent Visibility And User Binding

Use two visibility levels only.

- `personal`
- `global`

`AgentInstallation` visibility determines whether users can bind it.

Use `UserAgentBinding` to represent:

- whether a user has enabled an agent installation
- user-local preferences for that agent
- the default workspace for that user-agent pair
- any default deployment selection policy that should not live on the workspace

This allows:

- one global agent installation to be used by many users
- one personal agent installation to stay private to one user
- a bundled default agent to be auto-bound to the first admin without forcing it onto all users

Installation bootstrap rule:

- if bundled `agents/fenix` is available in the chosen deployment mode, it should be automatically registered and bound to the first admin user
- that binding should create an immediately usable default workspace
- bundled-agent bootstrap must close both halves of the graph: first reconcile the logical agent, execution environment, and deployment rows, then create the first-admin binding and default workspace

## Workspace Model

`Workspace` is always user-private.

Rules:

- a workspace belongs to exactly one `UserAgentBinding`
- every binding gets at least one default workspace
- workspaces are never directly shared or collaboratively edited in v1
- publication is the only supported sharing surface, and it is read-only

Design note:

- the model should allow future agent switching, but v1 behavior should forbid free switching between unrelated agents
- the workspace should bind to the logical agent relationship, not directly to a mutable deployment row

## Conversation Model

The runtime ownership chain is:

`Workspace -> Conversation -> Turn`

Turn-owned runtime resources are:

- selected pointers to transcript-bearing `Message` variants
- one `WorkflowRun`

Conversation-owned presentation resources are:

- transcript-bearing `Message` rows
- non-transcript `ConversationEvent` rows

Rules:

- a workspace has many conversations
- a conversation is branchable and tree-navigable
- a turn owns one workflow run plus selected input and output transcript pointers
- a workflow run owns nodes, artifacts, human-interaction requests including approvals, processes, and subagent runs
- a workflow run is a turn-scoped dynamic DAG, not a fixed template and not a conversation-wide graph
- workflow mutation may append nodes and edges at runtime, but the graph must remain acyclic at every step
- a conversation may project visible runtime state through append-only `ConversationEvent` rows without changing transcript ownership

Runtime pinning rules:

- a conversation belongs to a logical agent through the workspace binding
- each executing turn must pin to one specific deployment and snapshot set
- deployment drift must fail safe, not silently continue on a new runtime

Conversation kinds in v1 are:

- `root`: the primary conversation timeline in a workspace
- `branch`: a divergent timeline created from a historical message
- `thread`: a side timeline under a parent conversation for parallel work without rewriting the parent history
- `checkpoint`: a saved snapshot conversation created from a historical message for later revisit or recovery

Kind rules:

- `root` has no parent
- `branch`, `thread`, and `checkpoint` require a parent conversation
- `branch` and `checkpoint` require a historical message anchor
- `thread` may carry an anchor message for provenance, but it does not imply transcript cloning
- `checkpoint` is intended as a savepoint, not the default redirected working timeline

Conversation lifecycle state is orthogonal to kind.

Lifecycle states in v1 are:

- `active`
- `archived`

Lifecycle rules:

- any conversation kind may be archived and later unarchived
- archiving does not mutate transcript history, imports, summaries, or workflow artifacts
- archived conversations are excluded from default active listings
- archived conversations do not accept new turns, queue operations, or workflow restarts until unarchived

## Transcript And Workflow Model

The current transcript and workflow direction remains valid in principle and should be reused conceptually:

- tree-shaped conversation navigation
- append-only transcript
- per-turn workflow DAG
- workflow-owned artifacts and execution resources

This is the part of the current prototype worth keeping as design knowledge.

It should be rebuilt under the correct upper-layer aggregates rather than migrated in place.

## Workflow Graph Semantics

The workflow graph is the kernel's execution model for one turn.

Rules:

- the conversation tree and the workflow DAG are separate structures with different responsibilities
- a conversation is not modeled as one global DAG
- each turn owns one workflow DAG that may grow dynamically while the turn is active
- workflow mutation may add nodes and edges after execution has started, but it must reject any mutation that would introduce a cycle
- fan-out and fan-in are first-class scheduler patterns inside the turn-scoped DAG
- barrier-style join nodes must not become runnable until all required predecessor branches have reached a terminal or otherwise satisfied state
- swarm or multi-agent orchestration is expressed as DAG scheduling and node coordination, not as a separate top-level orchestration aggregate in v1

## Transcript Messages Versus Conversation Events

The model should keep transcript-bearing messages separate from other visible runtime projections.

Rules:

- `Message` is reserved for transcript-bearing turn input and output
- v1 may use STI on `Message`, but only for transcript-bearing subclasses such as `UserMessage` and `AgentMessage`
- non-transcript visible records such as human-interaction lifecycle updates, variable-promotion notices, and similar operational projections should use `ConversationEvent`, not `Message`
- `ConversationEvent` is append-only, does not create a new turn, and does not participate in transcript edit, retry, rerun, swipe, or fork legality rules
- `ConversationEvent` must carry deterministic live-projection ordering metadata, using a per-conversation projection sequence plus an optional turn anchor, so publication and future UI surfaces do not invent heterogeneous timeline order at render time
- `ConversationEvent` may also participate in replaceable live-projection streams for streaming text, progress, and transient status surfaces
- replaceable live-projection streams remain append-only in storage; live renderers collapse to the newest revision within one projection stream while replay, audit, and diagnostics may inspect the full revision chain
- canonical transcript listing APIs return `Message` rows only by default
- conversation pages or publication projections may render both transcript messages and visible conversation events, but they must preserve the semantic distinction

## Required Conversation Runtime Capability Baseline

The new design must continue to support the important runtime capabilities that were captured in the earlier conversation-runtime plans. Those older documents are no longer the aggregate-root truth, but their runtime feature coverage should not be lost.

The required baseline is:

- branch from historical messages without copying transcript history
- reusable attachments with origin references and materialization into new turns
- append-only input and output variants for edit, retry, rerun, and swipe-style selection
- mutable visibility overlays for soft delete and context exclusion without mutating historical message rows
- explicit import rows for `branch_prefix`, `merge_summary`, and `quoted_context`
- explicit summary-segment rows for context compaction and replacement
- queued turns and steer-current-input behavior until the first side-effecting node commits
- one active workflow per conversation at a time in v1
- workflow node event streams for live output, status transitions, and audit-friendly replay
- explicit execution lease and heartbeat ownership for workflow-bound active resources
- explicit process-run modes for bounded turn commands and long-lived background services

These capabilities are not optional polish. They are part of the runtime baseline that the greenfield model should preserve while moving the upper ownership model to the correct roots.

## Attachment Access And Model Context

`MessageAttachment` is a kernel-owned conversation resource first and a prompt-projection candidate second.

The model should separate three layers:

- stored attachment rows on immutable submitted messages
- frozen attachment manifests on turns or workflows
- capability-gated model input blocks derived from those manifests

Rules:

- attachments belong to submitted message rows and are never only a client-local concept once sent
- v1 does not introduce independent attachment-level visibility overlays; attachments inherit visibility and context inclusion from their parent message plus branch or checkpoint selection rules
- reusable attachment references must create new logical attachment rows with origin pointers rather than mutating or re-parenting the historical source row
- turn creation or workflow creation must freeze the eligible attachment manifest for the selected input path so later history edits, visibility changes, or capability refreshes do not silently reinterpret what the running workflow saw
- the frozen attachment manifest should carry stable attachment identity, source message identity, filename, media type, byte size, origin reference, and prepared runtime reference when one exists
- context assembly should derive two sibling projections from the frozen manifest:
  - a runtime attachment manifest for agent and tool side access inside the execution environment
  - model input blocks for modalities supported by the pinned provider or model capability snapshot
- provider or model capability gating must use the capability metadata pinned onto the executing turn, not only the latest global catalog view
- unsupported attachments may remain available as runtime resources, but the kernel must never serialize them as if the model saw them
- if prompt projection is skipped, downgraded, or preparation fails, the workflow trace should record that explicitly through a node event or equivalent diagnostic artifact
- hidden or context-excluded messages must also exclude their attachments from branch, checkpoint, export, runtime manifest, and model input results
- provider-specific transport encoding of model-visible attachments belongs to the kernel execution adapter layer, not to ad hoc agent-specific payload shaping
- backtrack prefill may help a client rehydrate reusable attachment references, but server-side execution only uses submitted and materialized attachment rows
- prepared runtime refs such as workspace files, imported handles, or staged proxies are execution artifacts and may be regenerated from the frozen manifest without changing the canonical attachment row

## Process Resource Model

`ProcessRun` is a first-class runtime resource and should not be treated as an opaque tool side effect.

Required ownership shape:

- every `ProcessRun` belongs to one `WorkflowNode`
- every `ProcessRun` belongs to one `ExecutionEnvironment`
- every `ProcessRun` should also redundantly store `turn_id` and `conversation_id` for efficient filtering, audit queries, and operational inspection
- user-visible agent process runs should record the originating message context through `origin_message_id` or an equivalent direct message reference

Kinds in v1 are:

- `turn_command`: short-lived command with bounded timeout
- `background_service`: long-lived managed process without a bounded timeout

Rules:

- `turn_command` and `background_service` are different lifecycle classes, not just labels
- `turn_command` is expected to terminate and report a terminal status
- `background_service` may remain active across multiple later workflow steps until explicitly stopped, lost, or retired
- stdout, stderr, status transitions, and similar user-visible process output should be emitted as `WorkflowNodeEvent` records or an equivalent event stream, not packed into mutable `ProcessRun` text columns
- process output is part of the agent's intermediate execution trace, not part of the user-authored transcript

## Human Interaction Request Model

Human-in-the-loop should be modeled as workflow-owned runtime resources, not as transcript messages.

Use STI under a shared `HumanInteractionRequest` base in v1.

Required subclasses:

- `ApprovalRequest`
- `HumanFormRequest`
- `HumanTaskRequest`

Shared rules:

- every human interaction request belongs to one `WorkflowNode`
- every human interaction request belongs to one `WorkflowRun`
- every human interaction request should redundantly store `turn_id` and `conversation_id` for efficient querying and user-facing inbox or dashboard surfaces
- `blocking` requests pause workflow progress until they resolve, cancel, or time out
- creation and lifecycle transitions of user-visible requests should project append-only `ConversationEvent` rows
- blocking-request lifecycle projections may use replaceable live-projection streams when a surface wants to update one visible card, banner, or status block in place without losing append-only history
- request outcomes write structured results back into workflow-local variable or node-output state before scheduling resumes
- resolving, submitting, or completing a blocking request resumes the same `WorkflowRun` on the same turn-scoped DAG by default
- blocking human interaction resolution does not create a new `Turn` or a new `WorkflowRun` unless an explicit restart or `manual_retry` path is chosen
- open requests, especially `HumanTaskRequest`, must be queryable without reconstructing transcript history

Subclass rules:

- `ApprovalRequest` remains the binary approve or deny gate
- `HumanFormRequest` carries an input schema, defaults, and validated structured submission payload
- `HumanTaskRequest` carries human-readable instructions plus optional structured completion evidence, notes, or payload
- `HumanTaskRequest` is the default kernel primitive for future `human_use` style flows where the agent asks a person to complete an external action before continuation

## Subagent Orchestration Model

`SubagentRun` is a workflow-owned runtime resource, not a second orchestration system.

Rules:

- every `SubagentRun` belongs to one `WorkflowNode` and one `WorkflowRun`
- swarm or multi-agent behavior is expressed as dynamic DAG fan-out, fan-in, and join scheduling inside the parent turn's workflow
- do not introduce a separate `SwarmRun` or `SwarmPlan` aggregate in v1
- `SubagentRun` should retain lightweight coordination metadata for later orchestration growth, including at minimum:
  - `parent_subagent_run_id` when the run descends from another subagent
  - `depth`
  - `batch_key`
  - `coordination_key`
  - `requested_role_or_slot`
  - `terminal_summary_artifact_id` or equivalent final result artifact reference
- subagent outputs flow back into workflow artifacts, node state, or node events rather than bypassing the workflow graph

## Workflow Wait State

`WorkflowRun` should expose a structured current wait state rather than relying on implicit paused-status inference.

Track at least:

- `wait_state`
- `wait_reason_kind`
- `wait_reason_payload`
- `waiting_since_at`
- `blocking_resource_type`
- `blocking_resource_id`

Reason kinds in v1 should include at least:

- `human_interaction`
- `agent_unavailable`
- `manual_recovery_required`
- `policy_gate`

Rules:

- the structured wait state describes the current blocking condition, not the whole historical timeline of pauses
- historical wait-state transitions belong in `WorkflowNodeEvent`, `ConversationEvent`, and `AuditLog` as appropriate
- blocking human-interaction requests, deployment outages, and explicit manual-recovery holds should all use the same structured wait-state mechanism
- `manual_resume` clears or replaces the current wait state on the same workflow when compatibility checks pass
- `manual_retry` creates a fresh workflow path and leaves the prior workflow's final wait state in history

## Client Draft Versus Conversation Override

Unsent composer draft state is not a kernel concern in v1.

Rules:

- client-local draft content, draft attachments, and in-progress form state may live entirely in the frontend or client
- Core Matrix does not persist unsent draft text as a first-class server-side aggregate in v1
- branching APIs may still return seed payloads for the client to prefill a new composer, but that payload is ephemeral unless the user submits it
- conversation-level execution settings are different from draft state and must remain server-persisted

The important boundary is:

- draft is UX state
- conversation override is execution state

## Conversation Override Model

Conversation-level overrides must be persisted because they affect real execution.

Persist on `Conversation` or its close equivalent:

- `override_payload`
- `override_last_schema_fingerprint`
- `override_reconciliation_report`
- `override_updated_at`

Rules:

- override payload is validated against the current deployment conversation-override schema
- override payload is best-effort reconciled when the deployment schema changes
- resolved override values are frozen onto the executing turn or workflow snapshot
- override persistence is independent from any client-local draft UX
- the user-visible interactive model selector should support:
  - `auto`
  - one explicit `provider_handle/model_ref` candidate
- `auto` means resolve through `role:main`
- conversation-level model selection applies only to the reserved interactive execution path; internal agent slots remain deployment-level or agent-controlled unless their schema explicitly allows overrides

## Canonical Variables

The kernel should distinguish workflow-local variables from durable canonical variables.

Rules:

- workflow-local variables belong to one workflow execution path and are not durable cross-turn truth
- canonical variables are kernel-owned durable state with auditable history
- v1 canonical variable scopes are:
  - `workspace`
  - `conversation`
- effective lookup precedence is `conversation > workspace`
- conversation-scope values may intentionally diverge from workspace-scope values and may later be explicitly promoted to workspace scope
- the latest accepted write becomes the current canonical value for a scope and key
- a later accepted write supersedes the earlier current value without deleting history
- when a user explicitly corrects a prior fact, the new accepted value should automatically supersede the previous current value
- every canonical variable write should retain at least:
  - scope
  - key
  - typed value payload
  - writer identity
  - source kind
  - source conversation, turn, or workflow reference when present
  - projection policy
  - created or superseded timestamps
- agent code may choose the target scope, but the kernel owns persistence, supersession, audit, and legality checks
- ordinary variable writes may remain silent in the transcript
- promotions, explicit corrections, or other user-significant changes may project `ConversationEvent` rows
- do not make `user-agent` scope part of the v1 kernel contract, even though future agents may maintain richer private memory outside the kernel

## Conversation Mutation Invariants

The kernel must preserve timeline consistency with explicit mutation rules.

Required invariants:

- rewriting operations are tail-only within one conversation timeline
- rewriting operations include edit, retry that replaces selected input or output, rerun that changes the selected output path, and swipe selection when the selected variant affects future prompt context
- editing a previously submitted historical user message is modeled as backtrack-prefill plus rollback or fork semantics, not as in-place mutation of a persisted transcript row
- soft delete and context exclusion may target non-tail messages through overlay rows
- fork-point messages are protected from rewriting and protected from soft delete
- regenerating or rerunning from a non-tail historical point must create a branch or equivalent divergent child timeline instead of mutating in place
- hidden messages must not leak into branch, checkpoint, export, or context assembly results unless a future explicit admin-only diagnostic mode is introduced

The product should expose these rules through shared action-policy objects or equivalent model hooks so that service code, APIs, and UI surfaces all enforce the same legality checks. The old `NodeBody` policy hook style is a valid design reference for this idea, even though the new aggregate model is different.

## Conversation Variant Operations

The runtime must distinguish four related but different mutation families.

### 1. Input edit

- unsent draft editing is client-local and out of scope for the kernel
- submitted input editing is only directly supported on the selected tail user input of the active conversation timeline
- tail input edit creates a new input variant, moves the turn's selected-input pointer, and invalidates or rebuilds dependent selected output and workflow state for that turn
- non-tail input edit is never an in-place mutation; it resolves through backtrack-prefill plus either rollback-to-turn or branch creation

### 2. Output retry

- retry is for failed, interrupted, timed-out, or otherwise unfinished assistant output
- retry reuses the currently selected input path and creates a new output variant in the same turn or version set
- retry must reject when an equivalent retry is already queued or when policy says the failed output is not retryable

### 3. Output rerun

- rerun is for a finished assistant output whose generation path should be executed again
- rerunning the selected tail output may replace the selected output path in place by creating a fresh output variant and rebuilding downstream workflow state
- rerunning a non-tail finished output must branch first, then rerun inside the branch

### 4. Output variant selection

- swipe or select-output-variant only changes the selected output pointer among finished variants from the same version set
- selecting a different output variant is tail-only in the current timeline when that selection would affect future prompt context
- selecting a non-tail variant in the current timeline is blocked; the user must branch and choose the variant in the branch

Shared rules:

- these operations never mutate historical message rows in place
- fork-point protection still applies
- queued or in-flight variants cannot become the selected variant
- action-policy checks should expose legality and reason codes consistently across services and UI

## During-Generation Input Policy

Conversation runtime behavior must define what happens when new human input arrives while work is already queued or running.

Supported policy modes in v1 are:

- `reject`: refuse the new input while active work exists
- `restart`: request stop on active work, clear queued follow-up work, and restart from the newest input
- `queue`: allow the running work to continue, but make sure newly queued follow-up work reflects the newest tail state

Required semantics:

- active work means a queued or running turn or workflow that can still produce transcript-affecting output
- `reject` returns a user-visible locked or invalid-state error without mutating transcript state
- `restart` creates an explicit cancel or stop boundary so partial stale output cannot later commit as the selected result
- `queue` must carry an expected-tail guard on queued work so stale queued work is canceled or skipped if the conversation tail changes before execution
- steering may mutate the active input only before the first transcript-affecting side effect is committed; after that boundary, the same user intent becomes queued follow-up or restart behavior rather than in-place mutation of already-sent work
- stale queued work must fail safe rather than silently committing output against the wrong tail

## Agent Registration Protocol

Do not implement full OAuth 2.0 client credentials.

Use a simpler trusted machine-to-machine protocol:

1. `AgentEnrollment` token is minted by Core Matrix.
2. Agent runtime starts and calls a registration endpoint.
3. Registration exchanges the one-time token for a durable machine credential.
4. Future calls authenticate with deployment identity plus a long-lived bearer secret.
5. Credential rotation and revocation are first-class control-plane actions.

This protocol is sufficient because:

- the kernel and agent are mutually trusted
- this is not delegated end-user authorization
- the main goals are registration, continuity, rotation, and auditability

## Agent Capability Handshake

The runtime contract should include a capability handshake after machine authentication.

Keep explicit lifecycle methods such as:

- `initialize` or equivalent identity probe
- `agent.describe`
- `agent.health`
- `agent.schemas.get`
- `capabilities.handshake`
- `capabilities.refresh`

The capability and schema handshake should return at least:

- deployment fingerprint
- protocol version
- agent SDK version
- supported methods
- agent capabilities version
- tool or hook catalog snapshot
- deployment config schema
- conversation override schema
- default config payload

## Agent Runtime Resource APIs

The machine-facing contract should expose stable resource APIs for agent program code, not only health and registration endpoints.

The runtime execution context sent to agents should include enough identity to let agent code reason about ownership safely, including at minimum:

- `user_id`
- `workspace_id`
- `conversation_id`
- `turn_id`
- the selected deployment identity

Required read APIs in v1:

- `conversation.transcript.list`
- `conversation.variables.get`
- `conversation.variables.mget`
- `conversation.variables.list`
- `conversation.variables.resolve`
- `workspace.variables.get`
- `workspace.variables.mget`
- `workspace.variables.list`

Required mutation-intent APIs in v1:

- `conversation.variables.write`
- `workspace.variables.write`
- `conversation.variables.promote`
- `human_interactions.request`

Read API rules:

- `conversation.transcript.list` returns only the canonical visible transcript by default, not workflow-local intermediate state
- transcript listing must use cursor pagination from the start
- variable APIs may borrow Redis-style `get` and `mget` naming, but they resolve kernel-owned canonical values rather than a raw process-local cache
- `conversation.variables.resolve` returns the effective merged view using `conversation > workspace` precedence
- hidden transcript rows, hidden attachments, and non-transcript runtime internals must not leak through these read APIs by default

Mutation-intent rules:

- agents may maintain their own private databases or memory systems, but kernel-owned canonical variables and human-interaction requests must flow through kernel APIs if they should participate in audit, publication, or shared runtime behavior
- these mutation APIs still declare intent; the kernel remains responsible for durable side effects, projection rows, and audit records

## Agent Configuration Model

The agent deployment must store configuration and schema snapshots.

The schema belongs to the deployment version, not only to the logical agent installation.

Persist on `AgentDeployment` or its close equivalent:

- `config_payload`
- `config_schema_snapshot`
- `conversation_override_schema_snapshot`
- `default_config_snapshot`
- `config_reconciliation_report`
- `bootstrap_manifest_snapshot`

Use two explicit schema layers:

- deployment config schema
- conversation override schema

Rationale:

- some agent settings are deployment-wide and not safe for conversation-level changes
- some settings, such as a primary conversation model, may be conversation-overridable
- some settings, such as subagent model or special-purpose models, should remain deployment-level only

Model-selection rules:

- `main` is the reserved default role for top-level interactive generation
- deployment config should expose one reserved slot name: `interactive`
- `interactive` defaults to `role:main`
- agent programs may define additional named model slots through deployment config schema
- slot definitions should be able to carry at least:
  - `selector`
  - `allowed_selector_kinds`
  - `user_visible`
  - `conversation_overridable`
  - `required_capabilities`
- the kernel should not hardcode a long list of fixed internal slots such as `planner_role` or `research_role`
- if an agent does not explicitly choose another selector, execution falls back to `interactive`, then to `role:main`

## Config Reconciliation

Agent upgrades may change schema.

Kernel behavior must be best effort, not fail-fast, when reconciling stored config against a new schema snapshot.

Rules:

- keep fields that remain valid
- drop fields no longer accepted
- fill missing fields from new defaults
- replace invalid values with defaults
- log warnings and reconciliation details
- do not fail deployment activation solely because of config incompatibility

The resolved config for a given execution must be frozen onto the turn or workflow snapshot.

Recommended resolution order:

1. deployment default config
2. persisted deployment config
3. conversation override
4. resolved per-turn snapshot

## Model Role Catalog

Model-role selection should be configuration-backed, deterministic, and provider-aware.

Use ordered provider-qualified candidate lists in the form:

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

Rules:

- role names are stable kernel-facing identifiers
- role contents are config, not code
- the kernel may ship generic default roles such as `main`, `planner`, `researcher`, `speaker`, `coder`, `classifier`, and `archivist`
- `main` is the only reserved default role
- do not introduce a second canonical alias layer such as `gpt5` or `opus_top` in v1
- fallback is only allowed inside the ordered candidate list of the currently selected role

## Model Resolution Pipeline

All runtime model requests should normalize to one of two selector forms:

- `role:<role_name>`
- `candidate:<provider_handle/model_ref>`

Normalization rules:

- conversation `auto` normalizes to `role:main`
- conversation explicit selection normalizes to one exact `candidate:...`
- agent-requested slots first resolve to their configured selector and then normalize

Resolution rules:

- a `role:*` selector expands to the ordered candidate list for that role
- a `candidate:*` selector expands to a single-item candidate list
- unknown roles and empty role lists are immediate errors
- candidate filtering must check, in order:
  - provider policy enablement
  - credential or subscription availability
  - required capability compatibility
  - entitlement availability
  - provider or model disable, deprecation, or retirement state
- the first passing candidate becomes the provisional selection

Execution-time reservation rules:

- the kernel must perform an execution-time entitlement reservation or equivalent atomic availability check before committing the selected candidate
- if reservation fails for a `role:*` selector, the kernel may try the next candidate in the same ordered role list
- if reservation fails for a `candidate:*` selector, the execution fails immediately
- v1 does not support implicit cross-role fallback
- if a specialized role such as `coder` is exhausted, execution fails rather than silently switching to `main`

Snapshot rules:

- once a candidate is actually selected, freeze onto the turn or workflow snapshot at least:
  - selector source
  - normalized selector
  - resolved role when applicable
  - resolved provider handle
  - resolved model ref
  - resolution reason
  - fallback count
  - pinned capability snapshot reference
  - pinned policy or entitlement snapshot references when needed

Failure rules:

- if no candidate can be selected, pause or fail explicitly
- do not guess another role or unrelated model
- administrators may repair availability by fixing provider access, adjusting role or slot config, changing policy, or retrying with a one-time recovery override

## Deployment Bootstrap

Deployment activation is not just a row update. It is a system-owned workflow.

Create a system-scoped `DeploymentBootstrapRun` or equivalent to handle:

- config reconciliation
- initial capability/schema fetch
- file materialization into the execution environment
- prompt or skill seeding
- environment overlay materialization
- health validation
- bootstrap report generation

This bootstrap flow must be auditable and repeatable.

## Kernel Execution Authority

This is a core architectural law:

All agent actions that affect user resources, workspace state, system state, or external services must be materialized and executed by Core Matrix workflows. The agent runtime may declare intent, but it must not be the final authority for durable side effects.

Implications:

- the rule applies to LLM-driven actions
- the rule also applies to pure programmatic actions that do not involve an LLM
- agent code should return plans, actions, or workflow intentions
- Core Matrix turns those intentions into nodes, runs them, and records the result

This is required for:

- auditability
- observability
- approval and policy control
- future separation of agent runtime from execution environment

The bundled agents under `agents/` must follow this rule by design.

## Decision Sources

Workflow nodes should record where a decision came from.

Suggested values:

- `llm`
- `agent_program`
- `system`
- `user`

This separation enables later analytics without confusing model decisions with deterministic program behavior.

## Health Monitoring And Recovery

Agents are external dependencies and must be monitored explicitly.

Track on `AgentDeployment`:

- `health_status`
- `last_heartbeat_at`
- `last_health_check_at`
- `unavailability_reason`
- `auto_resume_eligible`

Health states in v1 are:

- `healthy`
- `degraded`
- `offline`
- `retired`

Recovery semantics:

1. transient outage moves active work into a bounded waiting state
2. prolonged outage moves conversation or workflow state into `paused_agent_unavailable`
3. automatic resume is allowed only if runtime identity has not drifted
4. if deployment fingerprint or capabilities version changed, require explicit user resume or retry

This balances user experience with runtime safety.

Explicit recovery actions after drift:

- `manual_resume` means the user accepts continuation on a specific healthy deployment, the kernel records that decision, pins the new deployment snapshot, and resumes the paused workflow only if compatibility checks pass
- `manual_retry` means the user abandons the paused execution path, preserves it as historical state, and starts a fresh workflow from the last stable selected input on a chosen healthy deployment
- both actions must be auditable and must never be triggered silently

Compatibility for `manual_resume` should mean at minimum:

- the chosen deployment belongs to the same logical `AgentInstallation`
- required protocol methods and capability families for the paused workflow are still available
- any workflow-pinned config or override requirements can still be resolved safely

If those checks fail, `manual_resume` must be rejected and only `manual_retry` may proceed.

Recovery-time selector override rules:

- `manual_resume` or `manual_retry` may accept a one-time selector override
- that override may be either `role:*` or one explicit `candidate:*`
- the override applies only to the current recovery action
- it must not mutate the persisted conversation selector
- it must not mutate deployment slot configuration
- it must be frozen into the new execution snapshot
- it must be auditable as a temporary recovery override rather than a durable configuration change

## Provider Catalog

Provider and model catalogs should remain configuration-backed.

The catalog should describe:

- provider keys
- model references
- model-role candidate lists using `provider_handle/model_ref`
- protocol and transport
- capabilities
- input modality flags for at least image, audio, video, and generic file or document handling when the provider exposes them
- context window metadata
- request defaults
- display metadata

Do not store the full provider and model catalog as first-class relational entities in the database.

Rationale:

- model catalogs are volatile
- providers delist models
- metadata changes faster than transactional business entities
- cleanup is easier in config than in relational data

## Provider Governance

Store installation facts in the database:

- `ProviderCredential`
- `ProviderEntitlement`
- `ProviderPolicy`

`ProviderCredential` covers connection material such as API keys and refresh tokens.

`ProviderEntitlement` covers subscription or quota constructs such as a rolling five-hour Codex limit.

`ProviderPolicy` covers enablement, concurrency, throttling, and default selection rules.

All of these are `global`, not personal.

## Usage Accounting

Use an event-truth model with rollups.

Primary records:

- `UsageEvent`
- `UsageRollup`
- retention and archival metadata

`UsageEvent` should capture:

- user
- workspace
- conversation
- turn or workflow node
- agent installation and deployment
- provider key
- model reference
- operation kind
- input and output token counts when applicable
- media unit counts when applicable
- latency
- estimated cost
- success or failure
- entitlement window references when relevant

Operation kinds should not be LLM-only. They must cover:

- text generation
- image generation
- video generation
- embeddings
- speech or transcription
- future AI media operations

## Usage Limits

Only global hard limits should be enforced in v1.

Per-user accounting is detailed and queryable, but user-level quotas are not enforced in the kernel.

This keeps shared resources simple while preserving the ability to answer:

- who consumed what
- which models were used
- where failures happened
- how much shared entitlement was spent in a given window

## Usage Retention

Detailed events are necessary, but long-term storage growth must be controlled.

Recommended pattern:

- keep granular events as the short- and medium-term truth source
- project hourly, daily, and rolling-window rollups
- compress or archive old detailed events after a defined retention window

The rollup layer is for performance and reporting. It is not the only truth source.

## Profiling And Runtime Telemetry

Provider accounting should not absorb all execution telemetry.

Keep separate execution profiling facts for questions such as:

- tool call counts
- tool success and failure rates
- approval wait time
- subagent success rates
- process run failure modes

These facts may still join against usage data, but they should not be modeled as provider usage rows.

## Publication Model

Conversation sharing should be modeled as a live read-only projection.

`Publication` should include:

- owner user
- publication slug or access token
- visibility mode
- published and revoked timestamps
- explicit access-audit hook surface as a first-class `PublicationAccessEvent` record
- authenticated viewer user when available, otherwise anonymous request metadata on the access event

Publication modes in v1 are:

- disabled
- internal public
- external public

Publication rules:

- the published page is always read-only
- it does not share the same UI surface as the authoring experience
- it follows the current canonical conversation state
- it does not copy transcript data into a second source of truth
- `internal public` means any authenticated `User` inside the same `Installation` may read the projection; anonymous requests fail closed and v1 does not add per-publication allowlists
- `external public` means the projection may be read anonymously through the publication slug or token, while still recording access events
- visibility changes are publication-lifecycle actions and must be auditable independently from read-side access events

This is intentionally closer to a live public page than to a static export.

## Audit Model

`AuditLog` should record sensitive installation and runtime actions.

At minimum, audit:

- invitation creation and consumption
- admin grants and revocations
- provider credential or entitlement changes
- agent enrollment, credential rotation, and revocation
- deployment bootstrap, degradation, recovery, and retirement
- publication enable, disable, or visibility changes
- policy-sensitive tool or process execution
- config reconciliation fallbacks
- manual resume and retry decisions after drift or outage

An audited mutation should cross an explicit service boundary rather than depending on ad hoc model saves.

Policy-sensitive execution should be determined from explicit workflow-node or service metadata, not inferred from transcript text after the fact.

Admins may inspect audit metadata, but that does not imply content access to personal conversations.

## Admin Boundary

Admins are installation operators, not super-readers of personal content.

Admins may manage:

- users
- invitations
- admin role assignments
- global agent installations and deployments
- provider resources
- system health
- audits

Admins may not directly browse another user's personal workspaces or conversations in v1.

If a break-glass mechanism is ever added, it should be a new explicit object and audit flow, not an implicit admin privilege.

## Validation And Delivery Rules

The greenfield backend phase must be validated in three layers:

- unit tests for model rules, service invariants, query objects, and value transformations
- integration tests for cross-aggregate flows such as bootstrap, invitation join, agent enrollment, runtime pinning, branching, publication, and outage recovery
- manual real-environment validation using `bin/dev` before the phase is declared complete

Manual validation should be treated as a tracked deliverable, not as ad hoc developer memory.

Rules:

- keep a maintained manual checklist document with reproducible commands and expected outcomes for complex flows
- include pairing and machine-to-machine registration flows in that checklist
- record any manual-only prerequisites needed to run the validation
- if a flow cannot be exercised manually in the real environment, treat that as an implementation gap

Current phase boundary:

- no human-facing setup wizard or application UI implementation in this phase
- minimal machine-facing contract endpoints are allowed when they are required to exercise enrollment, registration, health, or recovery behavior in a real environment
- deferred UI work should be tracked in a dedicated follow-up document rather than folded into the backend baseline

## Deferred Topics

The following topics are intentionally deferred:

- collaborative conversations with multiple human participants
- bot-member conversation rooms
- richer environment scheduling and sandbox policies
- per-user hard quotas on shared provider resources
- export or snapshot publication modes
- team or group sharing models

## Open Decisions Still Remaining

The major product decisions are now resolved. The remaining open items are implementation details rather than boundary questions:

- exact machine credential format and rotation cadence
- exact bootstrap artifact manifest format
- exact health check intervals and outage thresholds
- exact retention periods for detailed usage events

These belong in the implementation plan, not in another architecture reset.

## Why The Current Prototype Should Not Be Evolved In Place

The current `core_matrix` prototype started from the runtime middle instead of the product root.

What it got directionally right:

- conversation tree
- append-only transcript
- per-turn workflow DAG
- workflow-scoped process, tool, and subagent records

What it got wrong at the aggregate-root level:

- it starts from `Agent` instead of from `Installation`, `Identity`, and `User`
- it binds `Conversation` directly to `Agent`
- it has no real `Workspace` aggregate
- it has no `UserAgentBinding`
- it has no `AgentInstallation` versus `AgentDeployment` split
- it has no provider governance layer
- it has no publication or audit root
- it has no installation-scoped health and recovery model for external agents

Because those errors are above the transcript and workflow layer, continuing in place would force constant semantic rewrites of existing tables and associations. The design cost would be higher than restarting cleanly.

Therefore the correct strategy is:

1. archive or stash the prototype code
2. keep only the design lessons
3. restart from a clean schema and clean application layer
4. rebuild transcript and workflow ideas under the correct ownership model

## Greenfield Implementation Guardrails

When implementation begins, follow these guardrails:

1. build root aggregates first: installation, identity, user, invitation
2. build agent registry second: agent installation, deployment, enrollment, environment
3. build user-facing ownership chain third: binding, workspace, publication ownership
4. build provider governance before runtime execution, so usage facts have the right home
5. rebuild conversation runtime only after the upper ownership and connectivity layers exist
6. require contract tests for every agent protocol boundary before production code grows
7. treat historical snapshots as first-class data, not optional metadata
8. require unit tests, integration tests, and a maintained manual validation checklist as first-class deliverables
9. require a final `bin/dev` smoke pass for the major backend flows before calling the phase complete

## Final Decision

Core Matrix should restart as a greenfield kernel.

The old design set should be cleared from the active planning path.

The new planning baseline is:

- single installation
- `Identity` plus `User`
- `AgentInstallation` plus `AgentDeployment`
- `UserAgentBinding` plus private `Workspace`
- conversation runtime under that ownership chain
- config-backed provider catalog with database-backed governance and accounting
- live read-only publication
- audit-first, workflow-first side-effect execution
