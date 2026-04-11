# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile expects a prebuilt cowork runtime base image. Build the base first:
# docker build -f images/nexus/Dockerfile -t nexus-local .
# docker build --build-arg NEXUS_BASE_IMAGE=nexus-local:latest -f agents/nexus/Dockerfile -t nexus-local agents/nexus
# docker run -d -p 3101:80 --env-file agents/nexus/.env --name nexus nexus-local

# For a containerized dev environment, see Dev Containers: https://guides.rubyonrails.org/getting_started_with_devcontainer.html

ARG NEXUS_BASE_IMAGE=nexus-local:latest
FROM ${NEXUS_BASE_IMAGE} AS base

# Rails app lives here
WORKDIR /rails

# The nexus base owns the broad toolchain baseline; the app image keeps only app-local wiring.
RUN ln -sf /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so

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
