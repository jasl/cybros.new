#!/usr/bin/env bash

if [[ -z "${VERIFICATION_ROOT:-}" ]]; then
  VERIFICATION_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi

VERIFICATION_PROCESS_REGISTRY_DIR="${VERIFICATION_PROCESS_REGISTRY_DIR:-${VERIFICATION_ROOT}/tmp/process-manager}"

verification_process_manager_generate_session_id() {
  date "+%Y%m%d-%H%M%S-$$"
}

verification_process_manager_current_registry_path() {
  local session_id="${1:-${VERIFICATION_PROCESS_SESSION_ID:-}}"
  [[ -n "${session_id}" ]] || return 1

  printf "%s/%s.tsv\n" "${VERIFICATION_PROCESS_REGISTRY_DIR}" "${session_id}"
}

verification_process_manager_prepare_session() {
  mkdir -p "${VERIFICATION_PROCESS_REGISTRY_DIR}"

  if [[ -z "${VERIFICATION_PROCESS_SESSION_ID:-}" ]]; then
    export VERIFICATION_PROCESS_SESSION_ID
    VERIFICATION_PROCESS_SESSION_ID="$(verification_process_manager_generate_session_id)"
  fi

  export VERIFICATION_PROCESS_REGISTRY_PATH
  VERIFICATION_PROCESS_REGISTRY_PATH="$(verification_process_manager_current_registry_path)"
  touch "${VERIFICATION_PROCESS_REGISTRY_PATH}"
}

verification_process_manager_process_command() {
  local pid="$1"
  ps -p "${pid}" -o command= 2>/dev/null | sed 's/^[[:space:]]*//'
}

verification_process_manager_pid_is_live() {
  local pid="$1"
  [[ -n "${pid}" ]] || return 1
  kill -0 "${pid}" 2>/dev/null
}

verification_process_manager_pid_matches_command() {
  local pid="$1"
  local expected_command="$2"

  verification_process_manager_pid_is_live "${pid}" || return 1
  [[ -z "${expected_command}" ]] && return 0

  local current_command
  current_command="$(verification_process_manager_process_command "${pid}")"
  [[ -n "${current_command}" ]] || return 1
  [[ "${current_command}" == "${expected_command}" ]]
}

verification_process_manager_port_has_listener() {
  local port="$1"
  [[ -n "${port}" ]] || return 1
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | grep -q .
}

verification_process_manager_stop_pid() {
  local pid="$1"
  verification_process_manager_pid_is_live "${pid}" || return 0

  kill -TERM "${pid}" 2>/dev/null || true
  sleep 1

  if verification_process_manager_pid_is_live "${pid}"; then
    kill -KILL "${pid}" 2>/dev/null || true
  fi
}

verification_process_manager_stop_port() {
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

verification_process_manager_stop_matching_process() {
  local pids=()

  while IFS= read -r pid; do
    [[ -n "${pid}" ]] && pids+=("${pid}")
  done < <(python3 - <<'PY' "$@"
import os
import subprocess
import sys

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
import os
import subprocess
import sys

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

verification_process_manager_track_process() {
  local label="$1"
  local pid="$2"
  local port="${3:-}"
  local registry_path
  local command=""

  [[ -n "${pid}" ]] || return 0

  verification_process_manager_prepare_session
  registry_path="${VERIFICATION_PROCESS_REGISTRY_PATH}"
  command="$(verification_process_manager_process_command "${pid}")"

  printf "%s\t%s\t%s\t%s\n" "${label}" "${pid}" "${port}" "${command}" >> "${registry_path}"
}

verification_process_manager_track_pidfile() {
  local label="$1"
  local pidfile="$2"
  local port="${3:-}"
  local pid=""

  [[ -f "${pidfile}" ]] || return 0
  pid="$(tr -d '[:space:]' < "${pidfile}")"
  verification_process_manager_track_process "${label}" "${pid}" "${port}"
}

verification_process_manager_registered_process_is_live() {
  local pid="$1"
  local port="$2"
  local command="$3"

  if verification_process_manager_pid_matches_command "${pid}" "${command}"; then
    return 0
  fi

  if verification_process_manager_port_has_listener "${port}"; then
    return 0
  fi

  return 1
}

verification_process_manager_cleanup_registry() {
  local registry_path="$1"
  local label pid port command

  [[ -f "${registry_path}" ]] || return 0

  while IFS=$'\t' read -r label pid port command || [[ -n "${label}${pid}${port}${command}" ]]; do
    [[ -n "${pid}" ]] || continue

    if verification_process_manager_pid_matches_command "${pid}" "${command}"; then
      verification_process_manager_stop_pid "${pid}"
    fi

    if [[ -n "${port}" ]]; then
      verification_process_manager_stop_port "${port}"
    fi
  done < "${registry_path}"
}

verification_process_manager_verify_session_clean() {
  local registry_path="${1:-${VERIFICATION_PROCESS_REGISTRY_PATH:-}}"
  local label pid port command
  local clean="true"

  [[ -n "${registry_path}" && -f "${registry_path}" ]] || return 0

  while IFS=$'\t' read -r label pid port command || [[ -n "${label}${pid}${port}${command}" ]]; do
    [[ -n "${pid}" ]] || continue

    if verification_process_manager_registered_process_is_live "${pid}" "${port}" "${command}"; then
      clean="false"
      printf 'managed verification process still alive: label=%s pid=%s port=%s command=%s\n' \
        "${label}" "${pid}" "${port:-none}" "${command:-unknown}" >&2
    fi
  done < "${registry_path}"

  [[ "${clean}" == "true" ]]
}

verification_process_manager_finalize_current_session() {
  local status="${1:-$?}"
  local registry_path="${VERIFICATION_PROCESS_REGISTRY_PATH:-}"

  if [[ -n "${registry_path}" ]]; then
    verification_process_manager_cleanup_registry "${registry_path}"
    verification_process_manager_verify_session_clean "${registry_path}" || status=1
    rm -f "${registry_path}"
  fi

  return "${status}"
}

verification_process_manager_cleanup_current_session_and_verify() {
  local status="$?"
  local pre_cleanup_hook="${VERIFICATION_PROCESS_MANAGER_PRE_CLEANUP_HOOK:-}"

  trap - EXIT
  if [[ -n "${pre_cleanup_hook}" ]] && declare -F "${pre_cleanup_hook}" >/dev/null 2>&1; then
    "${pre_cleanup_hook}"
  fi
  verification_process_manager_finalize_current_session "${status}"
  exit "$?"
}

verification_process_manager_cleanup_all_sessions() {
  local status=0
  local current_registry="${VERIFICATION_PROCESS_REGISTRY_PATH:-}"
  local registry_path

  mkdir -p "${VERIFICATION_PROCESS_REGISTRY_DIR}"
  shopt -s nullglob
  for registry_path in "${VERIFICATION_PROCESS_REGISTRY_DIR}"/*.tsv; do
    if [[ -n "${current_registry}" && "${registry_path}" == "${current_registry}" ]]; then
      continue
    fi

    verification_process_manager_cleanup_registry "${registry_path}"
    if verification_process_manager_verify_session_clean "${registry_path}"; then
      rm -f "${registry_path}"
    else
      status=1
    fi
  done
  shopt -u nullglob

  return "${status}"
}

verification_process_manager_cleanup_known_verification_processes() {
  local repo_root="${REPO_ROOT:-$(cd "${VERIFICATION_ROOT}/.." && pwd)}"
  local core_matrix_root="${CORE_MATRIX_ROOT:-${repo_root}/core_matrix}"
  local fenix_root="${FENIX_ROOT:-${repo_root}/agents/fenix}"
  local nexus_root="${NEXUS_ROOT:-${repo_root}/execution_runtimes/nexus}"
  local core_port="${CORE_MATRIX_PORT:-3000}"
  local fenix_port="${FENIX_RUNTIME_PORT:-3101}"
  local nexus_port="${NEXUS_RUNTIME_PORT:-3301}"

  verification_process_manager_stop_port "${core_port}"
  verification_process_manager_stop_port "${fenix_port}"
  verification_process_manager_stop_port "${nexus_port}"
  verification_process_manager_stop_matching_process "${core_matrix_root}/bin/jobs" "start"
  verification_process_manager_stop_matching_process "${fenix_root}/bin/jobs" "start"
  verification_process_manager_stop_matching_process "${nexus_root}/bin/jobs" "start"
  verification_process_manager_stop_matching_process "solid-queue-fork-supervisor"
  pkill -f "${repo_root}/tmp/fenix/game-2048" >/dev/null 2>&1 || true
}

verification_process_manager_auto_sweep() {
  local status=0

  verification_process_manager_cleanup_all_sessions || status=1
  verification_process_manager_cleanup_known_verification_processes || status=1
  verification_process_manager_cleanup_all_sessions || status=1

  return "${status}"
}
