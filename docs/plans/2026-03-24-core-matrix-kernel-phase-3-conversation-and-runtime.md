# Core Matrix Kernel Phase 3: Conversation And Runtime

Use this phase document together with:

1. `AGENTS.md`
2. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-design.md`
3. `docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
4. `docs/plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
5. `docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

This phase owns Tasks 7-10:

- conversation tree, turn core, interactive selector state, variant selection, and archive lifecycle
- transcript support models for attachments, imports, summaries, and visibility
- workflow core, context assembly, scheduling rules, and resolved model-selection snapshots
- execution resources, event streams, human-interaction requests, canonical variables, and lease control

Apply the shared guardrails and phase-gate audits from the implementation-plan index.

---
### Task 7: Rebuild Conversation Tree, Turn Core, And Variant Selection

**Files:**
- Create: `core_matrix/db/migrate/20260324090019_create_conversations.rb`
- Create: `core_matrix/db/migrate/20260324090020_create_conversation_closures.rb`
- Create: `core_matrix/db/migrate/20260324090021_create_turns.rb`
- Create: `core_matrix/db/migrate/20260324090022_create_messages.rb`
- Create: `core_matrix/db/migrate/20260324090023_add_turn_message_foreign_keys.rb`
- Create: `core_matrix/app/models/conversation.rb`
- Create: `core_matrix/app/models/conversation_closure.rb`
- Create: `core_matrix/app/models/turn.rb`
- Create: `core_matrix/app/models/message.rb`
- Create: `core_matrix/app/models/user_message.rb`
- Create: `core_matrix/app/models/agent_message.rb`
- Create: `core_matrix/app/services/conversations/create_root.rb`
- Create: `core_matrix/app/services/conversations/create_branch.rb`
- Create: `core_matrix/app/services/conversations/create_thread.rb`
- Create: `core_matrix/app/services/conversations/create_checkpoint.rb`
- Create: `core_matrix/app/services/conversations/archive.rb`
- Create: `core_matrix/app/services/conversations/unarchive.rb`
- Create: `core_matrix/app/services/conversations/rollback_to_turn.rb`
- Create: `core_matrix/app/services/conversations/update_override.rb`
- Create: `core_matrix/app/services/turns/start_user_turn.rb`
- Create: `core_matrix/app/services/turns/edit_tail_input.rb`
- Create: `core_matrix/app/services/turns/queue_follow_up.rb`
- Create: `core_matrix/app/services/turns/retry_output.rb`
- Create: `core_matrix/app/services/turns/rerun_output.rb`
- Create: `core_matrix/app/services/turns/select_output_variant.rb`
- Create: `core_matrix/app/services/turns/steer_current_input.rb`
- Create: `core_matrix/test/models/conversation_test.rb`
- Create: `core_matrix/test/models/conversation_closure_test.rb`
- Create: `core_matrix/test/models/turn_test.rb`
- Create: `core_matrix/test/models/message_test.rb`
- Create: `core_matrix/test/models/user_message_test.rb`
- Create: `core_matrix/test/models/agent_message_test.rb`
- Create: `core_matrix/test/services/conversations/create_root_test.rb`
- Create: `core_matrix/test/services/conversations/create_branch_test.rb`
- Create: `core_matrix/test/services/conversations/create_thread_test.rb`
- Create: `core_matrix/test/services/conversations/create_checkpoint_test.rb`
- Create: `core_matrix/test/services/conversations/archive_test.rb`
- Create: `core_matrix/test/services/conversations/unarchive_test.rb`
- Create: `core_matrix/test/services/conversations/rollback_to_turn_test.rb`
- Create: `core_matrix/test/services/conversations/update_override_test.rb`
- Create: `core_matrix/test/services/turns/start_user_turn_test.rb`
- Create: `core_matrix/test/services/turns/edit_tail_input_test.rb`
- Create: `core_matrix/test/services/turns/queue_follow_up_test.rb`
- Create: `core_matrix/test/services/turns/retry_output_test.rb`
- Create: `core_matrix/test/services/turns/rerun_output_test.rb`
- Create: `core_matrix/test/services/turns/select_output_variant_test.rb`
- Create: `core_matrix/test/services/turns/steer_current_input_test.rb`
- Create: `core_matrix/test/integration/conversation_turn_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- conversation belongs to workspace, not directly to agent
- closure-table integrity
- conversation kind rules for `root`, `branch`, `thread`, and `checkpoint`
- conversation lifecycle state rules for `active` and `archived`
- conversation interactive selector modes `auto | explicit candidate`
- `auto` normalizing to `role:main` for the interactive path
- historical-anchor requirements for branch and checkpoint creation
- turn sequence uniqueness within one conversation
- queued versus active versus terminal turn states
- message role, slot, and variant semantics
- message STI restricted to transcript-bearing subclasses only
- selected input and output pointers
- tail input edit creating a new selected input variant without historical row mutation
- retry versus rerun semantics for assistant output variants
- swipe or variant selection legality for tail versus non-tail assistant output
- backtrack or rollback semantics for historical user-message editing without row mutation
- persisted conversation override payload and schema-fingerprint tracking
- interactive selector persistence independent from deployment-level internal slots
- steering blocked after the first side-effecting workflow node completes
- runtime pinning columns on turns for deployment, capability snapshots, and resolved model-selection snapshots

**Step 2: Write a failing integration flow test**

`conversation_turn_flow_test.rb` should cover:

- root conversation creation
- historical branch creation without transcript copying
- thread and checkpoint creation with correct lineage
- archiving and unarchiving a conversation without mutating transcript history
- storing `auto` as the default interactive selector and allowing an explicit `provider_handle/model_ref` selector
- persisting a conversation override and freezing it onto the created turn snapshot
- editing the selected tail user input by creating a replacement input variant and resetting dependent output state
- editing a historical user message through rollback or fork semantics rather than in-place mutation
- active turn creation
- retrying a failed assistant output within the same turn
- rerunning a non-tail finished assistant output by auto-branching
- selecting a different tail output variant and rejecting the same action on non-tail history
- queued follow-up while another turn is active
- steering the active input before side effects

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/services/conversations/rollback_to_turn_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/services/turns/steer_current_input_test.rb test/integration/conversation_turn_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- no direct `conversation.agent_id` shortcut
- conversation rows must carry kind, parent lineage, optional historical anchor, and persisted override payload
- conversation rows must also carry the user-visible interactive selector in `auto | explicit candidate` form
- conversation lifecycle state must be modeled separately from kind
- store selected input and output message pointers on the turn
- keep explicit version-set semantics for input and output variants
- keep turn history append-only
- do not add a server-side unsent composer draft model in v1
- use `Message` STI only for transcript-bearing subclasses; non-transcript visible runtime state belongs in `ConversationEvent` or other runtime resources
- branch and checkpoint creation must preserve lineage without copying transcript rows
- thread creation must keep separate timeline identity and must not imply transcript cloning
- archived conversations must reject new turns and queue mutations until unarchived
- selected tail user input editing must create a new input variant and reset dependent output state, never mutate the historical row in place
- historical user-message editing must resolve through rollback or fork semantics, never direct row mutation
- retry must target failed or unfinished assistant output and create a new output variant in the same turn
- rerun must target finished assistant output; non-tail rerun auto-branches before execution
- selecting a different output variant is tail-only in the current timeline and must reject queued or in-flight variants
- pin deployment fingerprint, resolved config snapshot, and resolved model-selection snapshot on the executing turn

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_test.rb test/models/conversation_closure_test.rb test/models/turn_test.rb test/models/message_test.rb test/models/user_message_test.rb test/models/agent_message_test.rb test/services/conversations/create_root_test.rb test/services/conversations/create_branch_test.rb test/services/conversations/create_thread_test.rb test/services/conversations/create_checkpoint_test.rb test/services/conversations/archive_test.rb test/services/conversations/unarchive_test.rb test/services/conversations/rollback_to_turn_test.rb test/services/conversations/update_override_test.rb test/services/turns/start_user_turn_test.rb test/services/turns/edit_tail_input_test.rb test/services/turns/queue_follow_up_test.rb test/services/turns/retry_output_test.rb test/services/turns/rerun_output_test.rb test/services/turns/select_output_variant_test.rb test/services/turns/steer_current_input_test.rb test/integration/conversation_turn_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/conversations core_matrix/app/services/turns core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: rebuild conversation tree and turn foundations"
```

### Task 8: Add Transcript Support Models For Attachments, Imports, Summaries, And Visibility

**Files:**
- Create: `core_matrix/db/migrate/20260324090024_create_conversation_message_visibilities.rb`
- Create: `core_matrix/db/migrate/20260324090025_create_message_attachments.rb`
- Create: `core_matrix/db/migrate/20260324090026_create_conversation_imports.rb`
- Create: `core_matrix/db/migrate/20260324090027_create_conversation_summary_segments.rb`
- Create: `core_matrix/app/models/conversation_message_visibility.rb`
- Create: `core_matrix/app/models/message_attachment.rb`
- Create: `core_matrix/app/models/conversation_import.rb`
- Create: `core_matrix/app/models/conversation_summary_segment.rb`
- Create: `core_matrix/app/services/messages/update_visibility.rb`
- Create: `core_matrix/app/services/attachments/materialize_refs.rb`
- Create: `core_matrix/app/services/conversations/add_import.rb`
- Create: `core_matrix/app/services/conversation_summaries/create_segment.rb`
- Create: `core_matrix/test/models/conversation_message_visibility_test.rb`
- Create: `core_matrix/test/models/message_attachment_test.rb`
- Create: `core_matrix/test/models/conversation_import_test.rb`
- Create: `core_matrix/test/models/conversation_summary_segment_test.rb`
- Create: `core_matrix/test/services/messages/update_visibility_test.rb`
- Create: `core_matrix/test/services/attachments/materialize_refs_test.rb`
- Create: `core_matrix/test/services/conversations/add_import_test.rb`
- Create: `core_matrix/test/services/conversation_summaries/create_segment_test.rb`
- Create: `core_matrix/test/integration/transcript_support_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- soft delete and context exclusion through overlay rows
- attachment ancestry and origin pointers
- attachment visibility inheriting from the parent message instead of a separate attachment overlay model
- import kinds `branch_prefix`, `merge_summary`, and `quoted_context`
- summary segment replacement and supersession
- rollback behind a compaction boundary preserving earlier compacted history and dropping only superseded post-rollback state
- fork-point protection for soft delete and other rewriting operations
- Active Storage attachment presence for file-bearing attachment rows

**Step 2: Write a failing integration flow test**

`transcript_support_flow_test.rb` should cover:

- branching from a historical message and creating a `branch_prefix` import
- creating a checkpoint view of history without leaking hidden messages
- materializing reusable attachment references into a new turn
- confirming hidden or excluded message attachments do not appear in checkpoint or branch-derived transcript support projections
- creating a summary segment and importing it back as context
- rolling back behind a summary compaction without losing preserved earlier context
- excluding a message from context without deleting the immutable message row

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/integration/transcript_support_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- keep transcript rows immutable
- use overlay rows for mutable visibility
- use `has_one_attached` on `MessageAttachment`
- keep attachment visibility and context inclusion derived from the parent message in v1
- hidden transcript content must stay out of branch and checkpoint replay surfaces
- rollback must preserve valid summary segments or imports that still describe retained history while dropping superseded post-rollback context
- fork-point messages are not soft-deletable or otherwise rewritable
- never copy full transcript history into branch conversations

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/conversation_message_visibility_test.rb test/models/message_attachment_test.rb test/models/conversation_import_test.rb test/models/conversation_summary_segment_test.rb test/services/messages/update_visibility_test.rb test/services/attachments/materialize_refs_test.rb test/services/conversations/add_import_test.rb test/services/conversation_summaries/create_segment_test.rb test/integration/transcript_support_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/messages core_matrix/app/services/attachments core_matrix/app/services/conversations core_matrix/app/services/conversation_summaries core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add transcript support models"
```

### Task 9: Rebuild Workflow Core, Context Assembly, And Scheduling Rules

**Files:**
- Create: `core_matrix/db/migrate/20260324090028_create_workflow_runs.rb`
- Create: `core_matrix/db/migrate/20260324090029_create_workflow_nodes.rb`
- Create: `core_matrix/db/migrate/20260324090030_create_workflow_edges.rb`
- Create: `core_matrix/app/models/workflow_run.rb`
- Create: `core_matrix/app/models/workflow_node.rb`
- Create: `core_matrix/app/models/workflow_edge.rb`
- Create: `core_matrix/app/services/workflows/create_for_turn.rb`
- Create: `core_matrix/app/services/workflows/mutate.rb`
- Create: `core_matrix/app/services/workflows/scheduler.rb`
- Create: `core_matrix/app/services/workflows/context_assembler.rb`
- Create: `core_matrix/app/services/workflows/resolve_model_selector.rb`
- Create: `core_matrix/test/models/workflow_run_test.rb`
- Create: `core_matrix/test/models/workflow_node_test.rb`
- Create: `core_matrix/test/models/workflow_edge_test.rb`
- Create: `core_matrix/test/services/workflows/create_for_turn_test.rb`
- Create: `core_matrix/test/services/workflows/mutate_test.rb`
- Create: `core_matrix/test/services/workflows/scheduler_test.rb`
- Create: `core_matrix/test/services/workflows/context_assembler_test.rb`
- Create: `core_matrix/test/services/workflows/resolve_model_selector_test.rb`
- Create: `core_matrix/test/integration/workflow_core_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- one active workflow per conversation in v1
- one workflow per turn
- workflow node ordinal uniqueness
- workflow node decision-source enum for `llm`, `agent_program`, `system`, and `user`
- workflow node metadata carrying explicit policy-sensitive markers when needed for audit decisions
- edge ordering and same-workflow integrity
- selector normalization to `role:*` and `candidate:*`
- the reserved interactive path falling back to `role:main` when no more specific selector is present
- role-local fallback only within the current role's ordered candidate list
- explicit candidate selection rejecting fallback to unrelated models
- execution-time entitlement reservation causing fallback only to the next candidate in the same role list
- resolved model-selection snapshot fields on the executing turn or workflow
- context assembly from base rules, active imports, transcript tail, selected workflow outputs, and eligible attachment manifests
- execution-context identity fields for agent code, including `user_id`, `workspace_id`, `conversation_id`, and `turn_id`
- during-generation policy semantics for `reject`, `restart`, and `queue`
- expected-tail guards that skip or cancel stale queued work before execution
- steering after the first side-effect boundary becomes queued follow-up or restart behavior instead of mutating already-sent work
- capability-gated attachment prompt projection based on the turn's pinned provider or model snapshot
- hidden, excluded, or branch-ineligible attachments never appearing in runtime manifests or model input blocks
- unsupported attachments remaining available to runtime preparation without being serialized as if the model received them
- non-transcript `ConversationEvent` rows never entering canonical transcript context assembly by default
- scheduler selecting runnable nodes without executing side effects

**Step 2: Write a failing integration flow test**

`workflow_core_flow_test.rb` should cover:

- creating a workflow for a turn
- mutating nodes and edges
- ensuring only one active workflow exists for the conversation
- preserving workflow-node decision-source and policy metadata used later by execution and audit services
- resolving `auto` to `role:main`, choosing the first available role candidate, and freezing the resolved provider or model on the execution snapshot
- falling through to the next candidate when entitlement reservation fails for the first role-based choice
- rejecting implicit fallback when the selector is one explicit candidate
- assembling context that includes imports, summary artifacts, and capability-gated attachment prompt blocks without walking a global graph
- exposing the current `user_id`, `workspace_id`, `conversation_id`, and `turn_id` in the assembled execution context
- proving unsupported attachments are omitted from model input projection while remaining available in the runtime attachment manifest
- proving queued stale work is skipped after the conversation tail changes

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/services/workflows/scheduler_test.rb test/services/workflows/context_assembler_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_core_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- workflow resources remain subordinate to the workflow
- workflow nodes must persist explicit `decision_source` values and structured metadata needed by downstream execution, profiling, and audit services
- model selection should resolve through one explicit service boundary such as `workflows/resolve_model_selector`
- model selectors must normalize to `role:*` or `candidate:*`
- the reserved interactive path should fall back to `role:main`
- fallback is only allowed inside the ordered candidate list of the selected role
- execution-time entitlement reservation must happen before finalizing the selected candidate on the snapshot
- explicit candidate selection must fail immediately when unavailable instead of guessing another model
- resolved model snapshots should retain selector source, normalized selector, resolved provider, resolved model, resolution reason, and fallback count
- context assembly must not depend on a global conversation DAG
- context assembly must freeze a canonical attachment manifest for the executing turn or workflow and derive both runtime and model-facing projections from it
- attachment prompt projection must be capability-gated by pinned catalog metadata rather than the latest mutable catalog state
- context assembly must record explicit diagnostic events when attachment preparation or prompt projection is skipped or degraded
- context assembly must draw from transcript-bearing messages and approved support rows, not from `ConversationEvent` projections by default
- context assembly must expose stable ownership identity fields so agent code can reason about the current user, workspace, conversation, and turn without scraping transcript text
- scheduler must enforce `reject`, `restart`, and `queue` semantics deterministically
- queued work must fail safe when its expected-tail guard no longer matches
- scheduler determines runnable work only; it does not execute side effects

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_run_test.rb test/models/workflow_node_test.rb test/models/workflow_edge_test.rb test/services/workflows/create_for_turn_test.rb test/services/workflows/mutate_test.rb test/services/workflows/scheduler_test.rb test/services/workflows/context_assembler_test.rb test/services/workflows/resolve_model_selector_test.rb test/integration/workflow_core_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/workflows core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: rebuild workflow core"
```

### Task 10: Add Execution Resources, Conversation Events, Human Interactions, Canonical Variables, And Lease Control

**Files:**
- Create: `core_matrix/db/migrate/20260324090031_create_workflow_artifacts.rb`
- Create: `core_matrix/db/migrate/20260324090032_create_workflow_node_events.rb`
- Create: `core_matrix/db/migrate/20260324090033_create_process_runs.rb`
- Create: `core_matrix/db/migrate/20260324090034_create_subagent_runs.rb`
- Create: `core_matrix/db/migrate/20260324090035_create_human_interaction_requests.rb`
- Create: `core_matrix/db/migrate/20260324090036_create_canonical_variables.rb`
- Create: `core_matrix/db/migrate/20260324090037_create_conversation_events.rb`
- Create: `core_matrix/db/migrate/20260324090038_create_execution_leases.rb`
- Create: `core_matrix/app/models/workflow_artifact.rb`
- Create: `core_matrix/app/models/workflow_node_event.rb`
- Create: `core_matrix/app/models/process_run.rb`
- Create: `core_matrix/app/models/subagent_run.rb`
- Create: `core_matrix/app/models/human_interaction_request.rb`
- Create: `core_matrix/app/models/approval_request.rb`
- Create: `core_matrix/app/models/human_form_request.rb`
- Create: `core_matrix/app/models/human_task_request.rb`
- Create: `core_matrix/app/models/canonical_variable.rb`
- Create: `core_matrix/app/models/conversation_event.rb`
- Create: `core_matrix/app/models/execution_lease.rb`
- Create: `core_matrix/app/services/processes/start.rb`
- Create: `core_matrix/app/services/processes/stop.rb`
- Create: `core_matrix/app/services/subagents/spawn.rb`
- Create: `core_matrix/app/services/human_interactions/request.rb`
- Create: `core_matrix/app/services/human_interactions/resolve_approval.rb`
- Create: `core_matrix/app/services/human_interactions/submit_form.rb`
- Create: `core_matrix/app/services/human_interactions/complete_task.rb`
- Create: `core_matrix/app/services/conversation_events/project.rb`
- Create: `core_matrix/app/services/variables/write.rb`
- Create: `core_matrix/app/services/variables/promote_to_workspace.rb`
- Create: `core_matrix/app/services/leases/acquire.rb`
- Create: `core_matrix/app/services/leases/heartbeat.rb`
- Create: `core_matrix/app/services/leases/release.rb`
- Create: `core_matrix/test/models/workflow_artifact_test.rb`
- Create: `core_matrix/test/models/workflow_node_event_test.rb`
- Create: `core_matrix/test/models/process_run_test.rb`
- Create: `core_matrix/test/models/subagent_run_test.rb`
- Create: `core_matrix/test/models/human_interaction_request_test.rb`
- Create: `core_matrix/test/models/approval_request_test.rb`
- Create: `core_matrix/test/models/human_form_request_test.rb`
- Create: `core_matrix/test/models/human_task_request_test.rb`
- Create: `core_matrix/test/models/canonical_variable_test.rb`
- Create: `core_matrix/test/models/conversation_event_test.rb`
- Create: `core_matrix/test/models/execution_lease_test.rb`
- Create: `core_matrix/test/services/processes/start_test.rb`
- Create: `core_matrix/test/services/processes/stop_test.rb`
- Create: `core_matrix/test/services/subagents/spawn_test.rb`
- Create: `core_matrix/test/services/human_interactions/request_test.rb`
- Create: `core_matrix/test/services/human_interactions/resolve_approval_test.rb`
- Create: `core_matrix/test/services/human_interactions/submit_form_test.rb`
- Create: `core_matrix/test/services/human_interactions/complete_task_test.rb`
- Create: `core_matrix/test/services/conversation_events/project_test.rb`
- Create: `core_matrix/test/services/variables/write_test.rb`
- Create: `core_matrix/test/services/variables/promote_to_workspace_test.rb`
- Create: `core_matrix/test/services/leases/acquire_test.rb`
- Create: `core_matrix/test/services/leases/heartbeat_test.rb`
- Create: `core_matrix/test/services/leases/release_test.rb`
- Create: `core_matrix/test/integration/runtime_resource_flow_test.rb`

**Step 1: Write failing unit tests**

Cover at least:

- artifact storage mode behavior
- workflow node events for live output and status replay
- `ProcessRun` kinds `turn_command` and `background_service`
- `ProcessRun` ownership by workflow node and execution environment
- redundant `conversation_id` and `turn_id` query fields on `ProcessRun`
- originating-message association for user-visible process runs
- timeout required for bounded turn commands
- timeout forbidden for background services
- `ConversationEvent` append-only projection rules and separation from transcript-bearing `Message` rows
- `ConversationEvent` stable per-conversation ordering and optional turn anchoring for live projection
- `HumanInteractionRequest` STI legality and ownership by workflow node, turn, and conversation
- approval scope and transition rules
- form submission validation and timeout behavior
- task-request completion semantics and queryable open state
- canonical variable scope rules for `workspace` and `conversation`
- canonical variable supersession history and explicit promotion from conversation to workspace
- lease uniqueness, heartbeat freshness, and release semantics
- audit rows for policy-sensitive process execution

**Step 2: Write a failing integration flow test**

`runtime_resource_flow_test.rb` should cover:

- starting a short-lived `turn_command` process under workflow ownership
- starting a long-lived `background_service` process under workflow ownership
- recording the execution environment, originating message, and denormalized turn or conversation references
- emitting stdout or stderr node events without mutating transcript rows
- writing audit rows when a process run is flagged as policy-sensitive by workflow metadata
- opening and resolving an approval gate
- opening a blocking form request, submitting structured input, and resuming the workflow with workflow-local output state
- opening a human task request and recording a completion payload
- projecting visible conversation events for blocking human interaction lifecycle changes without creating transcript `Message` rows and preserving stable projection order
- writing a conversation-scope canonical variable and promoting it to workspace scope with preserved history
- spawning a subagent run
- acquiring, heartbeating, and releasing an execution lease

**Step 3: Run the targeted tests to confirm failure**

Run:

```bash
cd core_matrix
bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/models/subagent_run_test.rb test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/canonical_variable_test.rb test/models/conversation_event_test.rb test/models/execution_lease_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/services/subagents/spawn_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/runtime_resource_flow_test.rb
```

Expected:

- missing table and model failures

**Step 4: Write migrations, models, and services**

Rules:

- kernel owns durable side effects
- live output is modeled as workflow node events, not transcript mutation
- `ProcessRun` must belong to both `WorkflowNode` and `ExecutionEnvironment`
- `ProcessRun` must redundantly persist `conversation_id` and `turn_id` for operational querying
- user-visible process runs must retain an originating message reference
- `turn_command` and `background_service` must remain explicit kind values for filtering and lifecycle rules
- background services are explicit first-class runtime resources
- policy-sensitive process execution must create audit rows when the workflow node or service input marks it as such
- `HumanInteractionRequest` is the workflow-owned source of truth for approvals, forms, and human-task pauses
- `ConversationEvent` is append-only projection state and must not be reused as transcript-bearing `Message`
- `ConversationEvent` must persist deterministic projection-order metadata plus an optional turn anchor so live projection queries can merge events consistently
- blocking human interactions must pause workflow progress until they resolve, cancel, or time out
- human-interaction outcomes must write structured results into workflow-local state before resumption
- canonical variables must support only `workspace` and `conversation` scope in v1
- canonical variable writes supersede prior current values without deleting history
- conversation-scope canonical values may be explicitly promoted to workspace scope

**Step 5: Run migrations and targeted tests**

Run:

```bash
cd core_matrix
bin/rails db:migrate
bin/rails test test/models/workflow_artifact_test.rb test/models/workflow_node_event_test.rb test/models/process_run_test.rb test/models/subagent_run_test.rb test/models/human_interaction_request_test.rb test/models/approval_request_test.rb test/models/human_form_request_test.rb test/models/human_task_request_test.rb test/models/canonical_variable_test.rb test/models/conversation_event_test.rb test/models/execution_lease_test.rb test/services/processes/start_test.rb test/services/processes/stop_test.rb test/services/subagents/spawn_test.rb test/services/human_interactions/request_test.rb test/services/human_interactions/resolve_approval_test.rb test/services/human_interactions/submit_form_test.rb test/services/human_interactions/complete_task_test.rb test/services/conversation_events/project_test.rb test/services/variables/write_test.rb test/services/variables/promote_to_workspace_test.rb test/services/leases/acquire_test.rb test/services/leases/heartbeat_test.rb test/services/leases/release_test.rb test/integration/runtime_resource_flow_test.rb
```

Expected:

- targeted tests pass

**Step 6: Commit**

```bash
git -C .. add core_matrix/db/migrate core_matrix/app/models core_matrix/app/services/processes core_matrix/app/services/subagents core_matrix/app/services/human_interactions core_matrix/app/services/conversation_events core_matrix/app/services/variables core_matrix/app/services/leases core_matrix/test/models core_matrix/test/services core_matrix/test/integration core_matrix/db/schema.rb
git -C .. commit -m "feat: add runtime interaction and canonical variable resources"
```
