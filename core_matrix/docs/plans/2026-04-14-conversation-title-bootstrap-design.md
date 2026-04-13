# Conversation Title Bootstrap Design

## Goal

Move conversation title bootstrap out of the synchronous accepted-turn path
while keeping an immediately displayable default title and preserving a clear
upgrade path to runtime-provided title generation.

The target behavior is:

- newly created conversations always have a user-visible placeholder title
- accepted manual user turns no longer synchronously generate the real title
- title bootstrap becomes a best-effort asynchronous metadata upgrade
- workspace policy can enable/disable title bootstrap and choose runtime-first
  versus embedded-only behavior
- `core_matrix` retains an embedded fallback so title bootstrap still works
  even when the runtime does not implement a dedicated summary-title feature

## Scope

This pass changes five connected areas:

1. add an i18n-backed default conversation title
2. remove synchronous title bootstrap from manual user turn acceptance
3. add a background title-bootstrap job for the first manual user turn
4. add workspace-owned structured configuration for title bootstrap
5. reserve an optional runtime-first title-bootstrap path while implementing an
   embedded fallback in `core_matrix`

## Non-Goals

This pass does not:

- make title bootstrap part of accepted-turn correctness
- add backlog recovery or durable repair for missing title bootstrap jobs
- add a new UI surface beyond the existing workspace policy endpoint
- require `agents/fenix` to implement summary-title generation in this pass
- redesign conversation summary generation or metadata regeneration broadly
- introduce a new metadata failure state visible to users

Those remain follow-on work.

## Relationship To Existing Work

This follow-up builds on the accepted-turn and workflow-bootstrap slimming that
already landed in `core_matrix`.

Today:

- `Workbench::CreateConversationFromAgent` creates a root conversation and
  accepts a pending turn
- `Workbench::SendMessage` accepts a pending turn
- app-facing mutation responses already return `execution_status = pending`
  without synchronously materializing workflow substrate

Title bootstrap is one of the last user-facing metadata writes still happening
inside the accepted-turn transaction. This design moves it out of that path.

This pass also intentionally pre-lands a structured `workspaces.config` field
that the prompt-budget-guard plan expects later. Title bootstrap is the first
consumer of that config surface.

## Current Baseline

Today the relevant manual user-entry paths are:

- `AppAPI::ConversationsController#create`
  - `Workbench::CreateConversationFromAgent`
  - `Conversations::CreateRoot`
  - `Turns::AcceptPendingUserTurn`
- `AppAPI::Conversations::MessagesController#create`
  - `Workbench::SendMessage`
  - `Turns::AcceptPendingUserTurn`

Within those paths:

- new conversations are created without a guaranteed display title
- `Turns::AcceptPendingUserTurn` synchronously creates the first `UserMessage`
- it then calls `Conversations::Metadata::BootstrapTitle`
- `BootstrapTitle` derives the title from the first user message by:
  - taking the first non-blank line
  - truncating to a maximum length
  - falling back to `"Untitled conversation"`
- `title_source` is immediately set to `"bootstrap"`

That makes accepted-turn persistence do a metadata decision that is not part of
accepted-turn truth.

## Problem 1: Title Bootstrap Is Still In The Accepted-Turn Hot Path

The accepted-turn path is now supposed to own:

- conversation truth
- turn truth
- selected input message truth
- queue/pending execution truth

Title bootstrap is not part of that boundary. It is display metadata derived
from existing durable truth.

Keeping it synchronous causes the request path to:

- do extra metadata branching and writes
- claim the title is already bootstrapped before any asynchronous follow-up has
  had a chance to run
- couple a non-critical presentation concern to accepted-turn persistence

That contradicts the refactor direction already applied to workflow bootstrap,
diagnostics, and supervision projections.

## Problem 2: The Current Fallback Title Is Hardcoded And Misclassified

`BootstrapTitle` currently hardcodes `"Untitled conversation"` and writes it
with `title_source = "bootstrap"` when the first user input is blank.

Those are two separate concerns:

- the placeholder title needed for immediate display
- the actual bootstrap result produced from user intent

If the placeholder is written as a bootstrap result, the metadata source stops
being truthful. Export surfaces and later metadata operations cannot distinguish
between:

- a conversation that only has the default placeholder
- a conversation whose title was actually bootstrapped

## Problem 3: Runtime-First Title Generation Needs A Clear Fallback Contract

The product direction here should match prompt-budget compaction:

- runtime may provide a dedicated capability
- `core_matrix` retains a product-owned fallback

If title bootstrap is runtime-owned only, the feature becomes unavailable when:

- the runtime does not implement it
- the runtime is unavailable
- the runtime contract changes or declines the request

If title bootstrap is embedded-only forever, the runtime cannot eventually own a
more specialized or cheaper title-summary path.

The system needs both:

- a runtime-first policy mode
- an embedded fallback

## Problem 4: Workspace Policy Has No Structured Config Surface Yet

The prompt-budget-guard design already expects `workspaces.config` to exist as
a structured JSONB policy surface. That field does not exist yet in the branch.

If title bootstrap adds a one-off flat column or ad hoc side table now, the
product will immediately have two competing policy shapes.

This is a good place to land the shared direction early:

- `workspaces.config` becomes the structured policy container
- title bootstrap is the first consumer
- prompt-budget-guard later extends the same field

## Recommended Direction

### 1. Always Create Conversations With An I18n Placeholder Title

`Conversations::CreateRoot` should initialize new conversations with an i18n
default title, for example:

- key: `conversations.defaults.untitled_title`
- initial value: `"Untitled conversation"`

That placeholder is presentation truth only.

The conversation should still start as:

- `title_source = "none"`
- `title_lock_state = "unlocked"`

This keeps the metadata source honest while ensuring every API response has a
stable display title immediately.

### 2. Remove Synchronous Title Bootstrap From Manual User Turn Acceptance

`Turns::AcceptPendingUserTurn` and `Turns::StartUserTurn` should stop calling
`Conversations::Metadata::BootstrapTitle`.

Manual user entry should remain responsible only for:

- creating the turn
- creating the selected input message
- freezing execution identity
- updating anchors
- projecting pending execution state

Title generation becomes a separate metadata follow-up.

### 3. Add A Best-Effort `BootstrapTitleJob`

Introduce a background job such as
`Conversations::Metadata::BootstrapTitleJob`.

The enqueue point should be:

- after the first manual user turn is accepted
- outside the accepted-turn transaction, similar to workflow materialization

The job should:

1. load the target conversation and turn by `public_id`
2. resolve the selected input message or first manual user input message
3. re-enter under the conversation entry lock
4. verify the title is still eligible for bootstrap
5. attempt title generation through the resolved policy
6. persist the upgraded title only if it is still safe to do so

If the job fails or generation returns nothing usable:

- keep the placeholder title
- keep `title_source = "none"`
- log the failure
- do not fail the conversation or turn

This keeps title bootstrap optional and non-blocking.

### 4. Add A Strict Eligibility Gate Before Upgrading The Title

The asynchronous job should only overwrite the title when all of these remain
true inside the lock:

- `title_source == "none"`
- `title_lock_state == "unlocked"`
- `conversation.title` still equals the configured placeholder title
- the target message exists and is a user input message
- the target turn is still the first manual user turn for the conversation

This prevents the job from racing with:

- user title edits
- agent metadata updates
- summary/title regeneration
- future turns that should not re-bootstrap the title

### 5. Resolve Title-Bootstrap Policy From Workspace Feature Config First

Add structured workspace config under:

- `workspace.config.features.title_bootstrap.enabled`
- `workspace.config.features.title_bootstrap.mode`

The initial supported modes should be:

- `runtime_first`
- `embedded_only`

Recommended defaults:

- `enabled: true`
- `mode: "runtime_first"`

Resolution precedence should be:

1. workspace override from `workspace.config.features.title_bootstrap`
2. agent/runtime canonical config default
3. built-in fallback default of `enabled = true`, `mode = runtime_first`

This mirrors the prompt-budget-guard direction and avoids introducing another
policy shape later.

### 6. Reserve A Runtime-First Capability, But Keep It Optional In V1

The agent/runtime side should gain a reserved canonical config shape for title
bootstrap, but the actual summary-title capability is optional in this pass.

That means:

- `agents/fenix` may expose default config like
  `features.title_bootstrap.enabled` and
  `features.title_bootstrap.mode`
- `core_matrix` should not require a runtime implementation to ship this pass

When `mode = runtime_first`, `core_matrix` may attempt the runtime path first.
If the runtime does not expose the capability yet, the call should gracefully
fall back to the embedded path.

This should follow the same split used by prompt compaction:

- `features.title_bootstrap.*` expresses policy
- the frozen agent capability surface expresses actual implementation support

V1 does not need a separate feature-support manifest. If Fenix eventually
implements runtime title generation, it should advertise that through the
existing agent `tool_contract` and handle it through the existing
`execute_tool` mailbox path.

That implies two distinct fallback checks:

1. static capability check
   - if the frozen capability snapshot does not include the title-bootstrap
     tool, do not send mailbox work and fall back immediately
2. dynamic execution check
   - if the tool is advertised but Fenix returns `unsupported_tool`, times out,
     or otherwise fails the agent request, fall back to the embedded path

This keeps policy and capability orthogonal and avoids introducing a second
"does the runtime support this?" contract alongside the existing manifest and
tool-binding system.

### 7. Add An Embedded Title Agent In `core_matrix`

Add a dedicated embedded agent entry under `app/services/embedded_agents`, for
example:

- `EmbeddedAgents::ConversationTitle::Invoke`

This agent should be intentionally narrow:

- input:
  - first user message content
  - optional request summary
  - a very small transcript window when needed
- output:
  - one candidate title string
- constraints:
  - same language as the user input
  - no quotes, labels, prefixes, or explanations
  - single line
  - specific and user-facing
  - maximum 80 characters

This embedded path becomes the guaranteed product fallback when runtime title
generation is unavailable.

### 8. Keep A Deterministic Heuristic As The Last Fallback

The existing `BootstrapTitle` heuristic remains useful, but it should move from
"the synchronous primary path" to "the final fallback when modeled generation
is unavailable."

The fallback order should be:

1. runtime summary-title capability, when enabled and present in the frozen
   capability snapshot
2. embedded title agent
3. deterministic first-line heuristic

This keeps the feature resilient even when provider-backed generation is
unavailable.

## Prompt Guidance

The reference repos do not justify a large summarization prompt here.

Notably:

- the `claude-code` reference derives a session title from the first user
  message by flattening whitespace and truncating
- `core_matrix` already has a simple title-generation prompt in
  `Conversations::Metadata::GenerateField`

So the embedded title prompt should stay deliberately small. A good v1 system
prompt shape is:

> You write concise, user-facing conversation titles. Use the same language as
> the user input. Output only the title, with no quotes or explanation. Focus
> on the user’s concrete task or question. Keep it specific, single-line, and
> at most 80 characters.

This is enough for title quality without turning B3 into a general summary
system.

## Alternatives Considered

### A. Keep Synchronous Heuristic Bootstrap

Rejected because it keeps metadata generation in the accepted-turn hot path and
does not align with the rest of the refactor direction.

### B. Runtime-Only Title Bootstrap

Rejected because it makes title quality depend entirely on optional runtime
support and removes product-owned fallback behavior.

### C. Read-Time Placeholder Fallback Only

Rejected because it spreads placeholder logic across presenters and exporters
instead of keeping title truth on the conversation row.

## Risks

### Placeholder Titles May Persist Longer

If the background job is delayed or fails, users may see the placeholder title
for longer than before.

That is acceptable because:

- the title remains displayable immediately
- title bootstrap is not accepted-turn correctness
- the user can still rename the title manually

### Workspace Policy Surface Starts Small But Must Stay Structured

This pass introduces `workspaces.config` primarily for title bootstrap. The
implementation must keep the shape generic and structured so prompt-budget
guard can reuse it instead of reworking it.

### Runtime Capability Drift Must Not Break The Feature

The runtime-first path must be optional and failure-tolerant. Embedded fallback
must remain the product safety net.

Capability drift should be handled in two layers:

- missing capability in the frozen manifest/tool snapshot means "skip runtime"
- runtime-side `unsupported_tool` or equivalent mailbox failure means "fall
  back", not "fail title bootstrap"

## Testing Strategy

The implementation should lock five classes of behavior:

1. conversations are created with the i18n placeholder title and
   `title_source = "none"`
2. accepted manual user turns no longer synchronously set `title_source =
   "bootstrap"`
3. the title-bootstrap job upgrades eligible placeholder titles asynchronously
4. workspace policy show/update persists and returns the structured
   title-bootstrap config
5. embedded and heuristic fallbacks preserve title bootstrap when runtime
   support is absent

Specific regression coverage should include:

- first manual turn enqueues the title-bootstrap job
- later turns do not overwrite existing titles
- user-locked titles are never replaced
- runtime-first mode only attempts mailbox work when the frozen capability
  snapshot advertises the title tool
- runtime-first mode gracefully falls back when runtime support is unavailable
- runtime-first mode gracefully falls back when the agent returns
  `unsupported_tool`
- blank or low-signal input still lands on the deterministic fallback

## Success Criteria

This follow-up is successful when:

- accepted-turn hot paths no longer call synchronous title bootstrap
- new conversations always have an i18n-backed placeholder title
- title bootstrap becomes asynchronous and best-effort
- `WorkspacePolicy` exposes structured title-bootstrap config from
  `workspaces.config`
- `core_matrix` has an embedded fallback title agent
- the product keeps a safe deterministic fallback when modeled generation is
  unavailable
