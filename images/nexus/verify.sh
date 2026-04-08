#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
versions_file="${script_dir}/versions.env"
[[ -r "${versions_file}" ]] || versions_file="/usr/local/share/nexus/versions.env"

# shellcheck disable=SC1091
source "${versions_file}"

fail() {
  echo "nexus verify: $*" >&2
  exit 1
}

require_command() {
  local name="$1"

  command -v "${name}" >/dev/null 2>&1 || fail "missing command: ${name}"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local label="$3"

  [[ "${actual}" == "${expected}" ]] || fail "${label}: expected '${expected}', got '${actual}'"
}

assert_prefix() {
  local expected_prefix="$1"
  local actual="$2"
  local label="$3"

  [[ "${actual}" == "${expected_prefix}"* ]] || fail "${label}: expected prefix '${expected_prefix}', got '${actual}'"
}

global_npm_version() {
  local package_name="$1"

  npm ls -g "${package_name}" --depth=0 --json | jq -r ".dependencies[\"${package_name}\"].version"
}

browser_executable() {
  find "${PLAYWRIGHT_BROWSERS_PATH}" -type f \( -name chrome -o -name chromium \) | head -n 1
}

pnpm_version_with_fresh_home() {
  local temp_home
  temp_home="$(mktemp -d)"

  HOME="${temp_home}" pnpm --version 2>&1
  local status=$?

  rm -rf "${temp_home}"
  return "${status}"
}

for command_name in \
  bash bundle cargo corepack create-vite curl fd gcc g++ git go jq make \
  node npm pip3 playwright pnpm python python3 rg ruby rustc sqlite3 uv vite zip unzip
do
  require_command "${command_name}"
done

assert_eq "v${NODE_VERSION}" "$(node --version)" "node version"
assert_eq "${NPM_VERSION}" "$(npm --version)" "npm version"
assert_eq "${PNPM_VERSION}" "$(pnpm --version)" "pnpm version"
assert_eq "${PNPM_VERSION}" "$(pnpm_version_with_fresh_home)" "pnpm fresh-home readiness"
assert_eq "${VITE_VERSION}" "$(global_npm_version vite)" "vite version"
assert_eq "${CREATE_VITE_VERSION}" "$(global_npm_version create-vite)" "create-vite version"
assert_eq "${PLAYWRIGHT_VERSION}" "$(global_npm_version playwright)" "playwright version"
assert_prefix "Python ${PYTHON_MAJOR_MINOR}" "$(python3 --version)" "python3 version"
assert_prefix "Python ${PYTHON_MAJOR_MINOR}" "$(python --version)" "python version"
assert_prefix "uv ${UV_VERSION}" "$(uv --version)" "uv version"
assert_prefix "ruby ${RUBY_VERSION}" "$(ruby --version)" "ruby version"
assert_eq "${BUNDLER_VERSION}" "$(bundle --version | awk '{print $NF}')" "bundler version"
assert_eq "go version go${GO_VERSION} linux/$(go env GOARCH)" "$(go version)" "go version"
assert_prefix "rustc ${RUST_VERSION}" "$(rustc --version)" "rustc version"
assert_prefix "cargo ${RUST_VERSION}" "$(cargo --version)" "cargo version"

browser_path="$(browser_executable)"
[[ -n "${browser_path}" ]] || fail "chromium browser binary not found under ${PLAYWRIGHT_BROWSERS_PATH}"
[[ -x "${browser_path}" ]] || fail "chromium browser binary is not executable: ${browser_path}"
"${browser_path}" --version >/dev/null 2>&1 || fail "chromium browser failed to start: ${browser_path}"

echo "nexus verify: ok"
