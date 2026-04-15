# Workspace-Agent Global Instructions Design

## Goal

Introduce one durable, mount-scoped `global_instructions` capability on
`WorkspaceAgent`, project it into Fenix as explicit runtime context, and delete
Fenix's current filesystem-based `AGENTS.md` loading.

This round is intentionally narrow. It does **not** implement generic
mount-level settings, settings schema publication, or prompt sub-layer knobs.
Those remain a deferred follow-up.

This refactor is intentionally destructive with respect to Fenix's current
`workspace_root` / `AGENTS.md` behavior. Prompt construction authority remains
in Fenix.

For CoreMatrix schema work, this design assumes destructive migration rewrites
rather than additive compatibility migrations. The owning original migration
files should be updated in place and the database/schema should then be
regenerated using the repository-standard rebuild flow from `AGENTS.md`.

## Problem

Today Fenix still treats workspace instructions as a local filesystem concern:

- [`Shared::PayloadContext`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/shared/payload_context.rb:53)
  synthesizes `workspace_root` using payload/defaults/env/current working
  directory.
- [`BuildRoundInstructions`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/build_round_instructions.rb:26)
  reads that path.
- [`Prompts::WorkspaceInstructionLoader`](/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/prompts/workspace_instruction_loader.rb:1)
  loads `AGENTS.md` from disk.

That boundary is wrong for the current architecture:

- the agent should not discover user/workspace prompt state from local files
- CoreMatrix should own durable user/workspace/mount data
- the requested capability is not project-wide prompt layering; it is one
  shared instructions block for one mounted agent inside one workspace

## Design Principles

1. Prompt construction authority stays in Fenix.
2. CoreMatrix stores and transports mount-scoped data; it does not merge or
   interpret prompt layers.
3. Data that applies to one workspace-agent relationship belongs to
   `WorkspaceAgent`, not `Workspace` and not workspace policy.
4. User-configurable prompt-affecting behavior should start with the narrowest
   safe product primitive: one plain-text `global_instructions` block.
5. Frozen turn state must be reusable. Once `global_instructions` is snapped for
   a turn, CoreMatrix should reuse a deduplicated document reference rather than
   copy the same large text into multiple normalized rows.
6. No compatibility fallback should remain for `workspace_root`,
   `FENIX_WORKSPACE_ROOT`, `Dir.pwd`, or repo-local `AGENTS.md`.

## Recommended Model

### `WorkspaceAgent`

Keep the current `WorkspaceAgent` name for this round and add one mount-scoped
field directly to it:

- `global_instructions :text`

Semantics:

- this is the authoritative current editable value for one mounted agent inside
  one workspace
- blank values normalize to `nil`
- changing it affects future turns only; it does not rewrite already-frozen
  turns or queued mailbox payloads

`WorkspaceAgent` remains the right place because this data affects one mounted
agent in one workspace and should not bleed across other agents mounted into the
same workspace.

### Frozen Snapshot Storage

Turn execution needs a frozen copy of the current mount instructions, but that
copy should be stored using the repository's existing deduplicated document
pattern.

Recommended shape:

- keep the canonical editable text on `WorkspaceAgent.global_instructions`
- add a nullable document reference on `ExecutionContract`:
  `workspace_agent_global_instructions_document`
- store the frozen value in a deduplicated `JsonDocument` with
  `document_kind = "workspace_agent_global_instructions"` and payload:

```json
{
  "global_instructions": "Always prefer concise Chinese responses.\n"
}
```

Why this shape:

- the editable hot-path value stays simple and app-facing on `WorkspaceAgent`
- the frozen turn contract stays immutable
- repeated identical instruction blocks across many turns reuse one
  content-addressed `JsonDocument` row instead of expanding snapshot storage

If a mount has no `global_instructions`, no document ref should be stored.

## App Surface

### `WorkspaceAgent` App API

Extend the existing `WorkspaceAgentsController` surface rather than inventing a
new resource.

Allowed app-facing behavior in this round:

- create a mount with `global_instructions`
- update a mount's `global_instructions`
- present `global_instructions` on `WorkspaceAgentPresenter`

Rules:

- absent field preserves the stored value on update
- blank string clears the value
- payloads continue using public ids only

Do **not** put `global_instructions` in:

- `Workspace.config`
- workspace policy APIs
- runtime/capability policy payloads

Those are different domains.

Because `global_instructions` lives directly on the `workspace_agents` row, this
round should not require new `workspace_list` preload branches. If presenter
changes accidentally introduce extra lookups, that is a regression.

## Runtime Contract

Introduce explicit mount-scoped runtime context:

```json
{
  "workspace_agent_context": {
    "workspace_agent_id": "wsa_...",
    "global_instructions": "..."
  }
}
```

Rules:

- `workspace_context` remains reserved for workspace-root concerns
- `workspace_agent_context` carries only mount-scoped prompt data
- `workspace_agent_id` is always present
- `global_instructions` is present only when the frozen snapshot has a value

This context must be consistent across:

- `TurnExecutionSnapshot`
- direct `prepare_round` request construction
- mailbox compaction/reconstruction paths
- shared CoreMatrix↔Fenix contract fixtures

### Freeze Semantics

`global_instructions` should freeze at the same turn execution boundary as other
execution contract state:

1. the current `WorkspaceAgent.global_instructions` is read when
   `Workflows::BuildExecutionSnapshot` builds or refreshes the turn's execution
   contract
2. the frozen value is externalized through the deduplicated `JsonDocument` ref
3. `TurnExecutionSnapshot#workspace_agent_context` materializes the runtime
   payload from that frozen document ref
4. direct `prepare_round` and mailbox reconstruction both reuse the same frozen
   shape

Editing `WorkspaceAgent.global_instructions` later affects future turns only.
Already-frozen turns, queued mailbox items, retries, and recoveries continue to
use the frozen value captured for that turn.

## Fenix Behavior

Fenix should consume `workspace_agent_context.global_instructions` as an
additional prompt section and nothing more.

Recommended assembler layout:

1. `Code-Owned Base`
2. `Role Overlay`
3. `Global Instructions`
4. `Skill Overlay`
5. `Supervisor Guidance`
6. `CoreMatrix Durable State`
7. `Execution-Local Fenix Context`

Important constraints:

- `global_instructions` is additive product data, not a prompt-file override
- Fenix retains authority over how that text is rendered into the final system
  prompt
- no local `AGENTS.md` reads remain after this refactor

That keeps the new feature narrow, product-facing, and low-risk while fixing
the architecture boundary.

## Deferred Follow-Up

The following are intentionally **not** part of this round, but the
implementation should avoid boxing them out:

- `WorkspaceAgent.settings`
- agent-version-owned mount settings schema/default publication on
  `AgentDefinitionVersion`
- read-only app exposure of those schema/default documents
- future validation/defaulting of mount settings against agent-published schema

When that follow-up is resumed, keep these conventions:

- mount-owned mutable values live on `WorkspaceAgent`
- agent-owned schema/default contracts live on `AgentDefinitionVersion`
- CoreMatrix transports durable configuration state but does not own prompt
  layer assembly

## Non-Goals

This design intentionally does **not** do the following:

- no `prompt.soul`, `prompt.user`, or `prompt.worker` configuration
- no CoreMatrix-side prompt merge or precedence resolution
- no workspace-wide instructions that automatically affect every mounted agent
- no user-global cross-workspace instruction memory
- no generic settings UI in this round
- no agent capability contract changes for mount settings in this round
- no compatibility fallback for local filesystem prompt discovery in Fenix

## Testing And Verification Expectations

### CoreMatrix

Focused coverage should lock:

- `WorkspaceAgent` persistence and normalization for `global_instructions`
- `WorkspaceAgentPresenter` and `WorkspaceAgentsController` app-facing payloads
- workspace list payloads that fan out `workspace_agents`
- `ExecutionContract` frozen document ref behavior for mount instructions
- `Workflows::BuildExecutionSnapshot`
- `TurnExecutionSnapshot`
- `ProviderExecution::PrepareAgentRound`
- `AgentControl::CreateAgentRequest` compaction and
  [`AgentControlMailboxItem`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb:144)
  reconstruction for `workspace_agent_context`

Focused tests should explicitly prove:

- identical instruction content reuses one `JsonDocument`
- changing `WorkspaceAgent.global_instructions` after snapshot creation does not
  mutate the frozen payload for that turn
- direct `prepare_round` payloads and queued/reconstructed mailbox payloads stay
  identical

Because this changes an app-facing roundtrip and agent runtime request payloads,
the final verification must include:

- full `core_matrix` verification suite
- `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh`
  from repo root
- explicit inspection of the 2048 capstone export artifacts
- explicit inspection of the resulting database state to confirm the new fields,
  document refs, and payload shapes match the intended business contract

### Fenix

Focused coverage should lock:

- payload normalization for `workspace_agent_context`
- `BuildRoundInstructions` consumption of `global_instructions`
- final prompt assembly order/content
- removal of `workspace_root` / `AGENTS.md` filesystem behavior

And final verification must include the full `agents/fenix` verification suite.
