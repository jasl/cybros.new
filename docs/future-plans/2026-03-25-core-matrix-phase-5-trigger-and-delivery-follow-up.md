# Core Matrix Phase 5 Trigger And Delivery Follow-Up

## Status

Deferred future plan.

## Purpose

Add workspace-owned automation, trigger, and delivery infrastructure after the
loop and initial product shapes are proven.

## Design Direction

- `AutomationDefinition` belongs to `Workspace`
- `TriggerRegistration` belongs to `Workspace`
- `TriggerEvent` records one trigger fact
- execution continues through normal conversation and workflow roots

## Scope

- schedules
- webhook ingress
- delivery and outbox behavior
- retry, dedupe, and delivery receipts
- recovery-aware trigger and delivery flows

## Out Of Scope

- IM client surfaces
- plugin packaging
