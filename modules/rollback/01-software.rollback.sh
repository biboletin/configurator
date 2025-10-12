#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Rollback for 01-software.sh
# Removes only packages listed in /var/backups/server-rollback/software/installed.packages
# Use with caution on production systems.

# Provide minimal logging helpers if not provided by caller
if ! declare -f info >/dev/null 2>&1; then
    info()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[INFO] $*"; }
    warn()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[WARN] $*"; }
    die()   { printf '%s %s\n' "$(date --iso-8601=seconds)" "[ERROR] ❌ $*"; exit 1; }
fi

if [ "$(id -u)" -ne 0 ]; then
    die "Rollback must be run as root."
fi

BACKUP_DIR="${BACKUP_DIR:-/var/backups/server-rollback/software}"
INSTALLED_LIST="${BACKUP_DIR}/installed.packages"

if [[ ! -f "$INSTALLED_LIST" ]]; then
    info "No installed.packages file found at $INSTALLED_LIST. Nothing to rollback."
    exit 0
fi

mapfile -t TO_REMOVE < "$INSTALLED_LIST"
if [[ ${#TO_REMOVE[@]} -eq 0 ]]; then
    info "installed.packages is empty. Nothing to do."
    exit 0
fi

info "Packages recorded as installed by 01-software (will be removed): ${TO_REMOVE[*]}"

read -r -p "Proceed to remove these packages? [y/N]: " REPLY
case "$REPLY" in
    [yY][eE][sS]|[yY]) ;;
    *) info "Aborting rollback."; exit 0 ;;
esac

# Remove packages (purge)
apt-get remove --purge -y "${TO_REMOVE[@]}" || warn "apt-get remove returned non-zero"
apt-get autoremove -y || warn "apt-get autoremove returned non-zero"
apt-get clean -y || true

# Cleanup the recorded file
rm -f "$INSTALLED_LIST"
info "Rollback completed. ${INSTALLED_LIST} removed."
