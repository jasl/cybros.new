# Core Matrix

`core_matrix` is being rebuilt as the backend kernel substrate for Core Matrix.

Current authoritative project documents:

- Greenfield design: `../docs/design/2026-03-24-core-matrix-kernel-greenfield-design.md`
- Phase shaping: `../docs/design/2026-03-24-core-matrix-kernel-phase-shaping-design.md`
- Active implementation plan: `../docs/plans/2026-03-24-core-matrix-kernel-greenfield-implementation-plan.md`
- Deferred UI follow-up: `../docs/future-plans/2026-03-24-core-matrix-kernel-ui-follow-up.md`
- Manual validation checklist: `../docs/checklists/2026-03-24-core-matrix-kernel-manual-validation.md`

Current scope for this phase:

- backend models, services, protocol boundaries, tests, and manual backend validation
- no human-facing UI, Turbo, Stimulus, or browser delivery work

Useful baseline commands:

```bash
bin/rails db:version
bin/rails test
bin/rubocop app/models/application_record.rb
```

Environment notes:

- Host-side Rails commands load local `.env*` files via `dotenv-rails`, including bare-metal production boots.
- Leave `RAILS_DB_URL_BASE` unset on macOS to use bare-metal PostgreSQL over the default Unix socket.
- Set `RAILS_DB_URL_BASE=postgresql://postgres:postgres@127.0.0.1:5432` on Ubuntu when Rails runs on the host and PostgreSQL 18 runs in Docker with a published port.
- Containerized services still use Docker Compose environment injection. In `compose.yaml.sample`, explicit service `environment` values override same-named values coming from `env_file`.
