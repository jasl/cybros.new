#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"
CORE_MATRIX_ROOT="${REPO_ROOT}/core_matrix"
DEFAULT_ARTIFACT_STAMP="$(date '+%Y-%m-%d-%H%M%S')-core-matrix-loop-fenix-2048-final"
ARTIFACT_STAMP="${CAPSTONE_ARTIFACT_STAMP:-${DEFAULT_ARTIFACT_STAMP}}"
ARTIFACT_DIR="${REPO_ROOT}/acceptance/artifacts/${ARTIFACT_STAMP}"
BOOTSTRAP_STATE_PATH="${CAPSTONE_BOOTSTRAP_STATE_PATH:-${ARTIFACT_DIR}/evidence/capstone-runtime-bootstrap.json}"
RUNTIME_WORKER_BOOT_PATH="${CAPSTONE_RUNTIME_WORKER_BOOT_PATH:-${ARTIFACT_DIR}/evidence/docker-runtime-worker.json}"

export FENIX_RUNTIME_MODE="${FENIX_RUNTIME_MODE:-docker}"
export CAPSTONE_ARTIFACT_STAMP="${ARTIFACT_STAMP}"
export CAPSTONE_BOOTSTRAP_STATE_PATH="${BOOTSTRAP_STATE_PATH}"
export CAPSTONE_RUNTIME_WORKER_BOOT_PATH="${RUNTIME_WORKER_BOOT_PATH}"

bash "${SCRIPT_DIR}/fresh_start_stack.sh"

cd "${CORE_MATRIX_ROOT}"
CAPSTONE_PHASE=bootstrap \
CAPSTONE_SKIP_BACKEND_RESET=true \
bin/rails runner "${REPO_ROOT}/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb"

machine_credential="$(
  ruby -rjson -e 'state = JSON.parse(File.read(ARGV[0])); puts state.fetch("machine_credential")' \
    "${BOOTSTRAP_STATE_PATH}"
)"
execution_machine_credential="$(
  ruby -rjson -e 'state = JSON.parse(File.read(ARGV[0])); puts state.fetch("execution_machine_credential")' \
    "${BOOTSTRAP_STATE_PATH}"
)"

FENIX_MACHINE_CREDENTIAL="${machine_credential}" \
FENIX_EXECUTION_MACHINE_CREDENTIAL="${execution_machine_credential}" \
CAPSTONE_RUNTIME_WORKER_BOOT_PATH="${RUNTIME_WORKER_BOOT_PATH}" \
bash "${SCRIPT_DIR}/activate_fenix_docker_runtime.sh"

CAPSTONE_PHASE=execute bin/rails runner "${REPO_ROOT}/acceptance/scenarios/fenix_capstone_app_api_roundtrip_validation.rb"
