# Operator Proof And Specialist Acceptance Design

## Goal

Close the highest-value proof gaps left after the workspace-agent / ingress /
CLI refactor round:

- prove `WorkspaceAgent.settings_payload` model override in acceptance
- prove specialist/subagent export and review artifacts in acceptance
- extend the CLI smoke lane to cover explicit operator auth and Codex provider
  authorization
- make `cmctl status` distinguish selected local context from installation-wide
  defaults

## Problem

The current code paths exist, but the final proof is still incomplete in four
places:

1. the CLI smoke lane proves bootstrap / workspace / mount selection, but not
   explicit operator auth or Codex provider login
2. `cmctl status` still reports `default workspace` and `workspace agent`
   without clearly separating installation defaults from the CLI's selected
   local context
3. `WorkspaceAgent.settings_payload` model-selector overrides are covered by
   focused tests, but not by acceptance
4. the export / debug-export / workflow-mermaid chain already carries
   specialist metadata, but the current acceptance suite never exercises a real
   specialist/subagent path

## Boundary Rules

The `CoreMatrix / Agent / ExecutionRuntime` split remains the governing rule:

- `core_matrix_cli` proves the operator surface only
- `core_matrix` proves settings persistence, selector resolution, workflow
  state, export shape, and artifact integrity
- `agents/fenix` owns prompt routing and specialist behavior
- acceptance may use deterministic backend hooks only where there is still no
  stable user-facing surface

No new profile business logic or prompt semantics should be added to
CoreMatrix for this follow-up.

## Recommendation

### 1. Strengthen the CLI smoke lane

Extend the existing operator smoke scenario so it explicitly exercises:

- `cmctl init`
- `cmctl auth login`
- `cmctl providers codex login`
- `cmctl workspace create`
- `cmctl workspace use`
- `cmctl agent attach`
- `cmctl status`

The acceptance harness may complete the Codex authorization session through a
backend helper once the CLI has created the pending authorization request. This
keeps the proof target on the CLI contract while avoiding a real browser/OAuth
loop.

Telegram / Weixin setup remains out of scope for operator e2e.

### 2. Clarify `cmctl status`

`cmctl status` should report both:

- installation-wide signals:
  - bootstrap state
  - installation name
  - installation default workspace presence
- CLI-selected local context:
  - selected workspace id/name/lifecycle state
  - selected workspace-agent id/lifecycle state

This avoids the current misleading state where `default workspace: missing`
coexists with a valid locally selected workspace.

### 3. Add a mount model-override acceptance

Create one acceptance scenario that:

- bootstraps and seeds the stack
- registers the bundled Fenix runtime
- mounts the bundled agent
- updates the mounted `WorkspaceAgent.settings_payload` through app-api to set
  the CoreMatrix-owned interactive model selector override
- creates a conversation through app-api with no explicit selector
- proves the resolved provider/model came from the mounted override

For determinism, this scenario should target the `role:mock` baseline provider
path rather than a real external provider.

### 4. Add a specialist/subagent proof scenario

Create one acceptance scenario whose purpose is to prove the specialist path,
not to optimize the main agent's natural workflow.

The scenario should:

- configure the mount so only `tester` is enabled as a specialist
- set `tester` as the default specialist
- provide instructions that explicitly require the main agent to delegate the
  verification step to the tester specialist
- then validate:
  - a real `SubagentConnection` exists
  - ordinary export contains `delegation_summary`
  - debug export contains `subagent_connections.json`
  - `review/workflow-mermaid.md` includes the specialist node label

If provider behavior proves too unstable for this path, a deterministic
acceptance-owned control hook is acceptable as a fallback, but the first
attempt should still go through the real app-api/provider loop.

## Evidence

The new proof scenarios should emit:

- CLI evidence files for auth and provider login
- a scenario result proving the mounted model override was actually resolved
- export/debug-export payloads showing the specialist/subagent path
- `review/workflow-mermaid.md` with specialist node labels

## Success Criteria

- the CLI smoke lane proves explicit auth and Codex provider login
- `cmctl status` clearly shows selected local context
- one acceptance scenario proves mounted model-selector override behavior
- one acceptance scenario proves specialist/subagent export and review paths
- the full verification suite and active acceptance suite still pass
