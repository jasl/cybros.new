# Core Matrix Phase 2 Architecture Health Audit Follow-Up Findings

## Scope

- This is a whole-application audit of `core_matrix`.
- The primary review surfaces are `app/models`, `app/services`, `app/queries`,
  `app/controllers`, and `test`.
- The method is `six-boundary review + anti-pattern cross-check`.
- This work lands as a Milestone C follow-up.
- the frozen execution root shape is
  `Conversation -> Turn -> WorkflowRun -> WorkflowNode`
- current code volume is concentrated in:
  - `app/services` with `142` files
  - `app/models` with `59` files
  - `test/services` with `102` files
  - `test/models` with `55` files
  - `test/integration` with `34` files
- the heaviest service namespaces are:
  - `conversations` with `33` files
  - `agent_control` with `22` files
  - `workflows` with `13` files
  - `agent_deployments` with `11` files
  - `turns` with `11` files
- the six audit boundaries for this pass are:
  - conversation and lifecycle
  - workflow and execution graph
  - runtime control plane
  - runtime binding and deployments
  - provider and governance
  - read side and projection
- recent hardening work concentrated around close reconciliation, runtime
  binding, conversation mutation safety, and lineage or provenance contracts

## System Judgment

## Findings

## Simplification / Reinforcement Opportunities

## Top Structural Priorities

## Completeness Check

- architecture map captured from `app` and `test` namespace inventories
- hotspot inventory recorded from current file counts
- conversation and lifecycle boundary reviewed through
  `docs/behavior/conversation-structure-and-lineage.md`,
  `app/models/conversation.rb`, `app/services/conversations`, and
  `test/services/conversations`
- workflow and execution boundary reviewed through
  `docs/behavior/workflow-graph-foundations.md`,
  `docs/behavior/workflow-scheduler-and-wait-states.md`,
  `app/services/workflows`, and `test/services/workflows`
- runtime control-plane boundary reviewed through
  `docs/behavior/agent-runtime-resource-apis.md`,
  `app/services/agent_control`, `app/controllers/agent_api/control_controller.rb`,
  and `test/services/agent_control`
- runtime binding and deployment boundary reviewed through
  `app/models/execution_environment.rb`, `app/models/agent_deployment.rb`,
  `app/services/execution_environments`,
  `app/services/agent_deployments`,
  `app/services/runtime_capabilities`, and neighboring tests
- provider and governance boundary reviewed through
  `docs/behavior/provider-governance-models-and-services.md`,
  `app/services/provider_catalog`, `app/services/provider_execution`,
  `app/services/provider_credentials`, `app/services/provider_entitlements`,
  `app/services/provider_policies`, `app/services/providers`, and neighboring
  tests
- read-side and projection boundary reviewed through `app/queries`,
  `app/controllers/agent_api`, `test/queries`, and `test/requests/agent_api`
- candidate issues from these three boundaries are collected in local scratch
  and still pending cross-check before promotion
- findings, opportunities, and system judgment are still pending the
  anti-pattern pass and final promotion review
