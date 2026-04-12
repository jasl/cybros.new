#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACCEPTANCE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${ACCEPTANCE_ROOT}/.." && pwd)"

ENTRYPOINTS=()
while IFS= read -r entrypoint; do
  [[ -n "${entrypoint}" ]] && ENTRYPOINTS+=("${entrypoint}")
done < <(
  ruby -I "${REPO_ROOT}" -e 'require_relative "acceptance/lib/active_suite"; puts Acceptance::ActiveSuite.entrypoints'
)

SKIPPED_OPTIONAL_ENTRYPOINTS=()
while IFS= read -r skipped_entrypoint; do
  [[ -n "${skipped_entrypoint}" ]] && SKIPPED_OPTIONAL_ENTRYPOINTS+=("${skipped_entrypoint}")
done < <(
  ruby -I "${REPO_ROOT}" -e '
    require_relative "acceptance/lib/active_suite"
    Acceptance::ActiveSuite.skipped_optional_entrypoints.each do |entry|
      puts "#{entry.fetch(:entrypoint)}|#{entry.fetch(:env_var)}|#{entry.fetch(:reason)}"
    end
  '
)

if [[ "${#ENTRYPOINTS[@]}" -eq 0 ]]; then
  echo "no active acceptance entrypoints configured" >&2
  exit 1
fi

if [[ "${#SKIPPED_OPTIONAL_ENTRYPOINTS[@]}" -gt 0 ]]; then
  printf 'skipped optional acceptance entrypoints:\n'
  for skipped_entrypoint in "${SKIPPED_OPTIONAL_ENTRYPOINTS[@]}"; do
    IFS='|' read -r entrypoint env_var reason <<<"${skipped_entrypoint}"
    printf '  %s (set %s=1 to enable; %s)\n' "${entrypoint}" "${env_var}" "${reason}"
  done
fi

failures=()

for entrypoint in "${ENTRYPOINTS[@]}"; do
  echo "==> ${entrypoint}"
  if [[ "${entrypoint}" == *.rb ]]; then
    if ! bash "${SCRIPT_DIR}/run_with_fresh_start.sh" "${entrypoint}"; then
      failures+=("${entrypoint}")
    fi
  else
    if ! bash "${REPO_ROOT}/${entrypoint}"; then
      failures+=("${entrypoint}")
    fi
  fi
done

if [[ "${#failures[@]}" -gt 0 ]]; then
  printf 'active acceptance failures:\n' >&2
  printf '  %s\n' "${failures[@]}" >&2
  exit 1
fi
