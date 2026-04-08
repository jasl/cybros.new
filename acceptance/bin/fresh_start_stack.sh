#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
FENIX_ROOT="${FENIX_PROJECT_ROOT:-${REPO_ROOT}/agents/fenix}"
NEXUS_ROOT="${NEXUS_PROJECT_ROOT:-${REPO_ROOT}/images/nexus}"
LOG_DIR="${ACCEPTANCE_ROOT}/logs"

CORE_MATRIX_BASE_URL="${CORE_MATRIX_BASE_URL:-http://127.0.0.1:3000}"
FENIX_RUNTIME_BASE_URL="${FENIX_RUNTIME_BASE_URL:-http://127.0.0.1:3101}"
FENIX_RUNTIME_MODE="${FENIX_RUNTIME_MODE:-host}"
FENIX_DOCKER_CONTAINER="${FENIX_DOCKER_CONTAINER:-fenix-capstone}"
FENIX_DOCKER_PROXY_CONTAINER="${FENIX_DOCKER_PROXY_CONTAINER:-fenix-capstone-proxy}"
NEXUS_DOCKER_IMAGE="${NEXUS_DOCKER_IMAGE:-nexus-capstone-base}"
FENIX_DOCKER_IMAGE="${FENIX_DOCKER_IMAGE:-fenix-capstone-image}"
FENIX_DOCKER_PROXY_PORT="${FENIX_DOCKER_PROXY_PORT:-3310}"
FENIX_DOCKER_WORKSPACE_ROOT="${FENIX_DOCKER_WORKSPACE_ROOT:-${REPO_ROOT}/tmp/fenix}"
FENIX_DOCKER_ENV_FILE="${FENIX_DOCKER_ENV_FILE:-${FENIX_ROOT}/.env}"
RESET_DOCKER_DB="${RESET_DOCKER_DB:-false}"

mkdir -p "${LOG_DIR}"
rm -f "${LOG_DIR}"/*.log

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "missing required command: ${name}" >&2
    exit 1
  fi
}

require_command curl
require_command lsof
require_command python3
require_command rbenv

if [[ "${FENIX_RUNTIME_MODE}" == "docker" ]]; then
  require_command docker
fi

RBENV_BIN="$(command -v rbenv)"
RBENV_ROOT="$("${RBENV_BIN}" root)"
RUBY_BIN="${RBENV_ROOT}/shims/ruby"

if [[ ! -x "${RUBY_BIN}" ]]; then
  echo "missing rbenv ruby shim: ${RUBY_BIN}" >&2
  exit 1
fi

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

stop_listening_port() {
  local port="$1"
  local pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null || true)

  if [[ "${#pids[@]}" -eq 0 ]]; then
    return 0
  fi

  kill -TERM "${pids[@]}" 2>/dev/null || true
  sleep 1

  pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null || true)

  if [[ "${#pids[@]}" -gt 0 ]]; then
    kill -KILL "${pids[@]}" 2>/dev/null || true
  fi
}

clear_server_pidfile() {
  local project_root="$1"
  rm -f "${project_root}/tmp/pids/server.pid"
}

stop_matching_process() {
  local pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(python3 - <<'PY' "$@"
import subprocess
import sys
import os

required = sys.argv[1:]
ps_output = subprocess.check_output(["ps", "-eo", "pid=,args="], text=True)
for line in ps_output.splitlines():
    line = line.strip()
    if not line:
        continue
    pid, _, args = line.partition(" ")
    if pid == str(os.getpid()):
        continue
    if all(fragment in args for fragment in required):
        print(pid)
PY
)

  if [[ "${#pids[@]}" -eq 0 ]]; then
    return 0
  fi

  kill -TERM "${pids[@]}" 2>/dev/null || true
  sleep 1

  pids=()
  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(python3 - <<'PY' "$@"
import subprocess
import sys
import os

required = sys.argv[1:]
ps_output = subprocess.check_output(["ps", "-eo", "pid=,args="], text=True)
for line in ps_output.splitlines():
    line = line.strip()
    if not line:
        continue
    pid, _, args = line.partition(" ")
    if pid == str(os.getpid()):
        continue
    if all(fragment in args for fragment in required):
        print(pid)
PY
)

  if [[ "${#pids[@]}" -gt 0 ]]; then
    kill -KILL "${pids[@]}" 2>/dev/null || true
  fi
}

start_project_process() {
  local name="$1"
  local project_root="$2"
  local log_path="$3"
  local pid_path="${LOG_DIR}/${name}.pid"
  shift 3

  (
    cd "${project_root}"
    nohup "${RUBY_BIN}" "$@" >>"${log_path}" 2>&1 </dev/null &
    echo $! > "${pid_path}"
  )

  STARTED_PID="$(cat "${pid_path}")"
  rm -f "${pid_path}"
}

reset_project_database() {
  local name="$1"
  local project_root="$2"
  local log_path="$3"

  (
    cd "${project_root}"
    export DISABLE_DATABASE_ENVIRONMENT_CHECK=1
    "${RUBY_BIN}" bin/rails db:drop >>"${log_path}" 2>&1 || true
    rm -f db/schema.rb
    "${RUBY_BIN}" bin/rails db:create >>"${log_path}" 2>&1
    "${RUBY_BIN}" bin/rails db:migrate >>"${log_path}" 2>&1
    "${RUBY_BIN}" bin/rails db:seed >>"${log_path}" 2>&1
  )
}

reset_docker_database() {
  local container_name="$1"

  docker exec "${container_name}" sh -lc \
    "cd /rails && export RAILS_ENV=production DISABLE_DATABASE_ENVIRONMENT_CHECK=1 && (bin/rails db:drop || true) && rm -f db/schema.rb && bin/rails db:create && bin/rails db:migrate && bin/rails db:seed" \
    >>"${LOG_DIR}/fenix-docker-db-reset.log" 2>&1
}

remove_container_if_present() {
  local container_name="$1"
  docker rm -f "${container_name}" >/dev/null 2>&1 || true
  wait_for_container_absent "${container_name}"
}

remove_volume_if_present() {
  local volume_name="$1"
  docker volume rm -f "${volume_name}" >/dev/null 2>&1 || true
}

rebuild_docker_capstone_image() {
  docker build -t "${NEXUS_DOCKER_IMAGE}" -f "${NEXUS_ROOT}/Dockerfile" "${REPO_ROOT}" >>"${LOG_DIR}/fenix-docker-build.log" 2>&1
  docker build --build-arg "NEXUS_BASE_IMAGE=${NEXUS_DOCKER_IMAGE}" -t "${FENIX_DOCKER_IMAGE}" -f "${FENIX_ROOT}/Dockerfile" "${FENIX_ROOT}" >>"${LOG_DIR}/fenix-docker-build.log" 2>&1
}

recreate_docker_capstone_stack() {
  local docker_env_args=()

  mkdir -p "${FENIX_DOCKER_WORKSPACE_ROOT}"
  wait_for_docker_ready
  rebuild_docker_capstone_image

  if [[ -f "${FENIX_DOCKER_ENV_FILE}" ]]; then
    docker_env_args+=(--env-file "${FENIX_DOCKER_ENV_FILE}")
  else
    echo "missing Fenix docker env file: ${FENIX_DOCKER_ENV_FILE}" >&2
    exit 1
  fi

  remove_container_if_present "${FENIX_DOCKER_CONTAINER}"
  remove_container_if_present "${FENIX_DOCKER_PROXY_CONTAINER}"
  wait_for_container_absent "${FENIX_DOCKER_CONTAINER}"
  wait_for_container_absent "${FENIX_DOCKER_PROXY_CONTAINER}"
  remove_volume_if_present "fenix_capstone_storage"
  remove_volume_if_present "fenix_capstone_proxy_routes"

  docker run -d \
    --name "${FENIX_DOCKER_CONTAINER}" \
    -p "${FENIX_RUNTIME_PORT}:80" \
    "${docker_env_args[@]}" \
    -e "RAILS_ENV=production" \
    -e "FENIX_PUBLIC_BASE_URL=${FENIX_RUNTIME_BASE_URL}" \
    -e "PLAYWRIGHT_BROWSERS_PATH=/opt/playwright" \
    -e "FENIX_DEV_PROXY_PORT=${FENIX_DOCKER_PROXY_PORT}" \
    -e "FENIX_DEV_PROXY_ROUTES_FILE=/rails/tmp/dev-proxy/routes.caddy" \
    -v "${FENIX_DOCKER_WORKSPACE_ROOT}:/workspace" \
    -v "fenix_capstone_storage:/rails/storage" \
    -v "fenix_capstone_proxy_routes:/rails/tmp/dev-proxy" \
    "${FENIX_DOCKER_IMAGE}" \
    >/dev/null

  docker run -d \
    --name "${FENIX_DOCKER_PROXY_CONTAINER}" \
    -p "${FENIX_DOCKER_PROXY_PORT}:${FENIX_DOCKER_PROXY_PORT}" \
    "${docker_env_args[@]}" \
    -e "RAILS_ENV=production" \
    -e "PLAYWRIGHT_BROWSERS_PATH=/opt/playwright" \
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
}

start_rails_server_daemon() {
  local name="$1"
  local project_root="$2"
  local host="$3"
  local port="$4"
  local log_path="$5"

  (
    cd "${project_root}"
    "${RUBY_BIN}" bin/rails server -d -b "${host}" -p "${port}" >>"${log_path}" 2>&1
  )

  for _ in $(seq 1 50); do
    STARTED_PID="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
    if [[ -n "${STARTED_PID}" ]]; then
      return 0
    fi
    sleep 0.1
  done

  echo "timed out waiting for server on port ${port}" >&2
  return 1
}

CORE_MATRIX_HOST="$(parse_url_field "${CORE_MATRIX_BASE_URL}" host)"
CORE_MATRIX_PORT="$(parse_url_field "${CORE_MATRIX_BASE_URL}" port)"
FENIX_RUNTIME_HOST="$(parse_url_field "${FENIX_RUNTIME_BASE_URL}" host)"
FENIX_RUNTIME_PORT="$(parse_url_field "${FENIX_RUNTIME_BASE_URL}" port)"

if [[ -z "${CORE_MATRIX_HOST}" || -z "${CORE_MATRIX_PORT}" ]]; then
  echo "invalid CORE_MATRIX_BASE_URL: ${CORE_MATRIX_BASE_URL}" >&2
  exit 1
fi

if [[ -z "${FENIX_RUNTIME_HOST}" || -z "${FENIX_RUNTIME_PORT}" ]]; then
  echo "invalid FENIX_RUNTIME_BASE_URL: ${FENIX_RUNTIME_BASE_URL}" >&2
  exit 1
fi

stop_listening_port "${CORE_MATRIX_PORT}"
stop_matching_process "${CORE_MATRIX_ROOT}/bin/jobs" "start"
stop_matching_process "solid-queue-fork-supervisor"
clear_server_pidfile "${CORE_MATRIX_ROOT}"
reset_project_database "core-matrix" "${CORE_MATRIX_ROOT}" "${LOG_DIR}/core-matrix-db-reset.log"

start_rails_server_daemon "core-matrix-server" "${CORE_MATRIX_ROOT}" "${CORE_MATRIX_HOST}" "${CORE_MATRIX_PORT}" "${LOG_DIR}/core-matrix-server.log"
CORE_MATRIX_SERVER_PID="${STARTED_PID}"
start_project_process "core-matrix-jobs" "${CORE_MATRIX_ROOT}" "${LOG_DIR}/core-matrix-jobs.log" bin/jobs start
CORE_MATRIX_JOBS_PID="${STARTED_PID}"

wait_for_http_ok "${CORE_MATRIX_BASE_URL}/up"

if [[ "${FENIX_RUNTIME_MODE}" == "host" ]]; then
  stop_listening_port "${FENIX_RUNTIME_PORT}"
  stop_matching_process "${FENIX_ROOT}/bin/rails" "server"
  clear_server_pidfile "${FENIX_ROOT}"
  reset_project_database "fenix-runtime" "${FENIX_ROOT}" "${LOG_DIR}/fenix-runtime-db-reset.log"

  start_rails_server_daemon "fenix-runtime-server" "${FENIX_ROOT}" "${FENIX_RUNTIME_HOST}" "${FENIX_RUNTIME_PORT}" "${LOG_DIR}/fenix-runtime-server.log"
  FENIX_RUNTIME_PID="${STARTED_PID}"

  wait_for_http_ok "${FENIX_RUNTIME_BASE_URL}/up"
  wait_for_http_ok "${FENIX_RUNTIME_BASE_URL}/runtime/manifest"
  DOCKER_STATUS="not_applicable"
elif [[ "${FENIX_RUNTIME_MODE}" == "docker" ]]; then
  stop_matching_process "${FENIX_ROOT}/bin/rails" "server"
  clear_server_pidfile "${FENIX_ROOT}"
  recreate_docker_capstone_stack
  FENIX_RUNTIME_PID="docker:${FENIX_DOCKER_CONTAINER}"

  if [[ "${RESET_DOCKER_DB}" == "true" ]]; then
    reset_docker_database "${FENIX_DOCKER_CONTAINER}"
    DOCKER_STATUS="recreated+reset"
  else
    DOCKER_STATUS="recreated"
  fi
else
  echo "unsupported FENIX_RUNTIME_MODE: ${FENIX_RUNTIME_MODE}" >&2
  exit 1
fi

cat <<EOF
fresh start complete
core_matrix_base_url=${CORE_MATRIX_BASE_URL}
core_matrix_server_pid=${CORE_MATRIX_SERVER_PID}
core_matrix_jobs_pid=${CORE_MATRIX_JOBS_PID}
fenix_runtime_mode=${FENIX_RUNTIME_MODE}
fenix_runtime_base_url=${FENIX_RUNTIME_BASE_URL}
fenix_runtime_server_pid=${FENIX_RUNTIME_PID}
fenix_docker_container=${FENIX_DOCKER_CONTAINER}
fenix_docker_status=${DOCKER_STATUS}
log_dir=${LOG_DIR}
EOF
