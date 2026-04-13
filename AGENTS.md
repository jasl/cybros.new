# AGENTS.md

## Scope

This repository is a monorepo. Treat each top-level product directory as an independent project unless a change is explicitly shared.

`references/` is reference-only material. It is not part of the product codebase, should not be used as the default source of truth, and should not drive CI, tests, or implementation scope unless explicitly requested.

## Projects

- `agents/fenix`: active cowork Ruby on Rails application
- `core_matrix`: main Ruby on Rails application
- `core_matrix/vendor/simple_inference`: vendored Ruby gem maintained in-tree
- `images/nexus`: Docker runtime base project for cowork agents

## Working Rules

- Run commands from the target project directory.
- Keep changes scoped to the requested subproject whenever possible.
- For `core_matrix`, do not expose internal `bigint` ids at external or
  agent-facing boundaries; use `public_id` and see
  `core_matrix/docs/behavior/identifier-policy.md` for the product-specific
  rules.
- For `core_matrix`, changes that touch conversation/turn/workflow bootstrap,
  runtime event streams, app-facing roundtrip paths, or other
  acceptance-critical loop behavior are not complete with focused tests alone.
  Before closing that work, run the full `core_matrix` verification suite, run
  `ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh`
  from the repo root, and inspect both the relevant acceptance artifacts and the
  resulting database state to confirm business data shapes and state transitions
  are correct.
- For destructive schema refactors in any Rails subproject that owns
  `db/schema.rb` and rewrites original migrations in place, use the standard
  rebuild flow from that project root to safely regenerate the schema:
  `rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset`
  At the moment this applies to `core_matrix`; `agents/fenix` and
  `images/nexus` do not currently depend on a database.
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

For `core_matrix` changes that modify acceptance-critical loop behavior, finish
verification with:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
ACTIVE_ACCEPTANCE_ENABLE_2048_CAPSTONE=1 bash acceptance/bin/run_active_suite.sh
```

For destructive Rails migration rewrites in any database-backed subproject,
regenerate the database and `db/schema.rb` from that project root with:

```bash
rails db:drop && rm db/schema.rb && rails db:create && rails db:migrate && rails db:reset
```

### `core_matrix/vendor/simple_inference`

```bash
cd core_matrix/vendor/simple_inference
bundle exec rake
```

### `images/nexus`

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
docker build -f images/nexus/Dockerfile -t nexus-local .
docker run --rm -v /Users/jasl/Workspaces/Ruby/cybros:/workspace nexus-local /workspace/images/nexus/verify.sh
```
