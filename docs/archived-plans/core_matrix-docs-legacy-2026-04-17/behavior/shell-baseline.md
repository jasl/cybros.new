# Core Matrix Shell Baseline

## Purpose

Task 01 establishes the minimal backend shell for the greenfield Core Matrix
kernel. It is a documentation and scaffolding checkpoint, not a domain-model
delivery task.

## Observable Behavior

- `bin/rails db:version` resolves the configured development databases without
  missing-migration errors.
- `bin/rails test` is allowed to be empty, but it must complete successfully.
- `bin/rubocop app/models/application_record.rb` passes.
- `ApplicationRecord` remains the abstract Active Record base class.
- The shell routes stay limited to the Rails health endpoint and the root
  `home#index` entrypoint.
- Empty scaffolding directories exist for test support and future manual
  validation scripts.

## Invariants

- This phase remains backend-only.
- Human-facing UI, Turbo, Stimulus, and browser delivery are out of scope.
- Task 01 does not add domain models, migrations, or protocol endpoints.
- Root project docs remain the authoritative design and planning source.

## Side Effects

- Adds documentation references that point developers to the canonical design,
  deferred UI plan, manual validation checklist, and local behavior docs.
- Creates empty directories for upcoming tests, queries, request coverage, and
  manual scripts.

## Failure Modes

- The shell baseline is invalid if database version checks fail, tests fail, or
  RuboCop reports offenses in `ApplicationRecord`.
- Any added human-facing UI work or schema changes would violate this task's
  scope boundary.
