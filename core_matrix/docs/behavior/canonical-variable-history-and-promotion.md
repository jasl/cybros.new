# Canonical Variable History And Promotion

## Purpose

Task 10.3 adds the kernel-owned durable canonical-variable store.

This task does not expose machine-facing variable APIs or publication read
models yet. It establishes:

- durable canonical history rows
- explicit `workspace` and `conversation` scope boundaries
- supersession without history deletion
- explicit promotion from conversation scope to workspace scope

## Canonical Variable Shape

- `CanonicalVariable` is a durable history record, not an in-place mutable
  cache row.
- Each row stores at least:
  - scope
  - key
  - `typed_value_payload`
  - writer identity when present
  - source kind
  - source conversation, turn, and workflow run references when present
  - projection policy
  - created and superseded timestamps
- v1 only allows two scopes:
  - `workspace`
  - `conversation`

## Scope Rules

- Every canonical variable belongs to one installation and one workspace.
- `workspace` scope must not carry a target `conversation_id`.
- `conversation` scope must carry a target `conversation_id`.
- Conversation-scoped values must belong to the same workspace as the canonical
  variable row.
- The model keeps scope legality explicit; v1 does not introduce any extra
  per-user or per-agent scope.

## Current Value And History

- `current = true` marks the current accepted value for one scope and key.
- A later accepted write supersedes the older current row instead of mutating
  or deleting it.
- Superseded rows retain:
  - `current = false`
  - `superseded_at`
  - `superseded_by_id`
- Partial unique indexes enforce that only one current row may exist for:
  - one workspace-scope key inside one workspace
  - one conversation-scope key inside one conversation
- The write service handles supersession ordering explicitly so uniqueness and
  retained history remain consistent in the same transaction.

## Effective Lookup

- `CanonicalVariable.effective_for` implements the v1 precedence rule:
  `conversation > workspace`.
- If a current conversation-scoped row exists for the requested key, it wins.
- Otherwise the current workspace-scoped row for that key becomes the effective
  value.
- This read helper is still model-local infrastructure, not the later
  machine-facing resolve API.

## Write And Promotion Services

- `Variables::Write` is the kernel-owned write boundary.
- Callers provide:
  - target scope
  - workspace and optional conversation target
  - key
  - typed value payload
  - writer identity when present
  - source metadata
  - projection policy
- The service finds the existing current value for the same scope and key,
  supersedes it, and creates a new current row in one transaction.
- `Variables::PromoteToWorkspace` is the explicit promotion boundary.
- Promotion requires a current conversation-scoped canonical value.
- Promotion writes a new workspace-scoped canonical row with:
  - the same key
  - the same typed value payload
  - `source_kind = promotion`
  - the source conversation carried forward
- Promotion supersedes any prior current workspace-scoped value without
  deleting its history.
- Promotion does not delete or rewrite the originating conversation-scoped
  current value.

## Projection Policy

- Task 10.3 persists `projection_policy` on canonical writes, but does not yet
  expose read models or guaranteed conversation projection for every variable
  mutation.
- This keeps the write contract aligned with the design without prematurely
  deciding which canonical-variable changes must always become
  `ConversationEvent` rows.

## Failure Modes

- unsupported scope values are rejected
- workspace-scope rows reject target conversations
- conversation-scope rows reject missing target conversations
- non-hash typed payloads are rejected
- broken writer polymorphic pairings are rejected
- superseded rows reject missing `superseded_at` or `superseded_by`
- promotion rejects non-conversation or non-current source rows

## Rails And Reference Findings

- Local Rails validation guidance again fit this task's service-owned write
  pattern: legality checks stay on the model, while multi-row supersession
  sequencing lives in `Variables::Write`.
- A narrow Dify sanity check showed Dify keeps conversation variables in a
  distinct variable namespace instead of collapsing all variable spaces into one
  undifferentiated key store. Core Matrix keeps the stronger kernel contract of
  explicit scope values plus auditable supersession history and explicit
  promotion between scopes.
- No reference implementation was treated as authoritative for this task; the
  landed contract is defined by the local design and tests.
