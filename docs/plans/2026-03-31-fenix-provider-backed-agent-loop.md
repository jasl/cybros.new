# Fenix Provider-Backed Agent Loop Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Turn `Fenix` into a real provider-backed runtime-loop agent that can complete the capstone `2048` workload through normal `Core Matrix` conversations and turns.

**Architecture:** Keep `Core Matrix` as the collaboration kernel and implement the provider loop, tool loop, skill loop, and subagent loop inside `Fenix`. Build explicit internal seams that can later be extracted into an agent-program SDK or gem, but do not block on that extraction now.

**Tech Stack:** Ruby on Rails (`core_matrix`, `agents/fenix`), Action Cable mailbox control, provider-backed LLM transport, Dockerized `Fenix`, Playwright/browser tooling, mounted host workspace.

---

### Task 1: Re-baseline the runtime execution contract

**Files:**
- Read: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Read: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/context/build_execution_context.rb`
- Read: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/pairing_manifest.rb`
- Read: `/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb`

**Step 1: Write or update failing tests that assert a provider-backed mode exists**

- Add tests that fail until `ExecuteAssignment` supports a real provider-backed
  execution mode distinct from deterministic-only validation.
- Cover:
  - repeated provider rounds
  - tool-call roundtrip support
  - final output streaming hook presence

**Step 2: Run the targeted failing tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/integration/runtime_flow_test.rb
```

Expected:

- failing assertions proving the current runtime path is still deterministic

**Step 3: Introduce the new mode boundary**

- Refactor `ExecuteAssignment` so deterministic validation is one explicit mode,
  not the default behavior of the real agent path.
- Preserve deterministic coverage for smoke and contract tests.

**Step 4: Re-run the targeted tests**

Run the same command and confirm the updated contract passes.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb
git commit -m "feat: rebaseline fenix runtime execution contract"
```

### Task 2: Add provider session and real model transport

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/provider_session.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/prepare_turn.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/provider_session_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb`

**Step 1: Write the failing provider-session tests**

- Cover:
  - model/provider resolution from assignment hints
  - streaming callback support
  - normalized assistant output blocks
  - graceful surfacing of provider errors

**Step 2: Run just the new provider-session tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/agent_loop/provider_session_test.rb
```

Expected:

- failing because `ProviderSession` does not exist yet

**Step 3: Implement the minimal provider wrapper**

- Add `Fenix::AgentLoop::ProviderSession`
- Keep transport/provider specifics inside `Fenix`
- Support streamed final-output deltas without persisting raw intermediate text

**Step 4: Integrate the provider wrapper into assignment execution**

- Replace the "deterministic by default" top loop with a real provider entry
  path when the assignment mode requires the real agent

**Step 5: Re-run the targeted tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/agent_loop/provider_session_test.rb test/services/fenix/runtime/execute_assignment_test.rb
```

Expected:

- passing provider-session and assignment-path tests

**Step 6: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/provider_session.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/prepare_turn.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/provider_session_test.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/runtime/execute_assignment_test.rb
git commit -m "feat: add fenix provider session"
```

### Task 3: Implement the runtime-owned tool loop

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/tool_dispatcher.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/review_tool_call.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/tool_dispatcher_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb`

**Step 1: Write failing tests for repeated tool-loop rounds**

- Cover:
  - assistant chooses a visible tool
  - tool executes through existing runtime/plugin surfaces
  - tool result feeds back into the next provider round
  - loop ends only when the model returns a final answer

**Step 2: Run the targeted failing tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/agent_loop/tool_dispatcher_test.rb test/integration/runtime_flow_test.rb
```

**Step 3: Implement the dispatcher**

- Keep `allowed_tool_names` enforcement
- Preserve `ToolInvocation`, `CommandRun`, and `ProcessRun` provisioning paths
- Keep streamed tool output ephemeral
- Keep terminal tool summaries durable

**Step 4: Re-run the targeted tests**

Use the same command and confirm the tool loop passes.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/tool_dispatcher.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/review_tool_call.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/tool_dispatcher_test.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb
git commit -m "feat: add fenix runtime tool loop"
```

### Task 4: Make skills part of the real loop

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/skill_resolver.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/prompts/assembler.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/skill_resolver_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/skills_flow_test.rb`

**Step 1: Write failing tests for skill selection and injection**

- Cover:
  - skill discovery for current turn
  - loading one or more relevant skills
  - reading skill-relative files on demand
  - preserving "next top-level turn" activation for newly installed skills

**Step 2: Run the failing skill tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/agent_loop/skill_resolver_test.rb test/integration/skills_flow_test.rb
```

**Step 3: Implement `SkillResolver`**

- Keep skill ownership in `Fenix`
- Do not eagerly load every skill into the prompt
- Make installed skills affect real planning rather than passive file browsing

**Step 4: Wire skill-aware prompt assembly**

- Ensure selected skills participate in the prompt/context stack for the active
  provider-backed turn

**Step 5: Re-run the targeted tests**

Use the same command and confirm the skill loop passes.

**Step 6: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/skill_resolver.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/prompts/assembler.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/skill_resolver_test.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/skills_flow_test.rb
git commit -m "feat: add fenix skill loop"
```

### Task 5: Make subagent tools executable in Fenix

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/subagent_client.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/review_tool_call.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/subagent_client_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb`

**Step 1: Write failing tests for `subagent_*` tool execution**

- Cover:
  - `subagent_spawn`
  - `subagent_wait`
  - `subagent_send`
  - `subagent_close`
  - `subagent_list`
- Assert these produce real protocol work and reports rather than fake traces

**Step 2: Run the targeted failing tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/agent_loop/subagent_client_test.rb test/integration/runtime_flow_test.rb

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/agent_control/report_test.rb
```

**Step 3: Implement the subagent client**

- Treat subagents as kernel-reserved tools, not normal environment plugins
- Coordinate child work through mailbox/runtime protocol
- Preserve proofability in workflow and runtime reports

**Step 4: Re-run the targeted tests**

Use the same commands and confirm the real subagent path passes.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/subagent_client.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/hooks/review_tool_call.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/subagent_client_test.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb
git commit -m "feat: add fenix subagent loop"
```

### Task 6: Add a top-level turn runner and completion policy

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/turn_runner.rb`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/completion_policy.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/turn_runner_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb`

**Step 1: Write failing orchestration tests**

- Cover:
  - repeated provider/tool rounds
  - clean finalization
  - cancellation during live work
  - streaming callback emission
  - deterministic mode still available for smoke coverage

**Step 2: Run the targeted failing tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/rails test test/services/fenix/agent_loop/turn_runner_test.rb test/integration/runtime_flow_test.rb
```

**Step 3: Implement `TurnRunner` and `CompletionPolicy`**

- Make the top loop explicit
- Keep seams clean for later SDK extraction
- Keep business-specific behavior in `Fenix`

**Step 4: Re-run the targeted tests**

Use the same command and confirm the loop orchestration passes.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/turn_runner.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/agent_loop/completion_policy.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/app/services/fenix/runtime/execute_assignment.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/services/fenix/agent_loop/turn_runner_test.rb /Users/jasl/Workspaces/Ruby/cybros/agents/fenix/test/integration/runtime_flow_test.rb
git commit -m "feat: add fenix turn runner"
```

### Task 7: Teach Core Matrix the richer runtime report shapes it now needs

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_runtime_resource_report.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_runtime/broadcast.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/workflow_scheduler_flow_test.rb`

**Step 1: Write failing kernel-side tests for richer reports**

- Cover:
  - provider-backed Fenix terminal success
  - runtime-owned subagent updates
  - richer tool-loop event shapes
  - publication/runtime streaming for final output and structured events

**Step 2: Run the failing kernel tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/services/agent_control/report_test.rb test/integration/workflow_scheduler_flow_test.rb
```

**Step 3: Implement the minimal kernel-side support**

- Keep kernel truth durable and agent-facing IDs public
- Accept the richer runtime loop outputs without re-centralizing the agent loop

**Step 4: Re-run the targeted tests**

Use the same command and confirm the kernel report path passes.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/report.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_execution_report.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/agent_control/handle_runtime_resource_report.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/services/conversation_runtime/broadcast.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/services/agent_control/report_test.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/workflow_scheduler_flow_test.rb
git commit -m "feat: support richer fenix runtime reports"
```

### Task 8: Build the capstone manual harness

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/capstone/`
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/capstone/fenix_2048_acceptance.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/manual_acceptance_support.rb`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Test: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/workflow_proof_export_flow_test.rb`

**Step 1: Write failing harness-level expectations**

- Decide the exact proof outputs:
  - `turns.md`
  - `conversation-transcript.md`
  - `collaboration-notes.md`
  - `runtime-and-deployment.md`
  - `workspace-artifacts.md`
  - `playability-verification.md`

**Step 2: Run any relevant existing proof-export tests**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/rails test test/integration/workflow_proof_export_flow_test.rb
```

**Step 3: Implement the capstone helper and operator script**

- Reuse manual-acceptance support where it still matches reality
- Do not add a fake debug execution entrypoint
- Record only `public_id` values

**Step 4: Re-run the proof-related test**

Use the same command and confirm proof export remains aligned.

**Step 5: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/manual_acceptance_support.rb /Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/capstone /Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md /Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/integration/workflow_proof_export_flow_test.rb
git commit -m "feat: add fenix capstone acceptance harness"
```

### Task 9: Run the real capstone acceptance

**Files:**
- Use: `/Users/jasl/Workspaces/Ruby/cybros/docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Use: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/script/manual/capstone/fenix_2048_acceptance.rb`
- Update: `/Users/jasl/Workspaces/Ruby/cybros/docs/reports/`

**Step 1: Start the full stack from the `phase2` baseline plus the implemented loop**

- start `Core Matrix`
- start Dockerized `Fenix`
- mount `/Users/jasl/Workspaces/Ruby/cybros/tmp/fenix`

**Step 2: Install the required skills into Fenix**

- `obra/superpowers`
- `find-skills`

**Step 3: Execute the real conversation-driven 2048 build**

- no deterministic bypasses
- no fake operator injection
- real conversation and turn flow

**Step 4: Verify the result manually in a browser**

- ensure the final game is playable
- verify controls and rules
- collect proof package artifacts

**Step 5: Run full CI in both projects**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/ci

cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
bin/ci
```

Expected:

- both projects green
- capstone checklist satisfied

**Step 6: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/agents/fenix /Users/jasl/Workspaces/Ruby/cybros/core_matrix /Users/jasl/Workspaces/Ruby/cybros/docs/reports
git commit -m "feat: pass fenix provider-backed capstone acceptance"
```

### Task 10: Record the post-capstone SDK extraction seam

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/2026-03-31-agent-program-sdk-extraction-follow-up.md`
- Update: `/Users/jasl/Workspaces/Ruby/cybros/docs/future-plans/README.md`

**Step 1: Write the extraction follow-up**

- document the seams proven stable by the capstone:
  - provider session
  - tool dispatcher
  - skill resolver
  - subagent client
  - turn runner
  - completion policy

**Step 2: Verify the new future-plan doc is clean**

Run:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
git diff --check -- docs/future-plans
```

**Step 3: Commit**

```bash
git add /Users/jasl/Workspaces/Ruby/cybros/docs/future-plans
git commit -m "docs: record agent program sdk extraction follow-up"
```
