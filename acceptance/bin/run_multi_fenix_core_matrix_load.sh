#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
FENIX_ROOT="${REPO_ROOT}/agents/fenix"
LOG_DIR="${ACCEPTANCE_ROOT}/logs"
MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-smoke}"
FENIX_RUNTIME_MODE="${FENIX_RUNTIME_MODE:-host}"

if [[ "${FENIX_RUNTIME_MODE}" != "host" ]]; then
  echo "multi-fenix load wrapper only supports host runtimes" >&2
  exit 1
fi

DEFAULT_ARTIFACT_STAMP="$(date '+%Y-%m-%d-%H%M%S')-multi-fenix-core-matrix-load-${MULTI_FENIX_LOAD_PROFILE}"
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

require_command curl
require_command lsof
require_command ruby

RUN_ROOT=""
ARTIFACT_DIR=""
RUNNER_DB_POOL=""
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
    slot)
      SLOT_ROWS+=("${row}")
      ;;
  esac
done < <(
  ruby - "${MULTI_FENIX_LOAD_PROFILE}" "${REPO_ROOT}" "${ACCEPTANCE_ROOT}" "${ARTIFACT_STAMP}" <<'RUBY'
require "uri"

profile_name = ARGV.fetch(0)
repo_root = File.expand_path(ARGV.fetch(1))
acceptance_root = File.expand_path(ARGV.fetch(2))
artifact_stamp = ARGV.fetch(3)

require File.join(repo_root, "acceptance/lib/perf/profile")
require File.join(repo_root, "acceptance/lib/perf/topology")

profile = Acceptance::Perf::Profile.fetch(profile_name)
topology = Acceptance::Perf::Topology.build(
  profile: profile,
  repo_root: repo_root,
  acceptance_root: acceptance_root,
  artifact_stamp: artifact_stamp
)

puts ["run_root", topology.run_root.to_s].join("\t")
puts ["artifact_root", topology.artifact_root.to_s].join("\t")
puts ["runner_db_pool", profile.recommended_runner_db_pool].join("\t")
topology.runtime_slots.each do |slot|
  puts [
    "slot",
    slot.index,
    slot.label,
    slot.runtime_base_url,
    URI(slot.runtime_base_url).port,
    slot.home_root.to_s,
    slot.event_output_path.to_s
  ].join("\t")
end
RUBY
)

if [[ -z "${RUNNER_DB_POOL}" ]]; then
  echo "expected runner db pool sizing for profile ${MULTI_FENIX_LOAD_PROFILE}" >&2
  exit 1
fi

RUNTIME_COUNT="${#SLOT_ROWS[@]}"
if [[ "${RUNTIME_COUNT}" -lt 1 ]]; then
  echo "expected at least one runtime slot for profile ${MULTI_FENIX_LOAD_PROFILE}" >&2
  exit 1
fi

mkdir -p "${ARTIFACT_DIR}/evidence" "${ARTIFACT_DIR}/review" "${LOG_DIR}" "${RUN_ROOT}/pids"

IFS=$'\t' read -r _ FIRST_SLOT_INDEX FIRST_SLOT_LABEL FIRST_RUNTIME_BASE_URL FIRST_RUNTIME_PORT FIRST_HOME_ROOT FIRST_EVENT_OUTPUT_PATH <<< "${SLOT_ROWS[0]}"

CORE_MATRIX_PERF_EVENTS_PATH="${ARTIFACT_DIR}/evidence/core-matrix-events.ndjson"
CORE_MATRIX_PERF_INSTANCE_LABEL="${CORE_MATRIX_PERF_INSTANCE_LABEL:-core-matrix-01}"
FENIX_RUNTIME_COUNT="${RUNTIME_COUNT}"
FENIX_RUNTIME_BASE_URL="${FIRST_RUNTIME_BASE_URL}"
FENIX_HOME_ROOT="${FIRST_HOME_ROOT}"
CYBROS_PERF_EVENTS_PATH="${FIRST_EVENT_OUTPUT_PATH}"
CYBROS_PERF_INSTANCE_LABEL="${FIRST_SLOT_LABEL}"

export MULTI_FENIX_LOAD_ARTIFACT_STAMP="${ARTIFACT_STAMP}"
export MULTI_FENIX_LOAD_PROFILE
export CORE_MATRIX_PERF_EVENTS_PATH
export CORE_MATRIX_PERF_INSTANCE_LABEL
export FENIX_RUNTIME_MODE
export FENIX_RUNTIME_COUNT
export FENIX_RUNTIME_BASE_URL
export FENIX_HOME_ROOT
export CYBROS_PERF_EVENTS_PATH
export CYBROS_PERF_INSTANCE_LABEL

bash "${SCRIPT_DIR}/fresh_start_stack.sh"

declare -a EXTRA_RUNTIME_PIDFILES=()
trap cleanup_extra_runtime_servers EXIT

for index in $(seq 2 "${RUNTIME_COUNT}"); do
  row="${SLOT_ROWS[$((index - 1))]}"
  IFS=$'\t' read -r _ slot_index slot_label slot_base_url runtime_port slot_home_root slot_event_output_path <<< "${row}"
  pidfile="${RUN_ROOT}/pids/${slot_label}.pid"
  log_path="${LOG_DIR}/${slot_label}-server.log"

  stop_listening_port "${runtime_port}"
  rm -f "${pidfile}"
  mkdir -p "${slot_home_root}" "$(dirname "${slot_event_output_path}")"

  (
    cd "${FENIX_ROOT}"
    FENIX_HOME_ROOT="${slot_home_root}" \
      CYBROS_PERF_EVENTS_PATH="${slot_event_output_path}" \
      CYBROS_PERF_INSTANCE_LABEL="${slot_label}" \
      bin/rails server -d -b 127.0.0.1 -p "${runtime_port}" -P "${pidfile}" >>"${log_path}" 2>&1
  )

  EXTRA_RUNTIME_PIDFILES+=("${pidfile}")
  wait_for_http_ok "${slot_base_url}/up"
  wait_for_http_ok "${slot_base_url}/runtime/manifest"
done

cd "${CORE_MATRIX_ROOT}"
RAILS_DB_POOL="${MULTI_FENIX_LOAD_RUNNER_DB_POOL:-${RUNNER_DB_POOL}}" \
  bin/rails runner "${REPO_ROOT}/acceptance/scenarios/multi_fenix_core_matrix_load_validation.rb"
