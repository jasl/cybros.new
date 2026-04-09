# Core Matrix Kernel Manual Validation Checklist

## Status

Historical checklist preserved for the March 2026 backend acceptance run.
Use
`/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
for the current provider-backed product acceptance path.

Older route names, model names, and command paths remain below on purpose as
historical evidence. They do not describe the current April 2026 product
surface.

The command paths and committed artifact locations recorded below are kept as
historical evidence of that March run. Current acceptance automation now lives
under `/Users/jasl/Workspaces/Ruby/cybros/acceptance/`, and generated runtime
artifacts are no longer committed under `docs/`.

Current backend baseline was rerun on `2026-03-25`.

- `bin/dev`-backed live-server validation rechecked registration, heartbeat,
  health, transcript pagination, canonical variable endpoints, and machine-side
  human-interaction requests.
- Rails runner validation rechecked installation bootstrap, invitations, admin
  role changes, user bindings, bundled runtime reconciliation, credential
  rotation, revocation, and retirement, selector resolution, manual recovery,
  conversation structure and rewrite flows, human interaction resolution, and
  publication access logging.
- Reusable reset now rebuilds the development database through
  `DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:reset` before reapplying
  the acceptance seed baseline.
- `script/manual/dummy_agent_runtime.rb register` now sends a stable
  `environment_fingerprint`; this checklist exports it through
  `CORE_MATRIX_ENVIRONMENT_FINGERPRINT`.
- Publication validation remains service-level in phase 1 because there are no
  public publication HTTP routes yet.

Current-batch rule:

- keep this checklist backend-reproducible through shell commands, HTTP
  requests, Rails runner actions, and `script/manual/dummy_agent_runtime.rb`
- do not add browser-only or human-facing UI validation steps in the current
  backend greenfield batch
- treat this checklist as the real-environment baseline that accompanies, but
  does not replace, Milestone C `Protocol E2E` coverage
- when focused Phase 2 provider validation needs a real provider credential,
  run `bin/rails db:seed` so `.env`-backed provider credentials such as
  `OPENROUTER_API_KEY` are materialized before manual checks
- run the Phase 2 Ruby operator scripts with `bundle exec ruby`; plain `ruby`
  can hit gem activation conflicts in this repo, and the scripts are expected
  to emit pure JSON on stdout

## Phase 2 Full Agent Loop Acceptance Matrix (`2026-03-30`)

This matrix is the required execution order for the final Phase 2 manual run.

Rules:

- do not skip ahead; run the scenarios in order unless a prior scenario
  produces a blocker that must be discussed first
- every scenario must record concrete `public_id` values instead of internal
  numeric ids
- every scenario must record both the expected DAG shape and the observed DAG
  shape
- every scenario must record both the expected conversation outcome and the
  observed conversation outcome
- if a scenario generates proof artifacts, record the output directory under
  `docs/reports/phase-2/`

Record these fields for each scenario:

- scenario date and operator
- conversation `public_id`
- turn `public_id`
- workflow-run `public_id`
- deployment identifier and runtime mode
- provider and model, when applicable
- expected DAG shape
- observed DAG shape
- expected conversation state
- observed conversation state
- proof artifact path, when applicable
- pass, fail, or blocked outcome

Required final scenario order:

1. bundled `Fenix` fast terminal path
2. real provider-backed bundled `Fenix` turn
3. during-generation steering: `reject`, `restart`, and `queue`
4. human-interaction wait and resume
5. subagent spawn plus bounded `wait_all` barrier
6. `process_run` or turn-command-backed runtime path
7. governed tool invocation in a real loop
8. governed Streamable HTTP MCP invocation in a real loop
9. same-installation deployment rotation upgrade
10. same-installation deployment rotation downgrade
11. independent external `Fenix` validation
12. built-in system skill deploy flow
13. third-party skill install and next-top-level-turn activation
14. workflow proof export package generation

## Phase 2 Scenario Operator Script

Each section below is the authoritative operator flow for the final Phase 2
acceptance run.

### Phase 2 Scenario 01: Bundled Fenix Fast Terminal Path

- goal:
  verify the default bundled runtime can complete one fast terminal turn under
  the current Phase 2 kernel
- prerequisites:
  - `bin/dev` running in `core_matrix`
  - `AGENT_FENIX_PORT=3101 bin/dev` running in `agents/fenix`
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/bundled_fast_terminal_validation.rb \
  > /tmp/phase2_bundled_fast_terminal_validation.json

jq '.' /tmp/phase2_bundled_fast_terminal_validation.json
```

- expected outputs:
  - `delivery_mode: "realtime"`
  - `expected_dag_shape: ["agent_turn_step"]`
  - `observed_dag_shape: ["agent_turn_step"]`
  - `runtime_execution_status: "completed"`
  - `runtime_output: "The calculator returned 12."`
  - `observed_conversation_state.conversation_state: "active"`
  - `observed_conversation_state.workflow_lifecycle_state: "completed"`
  - `observed_conversation_state.workflow_wait_state: "ready"`
  - `observed_conversation_state.turn_lifecycle_state: "active"`
  - `observed_conversation_state.agent_task_run_state: "completed"`
  - `observed_conversation_state.selected_output_message_id: null`
- minimum evidence:
  - conversation, turn, workflow-run, and agent-task-run `public_id` values
  - one bundled runtime deployment and execution-environment `public_id`
  - one runtime output captured from the Fenix execution transcript
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-bundled-fenix-fast-terminal/`
- operator note:
  - this proves the bundled Fenix mailbox execution path over the
    websocket-first control plane; the runtime output completes on the
    task/control plane and is not projected into `turn.selected_output_message`
- cleanup steps:
  - none; the script resets and seeds the development database itself
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_bundled_fast_terminal_validation.json`

### Phase 2 Scenario 02: Real Provider-Backed Bundled Fenix Turn

- goal:
  verify one real provider-backed top-level turn succeeds with the configured
  `.env` credential materialized into the development database
- prerequisites:
  - `bin/dev` running in `core_matrix`
  - `AGENT_FENIX_PORT=3101 bin/dev` running in `agents/fenix`
  - `core_matrix/.env` contains a working `OPENROUTER_API_KEY`
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/provider_backed_turn_validation.rb \
  > /tmp/phase2_provider_backed_turn_validation.json

jq '.' /tmp/phase2_provider_backed_turn_validation.json
```

- expected outputs:
  - `provider_handle: "openrouter"`
  - `model_ref: "openai-gpt-5.4-live-acceptance"`
  - `api_model: "openai/gpt-5.4"`
  - `selector: "candidate:openrouter/openai-gpt-5.4-live-acceptance"`
  - `expected_dag_shape: ["turn_step"]`
  - `observed_dag_shape: ["turn_step"]`
  - `observed_conversation_state.conversation_state: "active"`
  - `observed_conversation_state.workflow_lifecycle_state: "completed"`
  - `observed_conversation_state.workflow_wait_state: "ready"`
  - `observed_conversation_state.turn_lifecycle_state: "completed"`
  - `observed_conversation_state.selected_output_content:
    "ACCEPTED-PHASE2"`
- minimum evidence:
  - deployment, conversation, turn, and workflow-run `public_id` values
  - real provider handle, model ref, and API model
  - selected output stored on the completed turn
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-provider-backed-turn/`
- operator note:
  - this is the real provider-backed `turn_step` path owned by Core Matrix; the
    bundled Fenix manifest provides the deployment context, but the actual text
    generation is the provider-backed kernel path
- cleanup steps:
  - none; the script resets and seeds the development database itself
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_provider_backed_turn_validation.json`

### Phase 2 Scenario 03: During-Generation Steering

- goal:
  verify `reject`, `restart`, and `queue` behavior under active generation,
  including one feature-disabled rejection and one stale-work fence
- prerequisites:
  - helper functions loaded
  - run `bin/rails db:seed` after reset so selector resolution stays aligned
    with the current provider catalog baseline
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/during_generation_steering_validation.rb \
  > /tmp/phase2_during_generation_steering.json

jq '.' /tmp/phase2_during_generation_steering.json
```

- expected outputs:
  - `reject.error.messages` includes
    `"reject policy does not allow new input while active work exists"`
  - `reject.observed_conversation_state.queued_turn_count: 0`
  - `restart.observed_conversation_state.wait_state: "waiting"`
  - `restart.observed_conversation_state.wait_reason_kind: "policy_gate"`
  - `restart.observed_dag_shape.blocking_resource_id` equals
    `restart.queued_turn_id`
  - `queue.observed_conversation_state.workflow_wait_state: "ready"`
  - `queue.observed_conversation_state.queued_turn_lifecycle_state: "queued"`
  - `feature_disabled.observed_conversation_state.error: "feature_not_enabled"`
  - `feature_disabled.observed_conversation_state.feature_id:
    "conversation_branching"`
  - `stale_work.observed_conversation_state.error_class` equals
    `ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError`
  - `stale_work.observed_conversation_state.selected_output_message_id` is
    `null`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - not yet rerun after Milestone `D` command refresh; execute during the final
    Phase 2 acceptance run

### Phase 2 Scenario 04: Human Interaction Wait And Resume

- goal:
  verify yielded human-interaction requests become workflow-owned waits and
  later resume correctly
- prerequisites:
  - helper functions loaded
  - `bin/dev` running if you want to watch logs while the agent-control reports
    are processed
  - run `bin/rails db:seed` after reset so selector resolution stays aligned
    with the current provider catalog baseline
  - this scenario intentionally uses rails-runner-driven agent-control reports;
    real bundled and external `Fenix` binaries are covered by scenarios `01`,
    `02`, and `11`
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/human_interaction_wait_resume_validation.rb \
  > /tmp/phase2_human_interaction_wait_resume.json

jq '.' /tmp/phase2_human_interaction_wait_resume.json
```

- expected outputs:
  - `human_interaction_request_id` is present
  - `observed_dag_shape_before` equals
    `["agent_turn_step->human_gate", "root->agent_turn_step"]`
  - `observed_conversation_state_before.workflow_wait_state: "waiting"`
  - `observed_conversation_state_before.workflow_wait_reason_kind:
    "human_interaction"`
  - `observed_conversation_state_before.blocking_resource_id` equals
    `human_interaction_request_id`
  - `observed_dag_shape_after` equals
    `["agent_turn_step->human_gate", "human_gate->agent_step_2",
    "root->agent_turn_step"]`
  - `observed_conversation_state_after.workflow_wait_state: "ready"`
  - `observed_conversation_state_after.successor_task_lifecycle_state:
    "queued"`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - not yet rerun after Milestone `D` command refresh; execute during the final
    Phase 2 acceptance run

### Phase 2 Scenario 05: Subagent Spawn And `wait_all` Barrier

- goal:
  verify bounded parallel subagent spawn, barrier waiting, and resumed parent
  progression
- prerequisites:
  - helper functions loaded
  - `bin/dev` running if you want to watch logs while the agent-control reports
    are processed
  - run `bin/rails db:seed` after reset so selector resolution stays aligned
    with the current provider catalog baseline
  - this scenario intentionally uses rails-runner-driven agent-control reports;
    real bundled and external `Fenix` binaries are covered by scenarios `01`,
    `02`, and `11`
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/subagent_wait_all_validation.rb \
  > /tmp/phase2_subagent_wait_all.json

jq '.' /tmp/phase2_subagent_wait_all.json
```

- expected outputs:
  - `subagent_session_ids` contains two `public_id` values
  - `observed_dag_shape_before` equals
    `["agent_turn_step->subagent_alpha", "agent_turn_step->subagent_beta",
    "root->agent_turn_step"]`
  - `observed_conversation_state_before.workflow_wait_state: "waiting"`
  - `observed_conversation_state_before.workflow_wait_reason_kind:
    "subagent_barrier"`
  - `observed_conversation_state_after_first_child.workflow_wait_state:
    "waiting"`
  - `observed_dag_shape_after` equals
    `["agent_turn_step->subagent_alpha", "agent_turn_step->subagent_beta",
    "root->agent_turn_step", "subagent_alpha->agent_step_2",
    "subagent_beta->agent_step_2"]`
  - `observed_conversation_state_after.workflow_wait_state: "ready"`
  - `observed_conversation_state_after.successor_task_lifecycle_state:
    "queued"`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - not yet rerun after Milestone `D` command refresh; execute during the final
    Phase 2 acceptance run

### Phase 2 Scenario 06: `process_run` Runtime Path

- goal:
  verify one real loop that exercises detached `process_exec` launch plus the
  mailbox-close path for one durable `ProcessRun`
- prerequisites:
  - `bin/dev` running in `core_matrix`
  - `AGENT_FENIX_PORT=3101 bin/dev` running in `agents/fenix`
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/process_run_close_validation.rb \
  > /tmp/phase2_process_run_close_validation.json

jq '.' /tmp/phase2_process_run_close_validation.json
```

- expected outputs:
  - `provider_handle: "dev"`
  - `model_ref: "mock-model"`
  - `selector: "candidate:dev/mock-model"`
  - `expected_dag_shape: ["agent_turn_step"]`
  - `observed_dag_shape: ["agent_turn_step"]`
  - `runtime_execution_status: "completed"`
  - `runtime_output` starts with
    `"Background service started as process run "`
  - `report_results: ["accepted", "accepted"]`
  - `observed_conversation_state.workflow_lifecycle_state: "completed"`
  - `observed_conversation_state.workflow_wait_state: "ready"`
  - `observed_conversation_state.turn_lifecycle_state: "active"`
  - `observed_conversation_state.agent_task_run_state: "completed"`
  - `observed_conversation_state.process_lifecycle_state: "stopped"`
  - `observed_conversation_state.process_close_state: "closed"`
  - `observed_conversation_state.process_close_outcome_kind: "graceful"`
  - `workflow_node_event_states: ["starting", "running"]`
- minimum evidence:
  - conversation, turn, workflow-run, and agent-task-run `public_id` values
  - process-run and close-request `public_id` values
  - deployment and execution-environment `public_id` values
  - one runtime output confirming the detached service was started through
    `process_exec`
  - observed graceful close on the environment-plane resource after the
    script-spawned persistent control worker delivers the close request
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-process-run-close-path/`
- operator note:
  - this path intentionally keeps the workflow DAG on one `agent_turn_step`
    node; detached background-service lifecycle lives on `ProcessRun`, not on a
    separate workflow node
  - the operator script now spawns one persistent `runtime:control_loop_forever`
    worker internally because one-shot mailbox tasks cannot retain
    long-lived local process handles across later close requests
- cleanup steps:
  - none; the script resets and seeds the development database itself
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_process_run_close_validation.json`

### Phase 2 Scenario 07: Governed Tool Invocation

- goal:
  verify one real tool call flows through the durable binding and invocation
  model
- prerequisites:
  - helper functions loaded
  - `bin/dev` running
  - development database reset with `core_matrix_reset_backend_state`
- exact commands:

```bash
core_matrix_reset_backend_state

bundle exec ruby script/manual/acceptance/governed_tool_validation.rb
```

- expected outputs:
  - `expected_dag_shape: ["root->agent_turn_step"]`
  - `observed_dag_shape: ["root->agent_turn_step"]`
  - `governance_mode: "reserved"`
  - `tool_invocation_status: "succeeded"`
  - non-empty `tool_binding_id`
  - non-empty `tool_invocation_id`
  - `response_payload.subagent_session_id` is present
  - `expected_conversation_state.turn_lifecycle_state: "active"`
- minimum evidence:
  - one `ToolBinding`
  - one `ToolInvocation`
  - conversation-visible outcome matches the invocation record
- record in addition:
  - `tool_binding.public_id`
  - `tool_invocation.public_id`
  - `tool_definition_id`
  - `tool_implementation_id`
  - `governance_mode`
  - invocation `status`
  - request and response payload excerpts
- reusable evidence query:

```bash
PHASE2_AGENT_TASK_RUN_ID=<agent_task_run_public_id> \
bin/rails runner - <<'RUBY'
task_run = AgentTaskRun.find_by!(public_id: ENV.fetch("PHASE2_AGENT_TASK_RUN_ID"))

payload = {
  "agent_task_run_id" => task_run.public_id,
  "tool_bindings" => task_run.tool_bindings.includes(:tool_definition, :tool_implementation).order(:created_at).map do |binding|
    {
      "tool_binding_id" => binding.public_id,
      "tool_name" => binding.tool_definition.tool_name,
      "tool_definition_id" => binding.tool_definition.public_id,
      "tool_implementation_id" => binding.tool_implementation.public_id,
      "implementation_ref" => binding.tool_implementation.implementation_ref,
      "governance_mode" => binding.tool_definition.governance_mode,
      "binding_reason" => binding.binding_reason
    }
  end,
  "tool_invocations" => task_run.tool_invocations.includes(:tool_definition, :tool_implementation).order(:created_at).map do |invocation|
    {
      "tool_invocation_id" => invocation.public_id,
      "tool_name" => invocation.tool_definition.tool_name,
      "tool_definition_id" => invocation.tool_definition.public_id,
      "tool_implementation_id" => invocation.tool_implementation.public_id,
      "implementation_ref" => invocation.tool_implementation.implementation_ref,
      "status" => invocation.status,
      "attempt_no" => invocation.attempt_no,
      "request_payload" => invocation.request_payload,
      "response_payload" => invocation.response_payload,
      "error_payload" => invocation.error_payload
    }
  end
}

puts JSON.pretty_generate(payload)
RUBY
```
- operator note:
  - use the query above after the real loop step completes so the acceptance
    report captures the durable binding and invocation rows without exposing
    internal numeric ids
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - execute during Milestone `E` and rerun during final bundled/external loop
    validation in Milestone `F`

### Phase 2 Scenario 08: Governed Streamable HTTP MCP Path

- goal:
  verify one real Streamable HTTP MCP capability works under the same governed
  invocation model
- prerequisites:
  - helper functions loaded
  - `bin/dev` running
  - development database reset with `core_matrix_reset_backend_state`
- exact commands:

```bash
core_matrix_reset_backend_state

bundle exec ruby script/manual/acceptance/governed_mcp_validation.rb
```

- expected outputs:
  - `expected_dag_shape: ["root->agent_turn_step"]`
  - `observed_dag_shape: ["root->agent_turn_step"]`
  - `tool_invocation_statuses: ["succeeded", "failed", "succeeded"]`
  - `failure_classification: "transport"`
  - `failure_code: "session_not_found"`
  - `issued_session_ids` contains at least two distinct session ids
  - `binding_payload.mcp.session_state: "open"`
  - `final_response_payload.content[0].text: "echo: third"`
  - `expected_conversation_state.turn_lifecycle_state: "active"`
- minimum evidence:
  - one governed MCP binding
  - one durable invocation history record
  - observable failure or success classification
- operator note:
  - this script uses the same governed binding and invocation rows as normal
    governed tools and exercises recovery after a durable `session_not_found`
    transport failure
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - execute during Milestone `E` and rerun during final acceptance in
    Milestone `F`

### Phase 2 Scenario 09: Deployment Rotation Upgrade

- goal:
  verify same-installation deployment rotation across an upgrade path
- prerequisites:
  - `bin/dev` running in `core_matrix`
  - `AGENT_FENIX_PORT=3101 bin/dev` running in `agents/fenix`
- exact commands:

```bash
bundle exec ruby script/manual/acceptance/bundled_rotation_validation.rb \
  > /tmp/phase2_bundled_rotation_validation.json

jq '{conversation_id, execution_environment_id, expected_dag_shape, expected_conversation_state, upgrade}' \
  /tmp/phase2_bundled_rotation_validation.json
```

- expected outputs:
  - `expected_dag_shape: ["turn_step"]`
  - `upgrade.previous_sdk_version: "fenix-0.1.0"`
  - `upgrade.new_sdk_version: "fenix-0.2.0"`
  - `upgrade.previous_bootstrap_state_after_cutover: "superseded"`
  - `upgrade.new_bootstrap_state_after_cutover: "active"`
  - `upgrade.conversation_agent_deployment_id_after_switch` equals
    `upgrade.new_deployment_id`
  - `upgrade.observed_dag_shape: ["turn_step"]`
  - `upgrade.observed_conversation_state.workflow_lifecycle_state:
    "completed"`
  - `upgrade.observed_conversation_state.turn_lifecycle_state: "completed"`
- minimum evidence:
  - shared conversation `public_id` across the pre-rotation baseline and the
    upgraded deployment
  - pre-cutover and post-cutover deployment `public_id` values
  - bootstrap-state transition from old `active` to `superseded`
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-deployment-rotation-upgrade/`
- operator note:
  - this script produces both the upgrade and downgrade evidence in one linear
    run; keep `/tmp/phase2_bundled_rotation_validation.json` for scenario `10`
- cleanup steps:
  - none; the script resets and seeds the development database itself
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_bundled_rotation_validation.json`

### Phase 2 Scenario 10: Deployment Rotation Downgrade

- goal:
  verify same-installation deployment rotation across a downgrade path
- prerequisites:
  - scenario `09` has already produced
    `/tmp/phase2_bundled_rotation_validation.json`
- exact commands:

```bash
test -f /tmp/phase2_bundled_rotation_validation.json || \
  bundle exec ruby script/manual/acceptance/bundled_rotation_validation.rb \
    > /tmp/phase2_bundled_rotation_validation.json

jq '{conversation_id, execution_environment_id, expected_dag_shape, expected_conversation_state, downgrade, current_conversation_agent_deployment_id, current_conversation_agent_deployment_fingerprint}' \
  /tmp/phase2_bundled_rotation_validation.json
```

- expected outputs:
  - `expected_dag_shape: ["turn_step"]`
  - `downgrade.previous_sdk_version: "fenix-0.2.0"`
  - `downgrade.new_sdk_version: "fenix-0.0.9"`
  - `downgrade.previous_bootstrap_state_after_cutover: "superseded"`
  - `downgrade.new_bootstrap_state_after_cutover: "active"`
  - `downgrade.conversation_agent_deployment_id_after_switch` equals
    `downgrade.new_deployment_id`
  - `current_conversation_agent_deployment_id` equals
    `downgrade.new_deployment_id`
  - `downgrade.observed_dag_shape: ["turn_step"]`
  - `downgrade.observed_conversation_state.workflow_lifecycle_state:
    "completed"`
- minimum evidence:
  - downgrade cutover to the older deployment fingerprint
  - conversation continuity preserved across the second deployment switch
  - final conversation deployment identity matches the downgraded release
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-deployment-rotation-downgrade/`
- cleanup steps:
  - none; this scenario reuses the scenario `09` output bundle
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_bundled_rotation_validation.json`

### Phase 2 Scenario 11: Independent External Fenix Validation

- goal:
  verify an external `Fenix` pairing works outside the bundled runtime path
- prerequisites:
  - `bin/dev` running in `core_matrix`
  - `AGENT_FENIX_PORT=3101 bin/dev` running in `agents/fenix`
- exact commands:

```bash
FENIX_RUNTIME_BASE_URL=http://127.0.0.1:3101 \
  bundle exec ruby script/manual/acceptance/external_fenix_validation.rb \
  > /tmp/phase2_external_fenix_validation.json

jq '.' /tmp/phase2_external_fenix_validation.json
```

- expected outputs:
  - `delivery_mode: "realtime"`
  - `registration_bootstrap_state: "pending"`
  - `heartbeat_bootstrap_state: "active"`
  - `expected_dag_shape: ["agent_turn_step"]`
  - `observed_dag_shape: ["agent_turn_step"]`
  - `runtime_execution_status: "completed"`
  - `runtime_output: "The calculator returned 12."`
  - `observed_conversation_state.agent_task_run_state: "completed"`
  - `observed_conversation_state.selected_output_message_id: null`
- minimum evidence:
  - external deployment, execution-environment, conversation, turn, workflow,
    and agent-task-run `public_id` values
  - external registration and heartbeat bootstrap-state evidence
  - durable task completion through the external control-plane path
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-external-fenix-validation/`
- cleanup steps:
  - none; the script resets and seeds the development database itself
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_external_fenix_validation.json`

### Phase 2 Scenario 12: Built-In System Skill Deploy Flow

- goal:
  verify the reserved built-in deploy skill can be listed, loaded, and used
  successfully
- prerequisites:
  - `bin/dev` running in `core_matrix`
  - a dedicated skills runtime running in `agents/fenix`:

```bash
AGENT_FENIX_PORT=3102 \
FENIX_HOME_ROOT=/tmp/phase2-acceptance-fenix-home \
bin/dev -P tmp/pids/server-3102.pid
```

- exact commands:

```bash
FENIX_RUNTIME_BASE_URL=http://127.0.0.1:3102 \
FENIX_HOME_ROOT=/tmp/phase2-acceptance-fenix-home \
bundle exec ruby acceptance/scenarios/fenix_skills_validation.rb \
  > /tmp/phase2_fenix_skills_validation.json

jq '{deployment_id, execution_environment_id, heartbeat_bootstrap_state, scenario_12}' \
  /tmp/phase2_fenix_skills_validation.json
```

- expected outputs:
  - `heartbeat_bootstrap_state: "active"`
  - `scenario_12.expected_dag_shape: ["agent_turn_step"]`
  - `scenario_12.catalog_names` equals
    `[["deploy-agent","system",true],["research-brief","curated",false]]`
  - `scenario_12.load_system_name: "deploy-agent"`
  - `scenario_12.load_system_files: ["scripts/deploy_agent.rb"]`
  - `scenario_12.read_system_content:
    "puts \"prepare deployment manifest\"\\n"`
- minimum evidence:
  - one clean system-plus-curated catalog listing
  - one successful system skill load
  - one successful system skill file read
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-system-skill-deploy-flow/`
- operator note:
  - the dedicated `3102` runtime keeps one disposable `FENIX_HOME_ROOT` under
    `/tmp` so installed skills and managed Python state remain isolated from
    the operator's real `~/.fenix` tree
- cleanup steps:
  - none; the script resets and seeds the development database itself, and it
    cleans the `/tmp/phase2-fenix-*` roots before running
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_fenix_skills_validation.json`

### Phase 2 Scenario 13: Third-Party Skill Install And Activation

- goal:
  verify one third-party skill install, promotion, and next-top-level-turn
  activation path
- prerequisites:
  - scenario `12` has already produced
    `/tmp/phase2_fenix_skills_validation.json`
- exact commands:

```bash
test -f /tmp/phase2_fenix_skills_validation.json || \
  FENIX_RUNTIME_BASE_URL=http://127.0.0.1:3102 \
  FENIX_HOME_ROOT=/tmp/phase2-acceptance-fenix-home \
  bundle exec ruby acceptance/scenarios/fenix_skills_validation.rb \
    > /tmp/phase2_fenix_skills_validation.json

jq '{deployment_id, execution_environment_id, scenario_13}' \
  /tmp/phase2_fenix_skills_validation.json
```

- expected outputs:
  - `scenario_13.expected_dag_shape: ["agent_turn_step"]`
  - `scenario_13.install_activation_state: "next_top_level_turn"`
  - `scenario_13.install_live_root:
    "/tmp/phase2-fenix-live-skills/portable-notes"`
  - `scenario_13.load_live_name: "portable-notes"`
  - `scenario_13.load_live_files: ["references/checklist.md"]`
  - `scenario_13.read_live_content: "# Checklist\\n"`
- minimum evidence:
  - staged install promoted into the live root
  - activation deferred until the next top-level turn
  - successful read from the newly active third-party skill
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-third-party-skill-activation/`
- cleanup steps:
  - none; this scenario reuses the scenario `12` output bundle
- last validated:
  - `2026-03-30` via
    `/tmp/phase2_fenix_skills_validation.json`

### Phase 2 Scenario 14: Workflow Proof Export Package

- goal:
  verify one workflow proof-export package is generated and committed as Phase 2
  evidence
- prerequisites:
  - scenario `11` has already produced
    `/tmp/phase2_external_fenix_validation.json`
- exact commands:

```bash
test -f /tmp/phase2_external_fenix_validation.json || \
  FENIX_RUNTIME_BASE_URL=http://127.0.0.1:3101 \
  bundle exec ruby script/manual/acceptance/external_fenix_validation.rb \
    > /tmp/phase2_external_fenix_validation.json

PHASE2_WORKFLOW_RUN_ID=$(jq -r '.workflow_run_id' /tmp/phase2_external_fenix_validation.json)
PHASE2_DEPLOYMENT_ID=$(jq -r '.deployment_id' /tmp/phase2_external_fenix_validation.json)
PHASE2_EXPECTED_DAG=$(jq -c '.expected_dag_shape' /tmp/phase2_external_fenix_validation.json)
PHASE2_OBSERVED_DAG=$(jq -c '.observed_dag_shape' /tmp/phase2_external_fenix_validation.json)
PHASE2_EXPECTED_STATE=$(jq -c '.expected_conversation_state' /tmp/phase2_external_fenix_validation.json)
PHASE2_OBSERVED_STATE=$(jq -c '.observed_conversation_state' /tmp/phase2_external_fenix_validation.json)

bundle exec ruby script/manual/workflow_proof_export.rb export \
  --workflow-run-id="$PHASE2_WORKFLOW_RUN_ID" \
  --scenario="Workflow Proof Export Package" \
  --out=../docs/reports/phase-2/2026-03-30-proof-export-package \
  --force \
  --date=2026-03-30 \
  --operator=Codex \
  --environment="bin/dev + AGENT_FENIX_PORT=3101 bin/dev" \
  --deployment-identifier="external:$PHASE2_DEPLOYMENT_ID" \
  --runtime-mode=external \
  --provider=dev \
  --model=mock-model \
  --expected-dag="$PHASE2_EXPECTED_DAG" \
  --observed-dag="$PHASE2_OBSERVED_DAG" \
  --expected-conversation-state="$PHASE2_EXPECTED_STATE" \
  --observed-conversation-state="$PHASE2_OBSERVED_STATE" \
  --operator-notes="Export the scenario 11 external Fenix workflow as the reusable Phase 2 proof package."
```

- expected outputs:
  - script stdout returns `proof_path` and `mermaid_path`
  - `proof_path` equals
    `../docs/reports/phase-2/2026-03-30-proof-export-package/proof.md`
  - `mermaid_path` matches
    `../docs/reports/phase-2/2026-03-30-proof-export-package/run-<workflow-run-id>.mmd`
  - both files exist on disk after the export
- minimum evidence:
  - one committed `proof.md`
  - one committed Mermaid DAG file
  - scenario directory recorded under `docs/reports/phase-2/`
- proof artifact path:
  - `docs/reports/phase-2/2026-03-30-proof-export-package/`
- cleanup steps:
  - none; this scenario reuses the scenario `11` output bundle
- last validated:
  - `2026-03-30` via
    `docs/reports/phase-2/2026-03-30-proof-export-package/`

## Prerequisites

- start `core_matrix` in one shell:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/dev
```

- start the default bundled/external Fenix runtime in a second shell:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
AGENT_FENIX_PORT=3101 bin/dev
```

- start the dedicated skills-validation runtime in a third shell when running
  scenarios `12` and `13`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
AGENT_FENIX_PORT=3102 \
FENIX_HOME_ROOT=/tmp/phase2-acceptance-fenix-home \
bin/dev -P tmp/pids/server-3102.pid
```

- then switch back to `core_matrix` for the checklist steps:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
```

- keep the Rails server reachable at `http://127.0.0.1:3000`
- make `curl`, `jq`, `ruby`, and `bundle` available in the shell session
- load the helper functions below once per shell session

## Shell Helpers

```bash
core_matrix_json_field() {
  ruby -rjson -e 'puts JSON.parse(ARGV[0]).fetch(ARGV[1])' "$1" "$2"
}

core_matrix_reset_backend_state() {
  DISABLE_DATABASE_ENVIRONMENT_CHECK=1 bin/rails db:reset
}
```

## Checklist Template

For each flow, keep:

- goal
- prerequisites
- exact commands
- expected rows, state changes, or HTTP payloads
- cleanup steps
- last validated date if the command body changed materially

## First-Admin Bootstrap

- goal:
  verify the backend bootstrap creates exactly one installation, one identity,
  one admin user, and one bootstrap audit row
- prerequisites:
  - helper functions loaded
  - `bin/dev` running
  - development database may be reset
- exact commands:

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

puts({
  installation_count: Installation.count,
  identity_count: Identity.count,
  user_roles: User.order(:id).pluck(:role),
  audit_actions: AuditLog.order(:action).pluck(:action),
  bootstrap_state: bootstrap.installation.reload.bootstrap_state,
}.to_json)
RUBY
```

- expected outputs:
  - `installation_count: 1`
  - `identity_count: 1`
  - `user_roles: ["admin"]`
  - `audit_actions: ["installation.bootstrapped"]`
  - `bootstrap_state: "bootstrapped"`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Invitation, Admin Roles, Bindings, And Bundled Runtime

- goal:
  verify invitation consumption, admin grant and revoke, default workspace
  binding, and bundled runtime reconciliation all remain aligned
- prerequisites:
  - helper functions loaded
- exact commands:

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
bundled_configuration = {
  enabled: true,
  agent_key: "fenix",
  display_name: "Bundled Fenix",
  visibility: "global",
  lifecycle_state: "active",
  environment_kind: "local",
  connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  fingerprint: "bundled-fenix-runtime",
  protocol_version: "2026-03-24",
  sdk_version: "fenix-0.1.0",
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: { "type" => "object", "properties" => {} },
  conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
  default_config_snapshot: { "sandbox" => "workspace-write" },
}

bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin",
  bundled_agent_configuration: bundled_configuration
)

invitation = Invitation.issue!(
  installation: bootstrap.installation,
  inviter: bootstrap.user,
  email: "member@example.com",
  expires_at: 2.days.from_now
)

consume = Invitations::Consume.call(
  token: invitation.plaintext_token,
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Member User"
)

Users::GrantAdmin.call(user: consume.user, actor: bootstrap.user)
Users::RevokeAdmin.call(user: consume.user, actor: bootstrap.user)

shared_agent = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "shared-agent",
  display_name: "Shared Agent",
  lifecycle_state: "active"
)

first_binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: shared_agent
).binding
duplicate_binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: shared_agent
).binding
UserAgentBindings::Enable.call(
  user: consume.user,
  agent_installation: shared_agent
)

first_registry = Installations::RegisterBundledAgentRuntime.call(
  installation: bootstrap.installation,
  configuration: bundled_configuration
)
second_registry = Installations::RegisterBundledAgentRuntime.call(
  installation: bootstrap.installation,
  configuration: bundled_configuration
)

puts({
  installation_count: Installation.count,
  bootstrap_role: bootstrap.user.reload.role,
  member_role: consume.user.reload.role,
  invitation_consumed: invitation.reload.consumed_at.present?,
  binding_count: UserAgentBinding.count,
  default_workspace_count: Workspace.where(is_default: true).count,
  duplicate_binding_reused: first_binding.id == duplicate_binding.id,
  bundled_agent_installation_ids: [
    first_registry.agent_installation.id,
    second_registry.agent_installation.id,
  ],
  bundled_deployment_ids: [
    first_registry.deployment.id,
    second_registry.deployment.id,
  ],
  audit_actions: AuditLog.order(:created_at).pluck(:action).last(6),
}.to_json)
RUBY
```

- expected outputs:
  - `installation_count: 1`
  - `bootstrap_role: "admin"`
  - `member_role: "member"`
  - `invitation_consumed: true`
  - `binding_count: 3`
  - `default_workspace_count: 3`
  - `duplicate_binding_reused: true`
  - `bundled_agent_installation_ids` contains the same id twice
  - `bundled_deployment_ids` contains the same id twice
  - trailing audit actions include
    `installation.bootstrapped`, `invitation.consumed`,
    `user.admin_granted`, and `user.admin_revoked`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Agent Registry And Credential Lifecycle

- goal:
  verify enrollment, registration, heartbeat, health, machine credential
  rotation, revocation, and retirement
- prerequisites:
  - helper functions loaded
  - `bin/dev` running
- exact commands:

```bash
core_matrix_reset_backend_state

STATE_JSON="$(bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "manual-runtime",
  display_name: "Manual Runtime",
  lifecycle_state: "active"
)

enrollment = AgentEnrollments::Issue.call(
  agent_installation: agent_installation,
  actor: bootstrap.user,
  expires_at: 2.hours.from_now
)

puts({
  enrollment_token: enrollment.plaintext_token,
}.to_json)
RUBY
)"

export CORE_MATRIX_BASE_URL=http://127.0.0.1:3000
export CORE_MATRIX_RUNTIME_BASE_URL=http://127.0.0.1:4100
export CORE_MATRIX_ENROLLMENT_TOKEN="$(core_matrix_json_field "$STATE_JSON" enrollment_token)"
export CORE_MATRIX_ENVIRONMENT_FINGERPRINT=manual-regression-environment
export CORE_MATRIX_FINGERPRINT=manual-regression-runtime

ruby script/manual/dummy_agent_runtime.rb register > /tmp/core_matrix_manual_register.json

export CORE_MATRIX_MACHINE_CREDENTIAL="$(
  ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("body").fetch("machine_credential")' \
    /tmp/core_matrix_manual_register.json
)"

ruby script/manual/dummy_agent_runtime.rb heartbeat > /tmp/core_matrix_manual_heartbeat.json
ruby script/manual/dummy_agent_runtime.rb health > /tmp/core_matrix_manual_health.json

ruby -rjson -e '
  register = JSON.parse(File.read("/tmp/core_matrix_manual_register.json"))
  heartbeat = JSON.parse(File.read("/tmp/core_matrix_manual_heartbeat.json"))
  health = JSON.parse(File.read("/tmp/core_matrix_manual_health.json"))

  puts({
    register_status: register.fetch("status"),
    heartbeat_status: heartbeat.fetch("status"),
    health_status: health.fetch("status"),
    bootstrap_state: register.fetch("body").fetch("bootstrap_state"),
    heartbeat_health: heartbeat.fetch("body").fetch("health_status"),
    health_method: health.fetch("body").fetch("method_id"),
  }.to_json)
'
```

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "registry-agent",
  display_name: "Registry Agent",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)

enrollment = AgentEnrollments::Issue.call(
  agent_installation: agent_installation,
  actor: bootstrap.user,
  expires_at: 2.hours.from_now
)

registration = AgentDeployments::Register.call(
  enrollment_token: enrollment.plaintext_token,
  execution_environment: execution_environment,
  fingerprint: "registry-runtime",
  endpoint_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: { "type" => "object", "properties" => {} },
  conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
  default_config_snapshot: { "sandbox" => "workspace-write" }
)

previous_credential = registration.machine_credential
rotated = AgentDeployments::RotateMachineCredential.call(
  deployment: registration.deployment,
  actor: bootstrap.user
)
AgentDeployments::RevokeMachineCredential.call(
  deployment: registration.deployment,
  actor: bootstrap.user
)
AgentDeployments::Retire.call(
  deployment: registration.deployment,
  actor: bootstrap.user
)

deployment = registration.deployment.reload

puts({
  rotated_credential_changed: rotated.machine_credential != previous_credential,
  old_credential_invalid: !deployment.matches_machine_credential?(previous_credential),
  rotated_credential_invalid_after_revoke: !deployment.matches_machine_credential?(rotated.machine_credential),
  unavailability_reason: deployment.unavailability_reason,
  health_status: deployment.health_status,
  bootstrap_state: deployment.bootstrap_state,
  eligible_for_scheduling: deployment.eligible_for_scheduling?,
  audit_actions: AuditLog.order(:created_at).pluck(:action).last(4),
}.to_json)
RUBY
```

- expected outputs:
  - live registration block returns `register_status: 201`
  - heartbeat returns `heartbeat_status: 200`
  - health returns `health_status: 200`
  - registration body reports `bootstrap_state: "pending"`
  - heartbeat body reports `heartbeat_health: "healthy"`
  - health body reports `health_method: "agent_health"`
  - credential lifecycle block reports
    `rotated_credential_changed: true`
  - credential lifecycle block reports
    `old_credential_invalid: true`
  - credential lifecycle block reports
    `rotated_credential_invalid_after_revoke: true`
  - credential lifecycle block reports
    `unavailability_reason: "deployment_retired"`
  - credential lifecycle block reports `health_status: "retired"`
  - credential lifecycle block reports `bootstrap_state: "superseded"`
  - credential lifecycle block reports `eligible_for_scheduling: false`
  - trailing audit actions include
    `agent_deployment.machine_credential_rotated`,
    `agent_deployment.machine_credential_revoked`, and
    `agent_deployment.retired`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Deployment Bootstrap And Recovery

- goal:
  verify deployment bootstrap, drift-triggered pause, and manual retry on a
  replacement deployment
- prerequisites:
  - helper functions loaded
  - `bin/dev` running if you also want to watch server logs while registering
- exact commands:

```bash
core_matrix_reset_backend_state

STATE_JSON="$(bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "manual-runtime",
  display_name: "Manual Runtime",
  lifecycle_state: "active"
)

enrollment = AgentEnrollments::Issue.call(
  agent_installation: agent_installation,
  actor: bootstrap.user,
  expires_at: 2.hours.from_now
)

puts({
  enrollment_token: enrollment.plaintext_token,
}.to_json)
RUBY
)"

export CORE_MATRIX_BASE_URL=http://127.0.0.1:3000
export CORE_MATRIX_RUNTIME_BASE_URL=http://127.0.0.1:4100
export CORE_MATRIX_ENROLLMENT_TOKEN="$(core_matrix_json_field "$STATE_JSON" enrollment_token)"
export CORE_MATRIX_ENVIRONMENT_FINGERPRINT=manual-regression-environment
export CORE_MATRIX_FINGERPRINT=manual-regression-runtime

ruby script/manual/dummy_agent_runtime.rb register > /tmp/core_matrix_manual_register.json
export CORE_MATRIX_MACHINE_CREDENTIAL="$(
  ruby -rjson -e 'puts JSON.parse(File.read(ARGV[0])).fetch("body").fetch("machine_credential")' \
    /tmp/core_matrix_manual_register.json
)"
ruby script/manual/dummy_agent_runtime.rb heartbeat > /tmp/core_matrix_manual_heartbeat.json

bin/rails runner - <<'RUBY'
bootstrap_user = User.find_by!(display_name: "Primary Admin")
agent_installation = AgentInstallation.find_by!(key: "manual-runtime")
deployment = AgentDeployment.find_by!(fingerprint: "manual-regression-runtime")

binding = UserAgentBindings::Enable.call(
  user: bootstrap_user,
  agent_installation: agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)

ProviderEntitlement.find_or_create_by!(
  installation: workspace.installation,
  provider_handle: "codex_subscription",
  entitlement_key: "shared_window"
) do |entitlement|
  entitlement.window_kind = "rolling_five_hours"
  entitlement.window_seconds = 5.hours.to_i
  entitlement.quota_limit = 200_000
  entitlement.active = true
  entitlement.metadata = {}
end

ProviderEntitlement.find_or_create_by!(
  installation: workspace.installation,
  provider_handle: "openai",
  entitlement_key: "shared_window"
) do |entitlement|
  entitlement.window_kind = "rolling_five_hours"
  entitlement.window_seconds = 5.hours.to_i
  entitlement.quota_limit = 200_000
  entitlement.active = true
  entitlement.metadata = {}
end

bootstrap = AgentDeployments::Bootstrap.call(
  deployment: deployment,
  workspace: workspace,
  manifest_snapshot: { "seeded_skills" => ["exec_command"] }
)

conversation = Conversations::CreateRoot.call(workspace: workspace)
turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Recover this workflow",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
workflow_run = Workflows::CreateForTurn.call(
  turn: turn,
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  metadata: {}
)

AgentDeployments::MarkUnavailable.call(
  deployment: deployment,
  severity: "transient",
  reason: "heartbeat_missed",
  occurred_at: Time.current
)

drifted_snapshot = CapabilitySnapshot.create!(
  agent_deployment: deployment,
  version: deployment.capability_snapshots.maximum(:version).to_i + 1,
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
    { "method_id" => "conversation_transcript_list" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
    {
      "tool_name" => "workspace_variables_get",
      "tool_kind" => "agent_observation",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/workspace_variables_get",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {
    "type" => "object",
    "properties" => {
      "interactive" => {
        "type" => "object",
        "properties" => {
          "selector" => { "type" => "string" },
        },
      },
    },
  },
  conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
  default_config_snapshot: {
    "sandbox" => "workspace-write",
    "interactive" => { "selector" => "role:main" },
  }
)

deployment.update!(active_capability_snapshot: drifted_snapshot)
AgentDeployments::RecordHeartbeat.call(
  deployment: deployment,
  health_status: "healthy",
  health_metadata: {},
  auto_resume_eligible: true
)

auto_resumed = AgentDeployments::AutoResumeWorkflows.call(deployment: deployment)
deployment.update!(bootstrap_state: "superseded")

replacement_environment = ExecutionEnvironment.create!(
  installation: workspace.installation,
  kind: "local",
  connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4200" },
  lifecycle_state: "active"
)

replacement = AgentDeployment.create!(
  installation: workspace.installation,
  agent_installation: deployment.agent_installation,
  execution_environment: replacement_environment,
  fingerprint: "manual-regression-runtime-2",
  endpoint_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4200" },
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.1",
  machine_credential_digest: AgentDeployment.digest_machine_credential("replacement-runtime"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  auto_resume_eligible: true,
  last_heartbeat_at: Time.current
)

replacement_snapshot = CapabilitySnapshot.create!(
  agent_deployment: replacement,
  version: 1,
  protocol_methods: drifted_snapshot.protocol_methods,
  tool_catalog: drifted_snapshot.tool_catalog,
  config_schema_snapshot: drifted_snapshot.config_schema_snapshot,
  conversation_override_schema_snapshot: drifted_snapshot.conversation_override_schema_snapshot,
  default_config_snapshot: {
    "sandbox" => "workspace-write",
    "interactive" => { "selector" => "role:main" },
    "model_slots" => { "research" => { "selector" => "role:researcher" } },
  }
)
replacement.update!(active_capability_snapshot: replacement_snapshot)

retried = Workflows::ManualRetry.call(
  workflow_run: workflow_run.reload,
  deployment: replacement,
  actor: workspace.user,
  selector: "role:planner"
)

puts({
  bootstrap_node_keys: bootstrap.workflow_run.workflow_nodes.order(:ordinal).pluck(:node_key),
  auto_resumed_ids: auto_resumed.map(&:id),
  paused_wait_reason: workflow_run.reload.wait_reason_kind,
  paused_recovery_state: workflow_run.wait_reason_payload["recovery_state"],
  retried_selector: retried.turn.normalized_selector,
  retried_provider: retried.turn.resolved_provider_handle,
  retried_model: retried.turn.resolved_model_ref,
  conversation_selector_mode: conversation.reload.interactive_selector_mode,
}.to_json)
RUBY
```

- expected outputs:
  - bootstrap reports `bootstrap_node_keys: ["deployment_bootstrap"]`
  - `auto_resumed_ids: []`
  - `paused_wait_reason: "manual_recovery_required"`
  - `paused_recovery_state: "paused_agent_unavailable"`
  - `retried_selector: "role:planner"`
  - `retried_provider: "openai"`
  - `retried_model: "gpt-5.4"`
  - `conversation_selector_mode: "auto"`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Selector Resolution And Recovery Override

- goal:
  verify `auto`, explicit candidate pinning, role-local fallback, specialized
  role exhaustion, and one-time manual resume override
- prerequisites:
  - helper functions loaded
  - run `bin/rails db:seed` after reset; with no real-provider credentials the
    shipped baseline now keeps `role:mock` usable while `role:main` correctly
    remains unavailable
  - the script below creates explicit `codex_subscription` and `openai`
    credentials so reservation and explicit-candidate checks stay deterministic
- exact commands:

```bash
core_matrix_reset_backend_state
bin/rails db:seed

bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "selector-agent",
  display_name: "Selector Agent",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)

deployment = AgentDeployment.create!(
  installation: bootstrap.installation,
  agent_installation: agent_installation,
  execution_environment: execution_environment,
  fingerprint: "selector-runtime",
  endpoint_metadata: {},
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  machine_credential_digest: AgentDeployment.digest_machine_credential("selector-runtime"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  auto_resume_eligible: true,
  last_heartbeat_at: Time.current
)

capability_snapshot = CapabilitySnapshot.create!(
  agent_deployment: deployment,
  version: 1,
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
    { "method_id" => "conversation_transcript_list" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
    {
      "tool_name" => "workspace_variables_get",
      "tool_kind" => "agent_observation",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/workspace_variables_get",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {
    "type" => "object",
    "properties" => {
      "interactive" => {
        "type" => "object",
        "properties" => {
          "selector" => { "type" => "string" },
        },
      },
      "model_slots" => {
        "type" => "object",
        "additionalProperties" => {
          "type" => "object",
          "properties" => {
            "selector" => { "type" => "string" },
          },
        },
      },
    },
  },
  conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
  default_config_snapshot: {
    "sandbox" => "workspace-write",
    "interactive" => { "selector" => "role:main" },
    "model_slots" => { "research" => { "selector" => "role:researcher" } },
  }
)
deployment.update!(active_capability_snapshot: capability_snapshot)

ProviderEntitlement.create!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription",
  entitlement_key: "shared_window",
  window_kind: "rolling_five_hours",
  window_seconds: 5.hours.to_i,
  quota_limit: 200_000,
  active: true,
  metadata: {}
)
ProviderEntitlement.create!(
  installation: bootstrap.installation,
  provider_handle: "openai",
  entitlement_key: "shared_window",
  window_kind: "rolling_five_hours",
  window_seconds: 5.hours.to_i,
  quota_limit: 200_000,
  active: true,
  metadata: {}
)
ProviderCredential.create!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription",
  credential_kind: "oauth_codex",
  secret: "oauth-codex-seed",
  last_rotated_at: Time.current,
  metadata: {}
)
ProviderCredential.create!(
  installation: bootstrap.installation,
  provider_handle: "openai",
  credential_kind: "api_key",
  secret: "sk-openai-seed",
  last_rotated_at: Time.current,
  metadata: {}
)

binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)

auto_conversation = Conversations::CreateRoot.call(workspace: workspace)
auto_turn = Turns::StartUserTurn.call(
  conversation: auto_conversation,
  content: "Selector input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
auto_snapshot = Workflows::ResolveModelSelector.call(
  turn: auto_turn,
  selector_source: "conversation"
)

ProviderEntitlement.find_by!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription"
).update!(metadata: { "reservation_denied" => true })

fallback_conversation = Conversations::CreateRoot.call(workspace: workspace)
fallback_turn = Turns::StartUserTurn.call(
  conversation: fallback_conversation,
  content: "Selector input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
fallback_snapshot = Workflows::ResolveModelSelector.call(
  turn: fallback_turn,
  selector_source: "conversation"
)

ProviderEntitlement.find_by!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription"
).update!(active: false, metadata: {})

explicit_conversation = Conversations::CreateRoot.call(workspace: workspace)
Conversations::UpdateOverride.call(
  conversation: explicit_conversation,
  payload: {},
  schema_fingerprint: "schema-v1",
  selector_mode: "explicit_candidate",
  selector_provider_handle: "codex_subscription",
  selector_model_ref: "gpt-5.4"
)
explicit_turn = Turns::StartUserTurn.call(
  conversation: explicit_conversation,
  content: "Selector input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
explicit_error = nil
begin
  Workflows::ResolveModelSelector.call(turn: explicit_turn, selector_source: "conversation")
rescue => error
  explicit_error = error.class.name
end

ProviderEntitlement.find_by!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription"
).update!(active: true, metadata: {})
ProviderEntitlement.find_by!(
  installation: bootstrap.installation,
  provider_handle: "openai"
).update!(active: false, metadata: {})

planner_conversation = Conversations::CreateRoot.call(workspace: workspace)
planner_turn = Turns::StartUserTurn.call(
  conversation: planner_conversation,
  content: "Planner input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
planner_error = nil
begin
  Workflows::ResolveModelSelector.call(
    turn: planner_turn,
    selector_source: "slot",
    selector: "role:planner"
  )
rescue => error
  planner_error = error.class.name
end

ProviderEntitlement.find_by!(
  installation: bootstrap.installation,
  provider_handle: "openai"
).update!(active: true, metadata: {})

recovery_conversation = Conversations::CreateRoot.call(workspace: workspace)
recovery_turn = Turns::StartUserTurn.call(
  conversation: recovery_conversation,
  content: "Paused recovery input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
workflow_run = Workflows::CreateForTurn.call(
  turn: recovery_turn,
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  metadata: {}
)
AgentDeployments::MarkUnavailable.call(
  deployment: deployment,
  severity: "prolonged",
  reason: "runtime_offline",
  occurred_at: Time.current
)
deployment.update!(bootstrap_state: "superseded")

replacement_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)
replacement = AgentDeployment.create!(
  installation: bootstrap.installation,
  agent_installation: agent_installation,
  execution_environment: replacement_environment,
  fingerprint: "selector-runtime-2",
  endpoint_metadata: {},
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.1",
  machine_credential_digest: AgentDeployment.digest_machine_credential("selector-runtime-2"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  auto_resume_eligible: true,
  last_heartbeat_at: Time.current
)

replacement_snapshot = CapabilitySnapshot.create!(
  agent_deployment: replacement,
  version: 1,
  protocol_methods: capability_snapshot.protocol_methods,
  tool_catalog: capability_snapshot.tool_catalog,
  config_schema_snapshot: capability_snapshot.config_schema_snapshot,
  conversation_override_schema_snapshot: capability_snapshot.conversation_override_schema_snapshot,
  default_config_snapshot: capability_snapshot.default_config_snapshot
)
replacement.update!(active_capability_snapshot: replacement_snapshot)

resumed = Workflows::ManualResume.call(
  workflow_run: workflow_run.reload,
  deployment: replacement,
  actor: bootstrap.user,
  selector: "role:planner"
)

puts({
  auto_selector: auto_snapshot["normalized_selector"],
  auto_provider: auto_snapshot["resolved_provider_handle"],
  fallback_provider: fallback_snapshot["resolved_provider_handle"],
  fallback_reason: fallback_snapshot["resolution_reason"],
  explicit_error: explicit_error,
  planner_error: planner_error,
  resumed_same_workflow_id: resumed.id == workflow_run.id,
  resumed_selector: resumed.turn.normalized_selector,
  resumed_provider: resumed.turn.resolved_provider_handle,
  conversation_selector_mode: recovery_conversation.reload.interactive_selector_mode,
}.to_json)
RUBY
```

- expected outputs:
  - `auto_selector: "role:main"`
  - `auto_provider: "codex_subscription"`
  - `fallback_provider: "openai"`
  - `fallback_reason: "role_fallback_after_reservation"`
  - `explicit_error: "ActiveRecord::RecordInvalid"`
  - `planner_error: "ActiveRecord::RecordInvalid"`
  - `resumed_same_workflow_id: true`
  - `resumed_selector: "role:planner"`
  - `resumed_provider: "openai"`
  - `conversation_selector_mode: "auto"`
- note:
  - if you omit the manual credential rows above, `auto_selector` should now
    fail because `role:main` excludes the shipped mock provider; use
    `role:mock` or explicit `candidate:dev/...` selection when you want to
    validate the seeded mock path
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Conversation Structure, Rewrite, Imports, Visibility, And Attachments

- goal:
  verify root or branch or thread or checkpoint lineage, archive or unarchive,
  summary import wiring, visibility overlays, attachment projection, tail edit,
  rollback, retry, rerun, and output variant selection
- prerequisites:
  - helper functions loaded
- exact commands:

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
require "stringio"

bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "history-agent",
  display_name: "History Agent",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)

deployment = AgentDeployment.create!(
  installation: bootstrap.installation,
  agent_installation: agent_installation,
  execution_environment: execution_environment,
  fingerprint: "history-runtime",
  endpoint_metadata: {},
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  machine_credential_digest: AgentDeployment.digest_machine_credential("history-runtime"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  last_heartbeat_at: Time.current
)

CapabilitySnapshot.create!(
  agent_deployment: deployment,
  version: 1,
  protocol_methods: [{ "method_id" => "agent_health" }],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {},
  conversation_override_schema_snapshot: {},
  default_config_snapshot: {}
)

binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)

structure_root = Conversations::CreateRoot.call(workspace: workspace)
structure_turn = Turns::StartUserTurn.call(
  conversation: structure_root,
  content: "Root input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
structure_output = AgentMessage.create!(
  installation: structure_root.installation,
  conversation: structure_root,
  turn: structure_turn,
  role: "agent",
  slot: "output",
  variant_index: 0,
  content: "Root output"
)
structure_turn.update!(selected_output_message: structure_output, lifecycle_state: "completed")

attachment = MessageAttachment.new(
  installation: structure_root.installation,
  conversation: structure_root,
  message: structure_turn.selected_input_message,
  origin_message: structure_turn.selected_input_message
)
attachment.file.attach(
  io: StringIO.new("brief attachment"),
  filename: "brief.txt",
  content_type: "text/plain",
  identify: false
)
attachment.save!

branch = Conversations::CreateBranch.call(
  parent: structure_root,
  historical_anchor_message_id: structure_turn.selected_input_message.id
)
thread = Conversations::CreateThread.call(parent: structure_root)
checkpoint = Conversations::CreateCheckpoint.call(
  parent: branch,
  historical_anchor_message_id: structure_turn.selected_input_message.id
)
Conversations::Archive.call(conversation: branch)
Conversations::Unarchive.call(conversation: branch)

summary_segment = ConversationSummaries::CreateSegment.call(
  conversation: structure_root,
  start_message: structure_turn.selected_input_message,
  end_message: structure_turn.selected_input_message,
  content: "Root summary"
)
quoted_context = Conversations::AddImport.call(
  conversation: structure_root,
  kind: "quoted_context",
  summary_segment: summary_segment
)

fork_rewrite_error = nil
begin
  Turns::EditTailInput.call(turn: structure_turn, content: "Fork point rewrite")
rescue => error
  fork_rewrite_error = error.class.name
end

Messages::UpdateVisibility.call(
  conversation: branch,
  message: structure_turn.selected_input_message,
  excluded_from_context: true
)

automation_root = Conversations::CreateAutomationRoot.call(workspace: workspace)

history_root = Conversations::CreateRoot.call(workspace: workspace)
first_turn = Turns::StartUserTurn.call(
  conversation: history_root,
  content: "First input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
first_output = AgentMessage.create!(
  installation: history_root.installation,
  conversation: history_root,
  turn: first_turn,
  role: "agent",
  slot: "output",
  variant_index: 0,
  content: "First output"
)
first_turn.update!(selected_output_message: first_output, lifecycle_state: "completed")

second_turn = Turns::StartUserTurn.call(
  conversation: history_root,
  content: "Second input",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
second_output = AgentMessage.create!(
  installation: history_root.installation,
  conversation: history_root,
  turn: second_turn,
  role: "agent",
  slot: "output",
  variant_index: 0,
  content: "Second output"
)
second_turn.update!(selected_output_message: second_output, lifecycle_state: "failed")

retried_turn = Turns::RetryOutput.call(message: second_output, content: "Second output retry")
retried_turn.update!(lifecycle_state: "completed")
alternative_output = AgentMessage.create!(
  installation: retried_turn.installation,
  conversation: retried_turn.conversation,
  turn: retried_turn,
  role: "agent",
  slot: "output",
  variant_index: 2,
  content: "Second output alternative"
)
Turns::SelectOutputVariant.call(message: alternative_output)
Conversations::RollbackToTurn.call(conversation: history_root, turn: first_turn)
edited_turn = Turns::EditTailInput.call(turn: first_turn, content: "First input revised")
branch_rerun = Turns::RerunOutput.call(message: first_output, content: "Branch rerun output")

puts({
  branch_state: branch.reload.lifecycle_state,
  thread_kind: thread.kind,
  checkpoint_depths: ConversationClosure.where(descendant_conversation: checkpoint)
    .order(depth: :desc)
    .pluck(:ancestor_conversation_id, :depth),
  quoted_context_kind: quoted_context.kind,
  fork_rewrite_error: fork_rewrite_error,
  branch_transcript_ids: branch.transcript_projection_messages.map(&:id),
  branch_context_attachment_ids: branch.context_projection_attachments.map(&:id),
  checkpoint_context_attachment_ids: checkpoint.context_projection_attachments.map(&:id),
  automation_root_kind: automation_root.kind,
  automation_root_purpose: automation_root.purpose,
  retried_selected_output: retried_turn.reload.selected_output_message.content,
  edited_input: edited_turn.selected_input_message.content,
  rerun_branch_kind: branch_rerun.conversation.kind,
  rerun_output: branch_rerun.selected_output_message.content,
}.to_json)
RUBY
```

- expected outputs:
  - `branch_state: "active"`
  - `thread_kind: "thread"`
  - `checkpoint_depths` shows root, branch, and checkpoint ancestry
  - `quoted_context_kind: "quoted_context"`
  - `fork_rewrite_error: "ActiveRecord::RecordInvalid"`
  - `branch_transcript_ids` contains the root input message id
  - `branch_context_attachment_ids: []`
  - `checkpoint_context_attachment_ids: []`
  - `automation_root_kind: "root"`
  - `automation_root_purpose: "automation"`
  - `retried_selected_output: "Second output alternative"`
  - `edited_input: "First input revised"`
  - `rerun_branch_kind: "branch"`
  - `rerun_output: "Branch rerun output"`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Human Interaction Pause And Resume

- goal:
  verify blocking approval requests pause the current workflow run, project
  append-only conversation events, and resume the same workflow run after
  approval
- prerequisites:
  - helper functions loaded
- exact commands:

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "approval-agent",
  display_name: "Approval Agent",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)

deployment = AgentDeployment.create!(
  installation: bootstrap.installation,
  agent_installation: agent_installation,
  execution_environment: execution_environment,
  fingerprint: "approval-runtime",
  endpoint_metadata: {},
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  machine_credential_digest: AgentDeployment.digest_machine_credential("approval-runtime"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  last_heartbeat_at: Time.current
)

capability = CapabilitySnapshot.create!(
  agent_deployment: deployment,
  version: 1,
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {
    "type" => "object",
    "properties" => {
      "interactive" => {
        "type" => "object",
        "properties" => { "selector" => { "type" => "string" } },
      },
    },
  },
  conversation_override_schema_snapshot: {},
  default_config_snapshot: {
    "sandbox" => "workspace-write",
    "interactive" => { "selector" => "role:main" },
  }
)
deployment.update!(active_capability_snapshot: capability)

ProviderEntitlement.create!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription",
  entitlement_key: "shared_window",
  window_kind: "rolling_five_hours",
  window_seconds: 5.hours.to_i,
  quota_limit: 200_000,
  active: true,
  metadata: {}
)
ProviderEntitlement.create!(
  installation: bootstrap.installation,
  provider_handle: "openai",
  entitlement_key: "shared_window",
  window_kind: "rolling_five_hours",
  window_seconds: 5.hours.to_i,
  quota_limit: 200_000,
  active: true,
  metadata: {}
)

binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)
conversation = Conversations::CreateRoot.call(workspace: workspace)
turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Need approval",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
workflow_run = Workflows::CreateForTurn.call(
  turn: turn,
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  metadata: {}
)
Workflows::Mutate.call(
  workflow_run: workflow_run,
  nodes: [
    {
      node_key: "human_gate",
      node_type: "human_interaction",
      decision_source: "agent_program",
      metadata: {},
    },
  ],
  edges: [{ from_node_key: "root", to_node_key: "human_gate" }]
)

request = HumanInteractions::Request.call(
  request_type: "ApprovalRequest",
  workflow_node: workflow_run.reload.workflow_nodes.find_by!(node_key: "human_gate"),
  blocking: true,
  request_payload: { "approval_scope" => "publish" }
)

wait_before = workflow_run.reload.wait_state
blocking_resource_id = workflow_run.blocking_resource_id
resolved = HumanInteractions::ResolveApproval.call(
  approval_request: request,
  decision: "approved",
  result_payload: { "comment" => "Ship it" }
)

puts({
  wait_before: wait_before,
  blocking_resource_id: blocking_resource_id,
  wait_after: resolved.workflow_run.reload.wait_state,
  same_workflow_run: resolved.workflow_run_id == workflow_run.id,
  conversation_event_kinds: ConversationEvent.where(conversation: conversation)
    .order(:projection_sequence)
    .pluck(:event_kind),
  live_projection_kinds: ConversationEvent.live_projection(conversation: conversation)
    .map(&:event_kind),
  turn_count: conversation.turns.count,
}.to_json)
RUBY
```

- expected outputs:
  - `wait_before: "waiting"`
  - `blocking_resource_id` is present
  - `wait_after: "ready"`
  - `same_workflow_run: true`
  - `conversation_event_kinds` equals
    `["human_interaction.opened", "human_interaction.resolved"]`
  - `live_projection_kinds` equals `["human_interaction.resolved"]`
  - `turn_count: 1`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Human Forms, Tasks, And Open Request Query

- goal:
  verify form submission, task completion, and open-request inbox projection for
  interactive and automation conversations
- prerequisites:
  - helper functions loaded
- exact commands:

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

member_identity = Identity.create!(
  email: "member@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  auth_metadata: {}
)
member = User.create!(
  installation: bootstrap.installation,
  identity: member_identity,
  role: "member",
  display_name: "Member User",
  preferences: {}
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "human-agent",
  display_name: "Human Agent",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)

deployment = AgentDeployment.create!(
  installation: bootstrap.installation,
  agent_installation: agent_installation,
  execution_environment: execution_environment,
  fingerprint: "human-runtime",
  endpoint_metadata: {},
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  machine_credential_digest: AgentDeployment.digest_machine_credential("human-runtime"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  last_heartbeat_at: Time.current
)

CapabilitySnapshot.create!(
  agent_deployment: deployment,
  version: 1,
  protocol_methods: [{ "method_id" => "agent_health" }],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {},
  conversation_override_schema_snapshot: {},
  default_config_snapshot: {}
)

def build_request_context(user:, deployment:)
  binding = UserAgentBindings::Enable.call(
    user: user,
    agent_installation: deployment.agent_installation
  ).binding
  workspace = binding.workspaces.find_by!(is_default: true)

  interactive_conversation = Conversations::CreateRoot.call(workspace: workspace)
  interactive_turn = Turns::StartUserTurn.call(
    conversation: interactive_conversation,
    content: "Interactive task",
    agent_deployment: deployment,
    resolved_config_snapshot: {},
    resolved_model_selection_snapshot: {}
  )
  interactive_workflow = WorkflowRun.create!(
    installation: interactive_conversation.installation,
    conversation: interactive_conversation,
    turn: interactive_turn,
    lifecycle_state: "active"
  )
  interactive_node = WorkflowNode.create!(
    installation: interactive_workflow.installation,
    workflow_run: interactive_workflow,
    ordinal: 0,
    node_key: "human_gate",
    node_type: "human_interaction",
    decision_source: "agent_program",
    metadata: {}
  )

  automation_conversation = Conversations::CreateAutomationRoot.call(workspace: workspace)
  automation_turn = Turns::StartAutomationTurn.call(
    conversation: automation_conversation,
    origin_kind: "automation_schedule",
    origin_payload: { "cron" => "0 9 * * *" },
    source_ref_type: "AutomationSchedule",
    source_ref_id: "schedule-1",
    idempotency_key: "idempotency-1",
    external_event_key: "event-1",
    agent_deployment: deployment,
    resolved_config_snapshot: {},
    resolved_model_selection_snapshot: {}
  )
  automation_workflow = WorkflowRun.create!(
    installation: automation_conversation.installation,
    conversation: automation_conversation,
    turn: automation_turn,
    lifecycle_state: "active"
  )
  automation_node = WorkflowNode.create!(
    installation: automation_workflow.installation,
    workflow_run: automation_workflow,
    ordinal: 0,
    node_key: "human_gate",
    node_type: "human_interaction",
    decision_source: "agent_program",
    metadata: {}
  )

  {
    interactive_node: interactive_node,
    automation_node: automation_node,
  }
end

owner_context = build_request_context(user: bootstrap.user, deployment: deployment)
other_context = build_request_context(user: member, deployment: deployment)

form_request = HumanInteractions::Request.call(
  request_type: "HumanFormRequest",
  workflow_node: owner_context[:interactive_node],
  blocking: true,
  request_payload: {
    "input_schema" => { "required" => ["ticket_id"] },
    "defaults" => { "priority" => "high" },
  }
)
submitted_form = HumanInteractions::SubmitForm.call(
  human_form_request: form_request,
  submission_payload: { "ticket_id" => "T-1000", "priority" => "low" }
)

task_request = HumanInteractions::Request.call(
  request_type: "HumanTaskRequest",
  workflow_node: owner_context[:automation_node],
  blocking: true,
  request_payload: { "instructions" => "Call the vendor and capture the ETA." }
)
completed_task = HumanInteractions::CompleteTask.call(
  human_task_request: task_request,
  completion_payload: {
    "eta" => "2026-03-26T09:00:00Z",
    "notes" => "Vendor confirmed dispatch.",
  }
)

open_owner_request = HumanInteractions::Request.call(
  request_type: "HumanTaskRequest",
  workflow_node: owner_context[:interactive_node],
  blocking: true,
  request_payload: { "instructions" => "Still open" }
)
other_open_request = HumanInteractions::Request.call(
  request_type: "HumanTaskRequest",
  workflow_node: other_context[:interactive_node],
  blocking: true,
  request_payload: { "instructions" => "Other user task" }
)

open_for_owner = HumanInteractions::OpenForUserQuery.call(user: bootstrap.user)

puts({
  form_resolution_kind: submitted_form.resolution_kind,
  form_ticket_id: submitted_form.result_payload["ticket_id"],
  task_resolution_kind: completed_task.resolution_kind,
  task_notes: completed_task.result_payload["notes"],
  owner_open_request_ids: open_for_owner.map(&:id),
  owner_open_request_types: open_for_owner.map(&:type),
  includes_other_user_request: open_for_owner.include?(other_open_request),
}.to_json)
RUBY
```

- expected outputs:
  - `form_resolution_kind: "submitted"`
  - `form_ticket_id: "T-1000"`
  - `task_resolution_kind: "completed"`
  - `task_notes: "Vendor confirmed dispatch."`
  - `owner_open_request_ids` contains only the still-open owner request
  - `owner_open_request_types: ["HumanTaskRequest"]`
  - `includes_other_user_request: false`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Machine-Facing Transcript, Variable, And Human Interaction APIs

- goal:
  verify transcript cursor pagination, canonical variable write and resolve and
  promote, and workflow-owned human-interaction creation through the agent API
- prerequisites:
  - helper functions loaded
  - `bin/dev` running
- exact commands:

```bash
core_matrix_reset_backend_state

STATE_JSON="$(bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "api-runtime",
  display_name: "API Runtime",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  lifecycle_state: "active"
)

enrollment = AgentEnrollments::Issue.call(
  agent_installation: agent_installation,
  actor: bootstrap.user,
  expires_at: 2.hours.from_now
)

registration = AgentDeployments::Register.call(
  enrollment_token: enrollment.plaintext_token,
  execution_environment: execution_environment,
  fingerprint: "api-runtime-001",
  endpoint_metadata: { "transport" => "http", "base_url" => "http://127.0.0.1:4100" },
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  protocol_methods: [
    { "method_id" => "agent_health" },
    { "method_id" => "capabilities_handshake" },
    { "method_id" => "conversation_transcript_list" },
  ],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {
    "type" => "object",
    "properties" => {
      "interactive" => {
        "type" => "object",
        "properties" => {
          "selector" => { "type" => "string" },
        },
      },
    },
  },
  conversation_override_schema_snapshot: { "type" => "object", "properties" => {} },
  default_config_snapshot: {
    "sandbox" => "workspace-write",
    "interactive" => { "selector" => "role:main" },
  }
)
AgentDeployments::RecordHeartbeat.call(
  deployment: registration.deployment,
  health_status: "healthy",
  health_metadata: {},
  auto_resume_eligible: true
)

ProviderEntitlement.create!(
  installation: bootstrap.installation,
  provider_handle: "codex_subscription",
  entitlement_key: "shared_window",
  window_kind: "rolling_five_hours",
  window_seconds: 5.hours.to_i,
  quota_limit: 200_000,
  active: true,
  metadata: {}
)
ProviderEntitlement.create!(
  installation: bootstrap.installation,
  provider_handle: "openai",
  entitlement_key: "shared_window",
  window_kind: "rolling_five_hours",
  window_seconds: 5.hours.to_i,
  quota_limit: 200_000,
  active: true,
  metadata: {}
)

binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)
conversation = Conversations::CreateRoot.call(workspace: workspace)

turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Canonical variable input",
  agent_deployment: registration.deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
first_output = AgentMessage.create!(
  installation: turn.installation,
  conversation: turn.conversation,
  turn: turn,
  role: "agent",
  slot: "output",
  variant_index: 0,
  content: "First answer"
)
turn.update!(selected_output_message: first_output, lifecycle_state: "completed")

second_turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Second question",
  agent_deployment: registration.deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
second_output = AgentMessage.create!(
  installation: second_turn.installation,
  conversation: second_turn.conversation,
  turn: second_turn,
  role: "agent",
  slot: "output",
  variant_index: 0,
  content: "Second answer"
)
second_turn.update!(selected_output_message: second_output)

workflow_run = Workflows::CreateForTurn.call(
  turn: second_turn,
  root_node_key: "root",
  root_node_type: "turn_root",
  decision_source: "system",
  metadata: {}
)
workflow_node = WorkflowNode.create!(
  installation: workflow_run.installation,
  workflow_run: workflow_run,
  ordinal: 1,
  node_key: "human_gate",
  node_type: "human_interaction",
  decision_source: "agent_program",
  metadata: {}
)

Variables::Write.call(
  scope: "workspace",
  workspace: workspace,
  key: "support_tier",
  typed_value_payload: { "type" => "string", "value" => "gold" },
  writer: bootstrap.user,
  source_kind: "manual_user",
  source_turn: second_turn,
  source_workflow_run: workflow_run
)

ConversationMessageVisibility.create!(
  installation: bootstrap.installation,
  conversation: conversation,
  message: first_output,
  hidden: true,
  excluded_from_context: false
)

puts({
  workspace_id: workspace.id,
  conversation_id: conversation.id,
  workflow_node_id: workflow_node.id,
  machine_credential: registration.machine_credential,
}.to_json)
RUBY
)"

MACHINE_CREDENTIAL="$(core_matrix_json_field "$STATE_JSON" machine_credential)"
WORKSPACE_ID="$(core_matrix_json_field "$STATE_JSON" workspace_id)"
CONVERSATION_ID="$(core_matrix_json_field "$STATE_JSON" conversation_id)"
WORKFLOW_NODE_ID="$(core_matrix_json_field "$STATE_JSON" workflow_node_id)"
AUTH_HEADER="Authorization: Token token=\"${MACHINE_CREDENTIAL}\""

curl -sS \
  -H "$AUTH_HEADER" \
  -H 'Accept: application/json' \
  "http://127.0.0.1:3000/agent_api/conversation_transcripts?conversation_id=${CONVERSATION_ID}&limit=2" \
  > /tmp/core_matrix_api_transcripts.json

curl -sS \
  -X POST \
  -H "$AUTH_HEADER" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  http://127.0.0.1:3000/agent_api/conversation_variables/write \
  --data "{\"workspace_id\":${WORKSPACE_ID},\"conversation_id\":${CONVERSATION_ID},\"key\":\"customer_name\",\"typed_value_payload\":{\"type\":\"string\",\"value\":\"Acme China\"},\"source_kind\":\"agent_runtime\"}" \
  > /tmp/core_matrix_api_write.json

curl -sS \
  -H "$AUTH_HEADER" \
  -H 'Accept: application/json' \
  "http://127.0.0.1:3000/agent_api/conversation_variables/resolve?workspace_id=${WORKSPACE_ID}&conversation_id=${CONVERSATION_ID}" \
  > /tmp/core_matrix_api_resolve.json

curl -sS \
  -X POST \
  -H "$AUTH_HEADER" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  http://127.0.0.1:3000/agent_api/conversation_variables/promote \
  --data "{\"workspace_id\":${WORKSPACE_ID},\"conversation_id\":${CONVERSATION_ID},\"key\":\"customer_name\"}" \
  > /tmp/core_matrix_api_promote.json

curl -sS \
  -X POST \
  -H "$AUTH_HEADER" \
  -H 'Accept: application/json' \
  -H 'Content-Type: application/json' \
  http://127.0.0.1:3000/agent_api/human_interactions \
  --data "{\"workflow_node_id\":${WORKFLOW_NODE_ID},\"request_type\":\"ApprovalRequest\",\"blocking\":true,\"request_payload\":{\"approval_scope\":\"publish\"}}" \
  > /tmp/core_matrix_api_human.json

ruby -rjson -e '
  transcripts = JSON.parse(File.read("/tmp/core_matrix_api_transcripts.json"))
  write = JSON.parse(File.read("/tmp/core_matrix_api_write.json"))
  resolve = JSON.parse(File.read("/tmp/core_matrix_api_resolve.json"))
  promote = JSON.parse(File.read("/tmp/core_matrix_api_promote.json"))
  human = JSON.parse(File.read("/tmp/core_matrix_api_human.json"))

  puts({
    transcript_method: transcripts.fetch("method_id"),
    transcript_contents: transcripts.fetch("items").map { |item| item.fetch("content") },
    next_cursor: transcripts.fetch("next_cursor"),
    write_method: write.fetch("method_id"),
    resolve_method: resolve.fetch("method_id"),
    resolved_customer_name: resolve.fetch("variables").fetch("customer_name").fetch("typed_value_payload").fetch("value"),
    resolved_support_tier: resolve.fetch("variables").fetch("support_tier").fetch("typed_value_payload").fetch("value"),
    promote_scope: promote.fetch("variable").fetch("scope"),
    human_method: human.fetch("method_id"),
    human_request_type: human.fetch("request_type"),
  }.to_json)
'
```

- expected outputs:
  - `transcript_method: "conversation_transcript_list"`
  - `transcript_contents` equals `["Canonical variable input", "Second question"]`
  - `next_cursor` is present
  - `write_method: "conversation_variables_write"`
  - `resolve_method: "conversation_variables_resolve"`
  - `resolved_customer_name: "Acme China"`
  - `resolved_support_tier: "gold"`
  - `promote_scope: "workspace"`
  - `human_method: "human_interactions_request"`
  - `human_request_type: "ApprovalRequest"`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`

## Publication Access Logging And Revoke

- goal:
  verify internal-public access, external-public access, live projection, access
  logging, and revoke behavior
- prerequisites:
  - helper functions loaded
- exact commands:

```bash
core_matrix_reset_backend_state

bin/rails runner - <<'RUBY'
bootstrap = Installations::BootstrapFirstAdmin.call(
  name: "Primary Installation",
  email: "admin@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  display_name: "Primary Admin"
)

viewer_identity = Identity.create!(
  email: "viewer@example.com",
  password: "Password123!",
  password_confirmation: "Password123!",
  auth_metadata: {}
)
viewer = User.create!(
  installation: bootstrap.installation,
  identity: viewer_identity,
  role: "member",
  display_name: "Viewer User",
  preferences: {}
)

agent_installation = AgentInstallation.create!(
  installation: bootstrap.installation,
  visibility: "global",
  key: "publish-agent",
  display_name: "Publish Agent",
  lifecycle_state: "active"
)

execution_environment = ExecutionEnvironment.create!(
  installation: bootstrap.installation,
  kind: "local",
  connection_metadata: {},
  lifecycle_state: "active"
)

deployment = AgentDeployment.create!(
  installation: bootstrap.installation,
  agent_installation: agent_installation,
  execution_environment: execution_environment,
  fingerprint: "publish-runtime",
  endpoint_metadata: {},
  protocol_version: "2026-03-24",
  sdk_version: "dummy-runtime-0.1.0",
  machine_credential_digest: AgentDeployment.digest_machine_credential("publish-runtime"),
  health_status: "healthy",
  health_metadata: {},
  bootstrap_state: "active",
  last_heartbeat_at: Time.current
)

CapabilitySnapshot.create!(
  agent_deployment: deployment,
  version: 1,
  protocol_methods: [{ "method_id" => "agent_health" }],
  tool_catalog: [
    {
      "tool_name" => "exec_command",
      "tool_kind" => "kernel_primitive",
      "implementation_source" => "kernel",
      "implementation_ref" => "kernel/exec_command",
      "input_schema" => { "type" => "object", "properties" => {} },
      "result_schema" => { "type" => "object", "properties" => {} },
      "streaming_support" => false,
      "idempotency_policy" => "best_effort",
    },
  ],
  config_schema_snapshot: {},
  conversation_override_schema_snapshot: {},
  default_config_snapshot: {}
)

binding = UserAgentBindings::Enable.call(
  user: bootstrap.user,
  agent_installation: agent_installation
).binding
workspace = binding.workspaces.find_by!(is_default: true)
conversation = Conversations::CreateRoot.call(workspace: workspace)
turn = Turns::StartUserTurn.call(
  conversation: conversation,
  content: "Share this conversation",
  agent_deployment: deployment,
  resolved_config_snapshot: {},
  resolved_model_selection_snapshot: {}
)
output = AgentMessage.create!(
  installation: conversation.installation,
  conversation: conversation,
  turn: turn,
  role: "agent",
  slot: "output",
  variant_index: 0,
  content: "Visible output"
)
turn.update!(selected_output_message: output, lifecycle_state: "completed")
ConversationEvents::Project.call(
  conversation: conversation,
  turn: turn,
  event_kind: "runtime.notice",
  payload: { "state" => "shared" }
)

internal_publication = Publications::PublishLive.call(
  conversation: conversation,
  actor: bootstrap.user,
  visibility_mode: "internal_public"
)
internal_access = Publications::RecordAccess.call(
  publication: internal_publication,
  viewer_user: viewer,
  request_metadata: { "user_agent" => "Browser" }
)

external_publication = Publications::PublishLive.call(
  conversation: conversation,
  actor: bootstrap.user,
  visibility_mode: "external_public"
)
slug_access = Publications::RecordAccess.call(
  slug: external_publication.slug,
  request_metadata: { "ip" => "127.0.0.1" }
)
token_access = Publications::RecordAccess.call(
  access_token: external_publication.plaintext_access_token,
  request_metadata: { "ip" => "127.0.0.2" }
)
projection_entries = Publications::LiveProjection.call(publication: external_publication)

Publications::Revoke.call(publication: external_publication, actor: bootstrap.user)

revoked_error = nil
begin
  Publications::RecordAccess.call(
    slug: external_publication.slug,
    request_metadata: { "ip" => "127.0.0.3" }
  )
rescue => error
  revoked_error = error.class.name
end

puts({
  internal_access_user_id: internal_access.viewer_user_id,
  external_slug_access_via: slug_access.access_via,
  external_token_access_via: token_access.access_via,
  projection_entry_types: projection_entries.map(&:entry_type),
  projection_record_types: projection_entries.map { |entry| entry.record.class.name },
  revoked_error: revoked_error,
  access_event_count: PublicationAccessEvent.where(publication: external_publication).count,
  audit_actions: AuditLog.order(:created_at).pluck(:action).last(3),
}.to_json)
RUBY
```

- expected outputs:
  - `internal_access_user_id` is present
  - `external_slug_access_via: "slug"`
  - `external_token_access_via: "access_token"`
  - `projection_entry_types` equals `["message", "conversation_event", "message"]`
  - `projection_record_types` equals
    `["UserMessage", "ConversationEvent", "AgentMessage"]`
  - `revoked_error: "ActiveRecord::RecordInvalid"`
  - `access_event_count: 3`
  - trailing audit actions equal
    `["publication.enabled", "publication.visibility_changed", "publication.revoked"]`
- cleanup steps:
  - `core_matrix_reset_backend_state`
- last validated:
  - `2026-03-25`
