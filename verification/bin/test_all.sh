#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

bash "${SCRIPT_DIR}/test_pure.sh"
bash "${SCRIPT_DIR}/test_core_matrix_hosted.sh"
