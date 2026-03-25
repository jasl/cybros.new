# Workflow Model Selector Resolution

## Purpose

`Workflows::ResolveModelSelector` chooses one provider-qualified model candidate
for a turn-scoped workflow run and freezes the resolved snapshot onto the turn.

This boundary does not assemble runtime input or attachment manifests. It only:

- normalizes execution-time selectors
- resolves one candidate within the selected role or explicit candidate path
- performs a pre-execution entitlement reservation check
- freezes the resolved snapshot onto the executing `Turn`
- exposes read-through selector helpers on `WorkflowRun`

## Resolution Boundary

- `Workflows::ResolveModelSelector` is the required application-service
  boundary for workflow model selection.
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
  - otherwise resolution defaults to `role:main`
- In the shipped catalog baseline, `role:main` contains only real-provider
  candidates. The mock development provider remains opt-in through `role:mock`
  or explicit `candidate:dev/...` selection.

## Candidate Expansion And Fallback

- `role:*` expands to the ordered provider-qualified candidate list from the
  provider catalog.
- `candidate:*` expands to exactly one provider-qualified candidate.
- Unknown roles fail explicitly.
- Candidate evaluation is ordered and deterministic.
- Candidate usability is delegated to `Providers::CheckAvailability`.
- A candidate is usable only when:
  - the provider exists in the catalog
  - the model exists in that provider entry
  - the model is catalog-enabled
  - the provider is catalog-enabled
  - the provider is visible in the current Rails environment
  - installation policy has not disabled the provider
  - one active provider entitlement exists
  - a matching credential exists when the provider requires one
- v1 continues to simulate the execution-time reservation check through active
  entitlement metadata. If `metadata["reservation_denied"] == true`,
  reservation fails for that candidate even after availability succeeds.
- Role-based fallback is allowed only to the next candidate inside the same
  role list.
- Disabled models inside a role list are filtered through the same ordered
  availability pass; they do not invalidate the role definition itself.
- Explicit candidate selection never falls back to a different candidate.
- Specialized roles do not implicitly fall back to `main`.

## Structured Unavailable Reasons

Availability resolution returns structured `reason_key` values for operator and
later UI-facing diagnostics:

- `unknown_provider`
- `unknown_model`
- `model_disabled`
- `provider_disabled`
- `environment_not_allowed`
- `policy_disabled`
- `missing_entitlement`
- `missing_credential`

Explicit candidate failures surface the unavailable reason in the validation
error instead of silently trying unrelated models.

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
- Resolution requires `agent_deployment.active_capability_snapshot_id` so the
  workflow turn cannot proceed without a pinned capability snapshot reference.

## Turn And Workflow Helpers

- `Turn` exposes read-only selector helpers for:
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
- explicit candidates fail immediately on availability rejection or reservation
  denial
- disabled models inside a role list are skipped, but explicit disabled-model
  selections fail immediately
- role-based selections continue only to the next candidate in the same role
  list when availability or reservation checks fail
- no resolution path guesses another role or unrelated model
