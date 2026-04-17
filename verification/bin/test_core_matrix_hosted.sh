#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

cd "${REPO_ROOT}/core_matrix"
bin/rails db:test:prepare
bundle exec ruby ../verification/test/core_matrix_hosted_runner.rb
