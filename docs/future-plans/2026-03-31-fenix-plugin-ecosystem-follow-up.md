# Fenix Plugin Ecosystem Follow-Up

## Status

Deferred follow-up after the runtime appliance and operator-surface work.

## Purpose

The current Fenix runtime already has a registry-backed plugin model, but it is
still intentionally conservative:

- code-owned system plugins are the primary execution path
- plugin manifests can carry wider metadata than the runtime currently uses
- workspace-loaded or third-party plugin execution remains intentionally
  constrained

This document records the next ecosystem-oriented expansion so it does not get
lost while the current effort stays focused on operator UX.

## Deferred Capability

The deferred plugin-ecosystem work includes:

- richer manifest fields becoming live behavior instead of passive metadata:
  - `healthcheck`
  - `bootstrap`
  - `config_schema`
  - `requirements`
  - `env_contract`
- curated plugin packaging and versioning rules
- workspace-local plugin loading policy
- optional third-party plugin trust and isolation rules
- plugin bootstrap/install diagnostics
- operator-facing plugin inventory and health reporting

## Why Deferred

This work is valuable, but it is not required to make the shipped runtime
appliance understandable and usable:

- the runtime already has enough built-in plugins to cover the current product
  surface
- ecosystem work widens the security and lifecycle design space
- manifest shape can stay wider than the first execution cut without requiring
  immediate implementation

## Activation Trigger

Re-open this follow-up when one or more of the following becomes true:

- operators need to load workspace-local plugins beyond code-owned built-ins
- plugin bootstrap or health state must drive runtime readiness
- product requirements need richer plugin packaging, versioning, or publishing
- the current manifest schema is being used as if it were executable policy

## Related Documents

- [2026-03-30-fenix-runtime-appliance-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance-design.md)
- [2026-03-30-fenix-runtime-appliance.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-30-fenix-runtime-appliance.md)
- [2026-03-31-fenix-operator-surface-design.md](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/fenix/2026-03-31-fenix-operator-surface-design.md)
