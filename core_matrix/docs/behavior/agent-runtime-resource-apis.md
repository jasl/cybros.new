# Agent Runtime Resource APIs

## Purpose

Task 11.2 exposes the first machine-facing runtime resource APIs for agent
program code: canonical transcript listing, conversation and workspace
variable reads, kernel-owned variable mutation intents, and human interaction
request creation.

## Controller And Query Boundaries

- `AgentAPI::ConversationTranscriptsController` exposes canonical transcript
  reads only.
- `AgentAPI::ConversationVariablesController` exposes conversation-scoped read
  and mutation-intent operations.
- `AgentAPI::WorkspaceVariablesController` exposes workspace-scoped read and
  mutation-intent operations.
- `AgentAPI::HumanInteractionsController` exposes machine-facing creation of
  workflow-owned human interaction requests.
- Read behavior lives in query objects under `app/queries`; controllers remain
  thin wrappers around authenticated lookups, read-side queries, and existing
  kernel-owned services.

## Authentication And Lookup Scope

- all runtime-resource endpoints require machine credential authentication
- authenticated lookups are scoped by the deployment installation and resolve
  resources by `public_id`, not by raw global `bigint` IDs
- workspaces, conversations, turns, workflow runs, and workflow nodes are
  resolved through installation-scoped finders before any read or mutation is
  attempted

## Transcript Listing

- transcript listing publishes the stable method ID
  `conversation_transcript_list`
- transcript reads return only the canonical visible transcript projection
- hidden transcript rows do not leak through this endpoint
- cursor pagination is required from the start
- the cursor is the last visible message `public_id` from the previous page and
  only resolves against the visible transcript projection

## Conversation Variable APIs

### Read Operations

- `conversation_variables_get` returns the current conversation-scoped value
  for one key
- `conversation_variables_mget` returns current conversation-scoped values
  keyed by requested names
- `conversation_variables_list` returns current conversation-scoped values in
  key order
- `conversation_variables_get`, `mget`, and `list` do not fall back to
  workspace values
- `conversation_variables_resolve` returns the effective merged view with
  `conversation > workspace` precedence

### Mutation-Intent Operations

- `conversation_variables_write` creates a new conversation-scoped canonical
  variable row through `Variables::Write`
- `conversation_variables_promote` copies the current conversation-scoped value
  into workspace scope through `Variables::PromoteToWorkspace`
- these endpoints remain kernel-owned mutation boundaries; they do not permit
  direct agent-owned row mutation
- machine-facing variable writes attribute the authenticated deployment as the
  writer when the caller does not provide another writer abstraction

## Workspace Variable APIs

- `workspace_variables_get` returns the current workspace-scoped value for one
  key
- `workspace_variables_mget` returns current workspace-scoped values keyed by
  requested names
- `workspace_variables_list` returns current workspace-scoped values in key
  order
- `workspace_variables_write` creates a new workspace-scoped canonical
  variable row through `Variables::Write`

## Human Interaction Requests

- `human_interactions_request` creates a workflow-owned
  `HumanInteractionRequest` through `HumanInteractions::Request`
- machine-facing request creation is attached to a concrete workflow node and
  therefore to the owning workflow run, turn, and conversation
- blocking requests still move the workflow run into `wait_state = "waiting"`
- request creation still projects `human_interaction.opened` conversation
  events through the existing kernel projection service

## Public Contract Rules

- runtime-resource method IDs remain stable `snake_case` protocol identifiers
- route names stay resource-oriented and do not redefine the canonical public
  method IDs
- existing field names such as `workspace_id`, `conversation_id`,
  `workflow_run_id`, and `turn_id` stay stable while now carrying public ids
- transcript items and human interaction payloads emit resource public ids
- canonical-variable payloads do not expose canonical-variable row ids because
  canonical-variable rows remain internal write-history records
- capability snapshots still publish `protocol_methods` separately from
  `tool_catalog`; runtime-resource controllers do not collapse those families

## Failure Modes

- unknown workspace, conversation, turn, workflow run, or workflow node IDs are
  rejected before the endpoint reads or mutates state
- raw internal bigint identifiers are not accepted as fallback resource lookups
  at these boundaries and therefore fail as missing resources
- transcript cursors that are not present in the visible projection are invalid
- promotion rejects missing conversation-scoped current values
- workflow-owned human interaction creation still inherits the existing service
  validations for blocking-state conflicts and unsupported request subtypes

## Retained Implementation Notes

- read-side behavior was extracted into query objects rather than embedded in
  controllers so transcript and canonical-variable semantics stay reusable
  outside HTTP transport
- collection routes were defined with explicit string paths such as `"get"` and
  `"mget"` so the public route shape stays stable without relying on symbol
  inference rules in the Rails routing DSL
