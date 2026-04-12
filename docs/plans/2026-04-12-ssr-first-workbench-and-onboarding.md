# SSR-First Workbench And Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Rebuild the `core_matrix` product surface in three phases: first a destructive foundation reset, then a stable workspace-first app surface, and only then the SSR workbench/admin UI.

**Architecture:** Treat the current codebase as needing a structural reset before product UI work begins. In Phase 1, split human-facing and machine-facing controller/auth boundaries, replace `PairingSession` with a neutral `OnboardingSession`, remove eager default workspace creation, and add user-authenticated realtime plumbing. Cookie-backed browser sessions must be CSRF-protected, while non-browser app clients may still use bearer-style session tokens. App-facing realtime must remain separate from the existing raw runtime stream used by publication or machine-adjacent consumers. In Phase 2, build the app-facing resource/query/presenter layer and stabilize `app_api` plus realtime contracts. In Phase 3, build the SSR workbench/admin UI on top of those contracts, following `references/original/references/fizzy` for Rails SSR style and Codex/ChatGPT for product layout.

**Tech Stack:** Ruby on Rails, Hotwire Turbo, Stimulus, Tailwind CSS 4, daisyUI 5, tailwindcss-motion, ActionCable, Minitest, Rails system tests, VitePress guides

---

## Phase 1: Foundation Reset

### Task 1: Split Human And Machine API Foundations

**Files:**
- Modify: `core_matrix/app/controllers/application_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/base_controller.rb`
- Modify: `core_matrix/app/controllers/execution_runtime_api/base_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/base_controller.rb`
- Create: `core_matrix/app/controllers/api_error_rendering.rb`
- Create: `core_matrix/app/controllers/session_authentication.rb`
- Create: `core_matrix/app/controllers/installation_scoped_lookup.rb`
- Create: `core_matrix/app/controllers/machine_api_support.rb`
- Create: `core_matrix/test/requests/app_api/authentication_test.rb`
- Modify: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Modify: `core_matrix/test/requests/execution_runtime_api/registrations_test.rb`

**Step 1: Write the failing request tests**

Add request coverage that proves:

- `app_api` no longer accepts machine connection credentials
- `app_api` requires a valid human session
- `agent_api` still authenticates by agent connection credential
- `execution_runtime_api` still authenticates by runtime connection credential

```ruby
test "app api rejects agent credentials and requires a human session" do
  get "/app_api/conversation_transcripts",
    headers: { "Authorization" => %(Token token="#{agent_connection.plaintext_connection_credential}") }

  assert_response :unauthorized
  assert_equal "session is required", response.parsed_body.fetch("error")
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/authentication_test.rb test/requests/agent_api/registrations_test.rb test/requests/execution_runtime_api/registrations_test.rb
```

Expected: FAIL because `AppAPI::BaseController` still inherits `AgentAPI::BaseController`.

**Step 3: Implement separate controller foundations**

Extract shared API rendering and installation lookup helpers into shared
controller support modules. Keep:

- `AgentAPI::BaseController` machine-only
- `ExecutionRuntimeAPI::BaseController` machine-only
- `AppAPI::BaseController` human-session-only via `ApplicationController`
- cookie-backed browser writes guarded by CSRF
- bearer session tokens available for non-browser app clients

Representative shape:

```ruby
module SessionAuthentication
  private

  def require_session!
    @current_session = Session.find_by_plaintext_token(session_cookie)
    @current_user = @current_session&.user if @current_session&.active?
    render json: { error: "session is required" }, status: :unauthorized if @current_user.blank?
  end
end
```

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/requests/app_api/authentication_test.rb test/requests/agent_api/registrations_test.rb test/requests/execution_runtime_api/registrations_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/application_controller.rb core_matrix/app/controllers/agent_api/base_controller.rb core_matrix/app/controllers/execution_runtime_api/base_controller.rb core_matrix/app/controllers/app_api/base_controller.rb core_matrix/app/controllers/api_error_rendering.rb core_matrix/app/controllers/session_authentication.rb core_matrix/app/controllers/installation_scoped_lookup.rb core_matrix/app/controllers/machine_api_support.rb core_matrix/test/requests/app_api/authentication_test.rb core_matrix/test/requests/agent_api/registrations_test.rb core_matrix/test/requests/execution_runtime_api/registrations_test.rb
git commit -m "refactor: split human and machine api foundations"
```

### Task 2: Replace `PairingSession` With Neutral `OnboardingSession`

**Files:**
- Delete: `core_matrix/app/models/pairing_session.rb`
- Delete: `core_matrix/app/services/pairing_sessions/issue.rb`
- Delete: `core_matrix/app/services/pairing_sessions/resolve_from_token.rb`
- Delete: `core_matrix/app/services/pairing_sessions/record_progress.rb`
- Modify: `core_matrix/app/controllers/agent_api/base_controller.rb`
- Modify: `core_matrix/app/controllers/agent_api/registrations_controller.rb`
- Modify: `core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb`
- Modify: `core_matrix/app/services/agent_definition_versions/register.rb`
- Modify: `core_matrix/app/services/execution_runtime_versions/register.rb`
- Create: `core_matrix/app/models/onboarding_session.rb`
- Create: `core_matrix/app/services/onboarding_sessions/issue.rb`
- Create: `core_matrix/app/services/onboarding_sessions/resolve_from_token.rb`
- Create: `core_matrix/app/services/onboarding_sessions/record_progress.rb`
- Create: `core_matrix/db/migrate/20260324090009_create_onboarding_sessions.rb`
- Modify: `core_matrix/db/schema.rb`
- Delete: `core_matrix/test/models/pairing_session_test.rb`
- Delete: `core_matrix/test/services/pairing_sessions/issue_test.rb`
- Create: `core_matrix/test/models/onboarding_session_test.rb`
- Create: `core_matrix/test/services/onboarding_sessions/issue_test.rb`
- Modify: `core_matrix/test/services/agent_definition_versions/register_test.rb`
- Modify: `core_matrix/test/services/execution_runtime_versions/register_test.rb`
- Modify: `core_matrix/test/requests/agent_api/registrations_test.rb`
- Modify: `core_matrix/test/requests/execution_runtime_api/registrations_test.rb`

**Step 1: Write the failing aggregate tests**

Add coverage that proves:

- agent onboarding sessions and runtime onboarding sessions use the same aggregate
- session tokens resolve by `target_kind`
- runtime onboarding no longer mutates `agent.default_execution_runtime` as a side effect

```ruby
test "runtime onboarding session does not require an agent" do
  session = OnboardingSessions::Issue.call(
    installation: installation,
    target_kind: "execution_runtime",
    target: nil,
    issued_by: admin_user
  )

  assert_equal "execution_runtime", session.target_kind
  assert_nil session.target_agent
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/models/onboarding_session_test.rb test/services/onboarding_sessions/issue_test.rb test/services/agent_definition_versions/register_test.rb test/services/execution_runtime_versions/register_test.rb test/requests/agent_api/registrations_test.rb test/requests/execution_runtime_api/registrations_test.rb
```

Expected: FAIL because only `PairingSession` exists.

**Step 3: Implement the destructive replacement**

Create a new aggregate with explicit status and target typing:

```ruby
class OnboardingSession < ApplicationRecord
  enum :target_kind, { agent: "agent", execution_runtime: "execution_runtime" }, validate: true
  enum :status, { issued: "issued", waiting: "waiting", registered: "registered", capabilities_received: "capabilities_received", healthy: "healthy", failed: "failed", revoked: "revoked", closed: "closed" }, validate: true
end
```

Refactor both registration flows to resolve through `OnboardingSessions::ResolveFromToken` and record progress against the onboarding aggregate, not against an agent-specific pairing object.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/models/onboarding_session_test.rb test/services/onboarding_sessions/issue_test.rb test/services/agent_definition_versions/register_test.rb test/services/execution_runtime_versions/register_test.rb test/requests/agent_api/registrations_test.rb test/requests/execution_runtime_api/registrations_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/agent_api/base_controller.rb core_matrix/app/controllers/agent_api/registrations_controller.rb core_matrix/app/controllers/execution_runtime_api/registrations_controller.rb core_matrix/app/services/agent_definition_versions/register.rb core_matrix/app/services/execution_runtime_versions/register.rb core_matrix/app/models/onboarding_session.rb core_matrix/app/services/onboarding_sessions/issue.rb core_matrix/app/services/onboarding_sessions/resolve_from_token.rb core_matrix/app/services/onboarding_sessions/record_progress.rb core_matrix/db/migrate/20260324090009_create_onboarding_sessions.rb core_matrix/db/schema.rb core_matrix/test/models/onboarding_session_test.rb core_matrix/test/services/onboarding_sessions/issue_test.rb core_matrix/test/services/agent_definition_versions/register_test.rb core_matrix/test/services/execution_runtime_versions/register_test.rb core_matrix/test/requests/agent_api/registrations_test.rb core_matrix/test/requests/execution_runtime_api/registrations_test.rb
git rm core_matrix/app/models/pairing_session.rb core_matrix/app/services/pairing_sessions/issue.rb core_matrix/app/services/pairing_sessions/resolve_from_token.rb core_matrix/app/services/pairing_sessions/record_progress.rb core_matrix/test/models/pairing_session_test.rb core_matrix/test/services/pairing_sessions/issue_test.rb
git commit -m "refactor: replace pairing sessions with onboarding sessions"
```

### Task 3: Stop Eager Default Workspace Creation

**Files:**
- Modify: `core_matrix/app/services/user_agent_bindings/enable.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb`
- Modify: `core_matrix/app/services/installations/bootstrap_first_admin.rb`
- Modify: `core_matrix/app/services/workspaces/create_default.rb`
- Create: `core_matrix/app/services/workspaces/materialize_default.rb`
- Create: `core_matrix/app/services/workspaces/build_default_reference.rb`
- Modify: `core_matrix/test/services/user_agent_bindings/enable_test.rb`
- Modify: `core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb`
- Modify: `core_matrix/test/services/workspaces/create_default_test.rb`
- Create: `core_matrix/test/services/workspaces/materialize_default_test.rb`
- Modify: `core_matrix/test/integration/user_binding_workspace_flow_test.rb`

**Step 1: Write the failing domain tests**

Add coverage that proves:

- enabling a user-agent binding does not create a workspace
- bundled bootstrap creates a binding but leaves the default workspace virtual
- explicit materialization is idempotent

```ruby
test "enable creates only the binding" do
  assert_difference("UserAgentBinding.count", +1) do
    assert_no_difference("Workspace.count") do
      UserAgentBindings::Enable.call(user: user, agent: agent)
    end
  end
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/user_agent_bindings/enable_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/services/workspaces/create_default_test.rb test/services/workspaces/materialize_default_test.rb test/integration/user_binding_workspace_flow_test.rb
```

Expected: FAIL because `UserAgentBindings::Enable` still calls `Workspaces::CreateDefault`.

**Step 3: Implement lazy materialization**

Change the binding flow so it only creates the binding. Move workspace creation into a dedicated idempotent service:

```ruby
module Workspaces
  class MaterializeDefault
    def call
      user_agent_binding.default_workspace || Workspaces::CreateDefault.call(user_agent_binding: user_agent_binding)
    end
  end
end
```

Also add a lightweight default reference builder that returns a virtual ref until materialization.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/user_agent_bindings/enable_test.rb test/services/installations/bootstrap_bundled_agent_binding_test.rb test/services/workspaces/create_default_test.rb test/services/workspaces/materialize_default_test.rb test/integration/user_binding_workspace_flow_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/services/user_agent_bindings/enable.rb core_matrix/app/services/installations/bootstrap_bundled_agent_binding.rb core_matrix/app/services/installations/bootstrap_first_admin.rb core_matrix/app/services/workspaces/create_default.rb core_matrix/app/services/workspaces/materialize_default.rb core_matrix/app/services/workspaces/build_default_reference.rb core_matrix/test/services/user_agent_bindings/enable_test.rb core_matrix/test/services/installations/bootstrap_bundled_agent_binding_test.rb core_matrix/test/services/workspaces/create_default_test.rb core_matrix/test/services/workspaces/materialize_default_test.rb core_matrix/test/integration/user_binding_workspace_flow_test.rb
git commit -m "refactor: make default workspaces lazy"
```

### Task 4: Add User-Authenticated Realtime Foundations

**Files:**
- Modify: `core_matrix/app/channels/application_cable/connection.rb`
- Modify: `core_matrix/app/services/conversation_runtime/broadcast.rb`
- Modify: `core_matrix/app/services/conversation_runtime/stream_name.rb`
- Create: `core_matrix/app/channels/workbench_channel.rb`
- Create: `core_matrix/app/services/conversation_runtime/authorize_subscription.rb`
- Create: `core_matrix/app/services/conversation_runtime/build_app_event.rb`
- Modify: `core_matrix/test/channels/application_cable/connection_test.rb`
- Create: `core_matrix/test/channels/workbench_channel_test.rb`
- Modify: `core_matrix/test/services/conversation_runtime/publish_event_test.rb`

**Step 1: Write the failing channel and event tests**

Add coverage that proves:

- ActionCable accepts a logged-in human session
- a user can subscribe only to accessible conversation/workspace streams
- broadcast payloads use a stable app event envelope rather than raw internal event names

```ruby
test "signed-in user can subscribe to a visible conversation stream" do
  connect params: { session_token: session.plaintext_token }
  subscribe conversation_id: conversation.public_id

  assert subscription.confirmed?
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/channels/application_cable/connection_test.rb test/channels/workbench_channel_test.rb test/services/conversation_runtime/publish_event_test.rb
```

Expected: FAIL because `ApplicationCable::Connection` only identifies machine tokens and publications.

**Step 3: Implement the human realtime layer**

Teach the cable connection to identify `current_session` and `current_user`, then authorize user subscriptions in a dedicated channel:

```ruby
class WorkbenchChannel < ApplicationCable::Channel
  def subscribed
    conversation = authorize_subscription!(params.fetch("conversation_id"))
    stream_from ConversationRuntime::StreamName.for_app_conversation(conversation)
  end
end
```

Preserve the existing raw runtime stream for publication/internal consumers and
add a separate app-facing conversation stream normalized through
`ConversationRuntime::BuildAppEvent` so later app clients and SSR partial
updaters both receive the same semantic event envelope.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/channels/application_cable/connection_test.rb test/channels/workbench_channel_test.rb test/services/conversation_runtime/publish_event_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/channels/application_cable/connection.rb core_matrix/app/channels/workbench_channel.rb core_matrix/app/services/conversation_runtime/broadcast.rb core_matrix/app/services/conversation_runtime/stream_name.rb core_matrix/app/services/conversation_runtime/authorize_subscription.rb core_matrix/app/services/conversation_runtime/build_app_event.rb core_matrix/test/channels/application_cable/connection_test.rb core_matrix/test/channels/workbench_channel_test.rb core_matrix/test/services/conversation_runtime/publish_event_test.rb
git commit -m "feat: add user-authenticated realtime foundations"
```

## Phase 2: App Surface And `app_api`

### Task 5: Establish App-Surface Authorization, Method Responses, And Presenters

**Files:**
- Modify: `core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `core_matrix/app/channels/workbench_channel.rb`
- Create: `core_matrix/app/services/app_surface/method_response.rb`
- Create: `core_matrix/app/services/app_surface/policies/workspace_access.rb`
- Create: `core_matrix/app/services/app_surface/policies/conversation_access.rb`
- Create: `core_matrix/app/services/app_surface/policies/admin_access.rb`
- Create: `core_matrix/app/services/app_surface/policies/onboarding_session_access.rb`
- Create: `core_matrix/app/services/app_surface/presenters/workspace_presenter.rb`
- Create: `core_matrix/app/services/app_surface/presenters/conversation_presenter.rb`
- Create: `core_matrix/app/services/app_surface/presenters/onboarding_session_presenter.rb`
- Create: `core_matrix/app/services/app_surface/queries/visible_agents.rb`
- Create: `core_matrix/test/services/app_surface/policies/workspace_access_test.rb`
- Create: `core_matrix/test/services/app_surface/policies/conversation_access_test.rb`
- Create: `core_matrix/test/services/app_surface/policies/admin_access_test.rb`
- Create: `core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb`
- Create: `core_matrix/test/services/app_surface/queries/visible_agents_test.rb`

**Step 1: Write the failing service tests**

Add coverage that proves:

- app-surface policies are the only end-user/operator authorization source for controllers and app-facing channels
- app-surface policies authorize by `current_user`, not by resource owner lookup shortcuts
- downstream services may still accept `actor` for audit/provenance, but do not duplicate app-surface access checks
- presenters emit `public_id` only
- method responses wrap payloads consistently

```ruby
test "workspace presenter emits only public ids" do
  payload = AppSurface::Presenters::WorkspacePresenter.call(workspace: workspace)

  assert_equal workspace.public_id, payload.fetch("workspace_id")
  refute_includes payload.to_json, %("#{workspace.id}")
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/app_surface/policies/workspace_access_test.rb test/services/app_surface/policies/conversation_access_test.rb test/services/app_surface/policies/admin_access_test.rb test/services/app_surface/presenters/workspace_presenter_test.rb test/services/app_surface/queries/visible_agents_test.rb
```

Expected: FAIL because the app-surface layer does not exist.

**Step 3: Implement the shared app-surface layer**

Build a small, explicit layer that every later `app_api` controller must use:

```ruby
module AppSurface
  class MethodResponse
    def self.call(method_id:, **payload)
      payload.deep_stringify_keys.merge("method_id" => method_id)
    end
  end
end
```

Do not let controllers hand-roll JSON after this task.

Keep the responsibility split explicit:

- controllers and app-facing channels authenticate, load resources, and delegate to app-surface policies
- app-surface policies are the single source of truth for end-user/operator authorization
- application/domain services keep workflow invariants, idempotency, staleness checks, and audit attribution, but not duplicate product authorization

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/app_surface/policies/workspace_access_test.rb test/services/app_surface/policies/conversation_access_test.rb test/services/app_surface/policies/admin_access_test.rb test/services/app_surface/presenters/workspace_presenter_test.rb test/services/app_surface/queries/visible_agents_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/app_api/base_controller.rb core_matrix/app/channels/workbench_channel.rb core_matrix/app/services/app_surface/method_response.rb core_matrix/app/services/app_surface/policies/workspace_access.rb core_matrix/app/services/app_surface/policies/conversation_access.rb core_matrix/app/services/app_surface/policies/admin_access.rb core_matrix/app/services/app_surface/policies/onboarding_session_access.rb core_matrix/app/services/app_surface/presenters/workspace_presenter.rb core_matrix/app/services/app_surface/presenters/conversation_presenter.rb core_matrix/app/services/app_surface/presenters/onboarding_session_presenter.rb core_matrix/app/services/app_surface/queries/visible_agents.rb core_matrix/test/services/app_surface/policies/workspace_access_test.rb core_matrix/test/services/app_surface/policies/conversation_access_test.rb core_matrix/test/services/app_surface/policies/admin_access_test.rb core_matrix/test/services/app_surface/presenters/workspace_presenter_test.rb core_matrix/test/services/app_surface/queries/visible_agents_test.rb
git commit -m "refactor: add app surface authorization and presenter layer"
```

### Task 6: Build Workspace-First Agent And Workspace Read APIs

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/agents_controller.rb`
- Create: `core_matrix/app/controllers/app_api/agent_homes_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspaces_controller.rb`
- Create: `core_matrix/app/services/app_surface/queries/agent_home.rb`
- Create: `core_matrix/app/services/app_surface/queries/workspaces_for_agent.rb`
- Create: `core_matrix/test/requests/app_api/agents_test.rb`
- Create: `core_matrix/test/requests/app_api/agent_homes_test.rb`
- Create: `core_matrix/test/requests/app_api/workspaces_test.rb`

**Step 1: Write the failing request tests**

Add request coverage for:

- `GET /app_api/agents`
- `GET /app_api/agents/:agent_id/home`
- `GET /app_api/agents/:agent_id/workspaces`

Assert:

- only visible agents appear
- `default_workspace_ref` can be `virtual`
- all external identifiers are `public_id`

```ruby
assert_equal "agent_home_show", response.parsed_body.fetch("method_id")
assert_equal "virtual", response.parsed_body.fetch("default_workspace_ref").fetch("state")
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/agents_test.rb test/requests/app_api/agent_homes_test.rb test/requests/app_api/workspaces_test.rb
```

Expected: FAIL because these routes/controllers do not exist.

**Step 3: Implement the workspace-first read surfaces**

Represent an agent home with an explicit default workspace ref:

```ruby
render json: AppSurface::MethodResponse.call(
  method_id: "agent_home_show",
  agent: agent_payload,
  default_workspace_ref: Workspaces::BuildDefaultReference.call(user_agent_binding: binding),
  workspaces: workspaces_payload
)
```

Do not materialize a workspace in the read path.

Every controller in this task should authorize through the app-surface policy layer from Task 5 rather than calling visibility helpers directly.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/requests/app_api/agents_test.rb test/requests/app_api/agent_homes_test.rb test/requests/app_api/workspaces_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/app_api/agents_controller.rb core_matrix/app/controllers/app_api/agent_homes_controller.rb core_matrix/app/controllers/app_api/workspaces_controller.rb core_matrix/app/services/app_surface/queries/agent_home.rb core_matrix/app/services/app_surface/queries/workspaces_for_agent.rb core_matrix/test/requests/app_api/agents_test.rb core_matrix/test/requests/app_api/agent_homes_test.rb core_matrix/test/requests/app_api/workspaces_test.rb
git commit -m "feat: add workspace-first agent read apis"
```

### Task 7: Build Conversation Actions And Workbench Read Models

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_transcripts_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_turn_todo_plans_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_turn_runtime_events_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_supervision_sessions_controller.rb`
- Modify: `core_matrix/app/controllers/app_api/conversation_supervision_messages_controller.rb`
- Create: `core_matrix/app/controllers/app_api/agent_conversations_controller.rb`
- Create: `core_matrix/app/controllers/app_api/conversation_messages_controller.rb`
- Create: `core_matrix/app/services/workbench/create_conversation_from_agent.rb`
- Create: `core_matrix/app/services/workbench/send_message.rb`
- Modify: `core_matrix/app/services/conversations/create_root.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/test/requests/app_api/agent_conversations_test.rb`
- Create: `core_matrix/test/requests/app_api/conversation_messages_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_transcripts_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_turn_runtime_events_controller_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_supervision_sessions_test.rb`
- Modify: `core_matrix/test/requests/app_api/conversation_supervision_messages_test.rb`
- Create: `core_matrix/test/services/workbench/create_conversation_from_agent_test.rb`
- Create: `core_matrix/test/services/workbench/send_message_test.rb`

**Step 1: Write the failing workbench action tests**

Add coverage that proves:

- `POST /app_api/agents/:agent_id/conversations` materializes the default workspace on first use
- `POST /app_api/conversations/:conversation_id/messages` appends user input through a product action
- transcript/plan/activity/supervision endpoints are authenticated via human session and presented via the new app-surface layer

```ruby
assert_difference("Workspace.count", +1) do
  post "/app_api/agents/#{agent.public_id}/conversations",
    params: { content: "Help me start" },
    headers: auth_headers(session)
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/agent_conversations_test.rb test/requests/app_api/conversation_messages_test.rb test/requests/app_api/conversation_transcripts_test.rb test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_runtime_events_controller_test.rb test/requests/app_api/conversation_supervision_sessions_test.rb test/requests/app_api/conversation_supervision_messages_test.rb test/services/workbench/create_conversation_from_agent_test.rb test/services/workbench/send_message_test.rb
```

Expected: FAIL because no workspace-first workbench actions exist yet.

**Step 3: Implement the workbench app surface**

Route all write operations through explicit product services:

```ruby
conversation = Workbench::CreateConversationFromAgent.call(
  user: current_user,
  agent: agent,
  workspace_id: params[:workspace_id],
  content: params[:content]
)
```

Use the same app-surface presenters for read endpoints so UI work later consumes already-stable payloads.
Write controllers should work on already-authorized resources and actors; keep product authorization in the app-surface layer, not duplicated inside downstream services.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/requests/app_api/agent_conversations_test.rb test/requests/app_api/conversation_messages_test.rb test/requests/app_api/conversation_transcripts_test.rb test/requests/app_api/conversation_turn_todo_plans_controller_test.rb test/requests/app_api/conversation_turn_runtime_events_controller_test.rb test/requests/app_api/conversation_supervision_sessions_test.rb test/requests/app_api/conversation_supervision_messages_test.rb test/services/workbench/create_conversation_from_agent_test.rb test/services/workbench/send_message_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/app_api/conversation_transcripts_controller.rb core_matrix/app/controllers/app_api/conversation_turn_todo_plans_controller.rb core_matrix/app/controllers/app_api/conversation_turn_runtime_events_controller.rb core_matrix/app/controllers/app_api/conversation_supervision_sessions_controller.rb core_matrix/app/controllers/app_api/conversation_supervision_messages_controller.rb core_matrix/app/controllers/app_api/agent_conversations_controller.rb core_matrix/app/controllers/app_api/conversation_messages_controller.rb core_matrix/app/services/workbench/create_conversation_from_agent.rb core_matrix/app/services/workbench/send_message.rb core_matrix/app/services/conversations/create_root.rb core_matrix/app/services/turns/start_user_turn.rb core_matrix/test/requests/app_api/agent_conversations_test.rb core_matrix/test/requests/app_api/conversation_messages_test.rb core_matrix/test/requests/app_api/conversation_transcripts_test.rb core_matrix/test/requests/app_api/conversation_turn_todo_plans_controller_test.rb core_matrix/test/requests/app_api/conversation_turn_runtime_events_controller_test.rb core_matrix/test/requests/app_api/conversation_supervision_sessions_test.rb core_matrix/test/requests/app_api/conversation_supervision_messages_test.rb core_matrix/test/services/workbench/create_conversation_from_agent_test.rb core_matrix/test/services/workbench/send_message_test.rb
git commit -m "feat: add workbench app api actions and projections"
```

### Task 8: Build Admin `app_api` Surfaces

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/admin/base_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/installations_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/agents_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/execution_runtimes_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/onboarding_sessions_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/workspace_policies_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/provider_accounts_controller.rb`
- Create: `core_matrix/app/controllers/app_api/admin/audit_entries_controller.rb`
- Create: `core_matrix/app/services/app_surface/queries/admin/installation_overview.rb`
- Create: `core_matrix/app/services/app_surface/queries/admin/list_agents.rb`
- Create: `core_matrix/app/services/app_surface/queries/admin/list_execution_runtimes.rb`
- Create: `core_matrix/app/services/app_surface/queries/admin/list_onboarding_sessions.rb`
- Create: `core_matrix/test/requests/app_api/admin/installations_test.rb`
- Create: `core_matrix/test/requests/app_api/admin/agents_test.rb`
- Create: `core_matrix/test/requests/app_api/admin/execution_runtimes_test.rb`
- Create: `core_matrix/test/requests/app_api/admin/onboarding_sessions_test.rb`

**Step 1: Write the failing admin request tests**

Add request coverage that proves:

- admin endpoints require an admin user
- runtime and agent onboarding sessions are surfaced through the same resource family
- admin JSON uses `public_id` and stable method IDs

```ruby
test "non-admin cannot list onboarding sessions" do
  get "/app_api/admin/onboarding_sessions", headers: auth_headers(non_admin_session)

  assert_response :forbidden
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/admin/installations_test.rb test/requests/app_api/admin/agents_test.rb test/requests/app_api/admin/execution_runtimes_test.rb test/requests/app_api/admin/onboarding_sessions_test.rb
```

Expected: FAIL because no admin `app_api` surface exists.

**Step 3: Implement the admin app surface**

Keep the browser-facing admin layer on top of product resources:

```ruby
render json: AppSurface::MethodResponse.call(
  method_id: "admin_onboarding_session_index",
  onboarding_sessions: sessions.map { |session| AppSurface::Presenters::OnboardingSessionPresenter.call(onboarding_session: session) }
)
```

Do not leak raw registration or heartbeat endpoints into admin JSON.
Use the same app-surface policy layer from Task 5 so admin authorization stays consistent between controllers, queries, and app-facing channels.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/requests/app_api/admin/installations_test.rb test/requests/app_api/admin/agents_test.rb test/requests/app_api/admin/execution_runtimes_test.rb test/requests/app_api/admin/onboarding_sessions_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/app_api/admin/base_controller.rb core_matrix/app/controllers/app_api/admin/installations_controller.rb core_matrix/app/controllers/app_api/admin/agents_controller.rb core_matrix/app/controllers/app_api/admin/execution_runtimes_controller.rb core_matrix/app/controllers/app_api/admin/onboarding_sessions_controller.rb core_matrix/app/controllers/app_api/admin/workspace_policies_controller.rb core_matrix/app/controllers/app_api/admin/provider_accounts_controller.rb core_matrix/app/controllers/app_api/admin/audit_entries_controller.rb core_matrix/app/services/app_surface/queries/admin/installation_overview.rb core_matrix/app/services/app_surface/queries/admin/list_agents.rb core_matrix/app/services/app_surface/queries/admin/list_execution_runtimes.rb core_matrix/app/services/app_surface/queries/admin/list_onboarding_sessions.rb core_matrix/test/requests/app_api/admin/installations_test.rb core_matrix/test/requests/app_api/admin/agents_test.rb core_matrix/test/requests/app_api/admin/execution_runtimes_test.rb core_matrix/test/requests/app_api/admin/onboarding_sessions_test.rb
git commit -m "feat: add admin app api surfaces"
```

### Task 9: Finalize App-Facing Event Contracts

**Files:**
- Modify: `core_matrix/app/channels/workbench_channel.rb`
- Modify: `core_matrix/app/services/conversation_runtime/build_app_event.rb`
- Create: `core_matrix/app/services/onboarding_sessions/build_app_event.rb`
- Create: `core_matrix/app/services/onboarding_sessions/broadcast.rb`
- Create: `core_matrix/test/services/onboarding_sessions/broadcast_test.rb`
- Modify: `core_matrix/test/channels/workbench_channel_test.rb`
- Modify: `core_matrix/test/services/conversation_runtime/publish_event_test.rb`

**Step 1: Write the failing event contract tests**

Add coverage that proves:

- conversation event envelopes use product-safe event names
- onboarding session events use the same envelope structure
- no internal node keys or `provider_round_*` names leak to app-facing subscribers

```ruby
assert_equal "turn.runtime_event.appended", payload.fetch("event_type")
refute_match(/provider_round|workflow_node/, payload.to_json)
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/channels/workbench_channel_test.rb test/services/conversation_runtime/publish_event_test.rb test/services/onboarding_sessions/broadcast_test.rb
```

Expected: FAIL because the current event envelope is conversation-runtime specific and not yet unified across onboarding.

**Step 3: Implement the final event envelope**

Standardize every app-facing broadcast on:

```ruby
{
  "event_type" => "onboarding_session.updated",
  "resource_type" => "onboarding_session",
  "resource_id" => onboarding_session.public_id,
  "occurred_at" => occurred_at.iso8601(6),
  "payload" => payload
}
```

This is the contract Phase 3 UI and future custom apps should consume.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/channels/workbench_channel_test.rb test/services/conversation_runtime/publish_event_test.rb test/services/onboarding_sessions/broadcast_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/channels/workbench_channel.rb core_matrix/app/services/conversation_runtime/build_app_event.rb core_matrix/app/services/onboarding_sessions/build_app_event.rb core_matrix/app/services/onboarding_sessions/broadcast.rb core_matrix/test/services/onboarding_sessions/broadcast_test.rb core_matrix/test/channels/workbench_channel_test.rb core_matrix/test/services/conversation_runtime/publish_event_test.rb
git commit -m "feat: finalize app event contracts"
```

### Task 10: Repoint End-User And Operator Acceptance Flows To App Surface

**Files:**
- Modify: `acceptance/lib/manual_support.rb`
- Create: `acceptance/lib/app_surface_support.rb`
- Modify: `acceptance/lib/active_suite.rb`
- Modify: `acceptance/lib/capstone_app_api_roundtrip.rb`
- Modify: `acceptance/lib/conversation_runtime_validation.rb`
- Modify: `acceptance/scenarios/*` for workbench and admin operator flows
- Modify: `core_matrix/test/lib/acceptance/manual_support_test.rb`
- Create: `core_matrix/test/lib/acceptance/app_surface_support_test.rb`

**Step 1: Write the failing acceptance helper tests**

Add coverage that proves:

- end-user and operator acceptance helpers drive `app_api` with human session authentication rather than machine credentials
- app-surface acceptance subscribers consume the app-facing event contract from Task 9
- machine protocol validation helpers remain direct to `agent_api` and `execution_runtime_api`

```ruby
test "app surface helper uses human session auth" do
  helper = Acceptance::AppSurfaceSupport.new(session: user_session)

  response = helper.get_json("/app_api/agents")

  assert_equal "agents_index", response.fetch("method_id")
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/lib/acceptance/manual_support_test.rb test/lib/acceptance/app_surface_support_test.rb
```

Expected: FAIL because the acceptance helpers still assume a transitional, machine-authenticated `app_api` shape.

**Step 3: Repoint acceptance to the product surface**

Split the helper boundary explicitly:

- end-user and operator flows use `app_api` plus app-facing realtime and human session auth
- machine protocol flows keep exercising `agent_api` and `execution_runtime_api`
- database reads, console commands, and log inspection remain allowed as observation and proof tools, not the primary action driver for product flows

Do not leave any end-user/operator acceptance scenario using machine credentials as the primary way to drive an equivalent `app_api` flow after this task.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/lib/acceptance/manual_support_test.rb test/lib/acceptance/app_surface_support_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add acceptance/lib/manual_support.rb acceptance/lib/app_surface_support.rb acceptance/lib/active_suite.rb acceptance/lib/capstone_app_api_roundtrip.rb acceptance/lib/conversation_runtime_validation.rb acceptance/scenarios core_matrix/test/lib/acceptance/manual_support_test.rb core_matrix/test/lib/acceptance/app_surface_support_test.rb
git commit -m "refactor: point product acceptance flows at app surface"
```

## Phase 3: SSR UI And Guides

### Task 11: Add Web Sessions, Setup Flows, And Authenticated HTML Shell

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/controllers/application_controller.rb`
- Create: `core_matrix/app/controllers/web/base_controller.rb`
- Create: `core_matrix/app/controllers/sessions_controller.rb`
- Create: `core_matrix/app/controllers/setup/installations_controller.rb`
- Create: `core_matrix/app/controllers/admin/base_controller.rb`
- Create: `core_matrix/app/views/layouts/web.html.erb`
- Create: `core_matrix/app/views/sessions/new.html.erb`
- Create: `core_matrix/app/views/setup/installations/new.html.erb`
- Create: `core_matrix/test/system/web_bootstrap_and_login_test.rb`
- Create: `core_matrix/test/requests/web_sessions_test.rb`

**Step 1: Write the failing HTML auth tests**

Add coverage that proves:

- first-install bootstrap renders when no installation exists
- login creates a human session cookie
- an authenticated user reaches the web shell

```ruby
test "bootstrap then login reaches the authenticated shell" do
  visit "/setup"
  fill_in "Email", with: "owner@example.com"
  fill_in "Password", with: "Password123!"
  click_button "Create installation"

  assert_text "Signed in as owner@example.com"
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/web_bootstrap_and_login_test.rb test/requests/web_sessions_test.rb
```

Expected: FAIL because the HTML shell does not exist yet.

**Step 3: Implement the minimal SSR shell**

Keep this HTML-first:

- server-render the shell
- use Turbo navigation
- leave app data loading to the already-built `app_api`

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/system/web_bootstrap_and_login_test.rb test/requests/web_sessions_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/application_controller.rb core_matrix/app/controllers/web/base_controller.rb core_matrix/app/controllers/sessions_controller.rb core_matrix/app/controllers/setup/installations_controller.rb core_matrix/app/controllers/admin/base_controller.rb core_matrix/app/views/layouts/web.html.erb core_matrix/app/views/sessions/new.html.erb core_matrix/app/views/setup/installations/new.html.erb core_matrix/test/system/web_bootstrap_and_login_test.rb core_matrix/test/requests/web_sessions_test.rb
git commit -m "feat: add authenticated web shell"
```

### Task 12: Build The Workbench SSR UI

**Files:**
- Create: `core_matrix/app/controllers/workbench/agents_controller.rb`
- Create: `core_matrix/app/controllers/workbench/workspaces_controller.rb`
- Create: `core_matrix/app/controllers/workbench/conversations_controller.rb`
- Create: `core_matrix/app/views/workbench/agents/index.html.erb`
- Create: `core_matrix/app/views/workbench/workspaces/show.html.erb`
- Create: `core_matrix/app/views/workbench/conversations/show.html.erb`
- Create: `core_matrix/app/views/workbench/conversations/_transcript.html.erb`
- Create: `core_matrix/app/views/workbench/conversations/_activity_lane.html.erb`
- Create: `core_matrix/app/views/workbench/conversations/_plan_lane.html.erb`
- Create: `core_matrix/app/javascript/controllers/workbench_composer_controller.js`
- Create: `core_matrix/app/javascript/controllers/workbench_subscription_controller.js`
- Create: `core_matrix/test/system/workbench_navigation_test.rb`
- Create: `core_matrix/test/system/workbench_conversation_flow_test.rb`

**Step 1: Write the failing system tests**

Add coverage that proves:

- the user enters via agent -> workspace -> conversation
- the default workspace appears even before materialization
- sending the first message creates the workspace and shows transcript/activity updates

```ruby
test "first message materializes the default workspace" do
  visit "/workbench/agents/#{agent.public_id}"
  click_button "Start working"
  fill_in "Message", with: "Help me start"
  click_button "Send"

  assert_text "Help me start"
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/workbench_navigation_test.rb test/system/workbench_conversation_flow_test.rb
```

Expected: FAIL because the workbench HTML/controllers do not exist.

**Step 3: Implement the Codex/ChatGPT-style workbench**

Follow the approved UI shape:

- left rail for agent/workspace/conversation
- center transcript/composer
- right lane for plan/activity/approvals

Use `app_api` for data fetches and the app event contract for live updates. Keep JS to small Stimulus controllers.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/system/workbench_navigation_test.rb test/system/workbench_conversation_flow_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/workbench/agents_controller.rb core_matrix/app/controllers/workbench/workspaces_controller.rb core_matrix/app/controllers/workbench/conversations_controller.rb core_matrix/app/views/workbench/agents/index.html.erb core_matrix/app/views/workbench/workspaces/show.html.erb core_matrix/app/views/workbench/conversations/show.html.erb core_matrix/app/views/workbench/conversations/_transcript.html.erb core_matrix/app/views/workbench/conversations/_activity_lane.html.erb core_matrix/app/views/workbench/conversations/_plan_lane.html.erb core_matrix/app/javascript/controllers/workbench_composer_controller.js core_matrix/app/javascript/controllers/workbench_subscription_controller.js core_matrix/test/system/workbench_navigation_test.rb core_matrix/test/system/workbench_conversation_flow_test.rb
git commit -m "feat: add workbench ssr ui"
```

### Task 13: Build The Admin Console SSR UI

**Files:**
- Create: `core_matrix/app/controllers/admin/dashboard_controller.rb`
- Create: `core_matrix/app/controllers/admin/agents_controller.rb`
- Create: `core_matrix/app/controllers/admin/execution_runtimes_controller.rb`
- Create: `core_matrix/app/controllers/admin/onboarding_sessions_controller.rb`
- Create: `core_matrix/app/views/admin/dashboard/show.html.erb`
- Create: `core_matrix/app/views/admin/agents/index.html.erb`
- Create: `core_matrix/app/views/admin/execution_runtimes/index.html.erb`
- Create: `core_matrix/app/views/admin/onboarding_sessions/show.html.erb`
- Create: `core_matrix/app/views/admin/onboarding_sessions/_command_block.html.erb`
- Create: `core_matrix/app/javascript/controllers/onboarding_status_controller.js`
- Create: `core_matrix/test/system/admin_runtime_onboarding_test.rb`
- Create: `core_matrix/test/system/admin_agent_onboarding_test.rb`

**Step 1: Write the failing admin system tests**

Add coverage that proves:

- an admin can create an onboarding session
- the page shows the canonical command block and status progression
- non-admins cannot enter the admin console

```ruby
test "admin sees runtime onboarding status progression" do
  visit "/admin/runtimes/new"
  fill_in "Display name", with: "Workstation Nexus"
  click_button "Create onboarding session"

  assert_text "waiting"
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/admin_runtime_onboarding_test.rb test/system/admin_agent_onboarding_test.rb
```

Expected: FAIL because the admin SSR pages do not exist.

**Step 3: Implement the operator console**

Keep the page layout document-driven:

- current step
- command block
- status badge
- recent events
- guide link

Use `app_api/admin/*` plus the shared event contract rather than reaching into machine endpoints.

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/system/admin_runtime_onboarding_test.rb test/system/admin_agent_onboarding_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/controllers/admin/dashboard_controller.rb core_matrix/app/controllers/admin/agents_controller.rb core_matrix/app/controllers/admin/execution_runtimes_controller.rb core_matrix/app/controllers/admin/onboarding_sessions_controller.rb core_matrix/app/views/admin/dashboard/show.html.erb core_matrix/app/views/admin/agents/index.html.erb core_matrix/app/views/admin/execution_runtimes/index.html.erb core_matrix/app/views/admin/onboarding_sessions/show.html.erb core_matrix/app/views/admin/onboarding_sessions/_command_block.html.erb core_matrix/app/javascript/controllers/onboarding_status_controller.js core_matrix/test/system/admin_runtime_onboarding_test.rb core_matrix/test/system/admin_agent_onboarding_test.rb
git commit -m "feat: add admin onboarding console"
```

### Task 14: Publish Guides And Run Manual Acceptance

**Files:**
- Create: `guides/docs/first-installation.md`
- Create: `guides/docs/runtime-onboarding.md`
- Create: `guides/docs/agent-onboarding.md`
- Create: `guides/docs/manual-acceptance-runtime-onboarding.md`
- Create: `guides/docs/manual-acceptance-agent-onboarding.md`
- Modify: `guides/index.md`
- Create: `core_matrix/test/system/manual_acceptance_runtime_onboarding_test.rb`
- Create: `core_matrix/test/system/manual_acceptance_agent_onboarding_test.rb`

**Step 1: Write the failing acceptance tests and document outlines**

Add test and doc stubs that prove:

- the documented onboarding flow matches the UI step names
- runtime onboarding and agent onboarding can be followed manually from the guides
- the lazy default workspace behavior is explicitly documented for acceptance

```ruby
test "runtime onboarding guide matches the admin status vocabulary" do
  visit "/admin/runtimes/new"

  assert_text "waiting"
  assert_text "registered"
  assert_text "healthy"
end
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/manual_acceptance_runtime_onboarding_test.rb test/system/manual_acceptance_agent_onboarding_test.rb
```

Expected: FAIL because the acceptance guides and guide-linked UI are not yet aligned.

**Step 3: Publish the guides and execute full verification**

Document the exact operator flows. Then run the full `core_matrix` verification suite:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

Then manually follow:

- `guides/docs/runtime-onboarding.md`
- `guides/docs/agent-onboarding.md`
- `guides/docs/manual-acceptance-runtime-onboarding.md`
- `guides/docs/manual-acceptance-agent-onboarding.md`

**Step 4: Confirm everything passes**

Expected:

- guides match UI language and sequence
- full verification PASS
- manual onboarding PASS
- default workspace lazy-materialization PASS

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add guides/docs/first-installation.md guides/docs/runtime-onboarding.md guides/docs/agent-onboarding.md guides/docs/manual-acceptance-runtime-onboarding.md guides/docs/manual-acceptance-agent-onboarding.md guides/index.md core_matrix/test/system/manual_acceptance_runtime_onboarding_test.rb core_matrix/test/system/manual_acceptance_agent_onboarding_test.rb
git commit -m "docs: publish onboarding guides and acceptance flows"
```
