# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile expects a prebuilt Nexus runtime base image from
# `images/nexus`. For multi-arch publishing, NEXUS_BASE_IMAGE must already
# resolve to a multi-arch manifest that includes linux/amd64 and linux/arm64.
#
# Local build:
#   docker build -f images/nexus/Dockerfile -t nexus-base-local .
#   docker build \
#     --build-arg NEXUS_BASE_IMAGE=nexus-base-local \
#     -f execution_runtimes/nexus/Dockerfile \
#     -t nexus-runtime-local \
#     execution_runtimes/nexus
#
# Multi-arch release:
#   docker buildx build --platform linux/amd64,linux/arm64 --push \
#     -f images/nexus/Dockerfile \
#     -t ghcr.io/your-org/nexus-base:latest .
#   docker buildx build --platform linux/amd64,linux/arm64 --push \
#     --build-arg NEXUS_BASE_IMAGE=ghcr.io/your-org/nexus-base:latest \
#     -f execution_runtimes/nexus/Dockerfile \
#     -t ghcr.io/your-org/nexus-runtime:latest \
#     execution_runtimes/nexus

ARG NEXUS_BASE_IMAGE=nexus-base-local
FROM ${NEXUS_BASE_IMAGE}

ENV GEM_HOME="/usr/local/bundle" \
    GEM_PATH="/usr/local/bundle" \
    NEXUS_HOME_ROOT="/var/lib/nexus" \
    PATH="/usr/local/bundle/bin:${PATH}"

WORKDIR /build

COPY Gemfile Gemfile.lock LICENSE.txt README.md cybros_nexus.gemspec .ruby-version ./
COPY exe/ ./exe/
COPY lib/ ./lib/
COPY scripts/ ./scripts/

RUN gem build cybros_nexus.gemspec && \
    gem_file="$(ls -1 cybros_nexus-*.gem | head -n 1)" && \
    gem install --no-document "${gem_file}" && \
    rm -f "${gem_file}"

RUN mkdir -p "${NEXUS_HOME_ROOT}" && \
    if ! getent group nexus >/dev/null; then groupadd --system nexus; fi && \
    if ! id -u nexus >/dev/null 2>&1; then useradd --system --gid nexus --create-home --shell /bin/bash nexus; fi && \
    chown -R nexus:nexus "${NEXUS_HOME_ROOT}"

WORKDIR /workspace
USER nexus:nexus

ENTRYPOINT ["nexus"]
CMD ["run"]
