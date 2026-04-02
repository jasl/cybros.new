# Conversation Export, Import, And Debug Bundles Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add user-facing asynchronous conversation export and import bundles, plus a separate internal debug export bundle flow, without mixing user asset portability with runtime diagnostics.

**Architecture:** Use three independent request models in `core_matrix`: `ConversationExportRequest`, `ConversationDebugExportRequest`, and `ConversationBundleImportRequest`. User export/import operates on a versioned `zip` bundle that contains only conversation-visible history and message-bound files. Debug export remains a separate internal bundle family. All request types are async, attached-file based, and time-limited via explicit expiry handling.

**Tech Stack:** Ruby on Rails, Active Record, Active Job, Active Storage, JSON/ZIP bundle generation, request controllers under `AgentAPI`, and existing conversation transcript/message attachment models.

---

## Preconditions

- Approved design:
  - `docs/plans/2026-04-02-conversation-export-import-and-debug-bundles-design.md`
- Re-read before implementing:
  - `core_matrix/app/models/conversation.rb`
  - `core_matrix/app/models/message.rb`
  - `core_matrix/app/models/message_attachment.rb`
  - `core_matrix/app/models/conversation_import.rb`
  - `core_matrix/app/models/workflow_artifact.rb`
  - `core_matrix/app/controllers/agent_api/conversation_transcripts_controller.rb`
  - `core_matrix/app/projections/conversation_transcripts/page_projection.rb`
  - `core_matrix/app/services/conversations/context_projection.rb`
  - `core_matrix/app/services/attachments/materialize_refs.rb`
  - `core_matrix/config/routes.rb`
- Guardrails:
  - do not reuse `ConversationImport` for user bundle import requests
  - do not reuse `WorkflowArtifact` as the export request container
  - do not scan workspace files
  - do not support append import
  - do not support third-party import formats in v1

## Target Deliverables

1. User export request flow

- `ConversationExportRequest`
- create/show/download API
- async bundle generation
- TTL expiry and file purge

2. User import request flow

- `ConversationBundleImportRequest`
- upload/create/show API
- async validation and import
- all-or-nothing import into a new conversation

3. Internal debug export request flow

- `ConversationDebugExportRequest`
- create/show/download API
- separate debug bundle payload

4. Shared bundle helpers

- manifest generation and verification
- transcript markdown rendering
- transcript HTML rendering
- zip assembly and extraction helpers

5. Test coverage

- model invariants
- service tests for bundle generation and import validation
- request tests for all public endpoints
- job tests for success, failure, and expiry

### Task 1: Add request tables and models for export, debug export, and bundle import

**Files:**
- Create: `core_matrix/db/migrate/20260402160000_create_conversation_export_requests.rb`
- Create: `core_matrix/db/migrate/20260402160100_create_conversation_debug_export_requests.rb`
- Create: `core_matrix/db/migrate/20260402160200_create_conversation_bundle_import_requests.rb`
- Create: `core_matrix/app/models/conversation_export_request.rb`
- Create: `core_matrix/app/models/conversation_debug_export_request.rb`
- Create: `core_matrix/app/models/conversation_bundle_import_request.rb`
- Test: `core_matrix/test/models/conversation_export_request_test.rb`
- Test: `core_matrix/test/models/conversation_debug_export_request_test.rb`
- Test: `core_matrix/test/models/conversation_bundle_import_request_test.rb`

**Step 1: Write the failing tests**

Add model tests for:

- installation/workspace/conversation consistency
- allowed lifecycle states for export requests: `queued`, `running`,
  `succeeded`, `failed`, `expired`
- allowed lifecycle states for import requests: `queued`, `running`,
  `succeeded`, `failed`
- required `expires_at` on export request models
- attached file presence rules for succeeded export requests
- attached upload presence rules for import request creation
- prohibition on reusing `ConversationImport`

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/models/conversation_export_request_test.rb test/models/conversation_debug_export_request_test.rb test/models/conversation_bundle_import_request_test.rb
```

Expected: FAIL because the tables and models do not exist yet.

**Step 3: Write minimal implementation**

- create the three tables with:
  - `installation_id`
  - `workspace_id`
  - `conversation_id` where applicable
  - `user_id` for initiator attribution
  - lifecycle state
  - request payload / result payload JSON
  - failure payload JSON
  - `expires_at`
  - timestamps for queue/start/finish
- add `has_one_attached :bundle_file` to export request models
- add `has_one_attached :upload_file` to the import request model
- add validations and public-id support where externally referenced

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/models/conversation_export_request_test.rb test/models/conversation_debug_export_request_test.rb test/models/conversation_bundle_import_request_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/db/migrate/20260402160000_create_conversation_export_requests.rb core_matrix/db/migrate/20260402160100_create_conversation_debug_export_requests.rb core_matrix/db/migrate/20260402160200_create_conversation_bundle_import_requests.rb core_matrix/app/models/conversation_export_request.rb core_matrix/app/models/conversation_debug_export_request.rb core_matrix/app/models/conversation_bundle_import_request.rb core_matrix/test/models/conversation_export_request_test.rb core_matrix/test/models/conversation_debug_export_request_test.rb core_matrix/test/models/conversation_bundle_import_request_test.rb
git commit -m "feat: add conversation bundle request models"
```

### Task 2: Build the user export bundle format and generation services

**Files:**
- Create: `core_matrix/app/services/conversation_exports/build_manifest.rb`
- Create: `core_matrix/app/services/conversation_exports/build_conversation_payload.rb`
- Create: `core_matrix/app/services/conversation_exports/render_transcript_markdown.rb`
- Create: `core_matrix/app/services/conversation_exports/render_transcript_html.rb`
- Create: `core_matrix/app/services/conversation_exports/write_zip_bundle.rb`
- Create: `core_matrix/app/services/conversation_exports/create_request.rb`
- Create: `core_matrix/app/services/conversation_exports/execute_request.rb`
- Test: `core_matrix/test/services/conversation_exports/build_manifest_test.rb`
- Test: `core_matrix/test/services/conversation_exports/build_conversation_payload_test.rb`
- Test: `core_matrix/test/services/conversation_exports/write_zip_bundle_test.rb`
- Test: `core_matrix/test/services/conversation_exports/execute_request_test.rb`

**Step 1: Write the failing tests**

Write tests that assert the user bundle contains exactly:

- `manifest.json`
- `conversation.json`
- `transcript.md`
- `conversation.html`
- `files/...`

Also assert:

- only message-bound files are included
- file entries contain `kind`, `message_public_id`, `filename`, `mime_type`,
  `byte_size`, `sha256`, and `relative_path`
- no bigint ids appear in the generated JSON

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/conversation_exports/build_manifest_test.rb test/services/conversation_exports/build_conversation_payload_test.rb test/services/conversation_exports/write_zip_bundle_test.rb test/services/conversation_exports/execute_request_test.rb
```

Expected: FAIL because the export services do not exist yet.

**Step 3: Write minimal implementation**

- build a stable `manifest.json`
- reuse transcript/message attachment semantics from existing conversation
  projections
- render a static markdown transcript
- render a static human-readable HTML transcript
- copy only message-bound files into `files/...`
- attach the resulting zip to `ConversationExportRequest#bundle_file`
- record `message_count`, `attachment_count`, and generator metadata into the
  request result payload

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/conversation_exports/build_manifest_test.rb test/services/conversation_exports/build_conversation_payload_test.rb test/services/conversation_exports/write_zip_bundle_test.rb test/services/conversation_exports/execute_request_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversation_exports core_matrix/test/services/conversation_exports
git commit -m "feat: build user conversation export bundles"
```

### Task 3: Build the user import parsing, validation, and atomic rehydration flow

**Files:**
- Create: `core_matrix/app/services/conversation_bundle_imports/parse_upload.rb`
- Create: `core_matrix/app/services/conversation_bundle_imports/validate_manifest.rb`
- Create: `core_matrix/app/services/conversation_bundle_imports/create_request.rb`
- Create: `core_matrix/app/services/conversation_bundle_imports/execute_request.rb`
- Create: `core_matrix/app/services/conversation_bundle_imports/rehydrate_conversation.rb`
- Test: `core_matrix/test/services/conversation_bundle_imports/parse_upload_test.rb`
- Test: `core_matrix/test/services/conversation_bundle_imports/validate_manifest_test.rb`
- Test: `core_matrix/test/services/conversation_bundle_imports/rehydrate_conversation_test.rb`
- Test: `core_matrix/test/services/conversation_bundle_imports/execute_request_test.rb`

**Step 1: Write the failing tests**

Add tests for:

- unsupported `bundle_kind`
- unsupported `bundle_version`
- checksum mismatch
- missing `conversation.json`
- missing attachment file referenced by manifest
- successful rehydration into a new conversation with new `public_id` values
- preservation of message order and timestamps
- rollback on any validation or attachment mismatch

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/conversation_bundle_imports/parse_upload_test.rb test/services/conversation_bundle_imports/validate_manifest_test.rb test/services/conversation_bundle_imports/rehydrate_conversation_test.rb test/services/conversation_bundle_imports/execute_request_test.rb
```

Expected: FAIL because the import pipeline does not exist yet.

**Step 3: Write minimal implementation**

- parse the uploaded zip into a temporary working area
- validate manifest and checksums before any conversation write
- refuse any third-party or unknown bundle format
- rehydrate a brand-new conversation, messages, and attachments inside one
  database transaction
- keep original timestamps and ordering in user-visible fields
- write provenance metadata into the import request result payload

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/conversation_bundle_imports/parse_upload_test.rb test/services/conversation_bundle_imports/validate_manifest_test.rb test/services/conversation_bundle_imports/rehydrate_conversation_test.rb test/services/conversation_bundle_imports/execute_request_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversation_bundle_imports core_matrix/test/services/conversation_bundle_imports
git commit -m "feat: import user conversation bundles atomically"
```

### Task 4: Build the internal debug export bundle flow

**Files:**
- Create: `core_matrix/app/services/conversation_debug_exports/build_payload.rb`
- Create: `core_matrix/app/services/conversation_debug_exports/write_zip_bundle.rb`
- Create: `core_matrix/app/services/conversation_debug_exports/create_request.rb`
- Create: `core_matrix/app/services/conversation_debug_exports/execute_request.rb`
- Test: `core_matrix/test/services/conversation_debug_exports/build_payload_test.rb`
- Test: `core_matrix/test/services/conversation_debug_exports/execute_request_test.rb`

**Step 1: Write the failing tests**

Write tests that assert debug export:

- uses a different bundle kind than user export
- includes diagnostics/runtime evidence payloads
- never produces an importable `conversation_export` manifest
- keeps bigint ids internal unless explicitly transformed to public ids for
  debug readability

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/services/conversation_debug_exports/build_payload_test.rb test/services/conversation_debug_exports/execute_request_test.rb
```

Expected: FAIL because the debug export services do not exist yet.

**Step 3: Write minimal implementation**

- build a debug payload containing transcript, diagnostics snapshots, workflow
  summaries, tool/process/command summaries, subagent summaries, and usage
  summaries
- write it into a dedicated debug zip bundle
- attach it to `ConversationDebugExportRequest#bundle_file`
- keep the format clearly distinct from the user export bundle family

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/services/conversation_debug_exports/build_payload_test.rb test/services/conversation_debug_exports/execute_request_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/services/conversation_debug_exports core_matrix/test/services/conversation_debug_exports
git commit -m "feat: add conversation debug export bundles"
```

### Task 5: Add jobs and expiry handling for all request types

**Files:**
- Create: `core_matrix/app/jobs/conversation_exports/execute_request_job.rb`
- Create: `core_matrix/app/jobs/conversation_exports/expire_request_job.rb`
- Create: `core_matrix/app/jobs/conversation_bundle_imports/execute_request_job.rb`
- Create: `core_matrix/app/jobs/conversation_debug_exports/execute_request_job.rb`
- Create: `core_matrix/app/jobs/conversation_debug_exports/expire_request_job.rb`
- Test: `core_matrix/test/jobs/conversation_exports/execute_request_job_test.rb`
- Test: `core_matrix/test/jobs/conversation_exports/expire_request_job_test.rb`
- Test: `core_matrix/test/jobs/conversation_bundle_imports/execute_request_job_test.rb`
- Test: `core_matrix/test/jobs/conversation_debug_exports/execute_request_job_test.rb`
- Test: `core_matrix/test/jobs/conversation_debug_exports/expire_request_job_test.rb`

**Step 1: Write the failing tests**

Add job tests for:

- transition from `queued` to `running`
- success and failure terminalization
- file purge on expiry
- request row retention after attached-file purge
- idempotent expiry handling

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/jobs/conversation_exports/execute_request_job_test.rb test/jobs/conversation_exports/expire_request_job_test.rb test/jobs/conversation_bundle_imports/execute_request_job_test.rb test/jobs/conversation_debug_exports/execute_request_job_test.rb test/jobs/conversation_debug_exports/expire_request_job_test.rb
```

Expected: FAIL because the jobs do not exist yet.

**Step 3: Write minimal implementation**

- create one execution job per request family
- create expiry jobs for the export families
- make expiry purge `bundle_file` while keeping the request metadata row
- guard against duplicate execution and duplicate expiry

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/jobs/conversation_exports/execute_request_job_test.rb test/jobs/conversation_exports/expire_request_job_test.rb test/jobs/conversation_bundle_imports/execute_request_job_test.rb test/jobs/conversation_debug_exports/execute_request_job_test.rb test/jobs/conversation_debug_exports/expire_request_job_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/app/jobs/conversation_exports core_matrix/app/jobs/conversation_bundle_imports core_matrix/app/jobs/conversation_debug_exports core_matrix/test/jobs/conversation_exports core_matrix/test/jobs/conversation_bundle_imports core_matrix/test/jobs/conversation_debug_exports
git commit -m "feat: add async execution and expiry for conversation bundles"
```

### Task 6: Expose separate API surfaces for user export, import, and debug export

**Files:**
- Modify: `core_matrix/config/routes.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_export_requests_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_bundle_import_requests_controller.rb`
- Create: `core_matrix/app/controllers/agent_api/conversation_debug_export_requests_controller.rb`
- Test: `core_matrix/test/requests/agent_api/conversation_export_requests_test.rb`
- Test: `core_matrix/test/requests/agent_api/conversation_bundle_import_requests_test.rb`
- Test: `core_matrix/test/requests/agent_api/conversation_debug_export_requests_test.rb`

**Step 1: Write the failing tests**

Add request tests that cover:

- `create` and `show` for all request families
- `download` only for export families
- public-id-only boundary behavior
- rejection of append-import semantics
- rejection of debug bundle import through the user import surface

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/requests/agent_api/conversation_export_requests_test.rb test/requests/agent_api/conversation_bundle_import_requests_test.rb test/requests/agent_api/conversation_debug_export_requests_test.rb
```

Expected: FAIL because the routes and controllers do not exist yet.

**Step 3: Write minimal implementation**

- add separate resource routes
- create request rows and enqueue jobs
- expose request status, expiry time, and download availability
- ensure all external ids are `public_id`
- keep debug export authorization separate from user export/import authorization

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/requests/agent_api/conversation_export_requests_test.rb test/requests/agent_api/conversation_bundle_import_requests_test.rb test/requests/agent_api/conversation_debug_export_requests_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/config/routes.rb core_matrix/app/controllers/agent_api/conversation_export_requests_controller.rb core_matrix/app/controllers/agent_api/conversation_bundle_import_requests_controller.rb core_matrix/app/controllers/agent_api/conversation_debug_export_requests_controller.rb core_matrix/test/requests/agent_api/conversation_export_requests_test.rb core_matrix/test/requests/agent_api/conversation_bundle_import_requests_test.rb core_matrix/test/requests/agent_api/conversation_debug_export_requests_test.rb
git commit -m "feat: add conversation bundle request APIs"
```

### Task 7: Add end-to-end regression coverage and documentation updates

**Files:**
- Modify: `core_matrix/test/integration/provider_backed_turn_execution_test.rb`
- Create: `core_matrix/test/integration/conversation_bundle_round_trip_test.rb`
- Modify: `docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md`
- Modify: `docs/plans/2026-04-02-conversation-diagnostics-and-usage-review.md`

**Step 1: Write the failing tests**

Add integration coverage for:

- exporting a conversation with attached files
- importing that bundle into a new conversation
- verifying message order and timestamps survive the round trip
- uploading an export bundle as a normal attachment without invoking import

**Step 2: Run tests to verify they fail**

```bash
cd core_matrix
bin/rails test test/integration/conversation_bundle_round_trip_test.rb
```

Expected: FAIL because the end-to-end bundle flow is not wired yet.

**Step 3: Write minimal implementation**

- finish any missing plumbing discovered by the integration test
- update the relevant docs to describe the new user export/import surfaces and
  the debug export split

**Step 4: Run tests to verify they pass**

```bash
cd core_matrix
bin/rails test test/integration/conversation_bundle_round_trip_test.rb
```

Expected: PASS

**Step 5: Commit**

```bash
git add core_matrix/test/integration/provider_backed_turn_execution_test.rb core_matrix/test/integration/conversation_bundle_round_trip_test.rb docs/checklists/2026-03-31-fenix-provider-backed-agent-capstone-acceptance.md docs/plans/2026-04-02-conversation-diagnostics-and-usage-review.md
git commit -m "test: cover conversation bundle round trip"
```

### Task 8: Run the full `core_matrix` verification matrix and perform one manual export/import smoke test

**Files:**
- Modify as needed based on failures from previous tasks

**Step 1: Run targeted verification**

```bash
cd core_matrix
bin/rails test test/models/conversation_export_request_test.rb test/models/conversation_debug_export_request_test.rb test/models/conversation_bundle_import_request_test.rb
bin/rails test test/services/conversation_exports
bin/rails test test/services/conversation_bundle_imports
bin/rails test test/services/conversation_debug_exports
bin/rails test test/jobs/conversation_exports test/jobs/conversation_bundle_imports test/jobs/conversation_debug_exports
bin/rails test test/requests/agent_api/conversation_export_requests_test.rb test/requests/agent_api/conversation_bundle_import_requests_test.rb test/requests/agent_api/conversation_debug_export_requests_test.rb
bin/rails test test/integration/conversation_bundle_round_trip_test.rb
```

Expected: PASS

**Step 2: Run full project verification**

```bash
cd core_matrix
bin/brakeman --no-pager
bin/bundler-audit
bin/rubocop -f github
bun run lint:js
bin/rails db:test:prepare test
bin/rails db:test:prepare test:system
```

Expected: PASS

**Step 3: Perform one manual smoke test**

Use a real conversation containing at least one uploaded attachment:

- create a user export request
- wait for bundle generation
- download the zip
- create an import request with the zip
- verify a new conversation is created
- verify attachment files are present on imported messages
- verify exporting bundle upload into a different conversation behaves as a
  normal attachment, not an import

**Step 4: Commit**

```bash
git add -A
git commit -m "feat: add conversation export and import bundles"
```

Plan complete and saved to `docs/plans/2026-04-02-conversation-export-import-and-debug-bundles.md`. Two execution options:

**1. Subagent-Driven (this session)** - I dispatch fresh subagent per task, review between tasks, fast iteration

**2. Parallel Session (separate)** - Open new session with executing-plans, batch execution with checkpoints

**Which approach?**
