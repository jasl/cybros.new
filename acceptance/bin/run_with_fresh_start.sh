#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"

TARGET_SCRIPT="${1:-acceptance/scenarios/provider_backed_turn_validation.rb}"
shift || true

"${SCRIPT_DIR}/fresh_start_stack.sh"

if [[ "${TARGET_SCRIPT}" = /* ]]; then
  TARGET_PATH="${TARGET_SCRIPT}"
else
  TARGET_PATH="${REPO_ROOT}/${TARGET_SCRIPT}"
fi

cd "${CORE_MATRIX_ROOT}"
export ACCEPTANCE_SKIP_BACKEND_RESET=true
bin/rails runner "${TARGET_PATH}" "$@"
