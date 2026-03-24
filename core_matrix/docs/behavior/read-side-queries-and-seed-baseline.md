# Read-Side Queries And Seed Baseline

## Purpose

Task 12.2 adds backend-facing read-side queries for the already-landed phase 1
roots and a safe seed baseline for environments that need the catalog and the
optional bundled runtime reconciled without inventing demo users or fake UI
state.

## Agent Visibility Query

### `AgentInstallations::VisibleToUserQuery`

- Returns only `AgentInstallation` rows that are visible to one user inside the
  single installation.
- Visibility remains distinct:
  - `global` agent installations are visible to every user in the installation.
  - `personal` agent installations are visible only to their `owner_user`.
- Retired logical agent rows are excluded from the default visible list.
- Results are ordered with global agents first, then personal agents, with a
  stable secondary order by display name and id.

## Human Interaction Inbox Query

### `HumanInteractions::OpenForUserQuery`

- Reads open `HumanInteractionRequest` rows for one user without mutating
  workflow or request state.
- Ownership is derived from the private workspace chain:
  `HumanInteractionRequest -> Conversation -> Workspace -> User`.
- The query returns open requests from both:
  - interactive conversations
  - automation conversations
- This preserves the design rule that blocked automation runs surface through
  inbox or dashboard style tooling rather than direct transcript reply.
- Results are ordered by creation time and id for a stable actionable list.

## Workspace Listing Query

### `Workspaces::ForUserQuery`

- Returns only private workspaces owned by one user inside the installation.
- The query does not widen access for admins or other users.
- Default workspaces are ordered first so a user-agent binding always presents
  an immediately usable primary workspace before secondary ones.

## Provider Usage Window Query

### `ProviderUsage::WindowUsageQuery`

- Reads `UsageRollup` rows from the `rolling_window` bucket only.
- Aggregates across dimension-specific rollup rows into provider/model/operation
  summaries for one explicit window key.
- Summary entries expose:
  - event counts
  - success and failure counts
  - token and media totals
  - total latency
  - total estimated cost
- The query treats rollups as a reporting projection over detailed usage facts,
  not as a replacement truth source.

## Execution Profiling Summary Query

### `ExecutionProfiling::SummaryQuery`

- Reads `ExecutionProfileFact` rows without touching provider usage tables.
- Aggregates facts by `fact_kind` and `fact_key`.
- Supports time-window filtering through `started_at` and `ended_at`.
- Supports optional narrowing by user or workspace when a later read surface
  needs a scoped summary.
- Summary entries expose:
  - event count
  - total `count_value`
  - total `duration_ms`
  - success and failure counts
  - most recent occurrence time

## Seed Baseline

- `db/seeds.rb` always loads the provider catalog so environment setup fails
  early if the catalog config is malformed or missing.
- Seeds do not create:
  - installations
  - identities
  - users
  - bindings
  - workspaces
- When an installation already exists, seeds only reconcile the optional bundled
  runtime through `Installations::RegisterBundledAgentRuntime`.
- Seed execution remains idempotent; rerunning it reuses the same bundled
  logical agent, environment, deployment, and capability snapshot when the
  configuration has not changed.

## Failure Modes

- Agent visibility queries exclude another user's personal agent installation.
- Human interaction inbox queries exclude resolved requests and requests owned
  by another user's private workspace.
- Workspace queries never cross the private workspace ownership boundary.
- Rolling-window usage queries ignore hourly and daily rollups.
- Execution profiling summaries ignore facts outside the requested time window.
- Seed execution with no installation present remains a safe no-op for runtime
  reconciliation after validating the provider catalog.

## Reference Sanity Check

- The retained conclusion from the consulted Dify human-input service slice is
  narrow: human-input submission and resume behavior stays anchored on durable
  workflow-owned request state instead of transcript reconstruction. Core
  Matrix keeps that same read-side stance by querying open
  `HumanInteractionRequest` rows directly for inbox surfaces.
- The retained conclusion from the consulted OpenClaw usage-type slice is also
  narrow: usage reporting is most useful when it is exposed as explicit
  aggregates over tracked usage facts. Core Matrix keeps detailed `UsageEvent`
  and `UsageRollup` roots, then adds query objects that project reporting
  summaries instead of inventing a parallel reporting store.
