# Workspace-Agent Settings Infrastructure Design

## Goal

Replace the current ad hoc flat `WorkspaceAgent.settings_payload` key set with a
structured settings contract backed by agent-version-owned schema/default
documents, while keeping runtime turn payloads small and preserving the
CoreMatrix/agent layering boundary.

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
- CoreMatrix currently mixes two responsibilities:
  - storing agent-owned settings
  - interpreting agent profile/business semantics from those settings

The user-facing need is now clear:

- Fenix owns profile, prompt, and stale-settings semantics
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
4. Runtime turn payloads stay small. CoreMatrix should freeze the raw nested
   settings payload, not a profile-aware interpreted projection.
5. Default values and override presence are different concepts. CoreMatrix
   stores the raw override payload and does not rewrite it to fit profile
   assumptions.
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
changes from a flat key bag to a structured override payload with an explicit
split between agent-owned settings and CoreMatrix-owned generic runtime hints.

It stores only mount-specific overrides, never:

- prompt fragments
- profile catalog metadata
- schema/default documents
- effective fully-expanded settings

CoreMatrix may surface schema/default documents to app clients, but it should
not validate, repair, normalize, or reject agent-owned stale values during
runtime paths. If the mounted agent later changes the meaning of settings, that
compatibility handling belongs to the agent.

## Structured Settings Shape

### Canonical mount override payload

The canonical stored override payload becomes:

```json
{
  "agent": {
    "interactive": {
      "profile_key": "friendly"
    },
    "subagents": {
      "default_profile_key": "developer",
      "enabled_profile_keys": ["researcher", "developer", "tester"],
      "delegation_mode": "prefer"
    }
  },
  "core_matrix": {
    "interactive": {
      "model_selector": "role:main"
    },
    "subagents": {
      "max_concurrent": 3,
      "max_depth": 2,
      "allow_nested": true,
      "default_model_selector": "role:main",
      "label_model_selectors": {
        "researcher": "role:researcher",
        "developer": "role:developer",
        "tester": "role:tester"
      }
    }
  }
}
```

Rules:

- every key is optional in the mount override payload
- absence means "fall back to agent-version defaults or current runtime logic"
- CoreMatrix only enforces that `settings_payload` is a hash
- agent-owned stale or incompatible values remain the agent's responsibility

### JSON schema contract

The agent-owned schema document should separate agent-owned and CoreMatrix-owned
fields, but CoreMatrix consumes it as app-surface metadata rather than as the
authoritative validator for agent-owned business settings:

```json
{
  "$schema": "https://json-schema.org/draft/2020-12/schema",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "agent": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "interactive": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "profile_key": { "type": "string", "minLength": 1 }
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
            }
          }
        }
      }
    },
    "core_matrix": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "interactive": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "model_selector": { "type": "string", "minLength": 1 }
          }
        },
        "subagents": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "max_concurrent": { "type": "integer", "minimum": 1 },
            "max_depth": { "type": "integer", "minimum": 1 },
            "allow_nested": { "type": "boolean" },
            "default_model_selector": { "type": "string", "minLength": 1 },
            "label_model_selectors": {
              "type": "object",
              "additionalProperties": {
                "type": "string",
                "minLength": 1
              }
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

- `agent.interactive.profile_key` defaults to the agent's default interactive profile
- `agent.subagents.default_profile_key` defaults to the definition-marked default
  specialist (`researcher` in the current Fenix catalog)
- `agent.subagents.enabled_profile_keys` defaults to the builtin specialist set
- `agent.subagents.delegation_mode` defaults to `allow`
- `core_matrix.subagents.max_concurrent` defaults to `3`
- `core_matrix.subagents.max_depth` defaults to the agent's default subagent depth
- `core_matrix.subagents.allow_nested` defaults to the agent's default nested-delegation
  policy
- `core_matrix.interactive.model_selector` and
  `core_matrix.subagents.default_model_selector` may be populated by the agent
  as generic *soft selector preferences*
- `core_matrix.subagents.label_model_selectors.*` stays optional and should
  default to empty; CoreMatrix users may populate it when a local installation
  wants opaque agent labels to prefer specific selectors

For Fenix, the shipped generic defaults should stay conservative:

- `core_matrix.interactive.model_selector = "role:main"`
- `core_matrix.subagents.default_model_selector = "role:main"`

If an installation wants opaque profile-label-specific routing, the
mount-scoped override may add entries under
`core_matrix.subagents.label_model_selectors.<opaque-key>`.

All of these are soft preferences. If an installation has no such selector,
CoreMatrix must fall back cleanly.

## Runtime Semantics

### Runtime payload shape

Freeze this raw payload into the execution contract:

```json
{
  "settings_payload": {
    "agent": {
      "interactive": {
        "profile_key": "friendly"
      },
      "subagents": {
        "default_profile_key": "developer",
        "enabled_profile_keys": ["researcher", "developer", "tester"],
        "delegation_mode": "prefer"
      }
    },
    "core_matrix": {
      "interactive": {
        "model_selector": "role:main"
      },
      "subagents": {
        "max_concurrent": 3,
        "max_depth": 2,
        "allow_nested": true,
        "default_model_selector": "role:main",
        "label_model_selectors": {
          "developer": "role:developer"
        }
      }
    }
  }
}
```

Rules:

- CoreMatrix freezes the raw nested override payload
- CoreMatrix does not flatten, translate, or normalize profile semantics
- `workspace_agent_context.settings_payload` is the settings payload that
  crosses into `prepare_round`

## Soft Model Selector Resolution

### Interactive turns

Interactive mounted turns must resolve selectors in this order:

1. explicit selector or explicit candidate on the turn/conversation
2. mount `core_matrix.interactive.model_selector` soft preference
3. normal catalog default resolution

If a mount-provided selector is unknown or unavailable, do **not** raise. Fall
through to the next step.

### Subagent turns

Subagent turns currently carry a `model_selector_hint` but still bootstrap the
child workflow from the origin turn selector. This round tightens that behavior.

When spawning a child, choose the child workflow selector in this order:

1. explicit tool argument `model_selector_hint`, if it resolves successfully
2. mount `core_matrix.subagents.label_model_selectors.<opaque-key>`, if it
   resolves successfully
3. mount `core_matrix.subagents.default_model_selector`, if it resolves successfully
4. origin turn normalized selector

The chosen successful selector becomes:

- the selector used for `Workflows::CreateForTurn`
- `SubagentConnection.resolved_model_selector_hint`
- the selector reflected in debug/export evidence

If none of the soft preferences resolve successfully, fall back to the origin
turn selector instead of failing the spawn.

CoreMatrix treats `<opaque-key>` as an agent-owned string. It does not validate
it against an agent profile catalog.

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

CoreMatrix only performs structural JSON-schema validation for agent-owned
settings data. It must not enforce profile-specific domain rules or normalize
agent-owned compatibility aliases. Agent-specific compatibility handling stays
inside Fenix.

## Migration Strategy

This is a destructive refactor with no compatibility obligation.

The migration should rewrite the `workspace_agents` owning migration in place
and preserve the existing `settings_payload` column name, but change the stored
shape and validation semantics.

The frozen runtime payload should use the same nested `settings_payload` shape
as `WorkspaceAgent.settings_payload`; CoreMatrix should not project it into a
second compact agent-specific view.

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
