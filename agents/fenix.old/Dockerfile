# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with Kamal or build'n'run by hand:
# docker build -t fenix .
# docker run -d -p 80:80 --env-file ./.env --name fenix fenix
#
# Runtime secrets are resolved through Rails.app.creds, which prefers ENV over
# encrypted credentials. The production image therefore does not depend on
# config/master.key being present inside the container unless you choose to
# mount credentials explicitly for a host-style deployment.

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

# Make sure RUBY_VERSION matches the Ruby version in .ruby-version
ARG RUBY_VERSION=4.0.2
ARG BUNDLER_VERSION=4.0.8
FROM ubuntu:24.04 AS base

ARG RUBY_VERSION
ARG BUNDLER_VERSION

# Rails app lives here
WORKDIR /rails

COPY scripts/bootstrap-runtime-deps.sh /tmp/bootstrap-runtime-deps.sh

# Install runtime toolchains and OS packages on the canonical Ubuntu 24.04 base.
RUN /tmp/bootstrap-runtime-deps.sh && \
    rm /tmp/bootstrap-runtime-deps.sh && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    npm install -g --no-audit --no-fund create-vite@latest vite@latest

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    PLAYWRIGHT_BROWSERS_PATH="/rails/.playwright"

# Build the pinned Ruby toolchain on the same Ubuntu 24.04 base so OpenSSL and
# native extensions remain ABI-compatible with the final runtime image.
FROM base AS ruby-runtime

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y bison build-essential curl libffi-dev libgdbm-dev libgmp-dev libncurses-dev libreadline-dev libsqlite3-dev libssl-dev libyaml-dev zlib1g-dev && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

RUN curl -fsSL "https://cache.ruby-lang.org/pub/ruby/${RUBY_VERSION%.*}/ruby-${RUBY_VERSION}.tar.gz" -o /tmp/ruby.tar.gz && \
    tar -xzf /tmp/ruby.tar.gz -C /tmp && \
    cd /tmp/ruby-${RUBY_VERSION} && \
    ./configure --disable-install-doc --enable-shared && \
    make -j"$(nproc)" && \
    make install && \
    gem install bundler -v "${BUNDLER_VERSION}" --no-document && \
    rm -rf /tmp/ruby*

# Throw-away build stage to reduce size of final image
FROM base AS build

COPY --from=ruby-runtime /usr/local/ /usr/local/

# Install packages needed to build gems
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libsqlite3-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Install application gems
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

COPY package.json package-lock.json ./
RUN npm ci && \
    npx playwright install chromium

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/


# Final stage for app image
FROM base

COPY --from=ruby-runtime /usr/local/ /usr/local/

# Create the runtime identity. The entrypoint performs any required volume
# preparation as root, then immediately drops privileges before running app
# processes.
# Ubuntu 24.04 already ships an "ubuntu" account at uid/gid 1000, so only
# create the identity when it is absent and rely on numeric ownership below.
RUN getent group 1000 >/dev/null || groupadd --system --gid 1000 rails && \
    getent passwd 1000 >/dev/null || useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

# Copy built artifacts: gems, application
COPY --chown=1000:1000 --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=1000:1000 --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
