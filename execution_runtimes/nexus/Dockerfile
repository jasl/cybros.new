# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile expects a prebuilt cowork runtime base image. Build the base first.
# For multi-arch publishing, NEXUS_BASE_IMAGE must already resolve to a
# multi-arch manifest that includes linux/amd64 and linux/arm64.
# docker build -f images/nexus/Dockerfile -t nexus-local .
# docker build --build-arg NEXUS_BASE_IMAGE=nexus-local:latest -f execution_runtimes/nexus/Dockerfile -t nexus-local execution_runtimes/nexus
# docker buildx build --platform linux/amd64,linux/arm64 --push \
#   --build-arg NEXUS_BASE_IMAGE=ghcr.io/your-org/nexus-base:latest \
#   -f execution_runtimes/nexus/Dockerfile -t ghcr.io/your-org/nexus-runtime:latest execution_runtimes/nexus
# docker run -d -p 3101:80 --env-file execution_runtimes/nexus/.env --name nexus nexus-local

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

ARG NEXUS_BASE_IMAGE=nexus-local:latest
FROM ${NEXUS_BASE_IMAGE} AS base

# Rails app lives here
WORKDIR /rails

# The nexus base owns the broad toolchain baseline; the app image keeps only
# app-local wiring and inherits multi-arch support from NEXUS_BASE_IMAGE.
RUN jemalloc_lib="$(find /usr/lib -name libjemalloc.so.2 -print -quit)" && \
    test -n "${jemalloc_lib}" && \
    ln -sf "${jemalloc_lib}" /usr/local/lib/libjemalloc.so

# Set production environment variables and enable jemalloc for reduced memory usage and latency.
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

# Throw-away build stage to reduce size of final image
FROM base AS build

# Install application gems
COPY vendor/ ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    # -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
    bundle exec bootsnap precompile -j 1 --gemfile

# Copy application code
COPY . .

# Precompile bootsnap code for faster boot times.
# -j 1 disable parallel compilation to avoid a QEMU bug: https://github.com/rails/bootsnap/issues/495
RUN bundle exec bootsnap precompile -j 1 app/ lib/


# Final stage for app image
FROM base

# Run and own only the runtime files as a non-root user for security
RUN if ! getent group rails >/dev/null; then groupadd --system rails; fi && \
    if ! id -u rails >/dev/null 2>&1; then useradd --system --gid rails --create-home --shell /bin/bash rails; fi
USER rails:rails

# Copy built artifacts: gems, application
COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

# Entrypoint prepares the database.
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# Start server via Thruster by default, this can be overwritten at runtime
EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
