# Core Matrix Kernel UI Follow-Up

## Status

Deferred follow-up scope. This document exists to keep human-facing UI work out of the current backend greenfield phase without losing the work queue.

## Purpose

The current phase delivers backend models, services, machine-facing contract boundaries, automated tests, and manual backend validation. It does not deliver human-facing application UI.

This follow-up document is the holding area for that deferred UI surface.

## Deferred Human-Facing Surfaces

- installation setup wizard for first-admin bootstrap
- password login, session management, and invitation acceptance pages
- admin UI for users, invitations, provider governance, agent lifecycle, and audit browsing
- user UI for agent bindings, workspaces, conversations, branching, publication controls, and runtime state
- publication pages for internal-public and external-public read-only views
- runtime feedback surfaces such as queued-turn state, approval prompts, process logs, and outage recovery affordances
- client-local composer draft behavior, including branch-prefill seed handling and unsent attachment staging UX

## Deferred Frontend And Delivery Work

- controllers and HTML responses for the human-facing product
- Turbo, Stimulus, or other frontend runtime decisions
- realtime delivery choices for transcript and workflow events
- view-model shaping and page-level query assembly
- system tests for browser flows

## Current Rule

Do not pull items from this document into the backend implementation phase unless a later plan explicitly widens scope.
