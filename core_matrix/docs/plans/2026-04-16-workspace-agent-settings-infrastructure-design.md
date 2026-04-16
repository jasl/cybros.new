# Workspace-Agent Settings Infrastructure Design

## Goal

Replace the current ad hoc flat `WorkspaceAgent.settings_payload` key set with a
structured settings contract backed by agent-version-owned schema/default
documents, while keeping runtime turn payloads small and preserving existing
mount-override semantics.

This follow-up resumes the deferred "mount settings / schema / default"
infrastructure that was explicitly left out of:

- [`2026-04-16-workspace-agent-global-instructions-design.md`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-16-workspace-agent-global-instructions-design.md)
- [`2026-04-16-workspace-agent-profile-catalog-design.md`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/docs/plans/2026-04-16-workspace-agent-profile-catalog-design.md)

The scope of this round is intentionally narrow:

- define the structured settings contract
- publish versioned settings schema/defaults from the agent definition
- migrate current mount settings onto that infrastructure
- make model-selector preferences real CoreMatrix-side mount overrides

This round does **not** move prompt bodies or the profile catalog into
CoreMatrix.

## Problem

The current `WorkspaceAgent.settings_payload` implementation solved the first
profile-catalog milestone quickly, but it is not a real settings
infrastructure:

- supported keys are hardcoded in [`WorkspaceAgent`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/app/models/workspace_agent.rb)
- the shape is a flat bag of string keys rather than a documented structured
  config
- there is no agent-version-owned settings schema/default contract
- app clients cannot discover valid settings from the mounted agent definition
- "model selector hint" handling is inconsistent:
  - interactive turns only support `interactive_profile_key -> role:<profile>`
  - subagent `model_selector_hint` is carried as advisory metadata, but child
    workflow selection still reuses the origin selector unless a direct tool
    caller explicitly sets a selector elsewhere

The user-facing need is now clear:

- Fenix owns profile and prompt semantics
- CoreMatrix-side users need to override model-selection preferences because
  Fenix does not know which model selectors exist in one installation
- those preferences should be soft:
  - try the configured selector
  - if unavailable or unknown, fall back cleanly
  - never force a hard failure for a mount preference

## Design Principles

1. Prompt/business content remains agent-owned. Settings schema/defaults may be
   stored in CoreMatrix because they are product configuration contracts, not
   prompt bodies.
2. Versioned settings schema/defaults belong to `AgentDefinitionVersion`, not
   to `WorkspaceAgent`.
3. Mutable mount values remain on `WorkspaceAgent`.
4. Runtime turn payloads stay small. We continue to freeze a compact
   `workspace_agent_context.profile_settings` projection rather than shipping
   schema/default documents through `prepare_round`.
5. Default values and override presence are different concepts. Runtime paths
   that currently depend on explicit key presence must keep that behavior.
6. Mount model preferences are soft selectors, not hard requirements.

## Ownership Model

### `AgentDefinitionVersion` owns versioned settings contract docs

Add two new document refs on `AgentDefinitionVersion`:

- `workspace_agent_settings_schema_document`
- `default_workspace_agent_settings_document`

They are agent-version-owned and come from the runtime definition package, just
like:

- `canonical_config_schema_document`
- `conversation_override_schema_document`
- `default_canonical_config_document`

This keeps the source of truth with the agent version while letting CoreMatrix
surface the contract to app clients.

### `WorkspaceAgent` owns mutable overrides only

`WorkspaceAgent.settings_payload` remains the storage field, but its shape
changes from a flat key bag to a structured override payload.

It stores only mount-specific overrides, never:

- prompt fragments
- profile catalog metadata
- schema/default documents
- effective fully-expanded settings

## Structured Settings Shape

### Canonical mount override payload

The canonical stored override payload becomes:

```json
{
  "interactive": {
    "profile_key": "friendly",
    "model_selector": "role:main"
  },
  "subagents": {
    "default_profile_key": "developer",
    "enabled_profile_keys": ["researcher", "developer", "tester"],
    "delegation_mode": "prefer",
    "max_concurrent": 3,
    "max_depth": 2,
    "allow_nested": true,
    "default_model_selector": "role:main",
    "profile_overrides": {
      "researcher": {
        "model_selector": "role:researcher"
      },
      "developer": {
        "model_selector": "role:developer"
      },
      "tester": {
        "model_selector": "role:tester"
      }
    }
  }
}
```

Rules:

- every key is optional in the mount override payload
- absence means "fall back to agent-version defaults or current runtime logic"
- unknown keys are rejected
- blank strings collapse away
- empty nested objects collapse away

### JSON schema contract

The agent-owned schema document should be a plain JSON Schema object of this
form:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "interactive": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "profile_key": { "type": "string", "minLength": 1 },
        "model_selector": { "type": "string", "minLength": 1 }
      }
    },
    "subagents": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "default_profile_key": { "type": "string", "minLength": 1 },
        "enabled_profile_keys": {
          "type": "array",
          "items": { "type": "string", "minLength": 1 },
          "uniqueItems": true
        },
        "delegation_mode": {
          "type": "string",
          "enum": ["allow", "prefer"]
        },
        "max_concurrent": { "type": "integer", "minimum": 1 },
        "max_depth": { "type": "integer", "minimum": 1 },
        "allow_nested": { "type": "boolean" },
        "default_model_selector": { "type": "string", "minLength": 1 },
        "profile_overrides": {
          "type": "object",
          "additionalProperties": {
            "type": "object",
            "additionalProperties": false,
            "properties": {
              "model_selector": { "type": "string", "minLength": 1 }
            }
          }
        }
      }
    }
  }
}
```

### Agent-owned defaults

The default settings document should be small and opinionated:

- `interactive.profile_key` defaults to the agent's default interactive profile
- `subagents.default_profile_key` defaults to the definition-marked default
  specialist (`researcher` in the current Fenix catalog)
- `subagents.enabled_profile_keys` defaults to the builtin specialist set
- `subagents.delegation_mode` defaults to `allow`
- `subagents.max_concurrent` defaults to `3`
- `subagents.max_depth` defaults to the agent's default subagent depth
- `subagents.allow_nested` defaults to the agent's default nested-delegation
  policy
- `interactive.model_selector`, `subagents.default_model_selector`, and
  `subagents.profile_overrides.*.model_selector` may be populated by the agent
  as *soft selector preferences*

For Fenix, the default model-selector entries may recommend selectors such as:

- `interactive.model_selector = "role:main"`
- `subagents.profile_overrides.researcher.model_selector = "role:researcher"`
- `subagents.profile_overrides.developer.model_selector = "role:developer"`
- `subagents.profile_overrides.tester.model_selector = "role:tester"`

These are soft preferences. If an installation has no such selector, CoreMatrix
must fall back cleanly.

## Runtime Semantics

### Two views, not one

This design requires two distinct settings views:

1. **canonical override payload**
   - the nested JSON stored on `WorkspaceAgent.settings_payload`
2. **compact runtime projection**
   - the small flattened hash frozen into `workspace_agent_context.profile_settings`

They must not be conflated.

The runtime projection remains necessary because current execution code relies
on:

- compact keys
- explicit override presence
- low protocol overhead

### Compact runtime projection

Freeze this compact payload into the execution contract:

```json
{
  "interactive_profile_key": "friendly",
  "interactive_model_selector": "role:main",
  "default_subagent_profile_key": "developer",
  "enabled_subagent_profile_keys": ["researcher", "developer", "tester"],
  "delegation_mode": "prefer",
  "max_concurrent_subagents": 3,
  "max_subagent_depth": 2,
  "allow_nested_subagents": true,
  "default_subagent_model_selector": "role:main",
  "subagent_model_selectors": {
    "researcher": "role:researcher",
    "developer": "role:developer",
    "tester": "role:tester"
  }
}
```

Rules:

- only explicit mount overrides and explicit default-derived values that are
  required for runtime routing should appear
- current consumers may continue to use `key?` to distinguish explicit override
  presence
- `workspace_agent_context.profile_settings` remains the only settings payload
  that crosses into `prepare_round`

## Soft Model Selector Resolution

### Interactive turns

Interactive mounted turns must resolve selectors in this order:

1. explicit selector or explicit candidate on the turn/conversation
2. mount `interactive.model_selector` soft preference
3. mount `interactive.profile_key -> role:<profile>` soft preference
4. normal catalog default resolution

If a mount-provided selector is unknown or unavailable, do **not** raise. Fall
through to the next step.

### Subagent turns

Subagent turns currently carry a `model_selector_hint` but still bootstrap the
child workflow from the origin turn selector. This round tightens that behavior.

When spawning a child, choose the child workflow selector in this order:

1. explicit tool argument `model_selector_hint`, if it resolves successfully
2. mount `subagents.profile_overrides.<profile_key>.model_selector`, if it
   resolves successfully
3. mount `subagents.default_model_selector`, if it resolves successfully
4. origin turn normalized selector

The chosen successful selector becomes:

- the selector used for `Workflows::CreateForTurn`
- `SubagentConnection.resolved_model_selector_hint`
- the selector reflected in debug/export evidence

If none of the soft preferences resolve successfully, fall back to the origin
turn selector instead of failing the spawn.

## App Surface

Expose three settings-related payloads on the workspace-agent app surface:

- `settings_payload`
  - the canonical nested mount override payload
- `settings_schema`
  - the current agent-version-owned JSON schema
- `default_settings_payload`
  - the current agent-version-owned default settings document

This should appear in:

- `WorkspaceAgentPresenter`
- workspace fan-out payloads that embed workspace agents

The app surface must continue to use only public ids.

## Agent API / Registration Contract

Because schema/defaults are agent-version-owned documents, they should be added
to the definition package and runtime capability contract alongside the other
agent-owned schema/default docs.

Add these fields to:

- agent runtime definition package
- `AgentDefinitionVersions::UpsertFromPackage`
- `RuntimeCapabilityContract`
- `/agent_api/capabilities`

This is acceptable churn because these fields are part of the agent-version
contract, not workspace-specific runtime payloads.

Do **not** add them to:

- `workspace_agent_context`
- `prepare_round`
- mailbox item payloads

## Validation Rules

In addition to structural JSON-schema validation, CoreMatrix must enforce
domain rules:

- `interactive.profile_key` must reference a known profile key
- `subagents.enabled_profile_keys` must reference known specialist profile keys
- `subagents.enabled_profile_keys` must not include the chosen interactive
  profile
- `subagents.default_profile_key`, when present, must be included in
  `subagents.enabled_profile_keys`
- `subagents.profile_overrides` keys must reference known specialist profile
  keys
- `subagents.profile_overrides` keys may be present even when the corresponding
  profile is not the default specialist, but they must still be known profiles

## Migration Strategy

This is a destructive refactor with no compatibility obligation.

The migration should rewrite the `workspace_agents` owning migration in place
and preserve the existing `settings_payload` column name, but change the stored
shape and validation semantics.

Current flat settings map to the new structure as follows:

- `interactive_profile_key` -> `interactive.profile_key`
- `default_subagent_profile_key` -> `subagents.default_profile_key`
- `enabled_subagent_profile_keys` -> `subagents.enabled_profile_keys`
- `delegation_mode` -> `subagents.delegation_mode`
- `max_concurrent_subagents` -> `subagents.max_concurrent`
- `max_subagent_depth` -> `subagents.max_depth`
- `allow_nested_subagents` -> `subagents.allow_nested`
- `default_subagent_model_selector_hint` -> `subagents.default_model_selector`

The frozen runtime `profile_settings` projection is allowed to keep its compact
shape, but it should adopt the new selector-related keys:

- `interactive_model_selector`
- `default_subagent_model_selector`
- `subagent_model_selectors`

## Acceptance Impact

This work touches acceptance-critical loop behavior because it changes:

- interactive selector resolution
- subagent child workflow bootstrap selection
- execution snapshot contents
- app surface payloads

Completion therefore requires:

- full `core_matrix` verification
- full `agents/fenix` verification if Fenix manifest/payload tests change
- repo-root active acceptance
- manual inspection of 2048 capstone artifacts and database state

The final audit must explicitly check whether the latest capstone export/debug
artifacts now reflect any subagent selector data when subagents are used.
