# Multi-Arch Docker Publishing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Harden every publishable Dockerfile in the repo so it can participate in a `docker buildx build --platform linux/amd64,linux/arm64 ...` release, while leaving the default GitHub CI verification flow unchanged.

**Architecture:** Keep `images/nexus` as the architecture-aware toolchain base, remove `uname -m`-driven path assumptions from app Dockerfiles, document that `execution_runtimes/nexus` inherits multi-arch support from a multi-arch `NEXUS_BASE_IMAGE`, and pin the release contract with focused tests and docs.

**Tech Stack:** Dockerfile, BuildKit/buildx semantics, Ruby/Minitest contract tests, existing monorepo docs under `docs/plans`, release-facing READMEs and env samples.

---

### Task 1: Add focused contract tests for the multi-arch publishing rules

**Files:**
- Create: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/test/lib/dockerfile_multi_arch_contract_test.rb`

**Steps:**
1. Write failing tests that assert:
   - `images/nexus/Dockerfile` contains `TARGETARCH` handling for `amd64` and `arm64`
   - publishable app Dockerfiles do not contain `uname -m`
   - `images/nexus/README.md` mentions `docker buildx build --platform linux/amd64,linux/arm64`
   - `execution_runtimes/nexus/README.md` or `env.sample` documents the requirement for a multi-arch `NEXUS_BASE_IMAGE`
2. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/rails test test/lib/dockerfile_multi_arch_contract_test.rb
   ```
   Expected: FAIL on the current single-arch documentation and `uname -m` usage.
3. Keep the failure output as the red phase proof before touching the Dockerfiles.

### Task 2: Remove `uname -m` coupling from publishable app Dockerfiles

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/core_matrix/Dockerfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/agents/fenix/Dockerfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Dockerfile`

**Steps:**
1. Replace the jemalloc symlink logic with a filesystem-based lookup that resolves the installed `libjemalloc.so.2` path from inside the image instead of deriving a multiarch directory from `uname -m`.
2. Keep the rest of each Dockerfile unchanged unless a change is necessary to support the new lookup.
3. Re-run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/rails test test/lib/dockerfile_multi_arch_contract_test.rb
   ```
   Expected: the `uname -m` assertions now pass, while the documentation assertions may still fail.

### Task 3: Make the release contract explicit in `images/nexus`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/images/nexus/Dockerfile`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/images/nexus/README.md`

**Steps:**
1. Tighten the Dockerfile comments or build args so the supported release targets and buildx-driven target-platform contract are explicit.
2. Add release-facing README examples for:
   - local verification build
   - multi-arch release build/push via `docker buildx build --platform linux/amd64,linux/arm64`
3. Re-run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/rails test test/lib/dockerfile_multi_arch_contract_test.rb
   ```
   Expected: the README multi-arch assertion now passes.

### Task 4: Document the inherited multi-arch rule for `execution_runtimes/nexus`

**Files:**
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/README.md`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/env.sample`
- Modify: `/Users/jasl/Workspaces/Ruby/cybros/execution_runtimes/nexus/Dockerfile`

**Steps:**
1. Update the Dockerfile comments and runtime docs so they say plainly that `NEXUS_BASE_IMAGE` must resolve to a multi-arch tag or digest for `execution_runtimes/nexus` to be published as `amd64` + `arm64`.
2. Add a concrete example that uses `docker buildx build --platform linux/amd64,linux/arm64` with a published multi-arch base image reference.
3. Re-run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/rails test test/lib/dockerfile_multi_arch_contract_test.rb
   ```
   Expected: all focused contract tests pass.

### Task 5: Run direct buildx verification on the bundled base image

**Files:**
- No new files expected

**Steps:**
1. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros
   docker buildx build --platform linux/amd64 --load -f images/nexus/Dockerfile -t nexus-test-amd64 .
   ```
   Expected: build completes successfully.
2. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros
   docker buildx build --platform linux/arm64 --load -f images/nexus/Dockerfile -t nexus-test-arm64 .
   ```
   Expected: build completes successfully.
3. If either build fails, fix only the release-contract issue revealed by the failure and repeat until both platforms build.

### Task 6: Final targeted verification

**Files:**
- No new files expected

**Steps:**
1. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros/core_matrix
   bin/rails test test/lib/dockerfile_multi_arch_contract_test.rb
   ```
2. Run:
   ```bash
   cd /Users/jasl/Workspaces/Ruby/cybros
   git diff -- docs/plans/2026-04-17-multi-arch-docker-publishing-design.md \
     docs/plans/2026-04-17-multi-arch-docker-publishing-implementation.md \
     core_matrix/Dockerfile \
     agents/fenix/Dockerfile \
     images/nexus/Dockerfile \
     images/nexus/README.md \
     execution_runtimes/nexus/Dockerfile \
     execution_runtimes/nexus/README.md \
     execution_runtimes/nexus/env.sample \
     core_matrix/test/lib/dockerfile_multi_arch_contract_test.rb
   ```
3. Confirm the diff matches the design scope: publishable Dockerfiles, focused docs, and focused tests only.

Plan complete and saved to `docs/plans/2026-04-17-multi-arch-docker-publishing-implementation.md`. Two execution options:

1. Subagent-Driven (this session)
2. Parallel Session (separate)
