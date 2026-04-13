# Prompt Budget Guard Design

## Goal

Add authoritative prompt-budget protection for `core_matrix` turns executed
through `agents/fenix` so oversized provider requests are compacted or rejected
predictably instead of surfacing as generic internal failures.

The target behavior is:

- `core_matrix` owns the final preflight decision before any provider request
  is sent
- prompt-budget checks still work when an exact tokenizer asset is missing
- prompt compaction can be delegated to the runtime first and fall back to an
  embedded implementation
- provider overflow responses produce user-recoverable failure states with
  explicit remediation guidance
- workspace-scoped prompt-compaction policy is resolved predictably and frozen
  into the execution snapshot for the current turn
- v1 changes only the transient provider input for the current round and does
  not rewrite durable transcript history

## Scope

This pass focuses on seven connected changes:

1. Add a token-estimation pipeline with deterministic fallback behavior
2. Add a `core_matrix`-owned prompt-budget guard before provider dispatch
3. Add runtime-first prompt compaction with an embedded fallback
4. Detect provider context overflow explicitly and classify it correctly
5. Project user remediation instructions for edit-or-resend recovery
6. Add workspace-owned structured prompt-compaction configuration
7. Expose prompt-compaction defaults through the Fenix canonical config

## Non-Goals

This pass does not:

- rewrite durable conversation transcript rows or summary segments
- redesign `prepare_round` or the base Fenix runtime protocol
- add a dedicated UI surface beyond the existing workspace policy endpoint
- add UI for tokenizer downloads
- make retry counts or compaction limits runtime-configurable
- guarantee provider-perfect token counts for every model family
- compress attachments or multimodal payloads beyond current provider support

Those remain follow-on work.

## Current Baseline

Today the execution path is:

- `AppAPI::Conversations::MessagesController#create`
  - `Workbench::SendMessage`
  - `Turns::AcceptPendingUserTurn`
  - `Turns::MaterializeAndDispatchJob`
- `ProviderExecution::ExecuteTurnStep`
  - `ProviderExecution::ExecuteRoundLoop`
  - `ProviderExecution::PrepareAgentRound`
  - `ProviderExecution::DispatchRequest`

Within that path:

- user input is stored as-is in `messages.content` with no prompt-size
  validation
- `BuildExecutionSnapshot` computes only advisory values such as
  `recommended_compaction_threshold`
- `PrepareAgentRound` passes those hints to Fenix in `provider_context`
- Fenix exposes `compact_context`, but only as an optional runtime tool
- `DispatchRequest` sends the final message list directly to the provider
- workspace policy currently exposes `disabled_capabilities` and
  `default_execution_runtime`, but not a structured prompt-compaction policy

This means the system currently relies on the runtime or upstream provider to
notice oversized prompt state. `core_matrix` never performs an authoritative
"can this exact request fit?" decision before dispatch, and there is no
workspace-owned control surface for prompt-compaction behavior.

## Problem 1: Budget Hints Exist, But No Authoritative Guard Uses Them

`BuildExecutionSnapshot` already freezes:

- `context_window_tokens`
- `max_output_tokens`
- `recommended_compaction_threshold`
- `tokenizer_hint`

Those values are useful, but they are not consumed by any code that can stop,
compact, or reject a request before `DispatchRequest`.

As a result:

- a long current user message is accepted immediately
- a long accumulated context is assembled into the round payload unchanged
- the provider remains the first actor that can enforce the real hard limit

The product therefore misses the chance to do a cheaper, clearer, and more
recoverable local decision.

## Problem 2: Token Estimation Is Not Guaranteed To Be Available

The repo already ships `tiktoken_ruby` and `tokenizers`, but the current system
does not guarantee:

- a model-specific tokenizer file exists locally
- a predownload path has already run
- every `tokenizer_hint` maps to a locally available exact tokenizer

If prompt-budget protection depends on exact local tokenizer assets, the guard
would silently disappear for some models or environments. The protection needs
an explicit degradation path so that "missing tokenizer asset" becomes "lower
precision estimate," not "no guard at all."

## Problem 3: Delegated Compaction Exists Only As A Suggestion

Fenix already exposes `compact_context` as a replaceable agent tool. That is
the existing hook where the runtime can own compaction behavior.

However, today that capability is only advisory:

- `core_matrix` tells the runtime a compaction threshold
- the runtime may choose to call `compact_context`
- no code in `core_matrix` requires that compaction happen before dispatch

This is insufficient for an actual safeguard. When the assembled provider input
is already close to or beyond the hard limit, the runtime must not be left to
notice the problem "inside the normal turn" because the dispatch payload may
already be too large.

## Problem 4: Provider Overflow Errors Collapse Into Generic Failures

`FailureClassification` currently gives explicit handling to:

- auth expiry
- credits exhaustion
- rate limiting
- overload
- transport failures
- contract failures

But provider-side context overflow currently falls through to the generic
implementation-error bucket. In practice, that means an oversized prompt can
surface as `internal_unexpected_error` even though the true cause is a
recoverable request-size constraint.

That is the wrong product contract. Users should see a direct instruction to
shorten the message and retry, not a misleading internal failure.

## Problem 5: Recovery Guidance Is Not Projected Structurally

The product already supports editing the tail input for some turns through
`Turns::EditTailInput`, but that path is only valid when the selected input is
the editable tail input of the active timeline.

When prompt overflow happens, the system needs to tell the UI and operator
which remediation applies:

- edit the tail input and retry
- send a new, shorter message instead

Without a structured recovery payload, the product can only show a generic text
error even though the actual recovery action depends on timeline state.

## Problem 6: Workspace Policy Cannot Express Prompt-Compaction Intent

The product requirement is that prompt compaction be controllable at the
workspace level. Today there is no workspace-owned structured configuration
surface that can express:

- whether prompt compaction is enabled for this workspace
- whether the workspace prefers runtime-first or embedded-only compaction

That leaves the system with only runtime defaults, which is too coarse. The
default agent/runtime contract should define the baseline, but each workspace
needs a structured override so policy can differ across workspaces using the
same agent/runtime pairing.

## Recommended Direction

### 1. Add A Prompt-Budget Guard In `ExecuteRoundLoop`

Introduce a new service such as
`ProviderExecution::PromptBudgetGuard` and call it after the final provider
messages for the round are assembled:

- after `PrepareAgentRound`
- after prior tool results are appended
- before `DispatchRequest`

That guard becomes the single authority that decides whether the current round:

- fits and may dispatch immediately
- should attempt compaction first
- must fail before provider dispatch

This keeps the decision in `core_matrix`, where the product already owns:

- model metadata
- provider hard limits
- workflow state
- user-facing failure projection

### 2. Use A Deterministic Token-Estimation Fallback Chain

The guard should estimate tokens using a fixed order:

1. exact local tokenizer asset resolved from `tokenizer_hint`
2. `tiktoken` encoder for known compatible hints
3. conservative heuristic fallback

The fallback chain should be explicit in code and tests. A missing local
tokenizer asset must never disable budget protection.

The heuristic path should bias toward over-estimation, not under-estimation.
That preserves safety when precision is unavailable.

### 3. Distinguish Soft Threshold, Hard Limit, And Current-Message Hard Failure

The guard should use three distinct outcomes:

- `allow`
  - total estimated prompt tokens are below the soft threshold
- `compact`
  - total estimated prompt tokens are at or above the soft threshold, or a
    prior provider overflow is being recovered
- `reject`
  - the latest selected user input alone exceeds the remaining hard budget, or
    compaction attempts are exhausted and the request still cannot fit

The "current user message alone is too large" path is important. In that case
the system must not compact older context and pretend recovery is still likely.
The correct action is immediate manual recovery by shortening the new message.

### 4. Make `core_matrix` Orchestrate Compaction Explicitly

`core_matrix` should no longer wait for Fenix to decide whether to compact.
Instead, the guard should actively invoke compaction when required.

The compaction order should be:

1. runtime-provided compaction through the existing `compact_context` tool
2. embedded fallback compaction through `EmbeddedAgents`

The runtime-first choice preserves the replaceable-runtime architecture: Fenix
can evolve the compaction strategy without changing `core_matrix`'s control
flow. The embedded fallback protects the product when:

- runtime compaction is disabled
- the runtime is unavailable
- the runtime declines or fails the compaction request

### 5. Reuse The Existing `compact_context` Tool Contract As The External Hook

The current protocol already supports agent-mediated tool execution and Fenix
already ships `compact_context`.

V1 should reuse that existing contract instead of inventing a new mailbox
request kind. `core_matrix` can issue an out-of-band `execute_tool` request to
the agent runtime before provider dispatch, using:

- the assembled round messages
- provider budget hints
- runtime-visible model context

This gives `core_matrix` an explicit, bounded compaction exchange while keeping
the runtime contract stable.

### 6. Add An Embedded Prompt Compactor As Fallback Only

Create a new embedded agent entry such as `prompt_compaction` under
`core_matrix/app/services/embedded_agents`.

Its responsibilities are limited:

- accept a current round message list and budget target
- preserve the newest user input verbatim
- compress or replace older context into a bounded summary form
- return a replacement message list for the current round only

This embedded implementation is a safety net, not the primary compaction path.
It should not persist summaries back into transcript storage.

### 7. Bound Compaction Attempts With Constants, Not Magic Numbers

Compaction and overflow recovery need explicit fixed limits. Per current repo
convention, these values should live as named constants in the owning classes,
not as inline magic numbers and not as runtime-tunable config.

At minimum, V1 needs constants for:

- max compaction attempts before dispatch
- max provider-overflow recovery attempts
- heuristic safety multiplier or reserve budget
- embedded compactor output budget

### 8. Project Structured Recovery Metadata

Prompt-budget failures should include structured remediation metadata in the
workflow wait/failure payload:

- `retry_mode`
  - `edit_tail_input`
  - `send_new_message`
- `editable_tail_input`
- `failure_scope`
  - `current_message`
  - `full_context`
- `turn_id`
- `selected_input_message_id`

The UI or operator surface can then decide whether to offer:

- "Edit and retry"
- "Send a shorter follow-up"

This keeps the failure actionable and avoids generic error prose.

### 9. Classify Provider Overflow Explicitly

`FailureClassification` should recognize provider overflow from:

- HTTP `413`
- HTTP `400` / `422` bodies containing known overflow phrases such as:
  - `prompt too long`
  - `context length`
  - `maximum context length`
  - `request too large`
  - `context window`

Those cases should map to dedicated non-implementation failure kinds:

- `prompt_too_large_for_retry`
- `context_window_exceeded_after_compaction`

These failures should default to manual retry. They are product-recoverable,
not internal logic bugs.

### 10. Allow One Bounded Provider-Overflow Recovery Loop

Preflight estimation can still be imperfect, especially on fallback paths.

To avoid turning those mismatches into one-shot failures, `ExecuteRoundLoop`
should allow one bounded overflow-recovery path:

- provider request returns explicit overflow
- guard re-enters compaction mode
- compaction runs again
- the request is retried once

If the retried request still overflows, the round fails with the explicit
overflow failure kind and user remediation payload.

This preserves safety while preventing infinite loops.

### 11. Resolve Prompt-Compaction Policy From Workspace Config Over Agent Defaults

V1 should add a structured JSONB `config` field to `workspaces` and reserve it
for workspace-owned policy. Prompt compaction should live under:

- `workspace.config.prompt_compaction.enabled`
- `workspace.config.prompt_compaction.mode`

The effective policy should resolve in this order:

1. workspace override from `workspace.config.prompt_compaction`
2. default from the effective agent canonical config
3. compatibility fallback for older registered runtimes missing the new config

The resolved policy should be frozen into the turn execution snapshot before the
round loop starts. That keeps in-flight turns stable even if a workspace policy
changes while a workflow is already running.

## Configuration Direction

### Agent Default Shape

Fenix canonical config should define the default prompt-compaction shape and
baseline values:

- `prompt_compaction.enabled`
- `prompt_compaction.mode`
  - `runtime_first`
  - `embedded_only`
  - `disabled`

Default behavior should be enabled and runtime-first in:

- `agents/fenix/config/canonical_config.defaults.json`
- `agents/fenix/config/canonical_config.schema.json`

This keeps the runtime contract self-describing and ensures newly registered
agent definitions carry the prompt-compaction baseline automatically.

### Workspace Override Surface

The mutable user-facing override should live in workspace policy, backed by the
new structured `workspaces.config` JSONB field rather than conversation
override payloads or ad hoc runtime overrides.

V1 should extend the existing workspace policy show/update path so it can
project and accept:

- `workspace_policy.prompt_compaction.enabled`
- `workspace_policy.prompt_compaction.mode`

This keeps prompt-compaction policy in the same ownership boundary as other
workspace-level execution settings such as disabled capabilities and default
runtime selection.

### Effective Resolution And Snapshot Freezing

`core_matrix` should resolve and freeze the prompt-compaction policy while
building the execution snapshot. The guard and compaction services should read
that frozen policy from `provider_context`, not from live workspace rows.

That avoids races and makes retries deterministic for the lifetime of the turn.

### Compatibility With Older Runtimes

`core_matrix` should treat missing canonical prompt-compaction config as
"enabled + runtime_first" only during transition, for compatibility with
already-registered older runtimes. Once the bundled/runtime registration path
ships the new config shape everywhere, the compatibility branch can be removed.

## Observability

V1 should record enough state to debug prompt-budget behavior without adding a
new persistence model:

- guard decision outcome
- estimator strategy used
- effective prompt-compaction policy
- estimated prompt tokens before and after compaction
- compaction strategy chosen
- compaction attempts used
- overflow recovery attempt count

This data can remain in workflow-node metadata / wait-reason payload and test
assertions for the first pass.

## Testing Strategy

The implementation should be driven by five test layers:

1. workspace policy and config-shape tests
   - Fenix manifest exposes canonical prompt-compaction defaults
   - workspace policy show/update persists structured prompt-compaction config
   - bundled/default test fixtures carry the new config shape
2. `TokenEstimator` unit tests
   - exact tokenizer path
   - `tiktoken` fallback path
   - heuristic fallback path
3. `PromptBudgetGuard` unit tests
   - `allow`
   - `compact`
   - `reject`
   - single-current-message overflow
4. `ExecuteRoundLoop` integration tests
   - soft-threshold compaction
   - runtime compaction failure with embedded fallback
   - provider overflow recovery retry
5. `FailureClassification` and workflow-failure tests
   - explicit overflow classification
   - remediation metadata for edit vs resend

Because this change touches `ExecuteRoundLoop`, workflow wait/failure state, and
app-facing recovery behavior, completion also requires the full `core_matrix`
verification suite plus the repo-mandated acceptance run from the monorepo
root.

## Summary

The recommended design keeps ownership lines clear:

- `core_matrix` owns the authoritative budget decision, frozen policy
  resolution, and product-facing failures
- Fenix owns the primary replaceable compaction behavior through its existing
  `compact_context` tool
- workspace policy owns the mutable user-facing prompt-compaction override
- embedded compaction exists only as a local safety net

Most importantly, this design turns "prompt too large" from an upstream
surprise into a predictable, bounded, user-recoverable workflow.
