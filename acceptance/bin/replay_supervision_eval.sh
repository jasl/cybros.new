#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUNDLE_PATH="${1:?usage: replay_supervision_eval.sh /absolute/path/to/review/supervision-eval-bundle.json}"

cd "${REPO_ROOT}/core_matrix"

bin/rails runner "require Rails.root.join('../acceptance/lib/supervision_eval_replay'); Acceptance::SupervisionEvalReplay.run!(bundle_path: ARGV.fetch(0))" "${BUNDLE_PATH}"
