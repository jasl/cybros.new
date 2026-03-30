#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "bootstrap-runtime-deps.sh only supports Linux hosts" >&2
  exit 1
fi

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
fi

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "bootstrap-runtime-deps.sh expects Ubuntu 24.04 as the primary runtime base" >&2
fi

export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install --no-install-recommends -y \
  bash \
  ca-certificates \
  caddy \
  curl \
  git \
  gnupg \
  libffi8 \
  libgmp10 \
  libjemalloc2 \
  libreadline8 \
  libsqlite3-0 \
  libssl3 \
  libyaml-0-2 \
  pkg-config \
  python3 \
  python3-pip \
  python3-venv \
  sqlite3 \
  xz-utils \
  zlib1g

if ! command -v node >/dev/null 2>&1 || [[ "$(node --version)" != v24* ]]; then
  install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | \
    gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" \
    >/etc/apt/sources.list.d/nodesource.list
  apt-get update -qq
  apt-get install --no-install-recommends -y nodejs
fi

npm install --global pnpm

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ln -sf /root/.local/bin/uv /usr/local/bin/uv
fi

rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
