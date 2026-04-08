# syntax=docker/dockerfile:1
# check=error=true

FROM ubuntu:24.04

ARG TARGETARCH
ARG NEXUS_CONTEXT_PREFIX=images/nexus/

ENV LANG="C.UTF-8" \
    COREPACK_HOME="/usr/local/share/corepack" \
    DEBIAN_FRONTEND="noninteractive" \
    PLAYWRIGHT_BROWSERS_PATH="/opt/playwright" \
    PATH="/root/.cargo/bin:/usr/local/go/bin:${PATH}"

SHELL ["/bin/bash", "-lc"]

COPY ${NEXUS_CONTEXT_PREFIX}versions.env /usr/local/share/nexus/versions.env

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      bash \
      bison \
      build-essential \
      ca-certificates \
      curl \
      fd-find \
      git \
      jq \
      libffi-dev \
      libgdbm-compat-dev \
      libgdbm-dev \
      libgmp-dev \
      libjemalloc2 \
      libncurses-dev \
      libreadline-dev \
      libsqlite3-dev \
      libssl-dev \
      libyaml-dev \
      pkg-config \
      python-is-python3 \
      python3 \
      python3-pip \
      python3-venv \
      ripgrep \
      sqlite3 \
      unzip \
      xz-utils \
      zip \
      zlib1g-dev && \
    ln -sf /usr/bin/fdfind /usr/local/bin/fd && \
    rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) node_arch="x64" ;; \
      arm64) node_arch="arm64" ;; \
      *) echo "unsupported architecture for Node.js: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    node_tmp_dir="$(mktemp -d)" && \
    curl -fsSL "https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-${node_arch}.tar.xz" \
      -o "${node_tmp_dir}/node.tar.xz" && \
    tar -xJf "${node_tmp_dir}/node.tar.xz" -C /usr/local --strip-components=1 --no-same-owner && \
    npm_tmp_dir="$(mktemp -d)" && \
    curl -fsSL "https://registry.npmjs.org/npm/-/npm-${NPM_VERSION}.tgz" \
      -o "${npm_tmp_dir}/npm.tgz" && \
    rm -rf /usr/local/lib/node_modules/npm && \
    mkdir -p /usr/local/lib/node_modules && \
    tar -xzf "${npm_tmp_dir}/npm.tgz" -C /usr/local/lib/node_modules && \
    mv /usr/local/lib/node_modules/package /usr/local/lib/node_modules/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
    ln -sf /usr/local/lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx && \
    rm -rf "${node_tmp_dir}" "${npm_tmp_dir}" && \
    mkdir -p "${COREPACK_HOME}" && \
    corepack enable && \
    corepack install --global "pnpm@${PNPM_VERSION}" && \
    npm install -g \
      "create-vite@${CREATE_VITE_VERSION}" \
      "playwright@${PLAYWRIGHT_VERSION}" \
      "vite@${VITE_VERSION}"

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    mkdir -p "${PLAYWRIGHT_BROWSERS_PATH}" && \
    playwright install chromium --with-deps

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64) go_arch="amd64" ;; \
      arm64) go_arch="arm64" ;; \
      *) echo "unsupported architecture for Go: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    go_tmp_dir="$(mktemp -d)" && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${go_arch}.tar.gz" \
      -o "${go_tmp_dir}/go.tar.gz" && \
    rm -rf /usr/local/go && \
    tar -xzf "${go_tmp_dir}/go.tar.gz" -C /usr/local && \
    rm -rf "${go_tmp_dir}"

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" | \
      env UV_UNMANAGED_INSTALL="/usr/local/bin" sh

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
      sh -s -- -y --profile minimal --default-toolchain "${RUST_VERSION}" && \
    rustup component add clippy rustfmt

RUN set -a && \
    source /usr/local/share/nexus/versions.env && \
    set +a && \
    ruby_tmp_dir="$(mktemp -d)" && \
    curl -fsSL "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" \
      -o "${ruby_tmp_dir}/ruby.tar.gz" && \
    tar -xzf "${ruby_tmp_dir}/ruby.tar.gz" -C "${ruby_tmp_dir}" && \
    pushd "${ruby_tmp_dir}/ruby-${RUBY_VERSION}" >/dev/null && \
    ./configure --disable-install-doc --enable-shared && \
    make -j"$(nproc)" && \
    make install && \
    popd >/dev/null && \
    gem install bundler -v "${BUNDLER_VERSION}" --no-document && \
    rm -rf "${ruby_tmp_dir}"

WORKDIR /workspace

COPY ${NEXUS_CONTEXT_PREFIX}verify.sh /usr/local/bin/nexus-verify
RUN chmod +x /usr/local/bin/nexus-verify

CMD ["bash"]
