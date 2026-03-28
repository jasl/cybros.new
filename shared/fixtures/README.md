# Shared Fixtures

This directory contains test fixtures shared across top-level projects in the
monorepo.

## Layout

- `contracts/`: frozen contract fixtures used to verify cross-project payload
  shapes at project boundaries.

## Rules

- Treat these files as test artifacts, not runtime source of truth.
- Keep fixtures scoped to boundaries that are intentionally shared across
  projects.
- When a contract fixture changes, update the producer-side and consumer-side
  tests in the affected projects in the same change.
