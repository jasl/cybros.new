# SSR UI And Guides Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build the Phase 3 SSR workbench, admin console, and guide-driven onboarding experience on top of the completed `app_api` product surface.

**Architecture:** Treat this as a UI-only phase. Phase 1 foundation reset and Phase 2 app surface are already complete. The HTML layer should stay SSR-first, follow the same scope-first route/controller design principles now used by `app_api`, and consume the existing product contract rather than reintroducing semantics in views or controllers.

**Tech Stack:** Ruby on Rails, ERB, Hotwire Turbo, Stimulus, Tailwind CSS 4, daisyUI 5, tailwindcss-motion, ActionCable, Minitest, Rails system tests, VitePress guides

## Current Status

As of 2026-04-13:

- Phase 1 is complete.
- Phase 2 is complete.
- `app_api` and app-facing realtime are in place.
- This plan is the extracted Phase 3 implementation plan.

---

## Task 11: Add Web Sessions, Setup Flows, And Authenticated HTML Shell

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Modify: `core_matrix/app/controllers/application_controller.rb`
- Create: `core_matrix/app/controllers/web/base_controller.rb`
- Create: `core_matrix/app/controllers/web/sessions_controller.rb`
- Create: `core_matrix/app/controllers/setup/installations_controller.rb`
- Create: `core_matrix/app/controllers/admin/base_controller.rb`
- Create: `core_matrix/app/views/layouts/web.html.erb`
- Create: `core_matrix/app/views/web/sessions/new.html.erb`
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
- keep controllers aligned to route scope
- leave product data loading to the already-built `app_api`

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
git add core_matrix/config/routes.rb core_matrix/app/controllers/application_controller.rb core_matrix/app/controllers/web/base_controller.rb core_matrix/app/controllers/web/sessions_controller.rb core_matrix/app/controllers/setup/installations_controller.rb core_matrix/app/controllers/admin/base_controller.rb core_matrix/app/views/layouts/web.html.erb core_matrix/app/views/web/sessions/new.html.erb core_matrix/app/views/setup/installations/new.html.erb core_matrix/test/system/web_bootstrap_and_login_test.rb core_matrix/test/requests/web_sessions_test.rb
git commit -m "feat: add authenticated web shell"
```

## Task 12: Build The Workbench SSR UI

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/web/agents/base_controller.rb`
- Create: `core_matrix/app/controllers/web/agents_controller.rb`
- Create: `core_matrix/app/controllers/web/agents/homes_controller.rb`
- Create: `core_matrix/app/controllers/web/workspaces/base_controller.rb`
- Create: `core_matrix/app/controllers/web/workspaces_controller.rb`
- Create: `core_matrix/app/controllers/web/conversations/base_controller.rb`
- Create: `core_matrix/app/controllers/web/conversations_controller.rb`
- Create: `core_matrix/app/views/web/agents/index.html.erb`
- Create: `core_matrix/app/views/web/agents/homes/show.html.erb`
- Create: `core_matrix/app/views/web/workspaces/show.html.erb`
- Create: `core_matrix/app/views/web/conversations/show.html.erb`
- Create: `core_matrix/app/views/web/conversations/_transcript.html.erb`
- Create: `core_matrix/app/views/web/conversations/_activity_lane.html.erb`
- Create: `core_matrix/app/views/web/conversations/_plan_lane.html.erb`
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
  visit "/agents/#{agent.public_id}"
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

**Step 3: Implement the workbench**

Follow the approved UI shape:

- left rail for agent/workspace/conversation
- center transcript/composer
- right lane for plan/activity/approvals

Use the existing `app_api` routes and app-facing event contract for product
behavior. Keep JS to small Stimulus controllers.

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
git add core_matrix/config/routes.rb core_matrix/app/controllers/web/agents/base_controller.rb core_matrix/app/controllers/web/agents_controller.rb core_matrix/app/controllers/web/agents/homes_controller.rb core_matrix/app/controllers/web/workspaces/base_controller.rb core_matrix/app/controllers/web/workspaces_controller.rb core_matrix/app/controllers/web/conversations/base_controller.rb core_matrix/app/controllers/web/conversations_controller.rb core_matrix/app/views/web/agents/index.html.erb core_matrix/app/views/web/agents/homes/show.html.erb core_matrix/app/views/web/workspaces/show.html.erb core_matrix/app/views/web/conversations/show.html.erb core_matrix/app/views/web/conversations/_transcript.html.erb core_matrix/app/views/web/conversations/_activity_lane.html.erb core_matrix/app/views/web/conversations/_plan_lane.html.erb core_matrix/app/javascript/controllers/workbench_composer_controller.js core_matrix/app/javascript/controllers/workbench_subscription_controller.js core_matrix/test/system/workbench_navigation_test.rb core_matrix/test/system/workbench_conversation_flow_test.rb
git commit -m "feat: add workbench ssr ui"
```

## Task 13: Build The Admin Console SSR UI

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/admin/dashboard_controller.rb`
- Create: `core_matrix/app/controllers/admin/agents_controller.rb`
- Create: `core_matrix/app/controllers/admin/execution_runtimes_controller.rb`
- Create: `core_matrix/app/controllers/admin/providers_controller.rb`
- Create: `core_matrix/app/controllers/admin/onboarding_sessions_controller.rb`
- Create: `core_matrix/app/views/admin/dashboard/show.html.erb`
- Create: `core_matrix/app/views/admin/agents/index.html.erb`
- Create: `core_matrix/app/views/admin/execution_runtimes/index.html.erb`
- Create: `core_matrix/app/views/admin/providers/index.html.erb`
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

Use `app_api/admin/*` plus the shared event contract rather than reaching into
machine endpoints.

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
git add core_matrix/config/routes.rb core_matrix/app/controllers/admin/dashboard_controller.rb core_matrix/app/controllers/admin/agents_controller.rb core_matrix/app/controllers/admin/execution_runtimes_controller.rb core_matrix/app/controllers/admin/providers_controller.rb core_matrix/app/controllers/admin/onboarding_sessions_controller.rb core_matrix/app/views/admin/dashboard/show.html.erb core_matrix/app/views/admin/agents/index.html.erb core_matrix/app/views/admin/execution_runtimes/index.html.erb core_matrix/app/views/admin/providers/index.html.erb core_matrix/app/views/admin/onboarding_sessions/show.html.erb core_matrix/app/views/admin/onboarding_sessions/_command_block.html.erb core_matrix/app/javascript/controllers/onboarding_status_controller.js core_matrix/test/system/admin_runtime_onboarding_test.rb core_matrix/test/system/admin_agent_onboarding_test.rb
git commit -m "feat: add admin onboarding console"
```

## Task 14: Publish Guides And Run Manual Acceptance

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

Expected: FAIL because the guides and guide-linked UI are not yet aligned.

**Step 3: Publish the guides and execute full verification**

Document the exact operator flows. Then run the full `core_matrix`
verification suite:

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

