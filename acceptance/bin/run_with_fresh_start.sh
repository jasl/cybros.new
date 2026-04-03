#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"

TARGET_SCRIPT="${1:-acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb}"
shift || true

if [[ "${TARGET_SCRIPT}" == "acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb" ]]; then
  export FENIX_RUNTIME_MODE="${FENIX_RUNTIME_MODE:-docker}"
  exec bash "${SCRIPT_DIR}/fenix_capstone_app_api_roundtrip_validation.sh" "$@"
fi

"${SCRIPT_DIR}/fresh_start_stack.sh"

if [[ "${TARGET_SCRIPT}" = /* ]]; then
  TARGET_PATH="${TARGET_SCRIPT}"
else
  TARGET_PATH="${REPO_ROOT}/${TARGET_SCRIPT}"
fi

cd "${CORE_MATRIX_ROOT}"
bin/rails runner "${TARGET_PATH}" "$@"
