#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
FENIX_ROOT="${FENIX_PROJECT_ROOT:-${REPO_ROOT}/agents/fenix}"
NEXUS_ROOT="${NEXUS_PROJECT_ROOT:-${REPO_ROOT}/execution_runtimes/nexus}"
LOG_DIR="${ACCEPTANCE_ROOT}/logs"

CORE_MATRIX_BASE_URL="${CORE_MATRIX_BASE_URL:-http://127.0.0.1:3000}"
CORE_MATRIX_PERF_EVENTS_PATH="${CORE_MATRIX_PERF_EVENTS_PATH:-}"
CORE_MATRIX_PERF_INSTANCE_LABEL="${CORE_MATRIX_PERF_INSTANCE_LABEL:-}"
FENIX_RUNTIME_BASE_URL="${FENIX_RUNTIME_BASE_URL:-http://127.0.0.1:3101}"
NEXUS_RUNTIME_BASE_URL="${NEXUS_RUNTIME_BASE_URL:-http://127.0.0.1:3301}"
FENIX_RUNTIME_COUNT="${FENIX_RUNTIME_COUNT:-1}"
FENIX_HOME_ROOT="${FENIX_HOME_ROOT:-${REPO_ROOT}/tmp/acceptance-fenix-home}"
FENIX_STORAGE_ROOT="${FENIX_STORAGE_ROOT:-${FENIX_HOME_ROOT}/storage}"
FENIX_HOST_START_JOBS_DAEMON="${FENIX_HOST_START_JOBS_DAEMON:-false}"
NEXUS_HOME_ROOT="${NEXUS_HOME_ROOT:-${REPO_ROOT}/tmp/acceptance-nexus-home}"
NEXUS_STORAGE_ROOT="${NEXUS_STORAGE_ROOT:-${NEXUS_HOME_ROOT}/storage}"
CYBROS_PERF_EVENTS_PATH="${CYBROS_PERF_EVENTS_PATH:-}"
CYBROS_PERF_INSTANCE_LABEL="${CYBROS_PERF_INSTANCE_LABEL:-}"

mkdir -p "${LOG_DIR}"
rm -f "${LOG_DIR}"/*.log
mkdir -p "${FENIX_HOME_ROOT}" "${FENIX_STORAGE_ROOT}"
mkdir -p "${NEXUS_HOME_ROOT}" "${NEXUS_STORAGE_ROOT}"

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

if ! [[ "${FENIX_RUNTIME_COUNT}" =~ ^[1-9][0-9]*$ ]]; then
  echo "invalid FENIX_RUNTIME_COUNT: ${FENIX_RUNTIME_COUNT}" >&2
  exit 1
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

core_matrix_worker_topology_ready() {
  local project_root="$1"

  (
    cd "${project_root}"
    "${RUBY_BIN}" bin/rails runner '
      expected_queues = %w[llm_dev workflow_default workflow_resume tool_calls]
      heartbeat_cutoff = 5.seconds.ago

      live_pid = lambda do |pid|
        next false unless pid

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      supervisor = SolidQueue::Process.find_by(kind: "Supervisor(fork)")
      workers = SolidQueue::Process.where(kind: "Worker")
      registered_queues =
        workers.filter_map do |worker|
          next unless worker.last_heartbeat_at && worker.last_heartbeat_at >= heartbeat_cutoff
          next unless live_pid.call(worker.pid)

          worker.metadata["queues"]
        end.uniq

      supervisor_ready =
        supervisor &&
        supervisor.last_heartbeat_at &&
        supervisor.last_heartbeat_at >= heartbeat_cutoff &&
        live_pid.call(supervisor.pid)

      exit(supervisor_ready && expected_queues.all? { |queue| registered_queues.include?(queue) } ? 0 : 1)
    ' >/dev/null 2>&1
  )
}

fetch_core_matrix_jobs_supervisor_pid() {
  local project_root="$1"

  (
    cd "${project_root}"
    "${RUBY_BIN}" bin/rails runner '
      heartbeat_cutoff = 5.seconds.ago
      supervisor = SolidQueue::Process.find_by(kind: "Supervisor(fork)")

      if supervisor&.last_heartbeat_at && supervisor.last_heartbeat_at >= heartbeat_cutoff
        begin
          Process.kill(0, supervisor.pid)
          puts supervisor.pid
        rescue Errno::ESRCH, Errno::EPERM
          puts ""
        end
      else
        puts ""
      end
    '
  )
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

wait_for_solid_queue_ready() {
  local project_root="$1"
  local attempts="${2:-30}"

  for _ in $(seq 1 "${attempts}"); do
    if core_matrix_worker_topology_ready "${project_root}"; then
      return 0
    fi

    sleep 0.2
  done

  return 1
}

fenix_worker_topology_ready() {
  local project_root="$1"

  (
    cd "${project_root}"
    "${RUBY_BIN}" bin/rails runner '
      expected_queues = %w[runtime_control maintenance]
      heartbeat_cutoff = 5.seconds.ago

      live_pid = lambda do |pid|
        next false unless pid

        Process.kill(0, pid)
        true
      rescue Errno::ESRCH, Errno::EPERM
        false
      end

      supervisor = SolidQueue::Process.find_by(kind: "Supervisor(fork)")
      workers = SolidQueue::Process.where(kind: "Worker")
      registered_queues =
        workers.filter_map do |worker|
          next unless worker.last_heartbeat_at && worker.last_heartbeat_at >= heartbeat_cutoff
          next unless live_pid.call(worker.pid)

          worker.metadata["queues"]
        end.uniq

      supervisor_ready =
        supervisor &&
        supervisor.last_heartbeat_at &&
        supervisor.last_heartbeat_at >= heartbeat_cutoff &&
        live_pid.call(supervisor.pid)

      exit(supervisor_ready && expected_queues.all? { |queue| registered_queues.include?(queue) } ? 0 : 1)
    ' >/dev/null 2>&1
  )
}

fetch_fenix_jobs_supervisor_pid() {
  local project_root="$1"

  (
    cd "${project_root}"
    "${RUBY_BIN}" bin/rails runner '
      heartbeat_cutoff = 5.seconds.ago
      supervisor = SolidQueue::Process.find_by(kind: "Supervisor(fork)")

      if supervisor&.last_heartbeat_at && supervisor.last_heartbeat_at >= heartbeat_cutoff
        begin
          Process.kill(0, supervisor.pid)
          puts supervisor.pid
        rescue Errno::ESRCH, Errno::EPERM
          puts ""
        end
      else
        puts ""
      end
    '
  )
}
start_core_matrix_jobs_daemon() {
  local attempts="${1:-3}"
  local log_path="${LOG_DIR}/core-matrix-jobs.log"

  for _ in $(seq 1 "${attempts}"); do
    (
      cd "${CORE_MATRIX_ROOT}"
      "${RUBY_BIN}" - "${log_path}" <<'RUBY'
log_path = ARGV.fetch(0)
STDOUT.reopen(log_path, "a")
STDERR.reopen(STDOUT)
STDOUT.sync = true
STDERR.sync = true
Process.daemon(true, true)
STDOUT.reopen(log_path, "a")
STDERR.reopen(STDOUT)
STDOUT.sync = true
STDERR.sync = true
exec("./bin/jobs", "start")
RUBY
    )

    if wait_for_solid_queue_ready "${CORE_MATRIX_ROOT}"; then
      STARTED_PID="$(fetch_core_matrix_jobs_supervisor_pid "${CORE_MATRIX_ROOT}")"
      return 0
    fi

    stop_matching_process "${CORE_MATRIX_ROOT}/bin/jobs" "start"
    stop_matching_process "solid-queue-fork-supervisor"
    sleep 0.5
  done

  echo "timed out waiting for core-matrix jobs to become ready" >&2
  return 1
}

start_fenix_jobs_daemon() {
  local attempts="${1:-3}"
  local log_path="${LOG_DIR}/fenix-runtime-jobs.log"

  for _ in $(seq 1 "${attempts}"); do
    (
      cd "${FENIX_ROOT}"
      "${RUBY_BIN}" - "${log_path}" <<'RUBY'
log_path = ARGV.fetch(0)
STDOUT.reopen(log_path, "a")
STDERR.reopen(STDOUT)
STDOUT.sync = true
STDERR.sync = true
Process.daemon(true, true)
STDOUT.reopen(log_path, "a")
STDERR.reopen(STDOUT)
STDOUT.sync = true
STDERR.sync = true
exec("./bin/jobs", "start")
RUBY
    )

    for _ in $(seq 1 30); do
      if fenix_worker_topology_ready "${FENIX_ROOT}"; then
        STARTED_PID="$(fetch_fenix_jobs_supervisor_pid "${FENIX_ROOT}")"
        return 0
      fi
      sleep 0.2
    done

    stop_matching_process "${FENIX_ROOT}/bin/jobs" "start"
    sleep 0.5
  done

  echo "timed out waiting for fenix-runtime jobs to become ready" >&2
  return 1
}

reset_project_database() {
  local name="$1"
  local project_root="$2"
  local log_path="$3"
  shift 3
  local -a extra_tasks=()
  if [[ "$#" -gt 0 ]]; then
    extra_tasks=("$@")
  fi

  (
    cd "${project_root}"
    export DISABLE_DATABASE_ENVIRONMENT_CHECK=1
    "${RUBY_BIN}" bin/rails db:drop >>"${log_path}" 2>&1 || true
    "${RUBY_BIN}" bin/rails db:prepare >>"${log_path}" 2>&1
    if [[ "${#extra_tasks[@]}" -gt 0 ]]; then
      for task in "${extra_tasks[@]}"; do
        "${RUBY_BIN}" bin/rails "${task}" >>"${log_path}" 2>&1
      done
    fi
    "${RUBY_BIN}" bin/rails db:seed >>"${log_path}" 2>&1
  )
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
NEXUS_RUNTIME_HOST="$(parse_url_field "${NEXUS_RUNTIME_BASE_URL}" host)"
NEXUS_RUNTIME_PORT="$(parse_url_field "${NEXUS_RUNTIME_BASE_URL}" port)"

if [[ -z "${CORE_MATRIX_HOST}" || -z "${CORE_MATRIX_PORT}" ]]; then
  echo "invalid CORE_MATRIX_BASE_URL: ${CORE_MATRIX_BASE_URL}" >&2
  exit 1
fi

if [[ -z "${FENIX_RUNTIME_HOST}" || -z "${FENIX_RUNTIME_PORT}" ]]; then
  echo "invalid FENIX_RUNTIME_BASE_URL: ${FENIX_RUNTIME_BASE_URL}" >&2
  exit 1
fi

if [[ -z "${NEXUS_RUNTIME_HOST}" || -z "${NEXUS_RUNTIME_PORT}" ]]; then
  echo "invalid NEXUS_RUNTIME_BASE_URL: ${NEXUS_RUNTIME_BASE_URL}" >&2
  exit 1
fi

stop_listening_port "${CORE_MATRIX_PORT}"
stop_matching_process "${CORE_MATRIX_ROOT}/bin/jobs" "start"
stop_matching_process "solid-queue-fork-supervisor"
clear_server_pidfile "${CORE_MATRIX_ROOT}"
reset_project_database "core-matrix" "${CORE_MATRIX_ROOT}" "${LOG_DIR}/core-matrix-db-reset.log" "db:schema:load:queue" "db:schema:load:cable"

export CORE_MATRIX_PERF_EVENTS_PATH
export CORE_MATRIX_PERF_INSTANCE_LABEL
start_rails_server_daemon "core-matrix-server" "${CORE_MATRIX_ROOT}" "${CORE_MATRIX_HOST}" "${CORE_MATRIX_PORT}" "${LOG_DIR}/core-matrix-server.log"
CORE_MATRIX_SERVER_PID="${STARTED_PID}"
start_core_matrix_jobs_daemon
CORE_MATRIX_JOBS_PID="${STARTED_PID}"

wait_for_http_ok "${CORE_MATRIX_BASE_URL}/up"

export NEXUS_HOME_ROOT
export NEXUS_STORAGE_ROOT
export CYBROS_PERF_EVENTS_PATH
export CYBROS_PERF_INSTANCE_LABEL
stop_listening_port "${NEXUS_RUNTIME_PORT}"
stop_matching_process "${NEXUS_ROOT}/bin/rails" "server"
clear_server_pidfile "${NEXUS_ROOT}"
reset_project_database "nexus-runtime" "${NEXUS_ROOT}" "${LOG_DIR}/nexus-runtime-db-reset.log"

start_rails_server_daemon "nexus-runtime-server" "${NEXUS_ROOT}" "${NEXUS_RUNTIME_HOST}" "${NEXUS_RUNTIME_PORT}" "${LOG_DIR}/nexus-runtime-server.log"
NEXUS_RUNTIME_PID="${STARTED_PID}"

wait_for_http_ok "${NEXUS_RUNTIME_BASE_URL}/up"
wait_for_http_ok "${NEXUS_RUNTIME_BASE_URL}/runtime/manifest"

export FENIX_HOME_ROOT
export FENIX_STORAGE_ROOT
export CYBROS_PERF_EVENTS_PATH
export CYBROS_PERF_INSTANCE_LABEL
stop_listening_port "${FENIX_RUNTIME_PORT}"
stop_matching_process "${FENIX_ROOT}/bin/rails" "server"
stop_matching_process "${FENIX_ROOT}/bin/jobs" "start"
clear_server_pidfile "${FENIX_ROOT}"
reset_project_database "fenix-runtime" "${FENIX_ROOT}" "${LOG_DIR}/fenix-runtime-db-reset.log"

start_rails_server_daemon "fenix-runtime-server" "${FENIX_ROOT}" "${FENIX_RUNTIME_HOST}" "${FENIX_RUNTIME_PORT}" "${LOG_DIR}/fenix-runtime-server.log"
FENIX_RUNTIME_PID="${STARTED_PID}"
if [[ "${FENIX_HOST_START_JOBS_DAEMON}" == "true" ]]; then
  start_fenix_jobs_daemon
  FENIX_RUNTIME_JOBS_PID="${STARTED_PID}"
else
  FENIX_RUNTIME_JOBS_PID="not_started"
fi

wait_for_http_ok "${FENIX_RUNTIME_BASE_URL}/up"
wait_for_http_ok "${FENIX_RUNTIME_BASE_URL}/runtime/manifest"

cat <<EOF
fresh start complete
core_matrix_base_url=${CORE_MATRIX_BASE_URL}
core_matrix_server_pid=${CORE_MATRIX_SERVER_PID}
core_matrix_jobs_pid=${CORE_MATRIX_JOBS_PID}
fenix_runtime_count=${FENIX_RUNTIME_COUNT}
fenix_runtime_base_url=${FENIX_RUNTIME_BASE_URL}
fenix_runtime_server_pid=${FENIX_RUNTIME_PID}
fenix_runtime_jobs_pid=${FENIX_RUNTIME_JOBS_PID:-not_applicable}
fenix_home_root=${FENIX_HOME_ROOT}
fenix_storage_root=${FENIX_STORAGE_ROOT}
nexus_runtime_base_url=${NEXUS_RUNTIME_BASE_URL}
nexus_runtime_server_pid=${NEXUS_RUNTIME_PID}
nexus_home_root=${NEXUS_HOME_ROOT}
nexus_storage_root=${NEXUS_STORAGE_ROOT}
log_dir=${LOG_DIR}
EOF
