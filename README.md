# cybros

`cybros` is a monorepo for CoreMatrix, a single-installation agent kernel
product, plus its bundled and companion runtimes such as Fenix and Nexus.

## Products

- `CoreMatrix` is the kernel product. It owns agent-loop execution,
  conversation state, workflow scheduling, human-interaction primitives,
  runtime supervision, and platform-level governance.
- `core_matrix_cli` is the operator-facing setup CLI for turning a CoreMatrix
  installation into a usable environment without relying on the unfinished Web
  UI. It handles first-run setup, Codex subscription authorization, workspace
  selection, and Telegram/Weixin ingress preparation.
- `Fenix` is the default bundled agent. It is both a usable assistant product,
  the first technical validation agent for the CoreMatrix loop, and an
  optional agent-side tool provider.
- `Nexus` is the default bundled execution runtime. It owns the local runtime
  tool surface and runtime-side resource execution for the CoreMatrix loop,
  but conversations may also run without a runtime when only agent-side and
  CoreMatrix-owned tools are needed.

## Documentation Lifecycle

Work moves through the documentation tree in this order:

1. `docs/proposed-designs`
2. `docs/proposed-plans`
3. `docs/future-plans`
4. `docs/plans`
5. `docs/finished-plans`
6. `docs/archived-plans`

Use `docs/design` for approved design baselines that should remain stable across
multiple future phases. Use `docs/future-plans` for accepted later-phase work
that is intentionally not active yet.

## Current Direction

- The current substrate batch continues to harden `core_matrix` foundations.
- The current agent-loop validation batch proves the real loop end to end.
- The current operator batch makes the system usable through `core_matrix_cli`
  while the Web UI is still incomplete.
- Later batches widen the product boundary through additional validation
  agents, runtimes, triggers, channels, and eventually extensions.

## Operator Setup

The fastest way to make a new installation usable today is through
[`core_matrix_cli`](/Users/jasl/Workspaces/Ruby/cybros/core_matrix_cli):

1. `cd core_matrix_cli`
2. `bundle exec ./bin/cmctl init`
3. `bundle exec ./bin/cmctl providers codex login`
4. `bundle exec ./bin/cmctl ingress telegram setup` or `bundle exec ./bin/cmctl ingress weixin setup`
5. `bundle exec ./bin/cmctl status`

For IM prerequisites and the exact values the CLI will ask for, see
[docs/operations/core-matrix-im-preparation-guide.md](/Users/jasl/Workspaces/Ruby/cybros/docs/operations/core-matrix-im-preparation-guide.md).

## Validation Rule

Loop-related work is not complete with automated tests alone. When a phase
claims real loop behavior, validation must include:

- unit and integration coverage
- `bin/dev`
- a real LLM API
- manual validation flows maintained under `docs/checklists`

## Licensing

Licensing in this monorepo is project-scoped.

- Repository-root materials that are not covered by a more specific
  subdirectory license are licensed under the O'Saasy License Agreement. See
  [LICENSE.md](/Users/jasl/Workspaces/Ruby/cybros/LICENSE.md).
- [core_matrix](/Users/jasl/Workspaces/Ruby/cybros/core_matrix) and each
  standalone project under
  [agents/](/Users/jasl/Workspaces/Ruby/cybros/agents) are licensed under the
  O'Saasy License Agreement, as stated in the license file at the root of the
  relevant project.
- [core_matrix/vendor/simple_inference](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference)
  is a separately licensed vendored gem and remains licensed under the MIT
  License. See
  [LICENSE.txt](/Users/jasl/Workspaces/Ruby/cybros/core_matrix/vendor/simple_inference/LICENSE.txt).
- Where a subdirectory contains its own license file, that subdirectory-specific
  license controls for the contents of that subdirectory.
