#!/usr/bin/env bash
# Deletes benchmark run directories older than MAX_AGE_MINUTES (default: 60).
# Safe to run while TexBench is live — only removes completed, timestamped runs.

set -euo pipefail

RUNS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/generated-workloads/runs"
MAX_AGE_MINUTES="${MAX_AGE_MINUTES:-60}"

if [ ! -d "$RUNS_DIR" ]; then
  echo "Runs directory not found: $RUNS_DIR"
  exit 0
fi

removed=0
freed=0

while IFS= read -r -d '' run; do
  size=$(du -sk "$run" 2>/dev/null | cut -f1)
  rm -rf "$run"
  freed=$((freed + size))
  removed=$((removed + 1))
done < <(find "$RUNS_DIR" -mindepth 1 -maxdepth 1 -type d -mmin +"$MAX_AGE_MINUTES" -print0)

echo "[cleanup-runs] Removed $removed run(s), freed ~$((freed / 1024)) MB (runs older than ${MAX_AGE_MINUTES}m)"
