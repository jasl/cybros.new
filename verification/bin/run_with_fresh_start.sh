#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERIFICATION_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${VERIFICATION_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
source "${SCRIPT_DIR}/process_manager.sh"

TARGET_SCRIPT="${1:-verification/scenarios/e2e/provider_backed_turn_validation.rb}"
shift || true

verification_process_manager_prepare_session
trap verification_process_manager_cleanup_current_session_and_verify EXIT

"${SCRIPT_DIR}/fresh_start_stack.sh"

if [[ "${TARGET_SCRIPT}" = /* ]]; then
  TARGET_PATH="${TARGET_SCRIPT}"
else
  TARGET_PATH="${REPO_ROOT}/${TARGET_SCRIPT}"
fi

cd "${CORE_MATRIX_ROOT}"
export VERIFICATION_SKIP_BACKEND_RESET=true
bin/rails runner "${TARGET_PATH}" "$@"
