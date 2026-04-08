#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "bootstrap-runtime-deps-darwin.sh only supports macOS hosts" >&2
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required to bootstrap the Fenix runtime on macOS" >&2
  exit 1
fi

brew install caddy chromium node@24 pnpm python@3.12 uv
