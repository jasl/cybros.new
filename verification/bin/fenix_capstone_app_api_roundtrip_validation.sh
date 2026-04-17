#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFICATION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${VERIFICATION_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
GENERATED_APP_DIR="${REPO_ROOT}/tmp/fenix/game-2048"
source "${SCRIPT_DIR}/process_manager.sh"

cleanup_capstone_processes() {
  pkill -f "${GENERATED_APP_DIR}" >/dev/null 2>&1 || true
}

cleanup_capstone_processes
verification_process_manager_prepare_session
VERIFICATION_PROCESS_MANAGER_PRE_CLEANUP_HOOK="cleanup_capstone_processes"
trap verification_process_manager_cleanup_current_session_and_verify EXIT

bash "${SCRIPT_DIR}/fresh_start_stack.sh"

cd "${CORE_MATRIX_ROOT}"
CAPSTONE_SKIP_BACKEND_RESET=true \
CAPSTONE_HOST_PREVIEW_PORT="${CAPSTONE_HOST_PREVIEW_PORT:-4274}" \
bin/rails runner "${REPO_ROOT}/verification/scenarios/proof/fenix_capstone_app_api_roundtrip_validation.rb"
