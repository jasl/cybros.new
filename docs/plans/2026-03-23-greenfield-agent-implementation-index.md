# Greenfield Agent Implementation Index

Use these documents in this order during backend-only implementation inside `core_matrix`:

1. [Greenfield Agent Architecture Design](./2026-03-23-greenfield-agent-conversation-tree-turn-dag-design.md)
   - read first
   - source of truth for domain boundaries, invariants, safety rules, and capability coverage

2. [Greenfield Agent Rails Bootstrap Plan](./2026-03-23-greenfield-agent-rails-bootstrap.md)
   - read second
   - source of truth for `core_matrix` baseline preparation, project structure, migration sequencing, and phase ordering

3. [Greenfield Agent V1 Backend Blueprint](./2026-03-23-greenfield-agent-v1-backend-blueprint.md)
   - read third
   - source of truth for concrete migration code, model code, and backend-first test inventory

Companion follow-up document:

- [CoreMatrix Agent UI And Runtime Follow-Up](./2026-03-23-core-matrix-agent-ui-runtime-follow-up.md)
  - do not use during the backend-only implementation slice
  - use only after the backend foundation is complete and the UI/runtime framework decisions are finalized

Implementation order:

1. prepare the existing `core_matrix` baseline
2. verify Active Storage is installed and the backend skeleton directories exist
3. verify the current repo baseline commands are green enough to start backend work
4. generate all models and migrations inside `core_matrix`
5. edit migrations before the first schema-changing `db:prepare`
6. run database setup
7. add model concerns and model files
8. add test support builders and backend test scaffolding
9. implement the first conversation/tree services
10. implement workflow mutation and scheduling
11. implement process/subagent control-plane services
12. implement projections and secondary backend features
13. stop before controllers, Action Cable, views, JavaScript UI work, job orchestration, or runtime adapters

Context-control rule:

- do not load all three long documents into one implementation step unless the step genuinely spans architecture, schema, and tests
- for migration work, load documents 2 and 3
- for model work, load documents 1 and 3
- for service work, load documents 1 and 2 first, then only the relevant section of document 3
- for deferred controller/UI/runtime work, switch to the follow-up document instead of stretching the backend docs beyond their current scope
