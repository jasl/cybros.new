# Prompt Budget Guard And Request Preparation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

## Goal

Build a dedicated request-preparation subsystem for prompt-budget protection and
Core Matrix-assisted prompt compaction.

The subsystem must:

- keep Core Matrix as the sole authoritative dispatch-time budget gate
- provide a strong working fallback for simple agents
- give sophisticated agents better drafting guidance and counting tools
- force all Core Matrix-assisted compaction through workflow-visible execution

## Target Outcome

At the end of this plan:

- Core Matrix publishes a budget envelope during prompt construction
- agents can call `POST /agent_api/responses/input_tokens`
- Core Matrix performs authoritative dispatch-time budget guarding
- prompt compaction uses a dedicated request-preparation contract, not the
  runtime feature platform
- prompt compaction consultation and workflow execution are available in Fenix
- embedded compaction provides a strong fallback
- provider overflow becomes explicit, recoverable failure metadata
- deterministic tiny-context e2e coverage exists

## Non-Goals

This plan does not:

- reimplement generic runtime-feature execution
- move prompt compaction onto `execute_feature`
- prevent agents from doing additional local budgeting or compaction on their
  own before they ask Core Matrix for help
- preserve compatibility with the interim feature-slice contract

## Architecture

The implementation introduces:

- a Core Matrix-owned token estimator
- a budget envelope in `provider_context`
- an AgentAPI counting endpoint shaped after OpenAI
- an authoritative `PromptBudgetGuard`
- a dedicated `request_preparation_contract` for prompt compaction
- direct consultation before workflow insertion
- workflow-backed compaction execution and re-entry
- explicit failure and degradation diagnostics

## Tech Stack

Ruby on Rails, Minitest, control-plane mailbox contracts, AgentAPI endpoints,
workflow nodes, embedded executors, fake/mock providers, `agents/fenix`.

---

### Task 1: Lock The Request-Preparation Contracts With Failing Tests

**Files:**
- Create: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/workflows/execute_node_test.rb`
- Modify: `core_matrix/test/services/workflows/dispatch_runnable_nodes_test.rb`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Create: `agents/fenix/test/services/requests/consult_prompt_compaction_test.rb`
- Create: `agents/fenix/test/services/requests/execute_prompt_compaction_test.rb`

**Step 1: Write failing Core Matrix guard tests**

Add tests that expect:

- Core Matrix computes authoritative guard decisions from the final
  provider-visible candidate
- the guard result is one of `allow`, `consult`, `compact_required`, `reject`
- the newest selected user input may force immediate `reject`
- `consult` and `compact_required` are distinct outcomes
- prompt-compaction policy is frozen into the prepared round before guard
  execution

**Step 2: Write failing round-loop boundary tests**

Extend `execute_round_loop_test.rb` so it expects:

- `consult` triggers runtime consultation when available
- `compact_required` triggers workflow insertion
- all Core Matrix-assisted compaction is represented as workflow work
- workflow execution re-enters the normal agent loop

Extend `execute_turn_step_test.rb`, `execute_node_test.rb`, and
`dispatch_runnable_nodes_test.rb` so they expect:

- a dedicated `prompt_compaction` node type is supported
- the current `turn_step` can yield into a `prompt_compaction` node plus a
  successor `turn_step`
- the workflow engine can dispatch and execute that node type
- the successor `turn_step` resumes from the compaction artifact instead of the
  default transcript

**Step 3: Write failing runtime-contract tests**

Extend Fenix manifest and request-preparation tests so they expect:

- top-level `request_preparation_contract`
- `prompt_compaction` capability under that contract
- consultation support
- workflow-node execution support
- `consult_prompt_compaction` and `execute_prompt_compaction` are valid
  `agent_request` kinds handled by Fenix

**Step 4: Run the targeted tests and verify they fail**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/workflows/execute_node_test.rb \
  test/services/workflows/dispatch_runnable_nodes_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/integration/runtime_manifest_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb \
  test/services/requests/consult_prompt_compaction_test.rb \
  test/services/requests/execute_prompt_compaction_test.rb
```

Expected: failures show the request-preparation contracts and boundaries do not
exist yet.

### Task 2: Implement Token Estimation, Budget Envelope, And Counting API

**Files:**
- Create: `core_matrix/app/services/provider_execution/token_estimator.rb`
- Create: `core_matrix/app/services/provider_execution/prompt_budget_advisory.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/app/services/provider_execution/prepare_agent_round.rb`
- Modify: `core_matrix/app/services/provider_execution/build_request_context.rb`
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/agent_api/responses/input_tokens_controller.rb`
- Modify: `core_matrix/test/services/provider_execution/token_estimator_test.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_budget_advisory_test.rb`
- Modify: `core_matrix/test/services/provider_execution/prepare_agent_round_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`
- Modify: `core_matrix/test/services/provider_execution/build_request_context_test.rb`
- Create: `core_matrix/test/requests/agent_api/responses/input_tokens_test.rb`
- Modify: `agents/fenix/app/services/shared/control_plane/client.rb`
- Modify: `agents/fenix/test/services/shared/control_plane/client_test.rb`
- Modify: `agents/fenix/test/services/build_round_instructions_test.rb`
- Modify: `agents/fenix/test/services/requests/prepare_round_test.rb`

**Step 1: Implement `TokenEstimator`**

The estimator should accept:

- provider-visible `input`
- model identity and tokenizer hints
- relevant budget context

It should return:

- `estimated_tokens`
- `strategy`
- diagnostics

Fallback order:

1. exact local tokenizer asset
2. `tiktoken`
3. heuristic estimate

**Step 2: Publish the prompt-construction budget envelope**

Update `BuildExecutionSnapshot` so `provider_context` includes:

- `model_context`
  - `provider_handle`
  - `model_ref`
  - `api_model`
  - `tokenizer_hint`
- `budget_hints.hard_limits`
  - `context_window_tokens`
  - `max_output_tokens`
  - `hard_input_token_limit`
- `budget_hints.advisory_hints`
  - `recommended_input_tokens`
  - `recommended_compaction_threshold`
  - `soft_threshold_tokens`
  - `reserved_tokens`
  - `reserved_output_tokens`
  - `context_soft_limit_ratio`

Add tests that prove:

- the envelope is produced in `BuildExecutionSnapshot`
- `PrepareAgentRound` forwards it without reshaping it
- `BuildRequestContext` still exposes the correct dispatch-time hard/advisory
  values
- Fenix can consume the envelope during prompt construction
- the prepared round carries frozen prompt-compaction policy for later guard,
  consultation, and workflow use

**Step 3: Expose the read-only counting API**

Implement:

- `POST /agent_api/responses/input_tokens`

The endpoint should:

- reuse the same estimator and budget logic
- accept provider-visible `input`
- support multimodal payload classes
- return model identity, effective budgets, `reserved_tokens`, estimated token
  usage, and `decision_hint`

Fenix should gain a small control-plane client wrapper for this endpoint.

**Step 4: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_advisory_test.rb \
  test/services/provider_execution/prepare_agent_round_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb \
  test/services/provider_execution/build_request_context_test.rb \
  test/requests/agent_api/responses/input_tokens_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/shared/control_plane/client_test.rb \
  test/services/build_round_instructions_test.rb \
  test/services/requests/prepare_round_test.rb
```

Expected: Core Matrix-owned budgeting surfaces are available before final
dispatch.

### Task 3: Add The Dedicated Prompt-Compaction Runtime Contract

**Files:**
- Modify: `agents/fenix/app/services/runtime/manifest/definition_package.rb`
- Modify: `agents/fenix/config/canonical_config.defaults.json`
- Modify: `agents/fenix/config/canonical_config.schema.json`
- Modify: `agents/fenix/test/integration/runtime_manifest_test.rb`
- Modify: `core_matrix/app/services/installations/register_bundled_agent_runtime.rb`
- Create: `core_matrix/app/services/provider_execution/request_preparation_capability_resolver.rb`
- Modify: `core_matrix/app/services/workflows/build_execution_snapshot.rb`
- Modify: `core_matrix/test/services/installations/register_bundled_agent_runtime_test.rb`
- Modify: `core_matrix/test/services/workflows/build_execution_snapshot_test.rb`

**Step 1: Add `request_preparation_contract`**

Update Fenix definition packaging so the manifest publishes a top-level
`request_preparation_contract`.

The initial entry should be `prompt_compaction` with:

- consultation support
- workflow execution support
- turn-scoped lifecycle metadata
- implementation reference

At the same time, keep Fenix runtime defaults aligned with the shared settings
contract by ensuring canonical config still publishes:

- `features.prompt_compaction.strategy = runtime_first`

**Step 2: Resolve request-preparation capability in Core Matrix**

Implement a Core Matrix-side resolver that:

- normalizes `request_preparation_contract`
- exposes effective prompt-compaction runtime capability for the current
  prepared round
- freezes that effective capability into the prepared round / execution
  snapshot
- does not depend on the runtime-feature platform

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/installations/register_bundled_agent_runtime_test.rb \
  test/services/workflows/build_execution_snapshot_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test test/integration/runtime_manifest_test.rb
```

Expected: prompt compaction now has a dedicated runtime contract separate from
`feature_contract`.

### Task 4: Add The Prompt-Compaction Agent-Request Exchange

**Files:**
- Modify: `core_matrix/app/services/agent_control/create_agent_request.rb`
- Modify: `core_matrix/app/models/agent_control_mailbox_item.rb`
- Modify: `core_matrix/app/services/provider_execution/agent_request_exchange.rb`
- Create: `core_matrix/app/services/provider_execution/request_preparation_exchange.rb`
- Modify: `core_matrix/test/services/agent_control/create_agent_request_test.rb`
- Modify: `core_matrix/test/services/provider_execution/agent_request_exchange_test.rb`
- Create: `core_matrix/test/services/provider_execution/request_preparation_exchange_test.rb`
- Modify: `agents/fenix/app/services/runtime/execute_mailbox_item.rb`
- Create: `agents/fenix/app/services/requests/consult_prompt_compaction.rb`
- Create: `agents/fenix/app/services/requests/execute_prompt_compaction.rb`
- Modify: `agents/fenix/test/services/runtime/execute_mailbox_item_test.rb`
- Create: `agents/fenix/test/services/requests/consult_prompt_compaction_test.rb`
- Create: `agents/fenix/test/services/requests/execute_prompt_compaction_test.rb`

**Step 1: Extend `agent_request` kinds**

Add two explicit request kinds:

- `consult_prompt_compaction`
- `execute_prompt_compaction`

These should ride over the existing `agent_request` mailbox path, not
`execution_assignment`.

**Step 2: Reconstruct snapshot-backed payload consistently**

Ensure agent-request payload reconstruction still hydrates:

- `provider_context`
- `agent_context`
- task identifiers

and carries explicit request payload needed for consultation or node execution.

**Step 3: Add a dedicated request-preparation exchange**

Introduce a Core Matrix-side exchange wrapper dedicated to prompt compaction so
consultation and node execution do not get mixed into generic `prepare_round`
or tool-execution call sites.

**Step 4: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/agent_control/create_agent_request_test.rb \
  test/services/provider_execution/agent_request_exchange_test.rb \
  test/services/provider_execution/request_preparation_exchange_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/runtime/execute_mailbox_item_test.rb \
  test/services/requests/consult_prompt_compaction_test.rb \
  test/services/requests/execute_prompt_compaction_test.rb
```

Expected: prompt compaction runtime participation now fits the current
agent-only Fenix transport model.

### Task 5: Implement The Shared Baseline Compaction Strategy

**Files:**
- Create: `core_matrix/app/services/provider_execution/prompt_compaction_strategy.rb`
- Create: `core_matrix/app/services/embedded_features/prompt_compaction/invoke.rb`
- Create: `core_matrix/test/services/provider_execution/prompt_compaction_strategy_test.rb`
- Create: `core_matrix/test/services/embedded_features/prompt_compaction/invoke_test.rb`
- Create: shared fixture or golden-test files under an appropriate common test-support path

**Step 1: Define the baseline invariants**

The shared baseline must preserve:

- newest selected user input verbatim
- explicit user constraints
- active task state and near-term plan
- file paths, resources, and identifiers still in play
- unresolved errors
- pending tool outcomes

It must prioritize reduction in this order:

1. bulky tool outputs
2. older transcript and imports
3. only then less-critical older narrative context

**Step 2: Implement the embedded executor**

Build a Core Matrix embedded compactor that follows the baseline strategy and
returns:

- compacted payload
- before/after estimates
- stop reason
- diagnostics

**Step 3: Implement the Fenix consultation responder**

The responder should:

- consume Core Matrix guard diagnostics
- return `skip`, `compact`, or `reject`
- return prioritization and preservation guidance
- stay aligned with the baseline strategy

**Step 4: Implement the Fenix workflow-node executor**

The runtime node executor should:

- run the actual compaction logic for the materialized workflow node
- use the same baseline invariants and fixture expectations as the embedded
  executor
- leave room for future Fenix-specific upgrades

**Step 5: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/prompt_compaction_strategy_test.rb \
  test/services/embedded_features/prompt_compaction/invoke_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/requests/consult_prompt_compaction_test.rb \
  test/services/requests/execute_prompt_compaction_test.rb
```

Expected: Core Matrix and Fenix share the same baseline compaction contract.

### Task 6: Add Workflow-Node Support And Ephemeral Context Handoff

**Files:**
- Create: `core_matrix/app/services/provider_execution/persist_turn_step_prompt_compaction_yield.rb`
- Create: `core_matrix/app/services/provider_execution/load_prompt_compaction_context.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/workflows/execute_node.rb`
- Modify: `core_matrix/app/services/workflows/dispatch_runnable_nodes.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`
- Modify: `core_matrix/test/services/workflows/execute_node_test.rb`
- Modify: `core_matrix/test/services/workflows/dispatch_runnable_nodes_test.rb`

**Step 1: Add a dedicated yielded outcome for compaction**

Extend the turn-step path so a guarded round can yield a third control result:

- `prompt_compaction_yield`

That outcome should:

- complete the current `turn_step`
- materialize a `prompt_compaction` node
- materialize a successor `turn_step`
- wire the graph edges explicitly

**Step 2: Teach the workflow engine the new node type**

Update workflow execution so:

- `DispatchRunnableNodes` can queue `prompt_compaction`
- `ExecuteNode` can execute `prompt_compaction`

The node executor should choose runtime-backed vs embedded execution according
to frozen policy and frozen request-preparation capability.

**Step 3: Hand compacted context to the successor turn step**

Persist an artifact such as:

- `artifact_kind = "prompt_compaction_context"`

and teach the successor `turn_step` to consume that artifact as its ephemeral
transcript source instead of the default snapshot transcript.

Do not rewrite durable transcript history in v1.

**Step 4: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/workflows/execute_node_test.rb \
  test/services/workflows/dispatch_runnable_nodes_test.rb
```

Expected: prompt compaction now fits the existing workflow graph and node
execution model.

### Task 7: Implement `PromptBudgetGuard` And Pre-Dispatch Gating

**Files:**
- Create: `core_matrix/app/services/provider_execution/prompt_budget_guard.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/test/services/provider_execution/prompt_budget_guard_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`

**Step 1: Implement the guard**

Add explicit constants, not magic numbers, for:

- reserve behavior
- heuristic safety buffers
- max compaction attempts
- max overflow-recovery attempts

The guard result should expose at least:

- `decision`
- `estimated_tokens`
- `estimator_strategy`
- `failure_scope`
- `retry_mode`
- diagnostics

**Step 2: Gate round execution before dispatch**

Update `ExecuteRoundLoop` so it:

- assembles the final provider-visible candidate
- runs `PromptBudgetGuard`
- dispatches only on `allow`
- routes `consult` into consultation
- routes `compact_required` into consultation followed by mandatory workflow
  insertion
- rejects explicitly on `reject`

At this stage, Core Matrix remains the sole authoritative preflight
decision-maker.

**Step 3: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb
```

Expected: pre-dispatch budget guarding is now authoritative.

### Task 8: Integrate Consultation, Workflow Insertion, And Bounded Recovery

**Files:**
- Modify: `core_matrix/app/services/provider_execution/execute_round_loop.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/provider_execution/request_preparation_exchange.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_prompt_compaction_yield.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_round_loop_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

**Step 1: Wire consultation**

When the guard says `consult` or `compact_required`:

- consult the runtime when request-preparation capability exists and policy
  allows it
- otherwise fall back to embedded baseline guidance

The consultation result may be:

- `skip`
- `compact`
- `reject`

**Step 2: Materialize workflow work**

If the final decision is `compact`, Core Matrix must:

- materialize a `prompt_compaction` workflow node
- materialize the successor `turn_step` at the same time
- carry budget diagnostics and preservation invariants into the node
- ensure execution happens through the workflow engine

The node may execute via:

- runtime-backed compaction
- embedded compaction

In both cases:

- artifacts and diagnostics must persist
- the successor `turn_step` must resume from the compaction artifact afterward

**Step 3: Add bounded overflow recovery**

Allow one explicit recovery loop when the provider still returns overflow:

1. classify overflow explicitly
2. re-enter compaction mode with `consultation_reason = "overflow_recovery"`
3. materialize another compaction node if needed
4. retry dispatch once

Stop after the hard attempt limit.

**Step 4: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: Core Matrix-assisted compaction is now workflow-backed and bounded.

### Task 9: Persist Explicit Failures, Remediation, And Degradation Diagnostics

**Files:**
- Modify: `core_matrix/app/services/provider_execution/failure_classification.rb`
- Modify: `core_matrix/app/services/provider_execution/execute_turn_step.rb`
- Modify: `core_matrix/app/services/provider_execution/persist_turn_step_failure.rb`
- Modify: `core_matrix/test/services/provider_execution/failure_classification_test.rb`
- Modify: `core_matrix/test/services/provider_execution/execute_turn_step_test.rb`

**Step 1: Classify prompt-size failures explicitly**

Map local and provider-side overflow signals into dedicated failure kinds:

- `prompt_too_large_for_retry`
- `context_window_exceeded_after_compaction`

Do not route these failures through `internal_unexpected_error`.

**Step 2: Persist remediation metadata**

Persist enough information for app-driven retry UX:

- whether the tail input is editable
- whether the user must send a new message
- whether failure is caused by current message alone or full context
- selected input message `public_id`
- whether runtime degraded to embedded compaction
- normalized runtime failure code when degradation occurred

**Step 3: Persist degradation diagnostics**

Ensure Fenix degradation is observable:

- `source = embedded`
- `fallback_used = true`
- `runtime_failure_code`

These must appear in persisted failure or artifact metadata, not just logs.

**Step 4: Run the targeted tests and make them green**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/failure_classification_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb
```

Expected: prompt-size failures are explicit, recoverable, and observable.

### Task 10: Verify The Subsystem End To End

**Step 1: Run focused subsystem verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
PARALLEL_WORKERS=1 bin/rails test \
  test/services/provider_execution/token_estimator_test.rb \
  test/services/provider_execution/prompt_budget_advisory_test.rb \
  test/services/provider_execution/prompt_compaction_strategy_test.rb \
  test/services/provider_execution/prompt_budget_guard_test.rb \
  test/services/provider_execution/execute_round_loop_test.rb \
  test/services/provider_execution/execute_turn_step_test.rb \
  test/services/provider_execution/failure_classification_test.rb \
  test/requests/agent_api/responses/input_tokens_test.rb
```

Then:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
PARALLEL_WORKERS=1 bin/rails test \
  test/integration/runtime_manifest_test.rb \
  test/services/runtime/execute_mailbox_item_test.rb \
  test/services/requests/consult_prompt_compaction_test.rb \
  test/services/requests/execute_prompt_compaction_test.rb \
  test/services/shared/control_plane/client_test.rb
```

**Step 2: Add and run deterministic tiny-context e2e coverage**

Create one end-to-end test path that forces compaction deterministically:

- use existing fake/mock provider adapters
- register a tiny test model definition with very small
  `context_window_tokens` and `max_output_tokens`
- drive:
  - `PrepareAgentRound`
  - budget guard
  - consultation
  - workflow node
  - re-entry
- assert workflow node, artifacts, degradation metadata, and failure payloads
  directly

Prefer this over real-LLM tests.

**Step 3: Run full `core_matrix` verification**

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

**Step 4: Run full `agents/fenix` verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros/agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails test
```

**Step 5: Run acceptance verification**

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

Inspect:

- acceptance artifacts relevant to turn failure handling and workflow
  transitions
- resulting database state for prompt-size failures, workflow nodes, artifacts,
  and degradation metadata

Expected: prompt-budget protection and Core Matrix-assisted compaction behave
correctly from draft construction through re-entry.
