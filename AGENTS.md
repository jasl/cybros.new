# AGENTS.md

## Scope

This repository is a monorepo. Treat each top-level product directory as an independent project unless a change is explicitly shared.

`references/` is reference-only material. It is not part of the product codebase, should not be used as the default source of truth, and should not drive CI, tests, or implementation scope unless explicitly requested.

## Projects

- `agents/fenix`: standalone Ruby on Rails application
- `core_matrix`: main Ruby on Rails application
- `core_matrix/vendor/simple_inference`: vendored Ruby gem maintained in-tree

## Working Rules

- Run commands from the target project directory.
- Keep changes scoped to the requested subproject whenever possible.
- For `core_matrix`, do not expose internal `bigint` ids at external or
  agent-facing boundaries; use `public_id` and see
  `core_matrix/docs/behavior/identifier-policy.md` for the product-specific
  rules.
- If you touch shared root files such as `AGENTS.md`, `.editorconfig`, `.gitattributes`, `.gitignore`, or `.github/workflows/*`, assume all subprojects may be affected.
- Ruby versions are managed per project, usually via `.ruby-version`, and this repo upgrades them in lockstep across projects.
- When adding a new subproject in the future, give it its own local toolchain files and add an explicit job/path rule in the root CI workflow.

## CI

The canonical CI entry point for this monorepo is `.github/workflows/ci.yml`.

Child workflow files under subprojects are reference implementations for their local checks, but the root workflow is the primary automation entry point for the monorepo.

## Verification Commands

### `agents/fenix`

```bash
cd agents/fenix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bin/rails db:test:prepare
bin/rails test
```

### `core_matrix`

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
```

### `core_matrix/vendor/simple_inference`

```bash
cd core_matrix/vendor/simple_inference
bundle exec rake
```
