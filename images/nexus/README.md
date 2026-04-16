# Nexus Runtime Base

`images/nexus` is the Docker-only cowork runtime base image for `agents/fenix`.
It owns durable toolchain setup only; it does not own prompt logic, memory, or
agent behavior.

## Source Of Truth

[`versions.env`](./versions.env) is the source of truth for installable
toolchain versions. The Ubuntu base image stays pinned in the Dockerfile
because Docker cannot read `versions.env` before `FROM`.

## Included In V1

- Ubuntu 24.04
- Node LTS with `npm`, `corepack`, `pnpm`
- `vite` and `create-vite`
- Playwright with Chromium and Linux browser dependencies
- `uv` plus a managed Python 3.12 runtime contract rooted at `FENIX_HOME_ROOT/python`, exposing `python` and `pip` from that managed runtime once the agent bootstraps
- Ruby 4.0.2 with Bundler 4.0.10 and native extension build prerequisites
- Go
- Rust
- common CLI/build tools: `git`, `curl`, `jq`, `unzip`, `zip`, `ripgrep`,
  `fd`, `sqlite3`, `build-essential`, `pkg-config`

## Command Availability

`images/nexus` intentionally splits command availability into two layers.

System-level commands are available directly from the image:

- `ruby`, `bundle`
- `node`, `npm`, `pnpm`, `corepack`
- `playwright`, `vite`, `create-vite`
- `uv`
- `go`
- `rustc`, `cargo`
- `git`, `curl`, `jq`, `rg`, `fd`, `sqlite3`
- Chromium/Chrome browser executables

Managed Python commands are not prebound into the base image `PATH`. Instead,
the agent bootstrap provisions `FENIX_HOME_ROOT/python` and then exposes:

- `python`, `python3`
- `pip`, `pip3`

This keeps the durable system toolchain separate from the agent-owned Python
runtime while still making `python` and `pip` transparently available inside a
running `Fenix` process.

## Build

Recommended local build: use the `images/nexus` directory as the Docker context
so the local `.dockerignore` applies.

```bash
docker build \
  --build-arg NEXUS_CONTEXT_PREFIX= \
  -f images/nexus/Dockerfile \
  -t nexus-local \
  images/nexus
```

Plan/acceptance build: build from the monorepo root.

```bash
docker build -f images/nexus/Dockerfile -t nexus-local .
```

## Multi-Arch Release

`images/nexus` is the canonical architecture-aware base image for the bundled
runtime stack. Release builds are intended to run through Buildx and currently
support `linux/amd64` and `linux/arm64`.

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  --build-arg NEXUS_CONTEXT_PREFIX= \
  -f images/nexus/Dockerfile \
  -t ghcr.io/your-org/nexus-base:latest \
  --push \
  images/nexus
```

## Verify

The acceptance check mounts this repository and runs the repo-owned verifier
inside the built image:

```bash
docker run --rm \
  -v /Users/jasl/Workspaces/Ruby/cybros:/workspace \
  nexus-local \
  /workspace/images/nexus/verify.sh
```

## Task 9 Verification

For the Task 9 verification and root CI flow, build `images/nexus` from the
repository root and run the verifier against the mounted checkout that also
contains `agents/fenix`:

```bash
cd /Users/jasl/Workspaces/Ruby/cybros
docker build -f images/nexus/Dockerfile -t nexus-local .
docker run --rm -v /Users/jasl/Workspaces/Ruby/cybros:/workspace nexus-local /workspace/images/nexus/verify.sh
```

## Design Notes

- project shape and verification flow borrow from
  `references/original/references/codex-universal`
- runtime dependency selection tracks the active `agents/fenix` contract
- version truth stays local to this subproject instead of copying the
  `codex-universal` matrix
