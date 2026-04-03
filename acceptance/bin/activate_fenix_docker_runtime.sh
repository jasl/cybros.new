#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
FENIX_ROOT="${FENIX_PROJECT_ROOT:-${REPO_ROOT}/agents/fenix}"
LOG_DIR="${ACCEPTANCE_ROOT}/logs"

FENIX_RUNTIME_BASE_URL="${FENIX_RUNTIME_BASE_URL:-http://127.0.0.1:3101}"
FENIX_DOCKER_CONTAINER="${FENIX_DOCKER_CONTAINER:-fenix-capstone}"
FENIX_DOCKER_PROXY_CONTAINER="${FENIX_DOCKER_PROXY_CONTAINER:-fenix-capstone-proxy}"
FENIX_DOCKER_IMAGE="${FENIX_DOCKER_IMAGE:-fenix-capstone-image}"
FENIX_DOCKER_PROXY_PORT="${FENIX_DOCKER_PROXY_PORT:-3310}"
FENIX_DOCKER_WORKSPACE_ROOT="${FENIX_DOCKER_WORKSPACE_ROOT:-${REPO_ROOT}/tmp/fenix}"
FENIX_DOCKER_ENV_FILE="${FENIX_DOCKER_ENV_FILE:-${FENIX_ROOT}/.env}"
DOCKER_CORE_MATRIX_BASE_URL="${DOCKER_CORE_MATRIX_BASE_URL:-http://host.docker.internal:3000}"
FENIX_MACHINE_CREDENTIAL="${FENIX_MACHINE_CREDENTIAL:?FENIX_MACHINE_CREDENTIAL is required}"
FENIX_EXECUTION_MACHINE_CREDENTIAL="${FENIX_EXECUTION_MACHINE_CREDENTIAL:-${FENIX_MACHINE_CREDENTIAL}}"
FENIX_RUNTIME_BOOT_JSON="${FENIX_RUNTIME_BOOT_JSON:-${CAPSTONE_RUNTIME_WORKER_BOOT_PATH:-}}"

mkdir -p "${LOG_DIR}"

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "missing required command: ${name}" >&2
    exit 1
  fi
}

require_command curl
require_command docker
require_command python3

parse_url_field() {
  local url="$1"
  local field="$2"
  python3 - <<'PY' "${url}" "${field}"
import sys
from urllib.parse import urlparse

url = urlparse(sys.argv[1])
field = sys.argv[2]
if field == "host":
    print(url.hostname or "")
elif field == "port":
    print(url.port or "")
else:
    raise SystemExit(f"unknown field: {field}")
PY
}

wait_for_docker_ready() {
  local attempts="${1:-75}"

  for _ in $(seq 1 "${attempts}"); do
    if docker ps >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "timed out waiting for docker daemon" >&2
  return 1
}

wait_for_http_ok() {
  local url="$1"
  local attempts="${2:-75}"

  for _ in $(seq 1 "${attempts}"); do
    if curl -fsS "${url}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "timed out waiting for ${url}" >&2
  return 1
}

wait_for_container_exec() {
  local container_name="$1"
  local attempts="${2:-75}"

  for _ in $(seq 1 "${attempts}"); do
    if docker exec "${container_name}" true >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "timed out waiting for docker container ${container_name}" >&2
  return 1
}

wait_for_container_absent() {
  local container_name="$1"
  local attempts="${2:-75}"

  for _ in $(seq 1 "${attempts}"); do
    if [[ -z "$(docker ps -a --filter "name=^/${container_name}$" --format '{{.ID}}')" ]]; then
      return 0
    fi
    sleep 0.2
  done

  echo "timed out waiting for docker container ${container_name} to disappear" >&2
  return 1
}

remove_container_if_present() {
  local container_name="$1"
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  wait_for_container_absent "${container_name}"
}

wait_for_runtime_worker() {
  local container_name="$1"
  local attempts="${2:-75}"

  for _ in $(seq 1 "${attempts}"); do
    if docker exec "${container_name}" sh -lc 'ps -eo args= | grep -F "runtime:control_loop_forever" | grep -v grep' >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "timed out waiting for runtime worker in ${container_name}" >&2
  return 1
}

docker_fenix_standalone_solid_queue() {
  local container_name="$1"
  docker exec "${container_name}" sh -lc 'case "${STANDALONE_SOLID_QUEUE:-}" in true|1) echo true ;; *) echo false ;; esac'
}

write_runtime_boot_json() {
  local container_name="$1"
  local standalone_solid_queue="$2"
  local output_path="$3"

  mkdir -p "$(dirname "${output_path}")"
  python3 - <<'PY' "${container_name}" "${standalone_solid_queue}" "${output_path}"
import json
import pathlib
import sys

container_name, standalone, output_path = sys.argv[1:]
payload = {
    "container_name": container_name,
    "worker_commands": ["bin/runtime-worker"],
    "standalone_solid_queue": standalone == "true",
}
path = pathlib.Path(output_path)
path.write_text(json.dumps(payload, indent=2) + "\n")
PY
}

FENIX_RUNTIME_HOST="$(parse_url_field "${FENIX_RUNTIME_BASE_URL}" host)"
FENIX_RUNTIME_PORT="$(parse_url_field "${FENIX_RUNTIME_BASE_URL}" port)"

if [[ -z "${FENIX_RUNTIME_HOST}" || -z "${FENIX_RUNTIME_PORT}" ]]; then
  echo "invalid FENIX_RUNTIME_BASE_URL: ${FENIX_RUNTIME_BASE_URL}" >&2
  exit 1
fi

if [[ ! -f "${FENIX_DOCKER_ENV_FILE}" ]]; then
  echo "missing Fenix docker env file: ${FENIX_DOCKER_ENV_FILE}" >&2
  exit 1
fi

mkdir -p "${FENIX_DOCKER_WORKSPACE_ROOT}"

wait_for_docker_ready
remove_container_if_present "${FENIX_DOCKER_CONTAINER}"
remove_container_if_present "${FENIX_DOCKER_PROXY_CONTAINER}"

docker run -d \
  --name "${FENIX_DOCKER_CONTAINER}" \
  -p "${FENIX_RUNTIME_PORT}:80" \
  --env-file "${FENIX_DOCKER_ENV_FILE}" \
  -e "RAILS_ENV=production" \
  -e "FENIX_PUBLIC_BASE_URL=${FENIX_RUNTIME_BASE_URL}" \
  -e "PLAYWRIGHT_BROWSERS_PATH=/rails/.playwright" \
  -e "FENIX_DEV_PROXY_PORT=${FENIX_DOCKER_PROXY_PORT}" \
  -e "FENIX_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy" \
  -e "CORE_MATRIX_BASE_URL=${DOCKER_CORE_MATRIX_BASE_URL}" \
  -e "CORE_MATRIX_MACHINE_CREDENTIAL=${FENIX_MACHINE_CREDENTIAL}" \
  -e "CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL=${FENIX_EXECUTION_MACHINE_CREDENTIAL}" \
  -v "${FENIX_DOCKER_WORKSPACE_ROOT}:/workspace" \
  -v "fenix_capstone_storage:/rails/storage" \
  -v "fenix_capstone_proxy_routes:/rails/tmp/dev-proxy" \
  "${FENIX_DOCKER_IMAGE}" \
  >/dev/null

docker run -d \
  --name "${FENIX_DOCKER_PROXY_CONTAINER}" \
  -p "${FENIX_DOCKER_PROXY_PORT}:${FENIX_DOCKER_PROXY_PORT}" \
  --env-file "${FENIX_DOCKER_ENV_FILE}" \
  -e "RAILS_ENV=production" \
  -e "PLAYWRIGHT_BROWSERS_PATH=/rails/.playwright" \
  -e "FENIX_DEV_PROXY_PORT=${FENIX_DOCKER_PROXY_PORT}" \
  -e "FENIX_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy" \
  -v "${FENIX_DOCKER_WORKSPACE_ROOT}:/workspace" \
  -v "fenix_capstone_proxy_routes:/rails/tmp/dev-proxy" \
  "${FENIX_DOCKER_IMAGE}" \
  /rails/bin/fenix-dev-proxy \
  >/dev/null

wait_for_container_exec "${FENIX_DOCKER_CONTAINER}"
wait_for_http_ok "${FENIX_RUNTIME_BASE_URL}/up"
wait_for_http_ok "${FENIX_RUNTIME_BASE_URL}/runtime/manifest"

docker exec "${FENIX_DOCKER_CONTAINER}" sh -lc 'cd /rails && bash scripts/bootstrap-runtime-deps.sh' \
  >>"${LOG_DIR}/fenix-runtime-bootstrap.log" 2>&1

docker exec -d -w /rails "${FENIX_DOCKER_CONTAINER}" /rails/bin/runtime-worker >/dev/null
wait_for_runtime_worker "${FENIX_DOCKER_CONTAINER}"

standalone_solid_queue="$(docker_fenix_standalone_solid_queue "${FENIX_DOCKER_CONTAINER}")"

if [[ -n "${FENIX_RUNTIME_BOOT_JSON}" ]]; then
  write_runtime_boot_json "${FENIX_DOCKER_CONTAINER}" "${standalone_solid_queue}" "${FENIX_RUNTIME_BOOT_JSON}"
fi

echo "fenix_runtime_base_url=${FENIX_RUNTIME_BASE_URL}"
echo "fenix_docker_container=${FENIX_DOCKER_CONTAINER}"
echo "standalone_solid_queue=${standalone_solid_queue}"
