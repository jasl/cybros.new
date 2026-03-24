# Core Matrix Structured JSON Contracts Research Note

## Status

Recorded research only. No adoption is approved for the current `core_matrix`
implementation phase.

## Decision Summary

- Do not introduce `store_model` in the current phase.
- Keep current `jsonb` handling lightweight until a field proves a stable,
  named contract.
- Revisit `easy_talk` before `store_model` if a future task needs one schema
  definition to drive both runtime validation and JSON Schema output.
- Treat `references/` and external repositories as supporting material only.
  The reasoning that matters should live in this note.

## Current `jsonb` Surface in `core_matrix`

As of this note, the current JSON-backed fields fall into several distinct
categories:

- settings or preference placeholders: `Installation#global_settings`,
  `User#preferences`, `UserAgentBinding#preferences`
- open-ended metadata: `Identity#auth_metadata`, `Session#metadata`,
  `AuditLog#metadata`, `ExecutionEnvironment#connection_metadata`,
  `AgentDeployment#endpoint_metadata`, `AgentDeployment#health_metadata`
- protocol and capability snapshots: `CapabilitySnapshot#protocol_methods`,
  `CapabilitySnapshot#tool_catalog`,
  `CapabilitySnapshot#config_schema_snapshot`,
  `CapabilitySnapshot#conversation_override_schema_snapshot`,
  `CapabilitySnapshot#default_config_snapshot`

Those categories should not be forced into one abstraction prematurely.
Snapshot and transport metadata should stay flexible until the product proves a
stable contract shape.

## Why `store_model` Is Deferred

`store_model` is still a plausible fit for stable JSON-backed value objects
inside one row, especially when the application needs:

- typed readers and writers
- enum-like accessors
- nested value objects
- ActiveModel-style validations around a long-lived shape

That makes it a possible future fit for fields such as:

- `Installation#global_settings`
- `User#preferences`
- `UserAgentBinding#preferences`

It is not a good fit yet for most current `core_matrix` JSONB usage because:

- most current fields are still metadata bags or protocol snapshots
- wrapping them now would harden shapes before the product has earned them
- nested dirty-tracking complexity is only worth paying once repeated business
  logic exists around a stable structure
- any adoption should first verify behavior against the project's current
  Rails 8.2 alpha baseline instead of assuming gem compatibility from older
  Rails versions

## Why `easy_talk` Is Worth Re-Evaluating Later

`easy_talk` is a better candidate when the schema itself needs to become a
first-class artifact. Its useful shape for future Core Matrix work is:

- define one Ruby-side contract
- generate JSON Schema from that same definition
- optionally run runtime validation from the same source
- keep nested structures and reusable definitions explicit

That makes it a stronger future candidate if Core Matrix later needs:

- schema-driven settings editors
- machine-facing config contracts
- reusable protocol or configuration documents
- exported schemas for external consumers or tooling
- one source of truth for both validation and schema publication

## Recorded Findings From The Tavern Kit Reference

The Tavern Kit playground reference is useful because it demonstrates a
schema-first settings system built around `easy_talk`. The useful patterns are:

- a shared base layer wraps the schema DSL and adds product-specific extension
  points such as UI metadata and storage mapping metadata
- nested schemas are explicitly registered and composed into a single root
  schema instead of being left as ad hoc nested hashes
- the root schema acts as the pack entry point and publishes an explicit schema
  version and schema identifier
- per-field UI hints are attached at the schema layer, which makes form
  generation or configuration editors easier later
- storage hints can live beside the same schema definition, which keeps mapping
  logic discoverable

These patterns are more important than the exact Tavern Kit implementation.
If Core Matrix ever adopts this direction, the target should be a small,
product-specific schema layer, not a direct copy.

## Practical Adoption Rule

Do not introduce `store_model` or `easy_talk` just to make JSON fields look
more structured.

Adopt one only when a future task selects a concrete field or contract and can
show at least one of these needs:

- a stable nested structure with repeated domain logic
- shared validation rules used in more than one code path
- a need to export JSON Schema or other machine-readable contract output
- a future UI or API surface that benefits from schema metadata

## Re-Evaluation Triggers

Re-open this note when one of the following happens:

- `global_settings` becomes a real installation configuration object instead of
  a loose hash
- user or binding preferences gain stable nested sections and repeated
  validation rules
- protocol/config publication requires JSON Schema as an explicit output
- a settings UI needs field metadata, grouping, or schema-driven rendering

## Adoption Guardrails

If a future task revisits either library, evaluate in this order:

- identify one concrete field or contract instead of introducing a generic
  abstraction layer first
- verify the library against the current project Ruby and Rails baseline,
  especially Rails 8.2 alpha behavior
- prove the chosen field benefits from the abstraction with real validation,
  schema, or type pressure
- keep the initial rollout narrow so reversal stays cheap if the fit is wrong

## Reference Index

These references were useful during the investigation, but they are not the
source of truth for Core Matrix behavior and their current state may drift.

External upstream references:

- [DmitryTsepelev/store_model](https://github.com/DmitryTsepelev/store_model)
- [sergiobayona/easy_talk](https://github.com/sergiobayona/easy_talk)

Local monorepo reference paths:

- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/tavern_kit/playground/app/models/conversation_settings/base.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/tavern_kit/playground/app/models/conversation_settings/base.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/tavern_kit/playground/app/models/conversation_settings/root_schema.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/tavern_kit/playground/app/models/conversation_settings/root_schema.rb)
- [/Users/jasl/Workspaces/Ruby/cybros/references/original/references/tavern_kit/playground/app/models/conversation_settings/preset_settings.rb](/Users/jasl/Workspaces/Ruby/cybros/references/original/references/tavern_kit/playground/app/models/conversation_settings/preset_settings.rb)
