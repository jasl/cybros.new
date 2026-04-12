# App API Route And Scope Design

## Purpose

This note defines the route and controller organization rules for the human
session `app_api` surface.

The goal is to keep URL structure, controller namespaces, and resource
ownership aligned so the presentation layer remains easy to navigate and safe
to extend.

## Core Rule

For `app_api`, route scope and controller scope should correspond.

When resource ownership is clear, refactors should move:

- the route path
- the controller namespace
- the namespace-local `BaseController`
- the request and acceptance coverage

together.

The codebase should not keep flat legacy paths or controller names around as
compatibility aliases once the new scope is ready.

## Namespace Boundaries

Each route subtree should have a narrow `BaseController` that loads and
authorizes only the resources shared by every controller in that subtree.

Examples:

- `AppAPI::Agents::BaseController`
- `AppAPI::Workspaces::BaseController`
- `AppAPI::Conversations::BaseController`
- `AppAPI::Conversations::Turns::BaseController`
- `AppAPI::Admin::BaseController`
- `AppAPI::Admin::LLMProviders::BaseController`

If a deeper subtree needs extra shared state, add a deeper base controller
instead of widening the parent controller.

## Ownership Rules

Route placement follows resource ownership rather than historical controller
names.

- conversation-owned resources belong under `/app_api/conversations/:id/...`
- turn-owned resources belong under
  `/app_api/conversations/:conversation_id/turns/:turn_id/...`
- workspace-owned resources belong under `/app_api/workspaces/:id/...`
- installation/operator resources belong under `/app_api/admin/...`

This means a legacy name such as `conversation_bundle_import_requests` does not
automatically belong under the `conversations` subtree if the owning resource
is actually a workspace.

Likewise, names such as `conversation_turn_feed` or
`conversation_turn_todo_plan` are not automatically turn-owned. If the
resource represents the conversation's current work projection rather than an
stable child of one turn, it should remain directly under the conversation
scope.

## RESTful Style

Prefer Rails-style nested resources and singular resources where the product
surface exposes one logical child per owner.

Examples:

- `/app_api/conversations/:conversation_id/metadata`
- `/app_api/conversations/:conversation_id/transcript`
- `/app_api/workspaces/:workspace_id/policy`

Avoid free-floating collection endpoints plus required query params when the
resource clearly belongs to one owner.

## Intentional Redundancy

Different scopes may expose similar or even temporarily identical read models
when the intent differs.

Examples:

- `/app_api/agents`
- `/app_api/admin/agents`

This is acceptable because one route is an end-user product surface and the
other is an operator/admin surface. Do not collapse scopes just to avoid
duplication.

## Acceptance And Documentation

When a route subtree moves:

- request tests should move to the new route shape
- acceptance helpers should call the new route shape
- behavior and planning docs should be updated in the same change

This keeps the route tree, controller tree, and operational documentation in
sync.
