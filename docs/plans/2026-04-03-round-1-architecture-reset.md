# Round 1 Architecture Reset Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete Round 1 of the multi-round architecture reset by reducing execution-envelope duplication, simplifying mailbox targeting, tightening program/execution boundaries, and extracting the largest cross-layer hotspots while preserving the full acceptance baseline.

**Architecture:** Round 1 works in bounded batches. First collapse duplicated runtime payload/context construction, then simplify mailbox target and routing schema, then shrink the worst aggregate redundancies, and finally extract oversized report/execution services. Keep all user-visible orchestration inside `Core Matrix` `Workflow`, and keep `Fenix` focused on program behavior and execution-runtime behavior instead of scheduling.

**Tech Stack:** Ruby on Rails, PostgreSQL, Action Cable, Active Job / Solid Queue, JSONB snapshots, mailbox-first runtime protocol, provider-backed LLM loop, Dockerized `Fenix`

## Current status

This plan now serves as the active Round 1 ledger rather than a greenfield
proposal.

- The duplication, mailbox, plane-split, and large-service extraction batches
  described in Tasks 2 through 7 have already landed in code.
- The current remaining value in this document is:
  - preserving the reset boundary decisions
  - recording what was intentionally removed in Round 1
  - guiding any final cleanup that still belongs to the same reset family
- Current acceptance execution uses the top-level
  [acceptance harness](/Users/jasl/Workspaces/Ruby/cybros/acceptance/README.md),
  not `core_matrix/script/manual/acceptance`.

---

### Task 1: Land the round-1 contract and deprecation list in docs

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-round-1-architecture-audit-design.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-round-1-architecture-reset.md`
- Check: `/Users/jasl/Workspaces/Ruby/cybros/docs/plans/2026-04-03-multi-round-architecture-audit-and-reset-framework.md`

**Steps:**
1. Freeze the round-1 boundary decisions in the audit document before code changes.
2. List the exact obsolete paths to remove:
   - mailbox `target_ref`
   - mailbox `target_kind`
   - legacy runtime-plane normalization from `"agent"` / `"environment"`
   - fake execution-plane assignment expectations
   - duplicate `Fenix` payload-to-context builders
3. Keep the success gate aligned with the framework and the capstone checklist.

**Verification:**
- Run: `git diff --check`
- Expected: no formatting or whitespace errors

### Task 2: Collapse `Fenix` runtime context building into one reusable builder

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/payload_context.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/prepare_round.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_program_tool.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/prepare_round_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/jobs/runtime_execution_job_test.rb`

**Steps:**
1. Write failing tests that assert the shared builder produces the same
   normalized context for assignment, `prepare_round`, and
   `execute_program_tool`.
2. Extract a single payload-context object that owns:
   - task ids
   - logical work metadata
   - capability projection / agent context normalization
   - workspace bootstrap / env overlay / prompts
   - provider/model context
3. Rewrite the three existing call sites to consume the shared builder instead
   of rebuilding the payload graph independently.
4. Remove duplicated normalization helpers that become dead after the
   extraction.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails db:test:prepare test test/services/fenix/runtime/prepare_round_test.rb test/services/fenix/runtime/execute_assignment_test.rb test/jobs/runtime_execution_job_test.rb`
- Expected: targeted runtime-context tests pass

### Task 3: Stop persisting full mailbox payload copies in `Fenix`

**Files:**
- Modify migration history under `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/db/migrate`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/db/schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/models/runtime_execution.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/jobs/runtime_execution_job.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/mailbox_worker_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/jobs/runtime_execution_job_test.rb`

**Steps:**
1. Write failing tests that capture the new persistence contract for
   `RuntimeExecution`.
2. Replace `mailbox_item_payload` with a smaller persisted operational shape:
   - mailbox item id
   - item type
   - request kind
   - agent task id
   - logical work id
   - attempt no
   - any minimal payload fragment still needed by the job
3. Make `RuntimeExecutionJob` reload the mailbox payload from the active job
   argument or a compact persisted fragment instead of relying on a full stored
   copy.
4. Keep reports/trace/output only as operational evidence, not as a second copy
   of the mailbox envelope.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails db:test:prepare test test/services/fenix/runtime/mailbox_worker_test.rb test/jobs/runtime_execution_job_test.rb`
- Expected: persistence and cancellation tests pass under the new compact row shape

### Task 4: Simplify mailbox target modeling and routing in `Core Matrix`

**Files:**
- Modify migration history under `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_agent_program_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_resource_close_request.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/resolve_target_runtime.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/serialize_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/test_helper.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_control_mailbox_item_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/resolve_target_runtime_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/requests/program_api/control_poll_test.rb`

**Steps:**
1. Write failing tests for the simpler mailbox contract:
   - no `target_ref`
   - no `target_kind`
   - no legacy plane aliases
   - execution routing uses `target_execution_runtime_id` only
2. Remove the redundant columns and validations from the model and migration
   history.
3. Update mailbox creation services to persist only the foreign keys and
   logical-work fields that are behaviorally necessary.
4. Update routing and polling to operate on the simplified contract.
5. Update helpers and fixtures so tests stop generating the removed fields.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare test test/models/agent_control_mailbox_item_test.rb test/services/agent_control/resolve_target_runtime_test.rb test/requests/program_api/control_poll_test.rb`
- Expected: mailbox creation, leasing, and routing tests pass without compatibility shims

### Task 5: Make the current plane split explicit and delete fake execution-plane assignment paths

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/provider_execution/route_tool_call.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/create_execution_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_mailbox_item.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/mailbox_worker.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/provider_execution/route_tool_call_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb`

**Steps:**
1. Write failing tests that describe the intended round-1 contract:
   - assignments are program-plane work
   - execution plane remains resource-API work
   - invalid execution-plane assignment fixtures are removed
2. Remove or rewrite code paths and tests that assume execution-plane
   assignments are valid.
3. Make `RouteToolCall` explicitly document whether execution-runtime tools are
   proxied through the program plane in round 1 or split into a later round.
4. Align `Fenix` runtime execution tests to the actual contract instead of the
   transitional one.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare test test/services/provider_execution/route_tool_call_test.rb`
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails db:test:prepare test test/services/fenix/runtime/execute_assignment_test.rb test/integration/runtime_flow_test.rb`
- Expected: plane-boundary tests now reflect one explicit contract

### Task 6: Shrink `WorkflowRun` and `AgentTaskRun` toward true aggregate facts

**Files:**
- Modify migration history under `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/migrate`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/db/schema.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workflow_run.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/agent_task_run.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/create_for_turn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/workflows/*`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/workflow_run_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/models/agent_task_run_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/workflows/create_for_turn_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/handle_execution_report_test.rb`

**Steps:**
1. Decide the exact redundant columns to remove first:
   - `WorkflowRun.workspace_id`
   - `WorkflowRun.feature_policy_snapshot`
   - `AgentTaskRun.feature_policy_snapshot`
   - any other field now trivially derivable from `turn` or `workflow_run`
2. Write failing tests for the slimmer aggregate responsibilities.
3. Remove the redundant columns from migration history and the model
   validations.
4. Update creation, refresh, and report-handling services to derive those facts
   from `turn` / `workflow_run` instead of storing them twice.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare test test/models/workflow_run_test.rb test/models/agent_task_run_test.rb test/services/workflows/create_for_turn_test.rb test/services/agent_control/handle_execution_report_test.rb`
- Expected: aggregate invariants pass with fewer stored duplicates

### Task 7: Extract the largest cross-layer services into narrower collaborators

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/execution_reports/*`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/assignments/*`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/project_tool_result.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/tool_result_projection_registry.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/handle_execution_report_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`

**Steps:**
1. Start with characterization tests around the existing large services.
2. Extract report-handling collaborators in `Core Matrix`:
   - task lifecycle updater
   - tool-invocation reconciler
   - command/process reconciler
   - workflow follow-up handler
   - runtime event broadcaster
3. Extract assignment collaborators in `Fenix`:
   - mode selection
   - deterministic tool execution
   - skill-flow execution
   - tool reporting
4. Convert `ProjectToolResult` from a static switchboard into a registry or map
   keyed by tool name or operator group.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/rails db:test:prepare test test/services/agent_control/handle_execution_report_test.rb`
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/rails db:test:prepare test test/services/fenix/runtime/execute_assignment_test.rb`
- Expected: characterization tests still pass while hotspot files shrink materially

### Task 8: Delete transitional wrappers and stale tests

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/runtime_capabilities/preview_for_conversation.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/subagent_sessions/spawn.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/runtime_capabilities/preview_for_conversation_test.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/subagent_sessions/spawn_test.rb`
- Scan: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test`
- Scan: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test`

**Steps:**
1. Replace the old conversation composition wrapper with an explicit preview-capability
   object for conversation-scoped visibility checks.
2. Update subagent spawning to use the new preview path.
3. Delete tests that only exist to preserve removed transitional behavior.
4. Run repo-wide scans for dead names introduced by the round-1 reset.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros && rg -n 'target_ref|target_kind|normalize_runtime_plane|mailbox_item_payload|ComposeForConversation' core_matrix/app agents/fenix/app core_matrix/test agents/fenix/test`
- Expected: only intentional survivors remain

### Task 9: Run the full round-1 gate

**Files:**
- Check all files touched by tasks 1-8
- Check: `/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`

**Steps:**
1. Reset both databases if migration history changed.
2. Run all required verification commands from `AGENTS.md`.
3. Perform the fresh-start gate through:
   - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/fresh_start_stack.sh`
4. Run the provider-backed `2048` capstone acceptance end to end. Prefer:
   - `/Users/jasl/Workspaces/Ruby/cybros/acceptance/bin/run_with_fresh_start.sh`
5. Do one more repo-wide dead-code and stale-name sweep before closing the round.

**Verification:**
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bun run lint:js && bin/rails db:test:prepare test && bin/rails db:test:prepare test:system`
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix && bin/brakeman --no-pager && bin/bundler-audit && bin/rubocop -f github && bin/rails db:test:prepare test`
- Run: `cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference && bundle exec rake`
- Run the full capstone checklist with the current acceptance harness and record proof artifacts
- Expected: all checks pass and the same `2048` acceptance workload still closes successfully
