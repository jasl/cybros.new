# Read-Side Queries And Seed Baseline

## Purpose

This note captures the backend-facing read-side queries for the phase 1 roots
and the seed baseline used to make development and reset flows usable without
inventing demo users or UI state.

## Agent Visibility Query

### `Agents::VisibleToUserQuery`

- Returns only `Agent` rows that are visible to one user inside the
  single installation.
- Visibility remains distinct:
  - `public` agents are visible to every user in the installation
  - `private` agents are visible only to their `owner_user`
- Retired logical agent rows are excluded from the default visible list.
- Results are ordered with public agents first, then private agents, with a
  stable secondary order by display name and id.

## Human Interaction Inbox Query

### `HumanInteractions::OpenForUserQuery`

- Reads open `HumanInteractionRequest` rows for one user without mutating
  workflow or request state.
- Ownership is read directly from the request header row:
  `installation_id`, `user_id`, `workspace_id`, and `agent_id`.
- `conversation_id` and `turn_id` stay redundantly persisted for direct
  filtering, but open-inbox access no longer reconstructs ownership by joining
  back through conversation and workspace.
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
- Workspaces disappear from the list when their owning `Agent` is no longer
  usable by the owning user under the current `public/private` visibility
  rules.
- Workspaces do not disappear merely because a default `ExecutionRuntime`
  becomes unavailable or unusable; the product remains agent-first and runtime
  selection stays optional.

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
- Supports optional narrowing by user, workspace, agent, execution runtime, or
  workflow run when a later read surface needs a scoped summary.
- Summary entries expose:
  - event count
  - total `count_value`
  - total `duration_ms`
  - success and failure counts
  - most recent occurrence time

## Workflow Projection

### `Workflows::Projection`

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

## Conversation Blocker Queries

### `Conversations::BlockerSnapshotQuery`

- Builds the canonical conversation blocker snapshot used by both operator
  close summaries and write-side mutation guards.
- Freezes one current set of:
  - mainline blocker counts
  - disposal-tail blocker counts
  - lineage and provenance blocker facts
  - live-mutation eligibility state
- `ConversationBlockerSnapshot` owns the derived predicates for close
  reconciliation and write-fence enforcement.

### Projection Queries

- `Conversations::DependencyBlockersQuery`
- `Conversations::WorkBarrierQuery`
- `Conversations::CloseSummaryQuery`

These queries now project from `Conversations::BlockerSnapshotQuery` instead
of carrying separate counter families and close-summary logic in parallel.

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
- Bundled-runtime reconciliation now keeps both the published version pointer
  and the persisted current-version pointer aligned on the reconciled
  `Agent` and `ExecutionRuntime`.
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
- The acceptance operator scripts intentionally call one combined
  bootstrap-and-seed path after each destructive reset so the development
  database always re-materializes:
  - the provider catalog baseline
  - optional real-provider credentials and governance rows
  - bundled runtime reconciliation when the scenario needs a bundled `Fenix`
    agent definition version
- The acceptance support layer silences seed stdout during those script runs so
  the operator scripts can write pure JSON to stdout and be redirected
  directly into `/tmp/*.json`.

## Failure Modes

- Agent visibility queries exclude another user's private agent
- Human interaction inbox queries exclude resolved requests and requests owned
  by another user's private workspace
- Workspace queries never cross the private workspace ownership boundary and
  hide rows whose bound resources are no longer usable by the owner
- Rolling-window usage queries ignore hourly and daily rollups
- Execution profiling summaries ignore facts outside the requested time window
- Seed execution with no installation present remains a safe no-op for runtime
  reconciliation after validating the provider catalog
