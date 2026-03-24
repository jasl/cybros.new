# Execution Profiling Facts

## Purpose

Task 06.2 adds execution-profile facts as a telemetry surface that stays
separate from provider billing and usage accounting. These rows answer runtime
questions about how work executed, not how providers billed for it.

## Fact Behavior

- `ExecutionProfileFact` records one execution telemetry fact at a point in
  time.
- Facts support generic profiling kinds for:
  - tool calls
  - subagent outcomes
  - approval wait intervals
  - process failures
- Facts can attach to installation-owned dimensions already present in this
  phase, including user and workspace.
- Facts also preserve nullable generic runtime references for later milestone
  roots:
  - `conversation_id`
  - `turn_id`
  - `workflow_node_key`
  - `process_run_id`
  - `subagent_run_id`
  - `human_interaction_request_id`
- Runtime reference columns are stored as loose scalar identifiers instead of
  future foreign keys so later runtime tables can land without forcing a schema
  redesign in this phase.
- `fact_key` keeps the concrete discriminator inside a generic fact kind, such
  as a tool identifier, subagent role, approval gate key, or process label.
- `count_value`, `duration_ms`, and `success` remain optional because different
  fact kinds project different telemetry shapes.
- `metadata` stores structured detail for a fact and must remain a hash.

## Recording Behavior

- `ExecutionProfiling::RecordFact` is the explicit write boundary for execution
  profiling facts.
- Recording a profiling fact creates an `ExecutionProfileFact` row only.
- Recording a profiling fact does not create or mutate `UsageEvent` or
  `UsageRollup` rows.

## Invariants

- execution profiling remains a separate telemetry surface from provider usage
  accounting
- profiling facts may later join with usage data for analysis, but they are not
  modeled as provider billing rows
- this task does not hard-couple to future runtime-resource tables from
  Milestone 3
- cross-installation user and workspace references are rejected

## Failure Modes

- malformed or missing fact kinds are rejected
- missing `fact_key` or `occurred_at` is rejected
- negative `count_value` or `duration_ms` is rejected
- non-hash `metadata` is rejected
- cross-installation user or workspace references are rejected

## Reference Sanity Check

The retained conclusion from the consulted OpenClaw changelog slices is narrow:
runtime lifecycle events and usage accounting evolve as separate concerns, even
when they can later be analyzed together.

Core Matrix keeps that same separation by storing operational execution
telemetry in `ExecutionProfileFact` rows while leaving provider billing facts in
`UsageEvent` and `UsageRollup`.
