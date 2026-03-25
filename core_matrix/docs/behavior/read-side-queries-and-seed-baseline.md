# Read-Side Queries And Seed Baseline

## Purpose

This note captures the backend-facing read-side queries for the phase 1 roots
and the seed baseline used to make development and reset flows usable without
inventing demo users or UI state.

## Agent Visibility Query

### `AgentInstallations::VisibleToUserQuery`

- Returns only `AgentInstallation` rows that are visible to one user inside the
  single installation.
- Visibility remains distinct:
  - `global` agent installations are visible to every user in the installation
  - `personal` agent installations are visible only to their `owner_user`
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
  inbox or dashboard tooling rather than direct transcript reply.
- Results are ordered by creation time and id for a stable actionable list.

## Workspace Listing Query

### `Workspaces::ForUserQuery`

- Returns only private workspaces owned by one user inside the installation.
- The query does not widen access for admins or other users.
- Default workspaces are ordered first so a user-agent binding presents an
  immediately usable primary workspace before secondary ones.

## Provider Usage Window Query

### `ProviderUsage::WindowUsageQuery`

- Reads `UsageRollup` rows from the `rolling_window` bucket only.
- Aggregates across dimension-specific rollup rows into provider-model-operation
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

## Workflow Projection Query

### `Workflows::ProjectionQuery`

- Reads one workflow run as a proof- and inspection-friendly bundle.
- Returns:
  - ordered workflow nodes
  - ordered workflow edges
  - node-key-grouped workflow node events
  - node-key-grouped workflow artifacts
- Relies on frozen workflow-owned projection metadata such as:
  - `workspace_id`
  - `conversation_id`
  - `turn_id`
  - `workflow_node_key`
  - `workflow_node_ordinal`
  - `presentation_policy`
- The query intentionally avoids graph-reconstruction SQL or node-by-node
  follow-up queries for artifacts and events.

## Seed Baseline

- `db/seeds.rb` always loads the provider catalog so environment setup fails
  early if the catalog config is malformed or missing.
- Seeds do not create:
  - installations
  - identities
  - users
  - bindings
  - workspaces
- When an installation already exists, seeds still reconcile the optional
  bundled runtime through `Installations::RegisterBundledAgentRuntime`.
- In environments where the shipped `dev` provider is visible, seeds create the
  minimal governance baseline needed for `dev` to be usable:
  - one enabled `ProviderPolicy`, only when no policy row exists for `dev`
  - one active `ProviderEntitlement`, only when no entitlement row exists for
    `dev`
- Seeds optionally import real-provider credentials from:
  - `OPENAI_API_KEY`
  - `OPENROUTER_API_KEY`
- When one of those environment variables is present, seeds:
  - upsert the matching `ProviderCredential` through
    `ProviderCredentials::UpsertSecret` with `actor: nil`
  - create the provider's baseline policy and entitlement only when governance
    rows for that provider do not already exist
- Seeds never rewrite an existing provider policy or entitlement just to reapply
  the baseline. This preserves manual operator disables and avoids unnecessary
  audit churn.
- Credential upserts are skipped when the existing credential already matches
  the intended secret and metadata.
- With no real-provider credentials present, the seeded `dev` baseline keeps
  the shipped mock path usable in `development` and `test` through
  `role:mock` or explicit `candidate:dev/...` selection.
- With `OPENAI_API_KEY` or `OPENROUTER_API_KEY` present, those real providers
  can participate in `role:main` immediately without changing conversation
  selector mode away from `auto`.

## Failure Modes

- Agent visibility queries exclude another user's personal agent installation
- Human interaction inbox queries exclude resolved requests and requests owned
  by another user's private workspace
- Workspace queries never cross the private workspace ownership boundary
- Rolling-window usage queries ignore hourly and daily rollups
- Execution profiling summaries ignore facts outside the requested time window
- Seed execution with no installation present remains a safe no-op for runtime
  reconciliation after validating the provider catalog
