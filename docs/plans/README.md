# Plans Index

This directory is reserved for active execution plans for `core_matrix`.

Plans should remain executable without reopening volatile references. If a task
uses `references/` or an external implementation for a sanity check, capture
the retained conclusion in the active plan record, the task document itself, or
another local document updated during the same execution unit.

When an active plan changes durable product behavior, update the long-lived
behavior docs in `core_matrix/docs/behavior` during the same execution unit so
the plan record does not become the only source of truth.

Current active `core_matrix` planning records:

- None currently. Move the next approved execution entry point into this
  directory when new work starts.

Phase 1 records now live in
[`docs/finished-plans`](/Users/jasl/Workspaces/Ruby/cybros/docs/finished-plans/README.md).

When phase 2 work is activated, move the approved execution entry point from
`docs/proposed-plans` or `docs/future-plans` into this directory and update
this index at the same time.
