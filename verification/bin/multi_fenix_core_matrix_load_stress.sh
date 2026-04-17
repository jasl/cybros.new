#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MULTI_FENIX_LOAD_PROFILE="${MULTI_FENIX_LOAD_PROFILE:-stress}"

export MULTI_FENIX_LOAD_PROFILE

exec bash "${SCRIPT_DIR}/run_multi_fenix_core_matrix_load.sh" "$@"
