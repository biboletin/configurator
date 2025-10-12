#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROLLBACK_DIR="$(dirname "$0")/modules/rollback"
LOGFILE="./tmp/server-rollback.log"

mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1

echo "=== Starting rollback process ==="

declare -a MODULES=(
  "system"
  "network"
  "apache"
  "php"
  "mariadb"
  "services"
  "security"
  "monitoring"
)

for module in "${MODULES[@]}"; do
  SCRIPT="${ROLLBACK_DIR}/rollback-${module}.sh"
  if [[ -x "$SCRIPT" ]]; then
    echo ">>> Running rollback for $module"
    bash "$SCRIPT"
  else
    echo "[WARN] No rollback script for $module"
  fi
done

echo "=== Rollback completed ==="
