#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFICATION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${VERIFICATION_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
FENIX_ROOT="${REPO_ROOT}/agents/fenix"
NEXUS_ROOT="${REPO_ROOT}/execution_runtimes/nexus"
LOG_DIR="${VERIFICATION_ROOT}/logs"
MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-smoke}"
source "${SCRIPT_DIR}/process_manager.sh"

DEFAULT_ARTIFACT_STAMP="$(date '+%Y-%m-%d-%H%M%S')-multi-agent-runtime-core-matrix-load-${MULTI_FENIX_LOAD_PROFILE}"
ARTIFACT_STAMP="${MULTI_FENIX_LOAD_ARTIFACT_STAMP:-${DEFAULT_ARTIFACT_STAMP}}"

require_command() {
  local name="$1"
  if ! command -v "${name}" >/dev/null 2>&1; then
    echo "missing required command: ${name}" >&2
    exit 1
  fi
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

cleanup_extra_runtime_servers() {
  local pidfile

  for pidfile in "${EXTRA_RUNTIME_PIDFILES[@]:-}"; do
    [[ -f "${pidfile}" ]] || continue

    local pid
    pid="$(cat "${pidfile}")"
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
      kill -TERM "${pid}" 2>/dev/null || true
      sleep 0.5
      kill -KILL "${pid}" 2>/dev/null || true
    fi
    rm -f "${pidfile}"
  done
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

fenix_worker_topology_ready() {
  local home_root="$1"
  local storage_root="$2"
  local event_output_path="$3"
  local slot_label="$4"

  (
    cd "${FENIX_ROOT}"
    FENIX_HOME_ROOT="${home_root}" \
      FENIX_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      ruby bin/rails runner '
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
  local home_root="$1"
  local storage_root="$2"
  local event_output_path="$3"
  local slot_label="$4"

  (
    cd "${FENIX_ROOT}"
    FENIX_HOME_ROOT="${home_root}" \
      FENIX_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      ruby bin/rails runner '
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

start_fenix_jobs_daemon() {
  local slot_label="$1"
  local home_root="$2"
  local storage_root="$3"
  local event_output_path="$4"
  local pidfile="$5"
  local log_path="$6"

  (
    cd "${FENIX_ROOT}"
    FENIX_HOME_ROOT="${home_root}" \
      FENIX_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      ruby - "${log_path}" <<'RUBY'
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
    if fenix_worker_topology_ready "${home_root}" "${storage_root}" "${event_output_path}" "${slot_label}"; then
      fetch_fenix_jobs_supervisor_pid "${home_root}" "${storage_root}" "${event_output_path}" "${slot_label}" >"${pidfile}"
      return 0
    fi
    sleep 0.2
  done

  stop_matching_process "${FENIX_ROOT}/bin/jobs" "start"
  echo "timed out waiting for ${slot_label} jobs daemon to become ready" >&2
  return 1
}

prepare_fenix_slot_database() {
  local slot_label="$1"
  local home_root="$2"
  local storage_root="$3"
  local event_output_path="$4"
  local log_path="$5"

  rm -rf "${storage_root}"
  mkdir -p "${home_root}" "${storage_root}" "$(dirname "${event_output_path}")"

  (
    cd "${FENIX_ROOT}"
    FENIX_HOME_ROOT="${home_root}" \
      FENIX_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      bin/rails db:prepare >>"${log_path}" 2>&1
  )
}

nexus_worker_topology_ready() {
  local home_root="$1"
  local storage_root="$2"
  local event_output_path="$3"
  local slot_label="$4"

  (
    cd "${NEXUS_ROOT}"
    NEXUS_HOME_ROOT="${home_root}" \
      NEXUS_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      ruby bin/rails runner '
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

fetch_nexus_jobs_supervisor_pid() {
  local home_root="$1"
  local storage_root="$2"
  local event_output_path="$3"
  local slot_label="$4"

  (
    cd "${NEXUS_ROOT}"
    NEXUS_HOME_ROOT="${home_root}" \
      NEXUS_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      ruby bin/rails runner '
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

start_nexus_jobs_daemon() {
  local slot_label="$1"
  local home_root="$2"
  local storage_root="$3"
  local event_output_path="$4"
  local pidfile="$5"
  local log_path="$6"

  (
    cd "${NEXUS_ROOT}"
    NEXUS_HOME_ROOT="${home_root}" \
      NEXUS_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      ruby - "${log_path}" <<'RUBY'
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
    if nexus_worker_topology_ready "${home_root}" "${storage_root}" "${event_output_path}" "${slot_label}"; then
      fetch_nexus_jobs_supervisor_pid "${home_root}" "${storage_root}" "${event_output_path}" "${slot_label}" >"${pidfile}"
      return 0
    fi
    sleep 0.2
  done

  stop_matching_process "${NEXUS_ROOT}/bin/jobs" "start"
  echo "timed out waiting for ${slot_label} jobs daemon to become ready" >&2
  return 1
}

prepare_nexus_slot_database() {
  local slot_label="$1"
  local home_root="$2"
  local storage_root="$3"
  local event_output_path="$4"
  local log_path="$5"

  rm -rf "${storage_root}"
  mkdir -p "${home_root}" "${storage_root}" "$(dirname "${event_output_path}")"

  (
    cd "${NEXUS_ROOT}"
    NEXUS_HOME_ROOT="${home_root}" \
      NEXUS_STORAGE_ROOT="${storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      bin/rails db:prepare >>"${log_path}" 2>&1
  )
}

require_command curl
require_command lsof
require_command ruby

PROFILE_INLINE_CONTROL_WORKER="$(
  REPO_ROOT="${REPO_ROOT}" PROFILE_NAME="${MULTI_FENIX_LOAD_PROFILE}" ruby - <<'RUBY'
require File.join(ENV.fetch("REPO_ROOT"), "verification/lib/verification/suites/perf/profile")

profile = Verification::Perf::Profile.fetch(ENV.fetch("PROFILE_NAME"))
puts(profile.inline_control_worker? ? "true" : "false")
RUBY
)"

START_FENIX_JOBS_DAEMONS="true"
if [[ "${PROFILE_INLINE_CONTROL_WORKER}" == "true" ]]; then
  START_FENIX_JOBS_DAEMONS="false"
fi

RUN_ROOT=""
ARTIFACT_DIR=""
RUNNER_DB_POOL=""
AGENT_COUNT=""
declare -a SLOT_ROWS=()
while IFS= read -r row; do
  IFS=$'\t' read -r row_kind _rest <<< "${row}"
  case "${row_kind}" in
    run_root)
      IFS=$'\t' read -r _ RUN_ROOT <<< "${row}"
      ;;
    artifact_root)
      IFS=$'\t' read -r _ ARTIFACT_DIR <<< "${row}"
      ;;
    runner_db_pool)
      IFS=$'\t' read -r _ RUNNER_DB_POOL <<< "${row}"
      ;;
    agent_count)
      IFS=$'\t' read -r _ AGENT_COUNT <<< "${row}"
      ;;
    slot)
      SLOT_ROWS+=("${row}")
      ;;
  esac
done < <(
  ruby - "${MULTI_FENIX_LOAD_PROFILE}" "${REPO_ROOT}" "${VERIFICATION_ROOT}" "${ARTIFACT_STAMP}" <<'RUBY'
require "uri"

profile_name = ARGV.fetch(0)
repo_root = File.expand_path(ARGV.fetch(1))
verification_root = File.expand_path(ARGV.fetch(2))
artifact_stamp = ARGV.fetch(3)

require File.join(repo_root, "verification/lib/verification/suites/perf/profile")
require File.join(repo_root, "verification/lib/verification/suites/perf/topology")

profile = Verification::Perf::Profile.fetch(profile_name)
topology = Verification::Perf::Topology.build(
  profile: profile,
  repo_root: repo_root,
  verification_root: verification_root,
  artifact_stamp: artifact_stamp
)

puts ["run_root", topology.run_root.to_s].join("\t")
puts ["artifact_root", topology.artifact_root.to_s].join("\t")
puts ["runner_db_pool", profile.recommended_runner_db_pool].join("\t")
puts ["agent_count", profile.agent_count].join("\t")
topology.runtime_slots.each do |slot|
  puts [
    "slot",
    slot.index,
    slot.label,
    slot.runtime_base_url,
    URI(slot.runtime_base_url).port,
    slot.home_root.to_s,
    slot.home_root.join("storage").to_s,
    slot.event_output_path.to_s
  ].join("\t")
end
RUBY
)

if [[ -z "${RUNNER_DB_POOL}" ]]; then
  echo "expected runner db pool sizing for profile ${MULTI_FENIX_LOAD_PROFILE}" >&2
  exit 1
fi

if [[ "${AGENT_COUNT}" != "1" ]]; then
  echo "multi-fenix load wrapper currently supports exactly one shared Fenix agent, got agent_count=${AGENT_COUNT:-unset}" >&2
  exit 1
fi

RUNTIME_COUNT="${#SLOT_ROWS[@]}"
if [[ "${RUNTIME_COUNT}" -lt 1 ]]; then
  echo "expected at least one runtime slot for profile ${MULTI_FENIX_LOAD_PROFILE}" >&2
  exit 1
fi

mkdir -p "${ARTIFACT_DIR}/evidence" "${ARTIFACT_DIR}/review" "${LOG_DIR}" "${RUN_ROOT}/pids"

PROVIDER_CATALOG_OVERRIDE_DIR="${RUN_ROOT}/core-matrix-config.d"
export PROVIDER_CATALOG_OVERRIDE_DIR

ruby - "${REPO_ROOT}" "${MULTI_FENIX_LOAD_PROFILE}" "${PROVIDER_CATALOG_OVERRIDE_DIR}" <<'RUBY'
repo_root = File.expand_path(ARGV.fetch(0))
profile_name = ARGV.fetch(1)
override_dir = File.expand_path(ARGV.fetch(2))

require File.join(repo_root, "verification/lib/verification/suites/perf/profile")
require File.join(repo_root, "verification/lib/verification/suites/perf/provider_catalog_override")

profile = Verification::Perf::Profile.fetch(profile_name)
Verification::Perf::ProviderCatalogOverride.write(
  profile: profile,
  override_dir: override_dir,
  env: "development"
)
RUBY

IFS=$'\t' read -r _ FIRST_SLOT_INDEX FIRST_SLOT_LABEL FIRST_RUNTIME_BASE_URL FIRST_RUNTIME_PORT FIRST_HOME_ROOT FIRST_STORAGE_ROOT FIRST_EVENT_OUTPUT_PATH <<< "${SLOT_ROWS[0]}"

CORE_MATRIX_PERF_EVENTS_PATH="${ARTIFACT_DIR}/evidence/core-matrix-events.ndjson"
CORE_MATRIX_PERF_INSTANCE_LABEL="${CORE_MATRIX_PERF_INSTANCE_LABEL:-core-matrix-01}"
FENIX_RUNTIME_COUNT="1"
FENIX_AGENT_BASE_URL="${FENIX_AGENT_BASE_URL:-http://127.0.0.1:3101}"
FENIX_RUNTIME_BASE_URL="${FENIX_AGENT_BASE_URL}"
FENIX_HOME_ROOT="${RUN_ROOT}/fenix-01/home"
FENIX_STORAGE_ROOT="${FENIX_HOME_ROOT}/storage"
FENIX_AGENT_EVENTS_PATH="${ARTIFACT_DIR}/evidence/fenix-01-events.ndjson"
CYBROS_PERF_EVENTS_PATH="${FENIX_AGENT_EVENTS_PATH}"
CYBROS_PERF_INSTANCE_LABEL="fenix-01"

export MULTI_FENIX_LOAD_ARTIFACT_STAMP="${ARTIFACT_STAMP}"
export MULTI_FENIX_LOAD_PROFILE
export MULTI_FENIX_LOAD_STACK_ALREADY_RESET="true"
export CORE_MATRIX_PERF_EVENTS_PATH
export CORE_MATRIX_PERF_INSTANCE_LABEL
export FENIX_AGENT_BASE_URL
export FENIX_RUNTIME_COUNT
export FENIX_RUNTIME_BASE_URL
export FENIX_HOME_ROOT
export FENIX_STORAGE_ROOT
export FENIX_HOST_START_JOBS_DAEMON="${START_FENIX_JOBS_DAEMONS}"
export FENIX_AGENT_EVENTS_PATH
export CYBROS_PERF_EVENTS_PATH
export CYBROS_PERF_INSTANCE_LABEL

verification_process_manager_prepare_session

bash "${SCRIPT_DIR}/fresh_start_stack.sh"

declare -a EXTRA_RUNTIME_PIDFILES=()
VERIFICATION_PROCESS_MANAGER_PRE_CLEANUP_HOOK="cleanup_extra_runtime_servers"
trap verification_process_manager_cleanup_current_session_and_verify EXIT

for row in "${SLOT_ROWS[@]}"; do
  IFS=$'\t' read -r _ slot_index slot_label slot_base_url runtime_port slot_home_root slot_storage_root slot_event_output_path <<< "${row}"
  pidfile="${RUN_ROOT}/pids/${slot_label}-server.pid"
  jobs_pidfile="${RUN_ROOT}/pids/${slot_label}-jobs.pid"
  log_path="${LOG_DIR}/${slot_label}-server.log"
  jobs_log_path="${LOG_DIR}/${slot_label}-jobs.log"

  stop_listening_port "${runtime_port}"
  rm -f "${pidfile}" "${jobs_pidfile}"
  prepare_nexus_slot_database \
    "${slot_label}" \
    "${slot_home_root}" \
    "${slot_storage_root}" \
    "${slot_event_output_path}" \
    "${LOG_DIR}/${slot_label}-db-prepare.log"

  (
    cd "${NEXUS_ROOT}"
    NEXUS_HOME_ROOT="${slot_home_root}" \
      NEXUS_STORAGE_ROOT="${slot_storage_root}" \
      CYBROS_PERF_EVENTS_PATH="${slot_event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      bin/rails server -d -b 127.0.0.1 -p "${runtime_port}" -P "${pidfile}" >>"${log_path}" 2>&1
  )

  EXTRA_RUNTIME_PIDFILES+=("${pidfile}")
  if [[ "${START_FENIX_JOBS_DAEMONS}" == "true" ]]; then
    start_nexus_jobs_daemon "${slot_label}" "${slot_home_root}" "${slot_storage_root}" "${slot_event_output_path}" "${jobs_pidfile}" "${jobs_log_path}"
    EXTRA_RUNTIME_PIDFILES+=("${jobs_pidfile}")
    verification_process_manager_track_pidfile "${slot_label}-jobs" "${jobs_pidfile}" ""
  fi
  wait_for_http_ok "${slot_base_url}/up"
  wait_for_http_ok "${slot_base_url}/runtime/manifest"
  verification_process_manager_track_pidfile "${slot_label}-server" "${pidfile}" "${runtime_port}"
done

cd "${CORE_MATRIX_ROOT}"
RAILS_DB_POOL="${MULTI_FENIX_LOAD_RUNNER_DB_POOL:-${RUNNER_DB_POOL}}" \
  bin/rails runner "${REPO_ROOT}/verification/scenarios/perf/multi_fenix_core_matrix_load_validation.rb"
