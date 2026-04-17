#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFICATION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${VERIFICATION_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
FENIX_ROOT="${REPO_ROOT}/agents/fenix"
NEXUS_ROOT="${REPO_ROOT}/execution_runtimes/nexus"
CORE_MATRIX_PORT="${CORE_MATRIX_PORT:-3000}"
FENIX_RUNTIME_PORT="${FENIX_RUNTIME_PORT:-3101}"
NEXUS_RUNTIME_PORT="${NEXUS_RUNTIME_PORT:-3301}"

source "${SCRIPT_DIR}/process_manager.sh"

status=0

verification_process_manager_cleanup_all_sessions || status=1
verification_process_manager_cleanup_known_verification_processes || status=1
verification_process_manager_cleanup_all_sessions || status=1

exit "${status}"
