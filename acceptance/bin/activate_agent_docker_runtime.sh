#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOG_DIR="${ACCEPTANCE_ROOT}/logs"

AGENT_PROJECT_ROOT="${AGENT_PROJECT_ROOT:?AGENT_PROJECT_ROOT is required}"
AGENT_RUNTIME_BASE_URL="${AGENT_RUNTIME_BASE_URL:?AGENT_RUNTIME_BASE_URL is required}"
AGENT_DOCKER_CONTAINER="${AGENT_DOCKER_CONTAINER:?AGENT_DOCKER_CONTAINER is required}"
AGENT_DOCKER_PROXY_CONTAINER="${AGENT_DOCKER_PROXY_CONTAINER:?AGENT_DOCKER_PROXY_CONTAINER is required}"
AGENT_DOCKER_IMAGE="${AGENT_DOCKER_IMAGE:?AGENT_DOCKER_IMAGE is required}"
AGENT_DOCKER_PROXY_PORT="${AGENT_DOCKER_PROXY_PORT:?AGENT_DOCKER_PROXY_PORT is required}"
AGENT_DOCKER_WORKSPACE_ROOT="${AGENT_DOCKER_WORKSPACE_ROOT:?AGENT_DOCKER_WORKSPACE_ROOT is required}"
AGENT_DOCKER_ENV_FILE="${AGENT_DOCKER_ENV_FILE:?AGENT_DOCKER_ENV_FILE is required}"
AGENT_DOCKER_STORAGE_VOLUME="${AGENT_DOCKER_STORAGE_VOLUME:-agent_capstone_storage}"
AGENT_DOCKER_PROXY_ROUTES_VOLUME="${AGENT_DOCKER_PROXY_ROUTES_VOLUME:-agent_capstone_proxy_routes}"
AGENT_DOCKER_PROXY_COMMAND="${AGENT_DOCKER_PROXY_COMMAND:?AGENT_DOCKER_PROXY_COMMAND is required}"
AGENT_PUBLIC_BASE_URL_ENV_KEY="${AGENT_PUBLIC_BASE_URL_ENV_KEY:?AGENT_PUBLIC_BASE_URL_ENV_KEY is required}"
AGENT_PROXY_PORT_ENV_KEY="${AGENT_PROXY_PORT_ENV_KEY:?AGENT_PROXY_PORT_ENV_KEY is required}"
AGENT_PROXY_ROUTES_ENV_KEY="${AGENT_PROXY_ROUTES_ENV_KEY:?AGENT_PROXY_ROUTES_ENV_KEY is required}"
AGENT_PROXY_ROUTES_PATH="${AGENT_PROXY_ROUTES_PATH:?AGENT_PROXY_ROUTES_PATH is required}"
AGENT_MACHINE_CREDENTIAL="${AGENT_MACHINE_CREDENTIAL:?AGENT_MACHINE_CREDENTIAL is required}"
AGENT_EXECUTION_MACHINE_CREDENTIAL="${AGENT_EXECUTION_MACHINE_CREDENTIAL:-${AGENT_MACHINE_CREDENTIAL}}"
AGENT_RUNTIME_BOOT_JSON="${AGENT_RUNTIME_BOOT_JSON:-${CAPSTONE_RUNTIME_WORKER_BOOT_PATH:-}}"
AGENT_OUTPUT_PREFIX="${AGENT_OUTPUT_PREFIX:-agent}"
DOCKER_CORE_MATRIX_BASE_URL="${DOCKER_CORE_MATRIX_BASE_URL:-http://host.docker.internal:3000}"

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

docker_agent_standalone_solid_queue() {
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

AGENT_RUNTIME_HOST="$(parse_url_field "${AGENT_RUNTIME_BASE_URL}" host)"
AGENT_RUNTIME_PORT="$(parse_url_field "${AGENT_RUNTIME_BASE_URL}" port)"

if [[ -z "${AGENT_RUNTIME_HOST}" || -z "${AGENT_RUNTIME_PORT}" ]]; then
  echo "invalid AGENT_RUNTIME_BASE_URL: ${AGENT_RUNTIME_BASE_URL}" >&2
  exit 1
fi

if [[ ! -f "${AGENT_DOCKER_ENV_FILE}" ]]; then
  echo "missing agent docker env file: ${AGENT_DOCKER_ENV_FILE}" >&2
  exit 1
fi

mkdir -p "${AGENT_DOCKER_WORKSPACE_ROOT}"

wait_for_docker_ready
remove_container_if_present "${AGENT_DOCKER_CONTAINER}"
remove_container_if_present "${AGENT_DOCKER_PROXY_CONTAINER}"

docker run -d \
  --name "${AGENT_DOCKER_CONTAINER}" \
  -p "${AGENT_RUNTIME_PORT}:80" \
  --env-file "${AGENT_DOCKER_ENV_FILE}" \
  -e "RAILS_ENV=production" \
  -e "${AGENT_PUBLIC_BASE_URL_ENV_KEY}=${AGENT_RUNTIME_BASE_URL}" \
  -e "PLAYWRIGHT_BROWSERS_PATH=/opt/playwright" \
  -e "${AGENT_PROXY_PORT_ENV_KEY}=${AGENT_DOCKER_PROXY_PORT}" \
  -e "${AGENT_PROXY_ROUTES_ENV_KEY}=${AGENT_PROXY_ROUTES_PATH}" \
  -e "CORE_MATRIX_BASE_URL=${DOCKER_CORE_MATRIX_BASE_URL}" \
  -e "CORE_MATRIX_MACHINE_CREDENTIAL=${AGENT_MACHINE_CREDENTIAL}" \
  -e "CORE_MATRIX_EXECUTION_MACHINE_CREDENTIAL=${AGENT_EXECUTION_MACHINE_CREDENTIAL}" \
  -v "${AGENT_DOCKER_WORKSPACE_ROOT}:/workspace" \
  -v "${AGENT_DOCKER_STORAGE_VOLUME}:/rails/storage" \
  -v "${AGENT_DOCKER_PROXY_ROUTES_VOLUME}:/rails/tmp/dev-proxy" \
  "${AGENT_DOCKER_IMAGE}" \
  >/dev/null

docker run -d \
  --name "${AGENT_DOCKER_PROXY_CONTAINER}" \
  -p "${AGENT_DOCKER_PROXY_PORT}:${AGENT_DOCKER_PROXY_PORT}" \
  --env-file "${AGENT_DOCKER_ENV_FILE}" \
  -e "RAILS_ENV=production" \
  -e "PLAYWRIGHT_BROWSERS_PATH=/opt/playwright" \
  -e "${AGENT_PROXY_PORT_ENV_KEY}=${AGENT_DOCKER_PROXY_PORT}" \
  -e "${AGENT_PROXY_ROUTES_ENV_KEY}=${AGENT_PROXY_ROUTES_PATH}" \
  -v "${AGENT_DOCKER_WORKSPACE_ROOT}:/workspace" \
  -v "${AGENT_DOCKER_PROXY_ROUTES_VOLUME}:/rails/tmp/dev-proxy" \
  "${AGENT_DOCKER_IMAGE}" \
  "${AGENT_DOCKER_PROXY_COMMAND}" \
  >/dev/null

wait_for_container_exec "${AGENT_DOCKER_CONTAINER}"
wait_for_http_ok "${AGENT_RUNTIME_BASE_URL}/up"
wait_for_http_ok "${AGENT_RUNTIME_BASE_URL}/runtime/manifest"

docker exec -d -w /rails "${AGENT_DOCKER_CONTAINER}" /rails/bin/runtime-worker >/dev/null
wait_for_runtime_worker "${AGENT_DOCKER_CONTAINER}"

standalone_solid_queue="$(docker_agent_standalone_solid_queue "${AGENT_DOCKER_CONTAINER}")"

if [[ -n "${AGENT_RUNTIME_BOOT_JSON}" ]]; then
  write_runtime_boot_json "${AGENT_DOCKER_CONTAINER}" "${standalone_solid_queue}" "${AGENT_RUNTIME_BOOT_JSON}"
fi

echo "${AGENT_OUTPUT_PREFIX}_runtime_base_url=${AGENT_RUNTIME_BASE_URL}"
echo "${AGENT_OUTPUT_PREFIX}_docker_container=${AGENT_DOCKER_CONTAINER}"
echo "standalone_solid_queue=${standalone_solid_queue}"
