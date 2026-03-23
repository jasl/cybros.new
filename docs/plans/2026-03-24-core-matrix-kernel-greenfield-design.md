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

## Product Definition

Core Matrix is a general-purpose agent kernel in the same sense that a JVM is a general-purpose program runtime. It hosts shared infrastructure that many agent programs can rely on, while leaving business behavior to the agent programs themselves.

The bundled `agents/fenix` service is the default reference agent. It is not the defining shape of the kernel, and the kernel must not hardcode Fenix-specific behavior into its domain model.

The product assumptions are:

- single installation, not multi-tenant SaaS
- trust boundary is the installation, not a zero-trust enterprise environment
- expected deployments are personal, family, or small-team environments with baseline trust
- users may deploy separate installations when they need stronger isolation
- Core Matrix is the user-facing product surface
- agents operate behind the scenes through a stable machine-to-machine contract

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
- `WorkflowRun`
- `WorkflowNode`
- `WorkflowArtifact`
- `ProcessRun`
- `SubagentRun`
- `ApprovalRequest`
- execution telemetry facts

Responsibilities:

- maintain conversation tree navigation
- preserve an append-only transcript
- materialize per-turn workflows
- run tools, processes, approvals, and subagents
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
- only one deployment is active for a given installation at a time in v1

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

The runtime chain is:

`Workspace -> Conversation -> Turn -> Message -> WorkflowRun`

Rules:

- a workspace has many conversations
- a conversation is branchable and tree-navigable
- a turn owns one workflow run
- a workflow run owns nodes, artifacts, approvals, processes, and subagent runs

Runtime pinning rules:

- a conversation belongs to a logical agent through the workspace binding
- each executing turn must pin to one specific deployment and snapshot set
- deployment drift must fail safe, not silently continue on a new runtime

## Transcript And Workflow Model

The current transcript and workflow direction remains valid in principle and should be reused conceptually:

- tree-shaped conversation navigation
- append-only transcript
- per-turn workflow DAG
- workflow-owned artifacts and execution resources

This is the part of the current prototype worth keeping as design knowledge.

It should be rebuilt under the correct upper-layer aggregates rather than migrated in place.

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

Recommended health states:

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

## Provider Catalog

Provider and model catalogs should remain configuration-backed.

The catalog should describe:

- provider keys
- model references
- protocol and transport
- capabilities
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
- access audit hooks

Publication modes may include:

- disabled
- internal public
- external public

Publication rules:

- the published page is always read-only
- it does not share the same UI surface as the authoring experience
- it follows the current canonical conversation state
- it does not copy transcript data into a second source of truth

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
- exact publication access control mechanics for internal-only visibility

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
