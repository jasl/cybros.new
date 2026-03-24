# Core Matrix Phase 3 Web UI Productization Follow-Up

## Status

Deferred future plan. This document now represents `Phase 3`, the first
user-facing Web product phase after the loop is proven.

## Purpose

After `Phase 2` proves the real agent loop, `Phase 3` makes Core Matrix and
Fenix usable as a real Web product without changing the kernel's execution
authority.

## Scope

- installation setup wizard for first-admin bootstrap
- password login, session management, and invitation acceptance pages
- admin UI for users, invitations, provider governance, agent lifecycle, and
  audit browsing
- user UI for agent bindings, workspaces, conversations, branching, publication
  controls, and runtime state
- runtime feedback surfaces such as queued-turn state, approval prompts,
  process logs, and outage recovery affordances
- conversation feature-policy-aware UI behavior
- agent-defined composer completions mounted into the Web product

## Out Of Scope

- workspace-owned trigger and delivery infrastructure
- IM, PWA, or desktop channels
- extension and plugin packaging

## Current Rule

Do not pull work from this document into the current substrate batch. This phase
begins only after the real loop is already validated.
