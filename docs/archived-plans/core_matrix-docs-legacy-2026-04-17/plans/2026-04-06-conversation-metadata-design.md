# Conversation Metadata Design

## Goal

Make conversation list metadata a first-class `Conversation` concern inside
`core_matrix`, with:

- fast CoreMatrix-owned bootstrap title generation after the first user message
- optional future `summary` support for heavier supervision/task views
- field-level user locking semantics
- explicit agent-driven metadata updates without workflow intents
- one unified CoreMatrix provider boundary for small product-owned prompt tasks

This design is intentionally destructive. It does not preserve compatibility
with the current `conversation_title_update` workflow-intent path, and it
assumes the local database can be reset.

## Why This Exists

The current title path is not actually modeled as durable conversation
metadata:

- `Conversation` has no persisted `title` or `summary`
- exports derive `original_title` by truncating the first user message
- `conversation_title_update` appears in workflow intent materialization and
  debug/export surfaces, but there is no canonical metadata write model behind
  it
- the new supervision `summary_model` shows that CoreMatrix now needs its own
  product-owned prompt generation path, but it currently bypasses the normal
  provider dispatch boundary and builds clients directly

That mix is neither product-correct nor architecture-correct. Conversation
metadata should be modeled as conversation metadata, not as workflow graph
state.

## Design Principles

### 1. Metadata lives on `Conversation`

`title` and `summary` are canonical properties of a conversation. They should
be stored directly on `conversations`, not inferred from transcript content and
not modeled as separate workflow nodes.

### 2. Initial naming is synchronous and cheap

The first title must be available immediately after the first user message is
persisted. That path must not depend on agent cooperation and should
not require a provider call.

### 3. User edits are authoritative

When the user manually edits `title` or `summary`, that field becomes
`user_locked`. Neither bootstrap logic, model generation, nor agent-written
metadata may overwrite it until the user explicitly requests regeneration.

### 4. Agent metadata updates remain possible, but are not workflow intents

Agents should still be able to explicitly update conversation metadata when
appropriate, but they should do so through a dedicated CoreMatrix metadata
command/tool, not through `yield` intent batches and workflow nodes.

### 5. Model-backed metadata generation uses one CoreMatrix gateway

Any CoreMatrix-owned “short prompt” generation path should go through one
installation-scoped provider gateway that handles selector resolution,
credentials, lease/governor, retry, and normalized response parsing. Business
services should not construct provider clients directly.

### 6. `summary` exists, but is not part of the default chat-list contract

Normal conversation lists should use `title` only. `summary` remains available
for future task-heavy or supervision views, but it is not auto-generated during
initial conversation bootstrap.

## Target Data Model

Extend `conversations` with the following fields:

- `title :string`
- `summary :text`
- `title_source :string, null: false, default: "none"`
- `summary_source :string, null: false, default: "none"`
- `title_lock_state :string, null: false, default: "unlocked"`
- `summary_lock_state :string, null: false, default: "unlocked"`
- `title_updated_at :datetime`
- `summary_updated_at :datetime`

Supported source values:

- `none`
- `bootstrap`
- `generated`
- `agent`
- `user`

Supported lock states:

- `unlocked`
- `user_locked`

`Conversation` should validate those enums and expose field-level predicates
such as:

- `title_locked?`
- `summary_locked?`
- `metadata_field_locked?(field_name)`

No history table is added in this version. Only the current metadata state is
canonical.

## Ownership And Layering

Use the following layer split:

- Presentation layer:
  - app controllers
  - CoreMatrix tool runner entrypoints
  - serializers/export payload builders
- Application layer:
  - `Conversations::Metadata::*` services
  - `ProviderGateway::DispatchText`
- Domain layer:
  - `Conversation` fields, validations, and metadata helpers
- Infrastructure layer:
  - Active Record persistence
  - provider adapters/credentials/HTTP clients

`Conversation` owns persisted metadata state. Application services orchestrate
how that state changes.

## Canonical Write Paths

### 1. `Conversations::Metadata::BootstrapTitle`

Trigger:

- immediately after the first user message for an interactive root
  conversation is persisted

Rules:

- only runs when `conversation.title` is blank
- only runs when `conversation.title_lock_state == "unlocked"`
- never writes `summary`
- never calls a provider

Suggested algorithm:

- read only the just-created first user message
- normalize whitespace
- prefer the first sentence or first line
- truncate to a stable length
- avoid generic wrappers when trivially removable

Write result:

- `title = generated_text`
- `title_source = "bootstrap"`
- `title_updated_at = now`

### 2. `Conversations::Metadata::UserEdit`

Trigger:

- user explicitly edits `title` and/or `summary`

Rules:

- writes the supplied field values directly
- sets edited fields to `source = "user"`
- sets edited fields to `lock_state = "user_locked"`
- does not affect unedited fields

### 3. `Conversations::Metadata::Regenerate`

Trigger:

- user explicitly chooses “regenerate title” or “regenerate summary”

Rules:

- clears `user_locked` only for the targeted field
- regenerates only the targeted field
- `title` may use a lightweight generation strategy
- `summary` may use a richer generation strategy

### 4. `Conversations::Metadata::AgentUpdate`

Trigger:

- agent explicitly calls the conversation metadata tool/command

Rules:

- may target `title`, `summary`, or both
- must reject writes to any `user_locked` field
- writes successful fields with `source = "agent"`
- never bypasses conversation-scoped locking semantics

## Read Model

Every user-facing conversation metadata surface should read persisted metadata
from `Conversation`, not infer it from transcript content.

### Default conversation list

Expose:

- `title`

Behavior:

- show stored `title` when present
- otherwise use a neutral fallback such as `Untitled conversation`
- do not show `summary`

### Heavy task / supervision views

Expose:

- `title`
- `summary`
- optional source/lock diagnostics for internal operators if needed

### Export surfaces

Stop exporting `original_title` derived from the first user message. Export the
canonical stored metadata instead:

- `title`
- `summary`
- `title_source`
- `summary_source`

## Agent Contract

Delete the old agent contract based on `conversation_title_update` yield
intents.

Replace it with one explicit CoreMatrix tool:

- `conversation_metadata_update`

Input:

- `title` optional
- `summary` optional

Rules:

- at least one field must be present
- public-id-only contract; no internal bigint ids
- locked fields return structured rejection rather than being overwritten

Execution:

- tool routing stays inside CoreMatrix
- the tool runner calls `Conversations::Metadata::AgentUpdate`

This keeps agent-driven metadata updates possible without pretending they are
workflow graph nodes.

## Provider Boundary

Introduce a new installation-scoped gateway for CoreMatrix-owned short prompt
generation:

- `ProviderGateway::DispatchText`

Input contract:

- `installation`
- `selector`
- `messages`
- `max_output_tokens`
- `purpose`
- `audit_context`
- optional workflow refs

Responsibilities:

- resolve selector through `ProviderCatalog::EffectiveCatalog`
- load credentials
- merge request defaults through `ProviderRequestSettingsSchema`
- apply provider governor / lease
- handle transient retry
- route by wire API
- normalize returned text/usage/provider request id

Use this gateway for:

- title regeneration
- future summary generation
- supervision `summary_model`
- any future CoreMatrix-owned single-shot metadata/product prompts

Do not let business services build `SimpleInference::Client` or
`OpenAIResponses` instances directly.

## Model Selection Contract

Stop hanging product-owned metadata generation off the agent’s normal
`model_slots`.

Instead, give these capabilities explicit selectors in catalog/configuration:

- `role:conversation_title`
- `role:conversation_summary`
- `role:supervision_summary`

This makes latency/cost/quality choices explicit and prevents unrelated agent
slot configuration from accidentally controlling product metadata behavior.

## Required Deletions

Delete, do not preserve:

- `conversation_title_update` workflow intent as a supported durable mutation
- workflow-node materialization for conversation metadata writes
- tests that treat title updates as accepted workflow nodes
- export/debug payload assumptions that title metadata is still intent-shaped
- any dynamic `original_title` derivation from the first transcript message as a
  canonical source of truth

Existing workflow/introspection artifacts may continue to show historical
records where relevant during the refactor, but the new system should not
generate new metadata writes through that path.

## Testing Strategy

### Domain / model tests

- validate metadata source enums
- validate metadata lock-state enums
- verify field-level lock predicates

### Application service tests

- bootstrap title only on first user message
- bootstrap skipped when title already exists
- user edit locks only edited fields
- regenerate unlocks only the targeted field
- agent update respects user locks

### Request / integration tests

- first user message creates a title immediately
- user-edited title survives later agent metadata updates
- conversation list payload exposes title without summary
- heavy metadata endpoint exposes both title and summary

### Provider-boundary tests

- `ProviderGateway::DispatchText` uses selector resolution and provider settings
- `summary_model` uses the gateway rather than direct client construction

### Cleanup tests

- no workflow materialization tests still assert `conversation_title_update`
- export payload tests read stored metadata instead of deriving `original_title`

## Migration Posture

This refactor is destructive by design:

- edit baseline conversation migrations in place
- regenerate `db/schema.rb`
- reset the local database

Run from `/Users/jasl/Workspaces/Ruby/cybros/core_matrix`:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

Do not carry compatibility layers for the old title-intent workflow. Replace
the old model in one pass.
