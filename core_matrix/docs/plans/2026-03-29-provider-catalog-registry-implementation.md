# Provider Catalog Registry Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Introduce a central provider catalog registry with safe reload semantics, migrate static catalog reads to it, and move catalog-backed validation to service boundaries with targeted concurrency and consistency tests.

**Architecture:** Add an immutable `ProviderCatalog::Snapshot`, a thread-safe `ProviderCatalog::Registry`, and a thin `ProviderCatalog::EffectiveCatalog` extension point. Migrate existing static catalog callers to `Registry.current`, remove model-level catalog validation, and enforce provider/model existence at the application service boundary.

**Tech Stack:** Ruby on Rails 8.2, ActiveSupport cache, Minitest

---

### Task 1: Add failing tests for the registry

**Files:**
- Create: `test/services/provider_catalog/registry_test.rb`

**Step 1: Write the failing test**

- cover initial load, reload, failed reload preserving the previous snapshot, shared-revision refresh, and concurrent reads during reload

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/provider_catalog/registry_test.rb`

Expected: FAIL because `ProviderCatalog::Registry` does not exist yet

**Step 3: Write minimal implementation**

- add `ProviderCatalog::Snapshot`
- add `ProviderCatalog::Registry`
- update the loader to return snapshots

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/provider_catalog/registry_test.rb`

Expected: PASS

### Task 2: Move provider existence validation to service boundaries

**Files:**
- Modify: `app/services/provider_credentials/upsert_secret.rb`
- Modify: `app/services/provider_policies/upsert.rb`
- Modify: `app/services/provider_entitlements/upsert.rb`
- Modify: `app/services/conversations/update_override.rb`
- Modify: `test/services/provider_credentials/upsert_secret_test.rb`
- Modify: `test/services/provider_policies/upsert_test.rb`
- Modify: `test/services/provider_entitlements/upsert_test.rb`
- Modify: `test/services/conversations/update_override_test.rb`
- Modify: `test/models/provider_credential_test.rb`
- Modify: `test/models/provider_policy_test.rb`
- Modify: `test/models/provider_entitlement_test.rb`

**Step 1: Write the failing test**

- add service tests for unknown provider/model rejection
- update model tests to stop expecting catalog-backed validation

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/provider_credentials/upsert_secret_test.rb test/services/provider_policies/upsert_test.rb test/services/provider_entitlements/upsert_test.rb test/services/conversations/update_override_test.rb test/models/provider_credential_test.rb test/models/provider_policy_test.rb test/models/provider_entitlement_test.rb`

Expected: FAIL until validation is moved into services

**Step 3: Write minimal implementation**

- remove catalog-backed validations from models
- add provider/model existence checks in the service entry points

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/provider_credentials/upsert_secret_test.rb test/services/provider_policies/upsert_test.rb test/services/provider_entitlements/upsert_test.rb test/services/conversations/update_override_test.rb test/models/provider_credential_test.rb test/models/provider_policy_test.rb test/models/provider_entitlement_test.rb`

Expected: PASS

### Task 3: Migrate static catalog readers to the registry

**Files:**
- Modify: `app/services/provider_catalog/load.rb`
- Modify: `app/services/workflows/resolve_model_selector.rb`
- Modify: `app/services/providers/check_availability.rb`
- Modify: `app/services/workflows/build_execution_snapshot.rb`
- Modify: `app/services/provider_execution/execute_turn_step.rb`
- Modify: `app/services/provider_execution/dispatch_request.rb`
- Modify: `app/controllers/mock_llm/v1/models_controller.rb`
- Modify: `db/seeds.rb`
- Modify: `test/test_helper.rb`
- Modify: `test/services/provider_catalog/load_test.rb`

**Step 1: Write the failing test**

- add or update tests to exercise callers through `ProviderCatalog::Registry.current`

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/provider_catalog/load_test.rb test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/services/workflows/build_execution_snapshot_test.rb`

Expected: FAIL while callers still depend on direct `Load.call`

**Step 3: Write minimal implementation**

- switch default catalog access to the registry
- keep targeted dependency injection where it already helps tests

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/provider_catalog/load_test.rb test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/services/workflows/build_execution_snapshot_test.rb`

Expected: PASS

### Task 4: Add the extension point for effective availability

**Files:**
- Create: `app/services/provider_catalog/effective_catalog.rb`
- Create or Modify: `test/services/provider_catalog/effective_catalog_test.rb`

**Step 1: Write the failing test**

- cover the initial facade behavior around static role candidates and installation-scoped availability checks

**Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/provider_catalog/effective_catalog_test.rb`

Expected: FAIL because the facade does not exist yet

**Step 3: Write minimal implementation**

- add a thin facade around `Registry.current` and `Providers::CheckAvailability`

**Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/provider_catalog/effective_catalog_test.rb`

Expected: PASS

### Task 5: Run focused verification and lint

**Files:**
- Modify: none unless fixes are required

**Step 1: Run targeted test suite**

Run: `bin/rails test test/services/provider_catalog/load_test.rb test/services/provider_catalog/registry_test.rb test/services/provider_catalog/effective_catalog_test.rb test/services/provider_credentials/upsert_secret_test.rb test/services/provider_policies/upsert_test.rb test/services/provider_entitlements/upsert_test.rb test/services/conversations/update_override_test.rb test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/services/workflows/build_execution_snapshot_test.rb test/models/provider_credential_test.rb test/models/provider_policy_test.rb test/models/provider_entitlement_test.rb`

Expected: PASS

**Step 2: Run focused lint**

Run: `bin/rubocop app/services/provider_catalog app/services/provider_credentials/upsert_secret.rb app/services/provider_policies/upsert.rb app/services/provider_entitlements/upsert.rb app/services/conversations/update_override.rb app/services/providers/check_availability.rb app/services/workflows/resolve_model_selector.rb app/services/workflows/build_execution_snapshot.rb app/services/provider_execution/execute_turn_step.rb app/services/provider_execution/dispatch_request.rb app/controllers/mock_llm/v1/models_controller.rb app/models/provider_credential.rb app/models/provider_policy.rb app/models/provider_entitlement.rb app/models/conversation.rb test/services/provider_catalog test/services/provider_credentials/upsert_secret_test.rb test/services/provider_policies/upsert_test.rb test/services/provider_entitlements/upsert_test.rb test/services/conversations/update_override_test.rb test/services/providers/check_availability_test.rb test/services/workflows/resolve_model_selector_test.rb test/services/workflows/build_execution_snapshot_test.rb test/models/provider_credential_test.rb test/models/provider_policy_test.rb test/models/provider_entitlement_test.rb`

Expected: PASS
