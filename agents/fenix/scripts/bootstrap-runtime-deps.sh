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
NODE_VERSION="${FENIX_NODE_VERSION:-22.22.2}"
NPM_VERSION="${FENIX_NPM_VERSION:-11.12.1}"

apt-get update -qq
apt-get install --no-install-recommends -y \
  bash \
  ca-certificates \
  caddy \
  curl \
  git \
  gnupg \
  iproute2 \
  libasound2t64 \
  libatk-bridge2.0-0t64 \
  libatk1.0-0t64 \
  libatspi2.0-0t64 \
  libcairo2 \
  libcups2t64 \
  libdbus-1-3 \
  libffi8 \
  libgbm1 \
  libglib2.0-0t64 \
  libgmp10 \
  libjemalloc2 \
  libpango-1.0-0 \
  libreadline8 \
  libsqlite3-0 \
  libssl3 \
  libx11-6 \
  libxcomposite1 \
  libxcb1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxkbcommon0 \
  libxrandr2 \
  libyaml-0-2 \
  lsof \
  pkg-config \
  python3 \
  python-is-python3 \
  python3-pip \
  python3-venv \
  sqlite3 \
  xz-utils \
  zlib1g

if ! command -v node >/dev/null 2>&1 || [[ "$(node --version)" != v22* ]]; then
  case "$(uname -m)" in
    x86_64)
      node_arch="x64"
      ;;
    aarch64 | arm64)
      node_arch="arm64"
      ;;
    *)
      echo "unsupported architecture for Node.js runtime bootstrap: $(uname -m)" >&2
      exit 1
      ;;
  esac

  node_tmp_dir="$(mktemp -d)"
  curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
    -o "${node_tmp_dir}/node.tar.xz"
  tar -xJf "${node_tmp_dir}/node.tar.xz" -C /usr/local --strip-components=1 --no-same-owner
  rm -rf "${node_tmp_dir}"
fi

npm_tmp_dir="$(mktemp -d)"
curl -fsSL "https://registry.npmjs.org/npm/-/npm-${NPM_VERSION}.tgz" \
  -o "${npm_tmp_dir}/npm.tgz"
rm -rf /usr/local/lib/node_modules/npm
mkdir -p /usr/local/lib/node_modules
tar -xzf "${npm_tmp_dir}/npm.tgz" -C /usr/local/lib/node_modules
mv /usr/local/lib/node_modules/package /usr/local/lib/node_modules/npm
ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm
ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx
rm -rf "${npm_tmp_dir}"

npm install --global pnpm

if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  ln -sf /root/.local/bin/uv /usr/local/bin/uv
fi

rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*
