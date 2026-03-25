# Agent Runtime Resource APIs

## Purpose

Core Matrix exposes machine-facing runtime resource APIs for:

- canonical transcript listing
- conversation-local canonical store reads and writes
- workspace-scoped canonical variable reads and writes
- workflow-owned human interaction request creation

These endpoints are thin HTTP boundaries over authenticated lookups, query
objects, and kernel-owned services.

## Authentication And Lookup Scope

- all runtime-resource endpoints require machine credential authentication
- lookups are scoped to the deployment installation
- lookups resolve resources by `public_id`, never raw internal `bigint` ids
- conversations are resolved only while `deletion_state = retained`
- deleted or pending-delete conversations are therefore hidden from
  agent-facing transcript and variable endpoints

## Transcript Listing

- transcript listing publishes the stable method ID
  `conversation_transcript_list`
- transcript reads return only the canonical visible transcript projection
- hidden transcript rows do not leak through this endpoint
- cursor pagination uses visible message `public_id`

## Conversation Variable APIs

### Read Operations

- `conversation_variables_get` returns one visible conversation-local value
- `conversation_variables_mget` returns visible conversation-local values keyed
  by requested names
- `conversation_variables_exists` returns whether a visible conversation-local
  key exists
- `conversation_variables_list_keys` returns paginated key metadata only
- `conversation_variables_resolve` returns the effective merged view with
  conversation-local values overriding workspace-scoped canonical variables

### Mutation Operations

- `conversation_variables_set` writes one conversation-local value through
  `CanonicalStores::Set`
- `conversation_variables_delete` writes one conversation-local tombstone
  through `CanonicalStores::DeleteKey`
- `conversation_variables_promote` reads the current conversation-local value
  and writes a new workspace canonical-variable history row through
  `Variables::PromoteToWorkspace`

### Contract Rules

- conversation-local runtime state is backed by the canonical store, not by
  `CanonicalVariable`
- `conversation_variables_get`, `mget`, `exists`, and `list_keys` do not fall
  back to workspace values
- `list_keys` returns metadata only:
  - key
  - scope
  - value type
  - value byte size
- `conversation_variables_list` and `conversation_variables_write` were removed
  in the same rollout; no compatibility aliases remain
- conversation-variable payloads do not expose canonical-store row ids or
  canonical-variable row ids
- writes, deletes, and promotion are rejected once a conversation is no longer
  retained

## Workspace Variable APIs

- `workspace_variables_get` returns the current workspace value for one key
- `workspace_variables_mget` returns current workspace values keyed by
  requested names
- `workspace_variables_list` returns current workspace values in key order
- `workspace_variables_write` creates a new workspace-scoped
  `CanonicalVariable` history row through `Variables::Write`

## Human Interaction Requests

- `human_interactions_request` creates a workflow-owned
  `HumanInteractionRequest` through `HumanInteractions::Request`
- blocking requests still move the workflow run into `wait_state = "waiting"`
- request creation still projects `human_interaction.opened`
  `ConversationEvent` rows
- opening a human interaction is rejected unless the owning conversation is
  both retained and active
- late human resolution paths are also rejected once the conversation is no
  longer retained or no longer active
- both checks are enforced from fresh locked conversation and workflow/request
  state rather than trusting a stale caller-side object snapshot

## Public Contract Rules

- runtime method IDs stay stable `snake_case` protocol identifiers
- route names stay resource-oriented and do not redefine the method IDs
- payload fields such as `workspace_id`, `conversation_id`, `turn_id`,
  `workflow_run_id`, and `workflow_node_id` carry `public_id` values
- raw internal bigint ids are never accepted as fallback resource lookups
- capability snapshots still expose `protocol_methods` separately from
  `tool_catalog`

## Failure Modes

- unknown public ids fail lookup before any read or mutation runs
- raw bigint identifiers fail as missing resources at these boundaries
- transcript cursors that are not present in the visible projection are invalid
- oversized or illegal canonical-store writes fail through the underlying
  canonical-store validations
- conversation-local writes, deletes, promotions, and human interaction opens
  are rejected for `pending_delete` or `deleted` conversations
- human interaction opens and late human-interaction resolution are rejected for
  archived conversations
