#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# 02-backup.sh - backup configuration files for rollback
# Expects config/env.sh to define array:
# CONFIG_FILES
# Respects DRY_RUN variable if present.


# Provide minimal logging helpers if not provided by caller
if ! declare -f info >/dev/null 2>&1; then
    info()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[INFO] $*"; }
    warn()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[WARN] ⚠️ $*"; }
    die()   { printf '%s %s\n' "$(date --iso-8601=seconds)" "[ERROR] ❌ $*"; exit 1; }
fi

# Ensure run as root (safe guard if run standalone)
if [ "$(id -u)" -ne 0 ]; then
    die "01-software.sh must be run as root."
fi

# Ensure env is loaded (install.sh should have already sourced it, but be robust)
ENV_FILE="${ENV_FILE:-./config/env.sh}"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
else
    die "Environment file not found: ${ENV_FILE}"
fi

backup_dir="/var/backups/server-rollback/configs_${TODAY}"
mkdir -p "$backup_dir"

info "Creating configuration backups in $backup_dir ..."

for file in "${CONFIG_FILES[@]}"; do
    if [[ -e "$file" ]]; then
        dest="$backup_dir/$(basename "$file")"

        # If it's a directory, create a tar archive
        if [[ -d "$file" ]]; then
            tar -czf "${dest}.tar.gz" -C "$(dirname "$file")" "$(basename "$file")"
            info "✓ Archived directory: $file"
        else
            cp -a "$file" "$dest"
            info "✓ Backed up file: $file"
        fi
    else
        warn "Skipped (not found): $file"
    fi
done

info "Backup completed successfully."
