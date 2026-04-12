# SSR UI And Guides Design

**Date:** 2026-04-13

## Goal

Define the Phase 3 Web product design for `core_matrix` now that the
foundation and app-surface work are complete.

This document covers:

- the SSR workbench UI
- the SSR admin console UI
- guide-driven onboarding UX
- the HTML route/controller design principles that should shape the UI layer

This document assumes the non-UI work described in
`docs/plans/2026-04-12-ssr-first-workbench-and-onboarding-design.md` is
already complete.

## Current Status

As of 2026-04-13:

- Phase 1 foundation reset is complete.
- Phase 2 app surface is complete.
- `app_api` now provides the stable product contract the UI should consume.
- The next remaining phase is SSR UI plus guide publication and manual
  acceptance.

## Scope

This design applies to:

- Rails-rendered HTML routes, controllers, layouts, and templates
- workbench navigation and page composition
- admin console navigation and onboarding flows
- VitePress guide publication and manual acceptance expectations

This design does not redefine:

- machine control protocols
- `app_api` resource semantics
- runtime handoff behavior
- deeper visual exploration that will be discussed separately with the user

## UI-Specific Design Principles

### SSR-First Product Shell

The Web product should stay HTML-first:

- server-render layout, navigation, and initial state
- use Turbo for navigation and partial replacement
- use small Stimulus controllers for focused interactivity
- do not introduce a second frontend framework in this phase

### Scope-First Route And Controller Design

UI routes should follow the same principle now used by `app_api`:

- route shape expresses ownership and scope
- controller namespace matches route scope
- each scope gets its own `BaseController` when it has shared loading,
  authorization, or layout concerns

This is now a project-level design principle. See:

- `core_matrix/docs/behavior/app-api-route-and-scope-design.md`

The same principle should guide HTML routes:

- prefer `Web::Agents::*`, `Web::Workspaces::*`, `Web::Conversations::*`,
  `Admin::*`, and `Setup::*` over flat controller naming
- keep route/controller alignment obvious to Rails developers
- allow intentional route redundancy across scopes when the product intent is
  different

### Product/API Boundary

The SSR UI is a client of `app_api`, not a substitute for it.

- HTML is not the contract
- `app_api` remains the product contract
- realtime continues to use the app-facing workbench stream
- HTML controllers should compose presenters and call app-surface services or
  queries, not recreate product semantics

## Existing Frontend Baseline

The approved frontend stack for this phase is already present in
`core_matrix`:

- Hotwire Turbo
- Stimulus
- `@rails/request.js`
- Tailwind CSS 4
- daisyUI 5
- `tailwindcss-motion`

This phase should reuse that stack directly.

## Product References

### UI Product References

The approved interaction/layout references are:

- Codex
- ChatGPT

These references should inform:

- a narrow, keyboard-friendly left navigation rail
- a dominant center transcript/composer column
- a secondary right context lane for plan, activity, and approvals
- dense productivity-oriented spacing and status language

### Rails SSR Reference

The approved Rails SSR implementation reference is:

- `references/original/references/fizzy`

The relevant lessons are:

- HTML-first flows
- Turbo as enhancement, not hidden SPA runtime
- small focused Stimulus controllers
- server-rendered navigation and structure

## Current App Surface Consumed By The UI

The Phase 3 UI should build on the routes that exist today.

### End-User Workbench Surface

- `GET /app_api/agents`
- `GET /app_api/agents/:agent_id/home`
- `GET /app_api/agents/:agent_id/workspaces`
- `POST /app_api/conversations`
- `POST /app_api/conversations/:conversation_id/messages`
- `GET /app_api/conversations/:conversation_id/metadata`
- `PATCH /app_api/conversations/:conversation_id/metadata`
- `POST /app_api/conversations/:conversation_id/metadata/regenerate`
- `GET /app_api/conversations/:conversation_id/transcript`
- `GET /app_api/conversations/:conversation_id/diagnostics`
- `GET /app_api/conversations/:conversation_id/diagnostics/turns`
- `GET /app_api/conversations/:conversation_id/todo_plan`
- `GET /app_api/conversations/:conversation_id/feed`
- `GET /app_api/conversations/:conversation_id/turns/:turn_id/runtime_events`
- `POST /app_api/conversations/:conversation_id/supervision_sessions`
- `GET /app_api/conversations/:conversation_id/supervision_sessions/:id`
- `POST /app_api/conversations/:conversation_id/supervision_sessions/:id/close`
- `GET /app_api/conversations/:conversation_id/supervision_sessions/:supervision_session_id/messages`
- `POST /app_api/conversations/:conversation_id/supervision_sessions/:supervision_session_id/messages`
- `GET /app_api/workspaces/:workspace_id/policy`
- `PATCH /app_api/workspaces/:workspace_id/policy`
- `POST /app_api/workspaces/:workspace_id/conversation_bundle_import_requests`
- `GET /app_api/workspaces/:workspace_id/conversation_bundle_import_requests/:id`

### Admin Surface

- `GET /app_api/admin/installation`
- `GET /app_api/admin/agents`
- `GET /app_api/admin/execution_runtimes`
- `GET /app_api/admin/onboarding_sessions`
- `POST /app_api/admin/onboarding_sessions`
- `GET /app_api/admin/audit_entries`
- `GET /app_api/admin/llm_providers`
- `GET /app_api/admin/llm_providers/:provider`
- `PATCH /app_api/admin/llm_providers/:provider`
- `PATCH /app_api/admin/llm_providers/:provider/credential`
- `PATCH /app_api/admin/llm_providers/:provider/policy`
- `PATCH /app_api/admin/llm_providers/:provider/entitlements`
- `POST /app_api/admin/llm_providers/:provider/test_connection`
- `GET /app_api/admin/llm_providers/codex_subscription/authorization`
- `POST /app_api/admin/llm_providers/codex_subscription/authorization`
- `DELETE /app_api/admin/llm_providers/codex_subscription/authorization`
- `GET /app_api/admin/llm_providers/codex_subscription/authorization/callback`

The UI should consume these routes as they exist rather than inventing a
parallel product contract.

## Workbench Information Architecture

The approved workbench remains a workspace-first cowork-style product surface.

### Primary Navigation

The user entry sequence is:

- `Agents`
- selected `Agent`
- selected `Workspace`
- selected `Conversation`

The default workspace may be implicit in the UI, but the product model remains
workspace-first.

### Main Desktop Layout

The approved desktop layout is three columns:

1. left column
   - agent switcher
   - workspace switcher
   - conversation list
2. center column
   - transcript
   - composer
   - inline approval cards when needed
3. right column
   - active plan
   - live activity feed
   - pending approvals
   - supervision entry points

### Mobile Layout

Mobile should not force a cramped three-column rendering. Use:

- default `Transcript` view
- `Activity` tab
- `Plan / Approvals` tab

### State Semantics

Keep user-facing state vocabulary product-safe:

- `Working`
- `Waiting for your input`
- `Completed`
- `Needs attention`

Avoid raw machine/internal labels such as:

- `provider round`
- `command_run_wait`
- raw tool names
- internal workflow node keys

### Transcript Rule

`Transcript` is the formal human/agent thread.

`Live activity` is a separate runtime/supporting lane.

Do not collapse raw runtime activity into the transcript. Approval prompts may
appear in both the transcript and the approval/activity lane because they are
blocking user-facing moments.

## Admin Console Information Architecture

The admin console should optimize for deployment ergonomics rather than expose
internal topology.

### Approved Admin Areas

- `/admin`
  - installation overview
  - recent onboarding sessions
  - degraded agents/runtimes
  - recent audit items
- `/admin/setup`
  - first-install bootstrap
  - provider setup
- `/admin/agents`
  - list, inspect, onboard, rotate credential
- `/admin/runtimes`
  - list, inspect, onboard, rotate credential
- `/admin/providers`
  - provider catalog-backed configuration
  - credential status
  - entitlement and policy overlay
  - connection testing
- `/admin/audit`
  - human operator audit review

### Onboarding As Product Object

The approved product object for setup flows is `onboarding_session`.

Browsers should reason about:

- session created
- session waiting
- session registered
- capabilities received
- healthy
- failed

Browsers should not reason directly about internal registration or heartbeat
endpoints.

## Document-Driven Onboarding

Onboarding for `Agent` and `ExecutionRuntime` must be documented in `guides`
and manually validated by following those guides.

Guide and UI must use the same:

- step ordering
- state names
- command snippets
- success criteria
- failure diagnosis vocabulary

### Approved Guide Families

The `guides` site should contain at least:

- `first-installation`
- `runtime-onboarding`
- `agent-onboarding`
- `manual-acceptance-runtime-onboarding`
- `manual-acceptance-agent-onboarding`

### Admin UX Rule

Each onboarding page should:

- link to the canonical guide
- show the current onboarding step
- show exact commands to run on the target machine
- show current status and recent events
- show next-step guidance on success
- show the shortest diagnosis path on failure

## Onboarding Page Layout

The recommended onboarding page layout is two-column:

1. main column
   - current step
   - status badge
   - copyable command blocks
   - next action
2. supporting column
   - guide summary
   - expected observations
   - recent onboarding events
   - common failure hints

## Manual Acceptance Requirements

The UI is only correctly implemented when onboarding can be manually followed
end to end using the published `guides`.

Required manual checks include:

### Runtime Onboarding

- create a runtime onboarding session in the admin UI
- follow the documented commands on a workstation
- observe the expected state progression in the admin UI
- confirm the runtime becomes healthy and inspectable

### Agent Onboarding

- create an agent onboarding session in the admin UI
- follow the documented commands
- observe registration, capability receipt, and healthy state

### Default Workspace Lazy Materialization

- enter an agent that has never been used by the user
- observe that the default workspace appears immediately in the UI
- confirm no real workspace is created before first substantive use
- send the first message
- confirm the workspace and conversation are materialized correctly
- revisit the same agent and confirm the existing default workspace is reused

## Future Frontend Separation Compatibility

The approved SSR-first phase must preserve a later path to full frontend
separation.

That means:

- `app_api` is the real contract
- HTML is not the contract
- server-side presenters and serializers define resource shape
- realtime events use a stable transport-neutral envelope
- page flows should be expressible in terms of app-facing resources and
  actions

Implementation should always ask:

- if this page were replaced by a custom React or native app later, would the
  same `app_api` endpoints and realtime events still make sense?

## Open UI Discussion Topics

These items are intentionally left open for later UI discussion with the user:

- the exact HTML route tree for the SSR workbench shell
- the final visual language and composition details
- how much of the workbench should use Turbo Streams versus request-driven
  refresh
- how much of the admin console should be list/detail versus guided wizard

## Verification

This design should be considered correctly implemented only when:

- the HTML route/controller structure follows scope-first RESTful ownership
- workbench flows remain workspace-first
- the default workspace is lazy-materialized rather than eagerly created
- the UI consumes `app_api` and app-facing realtime instead of machine control
  APIs
- admin onboarding is centered on `onboarding_session`
- `guides` document the onboarding flows and are used for manual acceptance
- the Web UI remains SSR-first without coupling product semantics to HTML

