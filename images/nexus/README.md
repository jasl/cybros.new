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
- Python 3.12 with `uv`
- Ruby 4.0.2 with Bundler 4.0.8 and native extension build prerequisites
- Go
- Rust
- common CLI/build tools: `git`, `curl`, `jq`, `unzip`, `zip`, `ripgrep`,
  `fd`, `sqlite3`, `build-essential`, `pkg-config`

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
- runtime dependency selection borrows from `agents/fenix.old`
- version truth stays local to this subproject instead of copying the
  `codex-universal` matrix
