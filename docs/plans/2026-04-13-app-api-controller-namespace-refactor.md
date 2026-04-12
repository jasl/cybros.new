# App API Route And Controller Namespace Refactor

**Goal:** Reorganize `core_matrix` `app_api` controllers and routes so resource ownership, URL structure, and controller namespaces line up with Rails conventions and the product's scope boundaries.

**Architecture:** Treat each `app_api` scope as a presentation-layer boundary with its own `BaseController`. Refactor routes and controllers together, not independently, so RESTful URLs, controller namespaces, and authorization/loading concerns all match the same resource tree.

**Tech Stack:** Ruby on Rails, Action Pack routing, namespaced controllers, app-surface policies, MethodResponse presenters

---

Related principle:

- [App API Route And Scope Design](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/behavior/app-api-route-and-scope-design.md)

## Why This Refactor Exists

The current `app_api` tree mixes two styles:

- route-first resources such as `AppAPI::Admin::*`
- flat legacy controllers such as `ConversationMessagesController`

That creates three recurring problems:

1. It is harder to find the controller for a given route.
2. Shared loading/auth logic for a scope gets duplicated or leaked into unrelated controllers.
3. The code stops looking like standard Rails resource ownership, which makes future UI work slower.

The target style is:

- route path and controller namespace should correspond
- each namespace gets a narrow `BaseController`
- resource ownership decides route nesting
- different scopes may intentionally expose similar data if the intent differs

Example:

- `/app_api/agents`
- `/app_api/admin/agents`

These are allowed to coexist even if they temporarily share much of the same read model, because one is end-user scope and the other is admin scope.

## Guiding Rules

### 1. Refactor Routes And Controllers Together

Do not only move controller files while keeping legacy paths forever.

When ownership is clear, update:

- the route path
- the controller namespace
- the base controller hierarchy
- the request tests

in the same refactor slice.

### 2. Scope Owns The Base Controller

Every namespace should have a `BaseController` that loads and authorizes only the resources that every controller in that namespace needs.

Examples:

- `AppAPI::Conversations::BaseController`
- `AppAPI::Conversations::Turns::BaseController`
- `AppAPI::Workspaces::BaseController`
- `AppAPI::Agents::BaseController`
- `AppAPI::Admin::LLMProviders::BaseController`

Do not turn a base controller into a generic toolbox. If one subgroup needs extra shared loading, introduce a deeper namespace base controller instead of broadening the parent.

### 3. Ownership Beats Historical Naming

Legacy names such as `conversation_*` are not enough to decide placement.

A controller belongs where the owning resource lives:

- conversation-owned resources live under `Conversations::*`
- turn-owned resources live under `Conversations::Turns::*`
- workspace-owned resources live under `Workspaces::*`
- installation/operator resources live under `Admin::*`

### 4. Redundancy Across Scopes Is Acceptable

API surfaces are allowed to overlap if their intent differs.

Examples:

- end-user `agents` index
- admin `agents` index
- end-user `workspaces/:id/policy`
- future admin workspace diagnostics

Do not force unrelated scopes to share one route just to reduce repetition.

## Approved Scope Tree

### End-User Scope

- `AppAPI::Agents::*`
- `AppAPI::Workspaces::*`
- `AppAPI::Conversations::*`
- `AppAPI::Conversations::Turns::*`

### Admin Scope

- `AppAPI::Admin::*`
- `AppAPI::Admin::LLMProviders::*`

## Target Route And Controller Shape

### Agents

Use the `agents` scope for resources a normal signed-in user can browse starting from an agent.

Recommended shape:

- `GET /app_api/agents`
  - `AppAPI::AgentsController`
- `GET /app_api/agents/:agent_id/home`
  - `AppAPI::Agents::HomesController`
- `GET /app_api/agents/:agent_id/workspaces`
  - `AppAPI::Agents::WorkspacesController`

Shared loading/auth:

- `AppAPI::Agents::BaseController`

### Workspaces

Use the `workspaces` scope for user-owned workspace resources and settings.

Recommended shape:

- `GET /app_api/workspaces/:workspace_id/policy`
  - `AppAPI::Workspaces::PoliciesController`
- `PATCH /app_api/workspaces/:workspace_id/policy`
  - `AppAPI::Workspaces::PoliciesController`
- `POST /app_api/workspaces/:workspace_id/conversation_bundle_import_requests`
  - `AppAPI::Workspaces::ConversationBundleImportRequestsController`
- `GET /app_api/workspaces/:workspace_id/conversation_bundle_import_requests/:id`
  - `AppAPI::Workspaces::ConversationBundleImportRequestsController`

Notes:

- `workspace_policies` should use singular `policy` in the route because it is one settings resource per workspace.
- `conversation_bundle_import_requests` belongs here, not under `conversations`, because the import is initiated against a workspace before a target conversation necessarily exists.

Shared loading/auth:

- `AppAPI::Workspaces::BaseController`

### Conversations

Use the `conversations` scope for direct conversation-owned resources.

Recommended shape:

- `POST /app_api/conversations`
  - `AppAPI::ConversationsController`
- `GET /app_api/conversations/:conversation_id/metadata`
  - `AppAPI::Conversations::MetadataController`
- `PATCH /app_api/conversations/:conversation_id/metadata`
  - `AppAPI::Conversations::MetadataController`
- `POST /app_api/conversations/:conversation_id/metadata/regenerate`
  - `AppAPI::Conversations::MetadataController`
- `POST /app_api/conversations/:conversation_id/messages`
  - `AppAPI::Conversations::MessagesController`
- `GET /app_api/conversations/:conversation_id/transcript`
  - `AppAPI::Conversations::TranscriptController`
- `GET /app_api/conversations/:conversation_id/diagnostics`
  - `AppAPI::Conversations::DiagnosticsController`
- `GET /app_api/conversations/:conversation_id/diagnostics/turns`
  - `AppAPI::Conversations::DiagnosticsController`
- `GET /app_api/conversations/:conversation_id/todo_plan`
  - `AppAPI::Conversations::TodoPlansController`
- `GET /app_api/conversations/:conversation_id/feed`
  - `AppAPI::Conversations::FeedsController`
- `POST /app_api/conversations/:conversation_id/export_requests`
  - `AppAPI::Conversations::ExportRequestsController`
- `GET /app_api/conversations/:conversation_id/export_requests/:id`
  - `AppAPI::Conversations::ExportRequestsController`
- `GET /app_api/conversations/:conversation_id/export_requests/:id/download`
  - `AppAPI::Conversations::ExportRequestsController`
- `POST /app_api/conversations/:conversation_id/debug_export_requests`
  - `AppAPI::Conversations::DebugExportRequestsController`
- `GET /app_api/conversations/:conversation_id/debug_export_requests/:id`
  - `AppAPI::Conversations::DebugExportRequestsController`
- `GET /app_api/conversations/:conversation_id/debug_export_requests/:id/download`
  - `AppAPI::Conversations::DebugExportRequestsController`
- `POST /app_api/conversations/:conversation_id/supervision_sessions`
  - `AppAPI::Conversations::Supervision::SessionsController`
- `GET /app_api/conversations/:conversation_id/supervision_sessions/:id`
  - `AppAPI::Conversations::Supervision::SessionsController`
- `POST /app_api/conversations/:conversation_id/supervision_sessions/:id/close`
  - `AppAPI::Conversations::Supervision::SessionsController`
- `GET /app_api/conversations/:conversation_id/supervision_sessions/:supervision_session_id/messages`
  - `AppAPI::Conversations::Supervision::MessagesController`
- `POST /app_api/conversations/:conversation_id/supervision_sessions/:supervision_session_id/messages`
  - `AppAPI::Conversations::Supervision::MessagesController`

Shared loading/auth:

- `AppAPI::Conversations::BaseController`
- `AppAPI::Conversations::Supervision::BaseController`

### Conversation Turns

Only genuinely turn-owned resources should live under the `turns` subtree.

Recommended shape:

- `GET /app_api/conversations/:conversation_id/turns/:turn_id/runtime_events`
  - `AppAPI::Conversations::Turns::RuntimeEventsController`

Shared loading/auth:

- `AppAPI::Conversations::Turns::BaseController`

That base controller should inherit from `AppAPI::Conversations::BaseController` and add turn lookup/authorization rules shared by all turn subresources.

### Admin

Keep admin resources separate even when they overlap with end-user read models.

Recommended shape:

- `GET /app_api/admin/installation`
  - `AppAPI::Admin::InstallationsController`
- `GET /app_api/admin/agents`
  - `AppAPI::Admin::AgentsController`
- `GET /app_api/admin/execution_runtimes`
  - `AppAPI::Admin::ExecutionRuntimesController`
- `GET /app_api/admin/onboarding_sessions`
  - `AppAPI::Admin::OnboardingSessionsController`
- `POST /app_api/admin/onboarding_sessions`
  - `AppAPI::Admin::OnboardingSessionsController`
- `GET /app_api/admin/audit_entries`
  - `AppAPI::Admin::AuditEntriesController`

Shared loading/auth:

- `AppAPI::Admin::BaseController`

### Admin LLM Providers

This subtree is already converging on the target style and should be treated as the reference pattern for nested admin resources.

Recommended shape:

- `GET /app_api/admin/llm_providers`
  - `AppAPI::Admin::LLMProvidersController`
- `GET /app_api/admin/llm_providers/:provider`
  - `AppAPI::Admin::LLMProvidersController`
- `PATCH /app_api/admin/llm_providers/:provider`
  - `AppAPI::Admin::LLMProvidersController`
- `PATCH /app_api/admin/llm_providers/:provider/credential`
  - `AppAPI::Admin::LLMProviders::CredentialsController`
- `PATCH /app_api/admin/llm_providers/:provider/policy`
  - `AppAPI::Admin::LLMProviders::PoliciesController`
- `PATCH /app_api/admin/llm_providers/:provider/entitlements`
  - `AppAPI::Admin::LLMProviders::EntitlementsController`
- `POST /app_api/admin/llm_providers/:provider/test_connection`
  - `AppAPI::Admin::LLMProviders::ConnectionTestsController`
- `GET /app_api/admin/llm_providers/codex_subscription/authorization`
  - `AppAPI::Admin::LLMProviders::CodexSubscription::AuthorizationsController`
- `POST /app_api/admin/llm_providers/codex_subscription/authorization`
  - `AppAPI::Admin::LLMProviders::CodexSubscription::AuthorizationsController`
- `DELETE /app_api/admin/llm_providers/codex_subscription/authorization`
  - `AppAPI::Admin::LLMProviders::CodexSubscription::AuthorizationsController`
- `GET /app_api/admin/llm_providers/codex_subscription/authorization/callback`
  - `AppAPI::Admin::LLMProviders::CodexSubscription::AuthorizationsController`

Shared loading/auth:

- `AppAPI::Admin::LLMProviders::BaseController`

## Current Flat Controllers And Their Intended Destinations

### Move Into `AppAPI::Conversations::*`

- `ConversationMessagesController`
  - `AppAPI::Conversations::MessagesController`
- `ConversationTranscriptsController`
  - `AppAPI::Conversations::TranscriptController`
- `ConversationDiagnosticsController`
  - `AppAPI::Conversations::DiagnosticsController`
- `ConversationTurnTodoPlansController`
  - `AppAPI::Conversations::TodoPlansController`
- `ConversationTurnFeedsController`
  - `AppAPI::Conversations::FeedsController`
- `ConversationExportRequestsController`
  - `AppAPI::Conversations::ExportRequestsController`
- `ConversationDebugExportRequestsController`
  - `AppAPI::Conversations::DebugExportRequestsController`
- `ConversationSupervisionSessionsController`
  - `AppAPI::Conversations::Supervision::SessionsController`
- `ConversationSupervisionMessagesController`
  - `AppAPI::Conversations::Supervision::MessagesController`

### Move Into `AppAPI::Conversations::Turns::*`

- `ConversationTurnRuntimeEventsController`
  - `AppAPI::Conversations::Turns::RuntimeEventsController`

### Move Into `AppAPI::Workspaces::*`

- `ConversationBundleImportRequestsController`
  - `AppAPI::Workspaces::ConversationBundleImportRequestsController`

### Already In A Good Direction

- `AppAPI::Conversations::MetadataController`
- `AppAPI::Admin::*`
- `AppAPI::Admin::LLMProviders::*`

## Migration Strategy

### Use Route/Controller Co-Refactors

For each slice:

1. add or adjust the target nested route
2. move or rename the controller into the matching namespace
3. introduce or narrow the relevant `BaseController`
4. update request tests to hit the new route
5. remove the old route/controller, because this refactor is destructive

Do not keep old flat routes around as compatibility aliases.

### Preserve App-Surface Contract Shape Unless Ownership Requires Change

This refactor is about scope, naming, and organization. It should not casually redesign payloads or `method_id` behavior.

Allowed changes:

- more RESTful route paths
- different controller classes
- stronger namespace-local loading/auth

Not the goal of this refactor:

- changing domain semantics
- changing authorization policy meaning
- redesigning JSON response schemas without a resource-ownership reason

## Recommended Execution Order

### Batch 1: Conversation Direct Resources

Start with the least controversial conversation-owned resources:

1. `ConversationMessagesController`
2. `ConversationTranscriptsController`
3. `ConversationDiagnosticsController`

These prove the route/controller synchronization pattern and validate `Conversations::BaseController`.

### Batch 2: Conversation Workbench Projections

Move the remaining conversation-owned workbench projections:

1. `ConversationTurnTodoPlansController`
2. `ConversationTurnFeedsController`

These stay under `Conversations::*` because they expose the conversation's
current work state rather than an immutable child of one turn.

### Batch 3: Conversation Turn Resources

Then move the genuinely turn-owned runtime event stream into
`Conversations::Turns::*`:

1. `ConversationTurnRuntimeEventsController`

This is the first place where the deeper namespace base controller matters.

### Batch 4: Conversation Request Resources

Move the export/debug export/supervision resources:

1. `ConversationExportRequestsController`
2. `ConversationDebugExportRequestsController`
3. `ConversationSupervisionSessionsController`
4. `ConversationSupervisionMessagesController`

### Batch 5: Workspace-Owned Import

Move `ConversationBundleImportRequestsController` under `Workspaces::*` and update the route shape accordingly.

### Batch 6: Namespace Completion

After the above slices:

- add missing `BaseController` classes for `Agents`, `Workspaces`, `Conversations::Turns`, and `Admin::LLMProviders`
- remove obsolete flat controller files
- run one final sweep for route/controller name mismatches

## Verification

For each batch:

- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails zeitwerk:check`
- run focused request tests for the moved controllers
- run any affected policy/query/presenter tests

After the full refactor:

- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/brakeman --no-pager`
- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/bundler-audit`
- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rubocop -f github`
- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bun run lint:js`
- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare`
- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test`
- `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails test:system`

Re-run any acceptance scenarios whose entry routes changed.

## Non-Goals

- redesigning the admin/user product surfaces
- adding new business capabilities
- implementing runtime handoff
- introducing compatibility aliases for old route shapes
- rewriting controller internals that already match the new scope unless the route move requires it

## Recommendation

Proceed with a destructive, scope-first refactor:

- routes and controllers should move together
- flat `conversation_*` controllers should be split by real ownership
- deeper nested resources should get deeper namespaces
- route redundancy across scopes is allowed when the intent differs

This will leave the `app_api` tree much closer to normal Rails expectations and make the upcoming SSR UI work easier to reason about.
