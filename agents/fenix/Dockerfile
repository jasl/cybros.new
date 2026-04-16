# syntax=docker/dockerfile:1
# check=error=true

# This Dockerfile is designed for production, not development. Use with
# docker compose or build'n'run by hand:
# docker build -t fenix-local agents/fenix
# docker run -d -p 3101:80 --env-file agents/fenix/.env --name fenix fenix-local

ARG RUBY_VERSION=4.0.2
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 sqlite3 && \
    jemalloc_lib="$(find /usr/lib -name libjemalloc.so.2 -print -quit)" && \
    test -n "${jemalloc_lib}" && \
    ln -sf "${jemalloc_lib}" /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY vendor/ ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/

FROM base

RUN if ! getent group rails >/dev/null; then groupadd --system rails; fi && \
    if ! id -u rails >/dev/null 2>&1; then useradd --system --gid rails --create-home --shell /bin/bash rails; fi
USER rails:rails

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 80
CMD ["./bin/thrust", "./bin/rails", "server"]
