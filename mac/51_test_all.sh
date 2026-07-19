#!/usr/bin/env bash
# 51_test_all.sh — Run every completed desktop subsystem regression bar (NNN_test_dN.sh) in order.
# New NNN_test_dN.sh scripts are picked up automatically. Band 51-99 = all-inclusive test orchestrators.
set -euo pipefail

# Resolve mac/ before _env.sh cds to the repo root.
MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_env.sh
source "${MAC_DIR}/_env.sh"

# Three-digit subsystem bars only (101+) — excludes this 51_test_all.sh orchestrator.
shopt -s nullglob
bars=( "${MAC_DIR}"/[0-9][0-9][0-9]_test_d*.sh )
if [[ ${#bars[@]} -eq 0 ]]; then
  echo "error: no NNN_test_dN.sh scripts found in ${MAC_DIR}" >&2
  exit 1
fi

# Lexicographic sort (106 before 107 before …).
IFS=$'\n' bars_sorted=( $(printf '%s\n' "${bars[@]}" | sort) )
unset IFS

echo "==> all desktop subsystem regressions (${#bars_sorted[@]} bar(s))"
for bar in "${bars_sorted[@]}"; do
  name="$(basename "${bar}")"
  echo ""
  echo "==> ${name}"
  "${bar}"
done

echo ""
echo "==> all desktop subsystem regressions complete"
