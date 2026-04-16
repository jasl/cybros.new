# Multi-Arch Docker Publishing Design

## Goal

Make every publishable Dockerfile in the monorepo capable of building for both
`linux/amd64` and `linux/arm64` with `docker buildx build --platform ...`,
without relying on GitHub CI-specific behavior and without expanding scope to
non-release containers.

The concrete target is:

- keep default GitHub CI verification unchanged
- ignore devcontainer and other non-publish container flows
- harden all publishable Dockerfiles so they can participate in a real
  multi-arch release
- document the publishing contract clearly, especially where one image depends
  on another published base image

## Problem

The repository already leans toward multi-arch compatibility, but the current
state is inconsistent:

1. `images/nexus/Dockerfile` already branches on `TARGETARCH` for Node.js and
   Go downloads, so it is the strongest multi-arch candidate in the repo.
2. `core_matrix/Dockerfile`, `agents/fenix/Dockerfile`, and
   `execution_runtimes/nexus/Dockerfile` still use `uname -m` for the jemalloc
   symlink path. That works in many cases, but it is an unnecessary host/arch
   coupling in a release contract.
3. `execution_runtimes/nexus` inherits its runtime toolchain from
   `images/nexus`, but that dependency is not documented as a multi-arch
   publishing requirement.
4. The current docs mostly show single-arch `docker build ...` commands, which
   makes it easy to keep shipping architecture-specific tags by accident even
   when the Dockerfiles themselves are close to ready.

The repo therefore has partial multi-arch compatibility, but not a clear or
uniform multi-arch publishing contract.

## Recommendation

Adopt a minimal, explicit multi-arch publishing contract:

- preserve the current `images/nexus` architecture-aware toolchain downloads
- remove architecture-sensitive runtime path logic from the application
  Dockerfiles
- document that `execution_runtimes/nexus` only becomes multi-arch when its
  `NEXUS_BASE_IMAGE` resolves to a multi-arch manifest
- add contract tests that guard the release-facing architecture assumptions

This keeps the repo aligned with the existing product boundaries:

- `images/nexus` owns the heavy runtime baseline and architecture-specific
  toolchain acquisition
- each application Dockerfile owns only app packaging and runtime-local wiring
- release workflow behavior stays outside the Dockerfiles themselves

## Scope

### In scope

- `images/nexus/Dockerfile`
- `core_matrix/Dockerfile`
- `agents/fenix/Dockerfile`
- `execution_runtimes/nexus/Dockerfile`
- release-facing documentation for `images/nexus` and `execution_runtimes/nexus`
- focused contract tests that pin the new multi-arch expectations

### Out of scope

- changing the default GitHub CI flow
- adding a new release workflow in this change
- changing devcontainer or local-only container flows
- introducing registry-specific tagging or push logic into the Dockerfiles

## Design

### 1. Keep `images/nexus` as the architecture-aware base image

`images/nexus` already contains the right kind of logic:

- `TARGETARCH` decides which Node.js archive to download
- `TARGETARCH` decides which Go archive to download
- the image fails fast for unsupported architectures

That should remain the source of truth for architecture-sensitive toolchain
setup. The design change here is not to replace that logic, but to make its
release contract more explicit:

- the supported release targets are `amd64` and `arm64`
- the Dockerfile is intended to be driven by `buildx`
- the README should show both local verification and multi-arch publishing
  commands distinctly

### 2. Remove `uname -m` from publishable application Dockerfiles

`core_matrix`, `agents/fenix`, and `execution_runtimes/nexus` only use
architecture detection to create the jemalloc symlink. They do not need
host-flavored architecture naming at all.

The preferred change is to resolve the installed `libjemalloc.so.2` path from
the image filesystem itself and link that resolved path into
`/usr/local/lib/libjemalloc.so`.

That produces a better release contract because:

- it depends on the package installed inside the target image, not on host
  naming conventions
- it works the same way for `amd64` and `arm64`
- it avoids maintaining an `amd64 -> x86_64-linux-gnu` / `arm64 ->
  aarch64-linux-gnu` mapping table in multiple Dockerfiles

### 3. Make `execution_runtimes/nexus` inherit multi-arch explicitly

`execution_runtimes/nexus` should not grow its own architecture selection
layer. The correct model is:

- `images/nexus` publishes a multi-arch base image
- `execution_runtimes/nexus` builds on top of that base image
- the resulting runtime image is multi-arch only if the referenced base image
  tag or digest is multi-arch

This dependency should be documented in both:

- `execution_runtimes/nexus/Dockerfile`
- `execution_runtimes/nexus/README.md` and/or `env.sample`

That makes the release behavior explicit instead of implied.

### 4. Guard the contract with focused tests

This work should not rely on humans remembering the new rules. Add a focused
contract test in `core_matrix/test/lib` that checks release-facing invariants,
for example:

- publishable Dockerfiles no longer rely on `uname -m` for architecture
  resolution
- `images/nexus/Dockerfile` still handles `amd64` and `arm64`
- `images/nexus/README.md` documents a multi-arch `buildx` command
- `execution_runtimes/nexus` docs mention the requirement for a multi-arch
  `NEXUS_BASE_IMAGE`

These are cheap, stable checks that protect the release contract without
changing CI topology.

## Evidence And Artifacts

The implementation should produce:

- a diff showing the publishable Dockerfiles no longer depend on `uname -m`
  for release-critical behavior
- updated docs showing the canonical multi-arch build/publish examples
- focused test output proving the new contract
- at least one direct `buildx` verification path on `images/nexus` for both
  `linux/amd64` and `linux/arm64`

## Testing Strategy

### Contract tests

- add or extend tests under `core_matrix/test/lib` to pin the new Dockerfile and
  documentation contract

### Direct Docker verification

- build `images/nexus` for `linux/amd64`
- build `images/nexus` for `linux/arm64`
- optionally spot-check dependent app images once the filesystem-path changes
  are in place

### Full verification

- run the focused `core_matrix` test file that covers the contract
- run any additional targeted tests affected by the documentation assertions

## Success Criteria

- all publishable Dockerfiles can participate in a `buildx` multi-arch release
  for `linux/amd64` and `linux/arm64`
- no publishable Dockerfile depends on `uname -m` for release-critical path
  resolution
- `images/nexus` remains the architecture-aware source of truth for the bundled
  runtime baseline
- `execution_runtimes/nexus` clearly documents its dependency on a multi-arch
  `NEXUS_BASE_IMAGE`
- repository docs show the intended multi-arch publishing flow without changing
  the default CI verification contract
