#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_MATRIX_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

TARGET_SCRIPT="${1:-script/manual/acceptance/fenix_capstone_app_api_roundtrip_validation.rb}"
shift || true

if [[ "${TARGET_SCRIPT}" == "script/manual/acceptance/fenix_capstone_app_api_roundtrip_validation.rb" ]]; then
  export FENIX_RUNTIME_MODE="${FENIX_RUNTIME_MODE:-docker}"
  exec bash "${SCRIPT_DIR}/fenix_capstone_app_api_roundtrip_validation.sh" "$@"
fi

"${SCRIPT_DIR}/fresh_start_stack.sh"

cd "${CORE_MATRIX_ROOT}"
bin/rails runner "${TARGET_SCRIPT}" "$@"
