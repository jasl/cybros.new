# Workflow Model Selector Resolution

## Purpose

Task 09.3 adds the explicit selector-resolution boundary that chooses one
provider-qualified model candidate for a turn-scoped workflow run.

This task does not assemble runtime input or attachment manifests. It only:

- normalizes execution-time selectors
- resolves one candidate within the selected role or explicit candidate path
- performs a pre-execution entitlement reservation check
- freezes the resolved snapshot onto the executing `Turn`
- exposes read-through selector helpers on `WorkflowRun`

## Resolution Boundary

- `Workflows::ResolveModelSelector` is the required application-service boundary
  for workflow model selection.
- `Workflows::CreateForTurn` resolves and freezes the selector snapshot before
  it creates the workflow run and root node.
- The canonical durable execution snapshot lives on
  `Turn.resolved_model_selection_snapshot`.
- `WorkflowRun` does not persist a second selector store in this task. It reads
  denormalized selector helpers from its owning turn for operational queries.

## Selector Normalization

- All execution-time selectors normalize to exactly one of:
  - `role:<role_name>`
  - `candidate:<provider_handle/model_ref>`
- If the service receives an explicit selector:
  - raw role names normalize to `role:*`
  - raw `provider_handle/model_ref` values normalize to `candidate:*`
  - already normalized selectors are preserved
- If no explicit selector is provided:
  - a conversation in `explicit_candidate` mode normalizes to its configured
    `candidate:<provider_handle/model_ref>`
  - otherwise resolution defaults to the reserved interactive path
    `role:main`

## Candidate Expansion And Fallback

- `role:*` expands to the ordered provider-qualified candidate list from the
  provider catalog.
- `candidate:*` expands to exactly one provider-qualified candidate.
- Unknown roles fail explicitly.
- Candidate evaluation is ordered and deterministic.
- A provisional candidate is usable only when:
  - provider policy does not disable that provider
  - the provider-qualified model exists in the provider catalog
  - one active provider entitlement exists for that provider
- v1 simulates the execution-time reservation check through active entitlement
  metadata. If `metadata["reservation_denied"] == true`, reservation fails for
  that candidate.
- Role-based fallback is allowed only to the next candidate inside the same
  role list.
- Explicit candidate selection never falls back to a different candidate.
- Specialized roles do not implicitly fall back to `main`.

## Frozen Snapshot Fields

- A successful resolution freezes at least these fields on the executing turn:
  - `selector_source`
  - `normalized_selector`
  - `resolved_role_name` when resolution came from a role
  - `resolved_provider_handle`
  - `resolved_model_ref`
  - `resolution_reason`
  - `fallback_count`
  - `capability_snapshot_id`
  - `entitlement_key` when one active entitlement was used
- Resolution now requires `agent_deployment.active_capability_snapshot_id` so
  the workflow turn cannot proceed without a pinned capability snapshot
  reference.

## Turn And Workflow Helpers

- `Turn` now exposes read-only selector helpers for:
  - `normalized_selector`
  - `resolved_provider_handle`
  - `resolved_model_ref`
  - `resolved_role_name`
- `WorkflowRun` delegates the same selector helpers to its owning turn with
  `allow_nil: true`, keeping workflow queries orthogonal to the canonical turn
  snapshot.

## Failure Modes

- missing active capability snapshot rejects resolution
- unknown model roles reject resolution
- empty or exhausted role candidate lists reject resolution
- disabled providers, missing catalog models, or missing active entitlements
  reject explicit candidates immediately
- role-based selections continue only to the next candidate in the same role
  list when filter or reservation checks fail
- no resolution path guesses another role or unrelated model

## Rails And Reference Findings

- Local Rails Active Support guides confirmed `delegate ... allow_nil: true` is
  the correct pattern for `WorkflowRun` read-through selector helpers that
  should return `nil` rather than raising when the association is absent.
- Local Rails validation guides confirmed the `errors.add` plus
  `ActiveRecord::RecordInvalid` pattern used here is the intended way to expose
  model-backed validation failures through a service boundary.
- A narrow Dify sanity check on
  `references/original/references/dify/api/services/workflow_service.py`
  showed Dify validates an exact provider-model choice and then reuses runtime
  credential fallback rules inside that provider context. Core Matrix
  intentionally freezes one provider-qualified candidate onto the turn and
  allows fallback only within the currently selected role list, not across
  unrelated roles or implicit model guesses.
