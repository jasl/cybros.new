# SSR-First Workbench And Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the first real Web product for `core_matrix`: a workspace-first cowork workbench for end users plus an admin console for setup and agent/runtime onboarding, while keeping the product API reusable by future custom apps.

**Architecture:** Keep `core_matrix` as the single Web host. Add human web sessions and HTML routes, extend `app_api` into a real user-facing contract, render SSR page shells for workbench/admin areas, and drive long-running activity through shared read models plus realtime subscriptions. Reuse `Workspace`, `UserAgentBinding`, `PairingSession`, and existing conversation/supervision services instead of creating a parallel product model. Follow `references/original/references/fizzy` for Rails SSR/Hotwire implementation style, and follow Codex/ChatGPT for product layout and workbench interaction patterns.

**Tech Stack:** Ruby on Rails, Hotwire Turbo, Stimulus, Tailwind CSS 4, daisyUI 5, tailwindcss-motion, `@rails/request.js`, ActionCable, Minitest, Rails system tests, VitePress guides

---

### Task 1: Add Human Web Sessions, Setup, And Admin Guards

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/controllers/application_controller.rb`
- Create: `core_matrix/app/controllers/web/base_controller.rb`
- Create: `core_matrix/app/controllers/sessions_controller.rb`
- Create: `core_matrix/app/controllers/setup/installations_controller.rb`
- Create: `core_matrix/app/controllers/invitations_controller.rb`
- Create: `core_matrix/app/controllers/admin/base_controller.rb`
- Create: `core_matrix/app/views/sessions/new.html.erb`
- Create: `core_matrix/app/views/setup/installations/new.html.erb`
- Create: `core_matrix/app/views/invitations/show.html.erb`
- Create: `core_matrix/test/system/web_bootstrap_and_login_test.rb`
- Create: `core_matrix/test/requests/web_sessions_test.rb`

**Step 1: Write the failing bootstrap/login system test**

Add a high-level system test that proves:

- the first-admin bootstrap page renders when no installation exists
- submitting bootstrap data calls `Installations::BootstrapFirstAdmin`
- a login page exists for an existing identity
- a logged-in admin reaches an authenticated shell

```ruby
test "bootstrap then login reaches the authenticated web shell" do
  visit "/setup"
  fill_in "Installation name", with: "Cybros"
  fill_in "Email", with: "owner@example.com"
  fill_in "Password", with: "Password123!"
  fill_in "Password confirmation", with: "Password123!"
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

Expected: FAIL because no human session routes/controllers/views exist yet.

**Step 3: Implement the minimal authenticated web shell**

Use the existing `Session` and `Identity` models. Add cookie-backed current-session helpers in `ApplicationController` and route HTML flows through small controllers.

Keep the client side minimal in the `fizzy` style:

- server-render the page shell
- use Turbo navigation
- use small Stimulus controllers only where interaction is needed
- do not introduce a SPA router or client state store

Route sketch:

```ruby
get "/setup", to: "setup/installations#new"
post "/setup", to: "setup/installations#create"
get "/login", to: "sessions#new"
post "/login", to: "sessions#create"
delete "/logout", to: "sessions#destroy"
get "/invitations/:token", to: "invitations#show"
post "/invitations/:token", to: "invitations#create"
```

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
git add core_matrix/config/routes.rb core_matrix/app/controllers/application_controller.rb core_matrix/app/controllers/web/base_controller.rb core_matrix/app/controllers/sessions_controller.rb core_matrix/app/controllers/setup/installations_controller.rb core_matrix/app/controllers/invitations_controller.rb core_matrix/app/controllers/admin/base_controller.rb core_matrix/app/views/sessions/new.html.erb core_matrix/app/views/setup/installations/new.html.erb core_matrix/app/views/invitations/show.html.erb core_matrix/test/system/web_bootstrap_and_login_test.rb core_matrix/test/requests/web_sessions_test.rb
git commit -m "feat: add human web session shell"
```

### Task 2: Turn `app_api` Into A User-Facing Workspace-First Surface

**Files:**
- Modify: `core_matrix/app/controllers/app_api/base_controller.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/agents_controller.rb`
- Create: `core_matrix/app/controllers/app_api/agent_homes_controller.rb`
- Create: `core_matrix/app/controllers/app_api/workspaces_controller.rb`
- Create: `core_matrix/app/services/app_api/agents/list_visible.rb`
- Create: `core_matrix/app/services/app_api/agents/build_home.rb`
- Create: `core_matrix/app/services/app_api/workspaces/list_for_agent.rb`
- Create: `core_matrix/app/services/app_api/workspaces/build_default_ref.rb`
- Create: `core_matrix/test/requests/app_api/agents_test.rb`
- Create: `core_matrix/test/requests/app_api/agent_homes_test.rb`
- Create: `core_matrix/test/requests/app_api/workspaces_test.rb`

**Step 1: Write the failing request tests**

Add request coverage for:

- `GET /app_api/agents`
- `GET /app_api/agents/:agent_id/home`
- `GET /app_api/agents/:agent_id/workspaces`

Assert:

- only user-visible agents appear
- response IDs are `public_id`
- the agent home includes a `default_workspace_ref`
- `default_workspace_ref` can be `virtual` before first use

```ruby
assert_equal "agent_home_show", body.fetch("method_id")
assert_equal "virtual", body.fetch("default_workspace_ref").fetch("state")
refute_includes response.body, %("#{agent.id}")
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/requests/app_api/agents_test.rb test/requests/app_api/agent_homes_test.rb test/requests/app_api/workspaces_test.rb
```

Expected: FAIL because the routes, controllers, and serializers do not exist.

**Step 3: Implement the shared read models**

Keep this layer resource-oriented and user-facing. Reuse `UserAgentBinding`,
`Workspace`, and `ResourceVisibility::Usability`.

Do not make the read models HTML-specific. The SSR pages will consume them
first, but future custom apps must be able to consume the same contract.

Controller sketch:

```ruby
render json: {
  method_id: "agent_home_show",
  agent_id: agent.public_id,
  default_workspace_ref: AppAPI::Workspaces::BuildDefaultRef.call(
    user_agent_binding: binding
  ),
  workspaces: workspaces.map { |workspace| serialize_workspace(workspace) },
}
```

Do not materialize a workspace row in the read path.

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
git add core_matrix/app/controllers/app_api/base_controller.rb core_matrix/config/routes.rb core_matrix/app/controllers/app_api/agents_controller.rb core_matrix/app/controllers/app_api/agent_homes_controller.rb core_matrix/app/controllers/app_api/workspaces_controller.rb core_matrix/app/services/app_api/agents/list_visible.rb core_matrix/app/services/app_api/agents/build_home.rb core_matrix/app/services/app_api/workspaces/list_for_agent.rb core_matrix/app/services/app_api/workspaces/build_default_ref.rb core_matrix/test/requests/app_api/agents_test.rb core_matrix/test/requests/app_api/agent_homes_test.rb core_matrix/test/requests/app_api/workspaces_test.rb
git commit -m "feat: add workspace-first app api surfaces"
```

### Task 3: Add Lazy Default Workspace Materialization And Conversation Creation

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/app_api/agent_conversations_controller.rb`
- Create: `core_matrix/app/services/workspaces/resolve_default_reference.rb`
- Create: `core_matrix/app/services/workbench/create_conversation_from_agent.rb`
- Modify: `core_matrix/app/services/workspaces/create_default.rb`
- Modify: `core_matrix/app/services/conversations/create_root.rb`
- Modify: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/test/services/workbench/create_conversation_from_agent_test.rb`
- Create: `core_matrix/test/requests/app_api/agent_conversations_test.rb`
- Modify: `core_matrix/test/services/workspaces/create_default_test.rb`

**Step 1: Write the failing creation tests**

Add coverage that proves:

- posting to `POST /app_api/agents/:agent_id/conversations` without a
  `workspace_id` uses the agent default workspace
- the default workspace is created only on first substantive use
- the first request can create the workspace, the conversation, and the first
  user turn in one path

```ruby
assert_difference("Workspace.count", +1) do
  post "/app_api/agents/#{agent.public_id}/conversations", params: {
    content: "Help me start"
  }
end

assert_equal "conversation_create", body.fetch("method_id")
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/workbench/create_conversation_from_agent_test.rb test/requests/app_api/agent_conversations_test.rb test/services/workspaces/create_default_test.rb
```

Expected: FAIL because no agent-scoped conversation creation action exists.

**Step 3: Implement the materialization path**

Build one orchestration service that:

1. resolves the caller's `UserAgentBinding`
2. resolves or creates the default workspace only when needed
3. creates the root conversation
4. optionally starts the first user turn

Keep the endpoint as an app-facing action rather than exposing the lower-level
conversation/turn orchestration vocabulary directly.

Service sketch:

```ruby
workspace =
  if workspace_id.present?
    find_workspace!(workspace_id)
  else
    Workspaces::CreateDefault.call(user_agent_binding: binding)
  end

conversation = Conversations::CreateRoot.call(workspace: workspace)
Turns::StartUserTurn.call(conversation: conversation, content: content, ...)
```

**Step 4: Run the tests to verify they pass**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/services/workbench/create_conversation_from_agent_test.rb test/requests/app_api/agent_conversations_test.rb test/services/workspaces/create_default_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/app_api/agent_conversations_controller.rb core_matrix/app/services/workspaces/resolve_default_reference.rb core_matrix/app/services/workbench/create_conversation_from_agent.rb core_matrix/app/services/workspaces/create_default.rb core_matrix/app/services/conversations/create_root.rb core_matrix/app/services/turns/start_user_turn.rb core_matrix/test/services/workbench/create_conversation_from_agent_test.rb core_matrix/test/requests/app_api/agent_conversations_test.rb core_matrix/test/services/workspaces/create_default_test.rb
git commit -m "feat: add lazy default workspace conversation creation"
```

### Task 4: Build The SSR Workbench Shell

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/workbench/base_controller.rb`
- Create: `core_matrix/app/controllers/workbench/agents_controller.rb`
- Create: `core_matrix/app/controllers/workbench/workspaces_controller.rb`
- Create: `core_matrix/app/controllers/workbench/conversations_controller.rb`
- Create: `core_matrix/app/views/layouts/workbench.html.erb`
- Create: `core_matrix/app/views/workbench/agents/show.html.erb`
- Create: `core_matrix/app/views/workbench/workspaces/show.html.erb`
- Create: `core_matrix/app/views/workbench/conversations/show.html.erb`
- Create: `core_matrix/test/system/workbench_navigation_test.rb`

**Step 1: Write the failing workbench system test**

Cover the happy path:

- log in
- open an agent
- land in the default workspace view
- open a conversation
- see the three-column shell

```ruby
assert_selector "[data-role='agent-switcher']"
assert_selector "[data-role='workspace-switcher']"
assert_selector "[data-role='conversation-list']"
assert_selector "[data-role='transcript-pane']"
assert_selector "[data-role='activity-pane']"
```

**Step 2: Run the focused test to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/workbench_navigation_test.rb
```

Expected: FAIL because no workbench HTML routes or views exist.

**Step 3: Implement the SSR shell with server-rendered initial data**

Keep the workbench page server-first:

- preload agent/workspace/conversation state on the server
- render the current transcript snapshot
- render current plan and recent activity in adjacent panes
- style with the existing Tailwind + daisyUI stack
- follow Codex/ChatGPT information density and column hierarchy rather than a
  dashboard/card-heavy layout

View skeleton:

```erb
<main class="grid min-h-screen grid-cols-[18rem_minmax(0,1fr)_22rem]">
  <aside data-role="agent-switcher"></aside>
  <section data-role="transcript-pane"></section>
  <aside data-role="activity-pane"></aside>
</main>
```

Use daisyUI only as a component vocabulary and utility accelerator. Do not let
the workbench collapse into generic boxed-card UI.

**Step 4: Run the test to verify it passes**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/system/workbench_navigation_test.rb
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/config/routes.rb core_matrix/app/controllers/workbench/base_controller.rb core_matrix/app/controllers/workbench/agents_controller.rb core_matrix/app/controllers/workbench/workspaces_controller.rb core_matrix/app/controllers/workbench/conversations_controller.rb core_matrix/app/views/layouts/workbench.html.erb core_matrix/app/views/workbench/agents/show.html.erb core_matrix/app/views/workbench/workspaces/show.html.erb core_matrix/app/views/workbench/conversations/show.html.erb core_matrix/test/system/workbench_navigation_test.rb
git commit -m "feat: add SSR workbench shell"
```

### Task 5: Add Realtime Transcript, Plan, Activity, And Approval Updates

**Files:**
- Create: `core_matrix/app/javascript/controllers/workbench_realtime_controller.js`
- Create: `core_matrix/app/javascript/controllers/composer_controller.js`
- Modify: `core_matrix/app/javascript/controllers/index.js`
- Modify: `core_matrix/app/views/workbench/conversations/show.html.erb`
- Modify: `core_matrix/app/channels/publication_runtime_channel.rb`
- Modify: `core_matrix/app/services/conversation_runtime/broadcast.rb`
- Modify: `core_matrix/app/services/conversation_supervision/publish_update.rb`
- Create: `core_matrix/test/system/workbench_realtime_updates_test.rb`
- Modify: `core_matrix/test/channels/publication_runtime_channel_test.rb`

**Step 1: Write the failing realtime test**

Cover one browser-visible update path:

- open a conversation page
- append a runtime event / plan update / approval update from the server side
- assert the DOM updates without a full page reload

```ruby
assert_text "Working"
perform_enqueued_jobs { publish_runtime_event_for!(conversation) }
assert_text "Started the preview server"
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/workbench_realtime_updates_test.rb test/channels/publication_runtime_channel_test.rb
```

Expected: FAIL because the workbench page does not subscribe/render these updates yet.

**Step 3: Implement one shared browser subscription controller**

Use one Stimulus controller to subscribe to the conversation stream and route
known event types into small DOM updates for:

- transcript append
- activity append
- plan replacement
- approval card add/remove

Keep this controller narrow. Prefer one focused realtime controller plus small
supporting controllers over a large client-side app runtime, following the
`fizzy` Stimulus style.

Controller sketch:

```js
received(data) {
  switch (data.event_type) {
    case "transcript.item.appended":
      this.appendTranscript(data.payload)
      break
    case "turn.runtime_event.appended":
      this.appendActivity(data.payload)
      break
  }
}
```

**Step 4: Run the tests plus JS lint**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/system/workbench_realtime_updates_test.rb test/channels/publication_runtime_channel_test.rb
bun run lint:js
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix/app/javascript/controllers/workbench_realtime_controller.js core_matrix/app/javascript/controllers/composer_controller.js core_matrix/app/javascript/controllers/index.js core_matrix/app/views/workbench/conversations/show.html.erb core_matrix/app/channels/publication_runtime_channel.rb core_matrix/app/services/conversation_runtime/broadcast.rb core_matrix/app/services/conversation_supervision/publish_update.rb core_matrix/test/system/workbench_realtime_updates_test.rb core_matrix/test/channels/publication_runtime_channel_test.rb
git commit -m "feat: add realtime workbench updates"
```

### Task 6: Build The Admin Console And Onboarding Session UI

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/admin/dashboard_controller.rb`
- Create: `core_matrix/app/controllers/admin/setup_controller.rb`
- Create: `core_matrix/app/controllers/admin/agents_controller.rb`
- Create: `core_matrix/app/controllers/admin/execution_runtimes_controller.rb`
- Create: `core_matrix/app/controllers/admin/onboarding_sessions_controller.rb`
- Create: `core_matrix/app/services/admin/build_dashboard.rb`
- Create: `core_matrix/app/services/admin/build_onboarding_session_view.rb`
- Modify: `core_matrix/app/models/pairing_session.rb`
- Modify: `core_matrix/app/services/pairing_sessions/issue.rb`
- Modify: `core_matrix/app/services/pairing_sessions/record_progress.rb`
- Create: `core_matrix/app/views/layouts/admin.html.erb`
- Create: `core_matrix/app/views/admin/dashboard/show.html.erb`
- Create: `core_matrix/app/views/admin/agents/index.html.erb`
- Create: `core_matrix/app/views/admin/execution_runtimes/index.html.erb`
- Create: `core_matrix/app/views/admin/onboarding_sessions/show.html.erb`
- Create: `core_matrix/test/system/admin_runtime_onboarding_test.rb`
- Create: `core_matrix/test/system/admin_agent_onboarding_test.rb`

**Step 1: Write the failing admin onboarding system tests**

Cover:

- admin can issue a runtime onboarding session
- admin can issue an agent onboarding session
- the show page displays commands, current state, and expected next steps

```ruby
click_link "Add runtime"
assert_text "Waiting for registration"
assert_selector "[data-role='onboarding-command']"
assert_link "Open guide"
```

**Step 2: Run the focused tests to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/admin_runtime_onboarding_test.rb test/system/admin_agent_onboarding_test.rb
```

Expected: FAIL because the admin pages do not exist.

**Step 3: Implement admin pages around `PairingSession` as the onboarding object**

Do not invent a second onboarding aggregate. Reuse `PairingSession` and
present it as an onboarding session in the UI.

Render these pages as Rails views with Tailwind/daisyUI styling and small
Stimulus helpers for copy-to-clipboard, live status refresh, and guide links.

Show fields such as:

- `created`
- `waiting_for_registration`
- `registered`
- `capabilities_received`
- `healthy`
- `failed`

View sketch:

```erb
<section data-role="onboarding-status">
  <span>Waiting for registration</span>
  <pre data-role="onboarding-command"><%= @onboarding.command %></pre>
</section>
```

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
git add core_matrix/config/routes.rb core_matrix/app/controllers/admin/dashboard_controller.rb core_matrix/app/controllers/admin/setup_controller.rb core_matrix/app/controllers/admin/agents_controller.rb core_matrix/app/controllers/admin/execution_runtimes_controller.rb core_matrix/app/controllers/admin/onboarding_sessions_controller.rb core_matrix/app/services/admin/build_dashboard.rb core_matrix/app/services/admin/build_onboarding_session_view.rb core_matrix/app/models/pairing_session.rb core_matrix/app/services/pairing_sessions/issue.rb core_matrix/app/services/pairing_sessions/record_progress.rb core_matrix/app/views/layouts/admin.html.erb core_matrix/app/views/admin/dashboard/show.html.erb core_matrix/app/views/admin/agents/index.html.erb core_matrix/app/views/admin/execution_runtimes/index.html.erb core_matrix/app/views/admin/onboarding_sessions/show.html.erb core_matrix/test/system/admin_runtime_onboarding_test.rb core_matrix/test/system/admin_agent_onboarding_test.rb
git commit -m "feat: add admin onboarding console"
```

### Task 7: Publish Guides And Manual Acceptance Flows

**Files:**
- Modify: `guides/.vitepress/config.mjs`
- Modify: `guides/index.md`
- Create: `guides/first-installation.md`
- Create: `guides/runtime-onboarding.md`
- Create: `guides/agent-onboarding.md`
- Create: `guides/manual-acceptance-runtime-onboarding.md`
- Create: `guides/manual-acceptance-agent-onboarding.md`
- Create: `guides/manual-acceptance-default-workspace.md`
- Create: `core_matrix/test/system/admin_guides_linkage_test.rb`

**Step 1: Write the failing guides-linkage test**

Add one system test that proves:

- onboarding pages link to the correct guide pages
- the guide labels match the onboarding step names shown in the UI

```ruby
assert_link "Runtime onboarding guide"
assert_text "Step 1: Create onboarding session"
```

**Step 2: Run the focused test to verify failure**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/system/admin_guides_linkage_test.rb
```

Expected: FAIL because no guide pages or UI linkage exist yet.

**Step 3: Write the guides and wire them into the admin UI**

Update VitePress nav/sidebar and create canonical operator documents that
contain:

- exact commands
- expected state changes
- failure diagnosis checkpoints
- manual acceptance instructions

Make the guide language match the admin UI labels exactly so the same steps can
be followed manually during acceptance without translation.

Guide nav sketch:

```js
nav: [
  { text: "Guides", link: "/" },
  { text: "Runtime Onboarding", link: "/runtime-onboarding" },
  { text: "Agent Onboarding", link: "/agent-onboarding" },
]
```

**Step 4: Run the system test and build the docs**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test test/system/admin_guides_linkage_test.rb
cd /Users/jasl/Workspaces/Ruby/cybros
bunx vitepress build guides
```

Expected: PASS.

**Step 5: Commit**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add guides/.vitepress/config.mjs guides/index.md guides/first-installation.md guides/runtime-onboarding.md guides/agent-onboarding.md guides/manual-acceptance-runtime-onboarding.md guides/manual-acceptance-agent-onboarding.md guides/manual-acceptance-default-workspace.md core_matrix/test/system/admin_guides_linkage_test.rb
git commit -m "docs: add onboarding guides and manual acceptance flows"
```

### Task 8: Run Full Verification And Manual Acceptance

**Files:**
- Modify as needed: any files touched in earlier tasks
- Test: `core_matrix/test/system/*.rb`
- Test: `core_matrix/test/requests/app_api/*.rb`
- Test: `core_matrix/test/services/workbench/*.rb`
- Test: `guides/*.md`

**Step 1: Run the complete focused automated verification set**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails db:test:prepare
bin/rails test \
  test/system/web_bootstrap_and_login_test.rb \
  test/system/workbench_navigation_test.rb \
  test/system/workbench_realtime_updates_test.rb \
  test/system/admin_runtime_onboarding_test.rb \
  test/system/admin_agent_onboarding_test.rb \
  test/system/admin_guides_linkage_test.rb \
  test/requests/web_sessions_test.rb \
  test/requests/app_api/agents_test.rb \
  test/requests/app_api/agent_homes_test.rb \
  test/requests/app_api/workspaces_test.rb \
  test/requests/app_api/agent_conversations_test.rb \
  test/services/workbench/create_conversation_from_agent_test.rb \
  test/services/workspaces/create_default_test.rb
bun run lint:js
cd /Users/jasl/Workspaces/Ruby/cybros
bunx vitepress build guides
```

Expected: PASS.

**Step 2: Run the existing project verification commands**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails test
bin/rails test:system
```

Expected: PASS.

**Step 3: Perform the documented manual acceptance runs**

Follow these guides exactly in the browser and workstation shell:

- `guides/runtime-onboarding.md`
- `guides/agent-onboarding.md`
- `guides/manual-acceptance-default-workspace.md`

Record:

- onboarding state progression
- copy/paste ergonomics of command blocks
- first-use default workspace behavior
- any confusing step names or missing recovery guidance

**Step 4: Fix any failures or UX dead ends, then rerun the affected checks**

Use `superpowers:systematic-debugging` if any automated or manual verification
fails unexpectedly. Keep fixes minimal and rerun only the affected checks first,
then rerun the full verification set.

**Step 5: Commit the final verified batch**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git add core_matrix guides
git commit -m "feat: ship SSR-first workbench and onboarding surfaces"
```
