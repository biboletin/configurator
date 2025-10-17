#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# 01-software.sh - idempotent install of packages from env arrays
# Expects config/env.sh to define arrays:
# TOOLS WEB DATABASES SECURITY EMAIL SSL FIREWALL EXTRAS etc.
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

# Backup dir for rollback
BACKUP_DIR="${BACKUP_DIR:-/var/backups/server-rollback/software}"
mkdir -p "$BACKUP_DIR"
INSTALLED_LIST="${BACKUP_DIR}/installed.packages"

# Aggregate desired packages from arrays. Use bash associative to dedupe (works in bash 4+)
declare -A pkgs_map
add_array() {
    local -n arr="$1"
    for p in "${arr[@]:-}"; do
        # skip empty strings
        [[ -n "${p// /}" ]] || continue
        pkgs_map["$p"]=1
    done
}

# Add arrays if defined
add_array TOOLS      2>/dev/null || true
add_array WEB        2>/dev/null || true
add_array DATABASES  2>/dev/null || true
add_array SECURITY   2>/dev/null || true
add_array EMAIL      2>/dev/null || true
add_array SSL        2>/dev/null || true
add_array FIREWALL   2>/dev/null || true
add_array EXTRAS     2>/dev/null || true

# Build package list
ALL_PKGS=()
for k in "${!pkgs_map[@]}"; do
    ALL_PKGS+=("$k")
done

if [[ ${#ALL_PKGS[@]} -eq 0 ]]; then
    info "No packages configured to install. Exiting."
    exit 0
fi

# Determine which packages are missing (not installed)
MISSING=()
ALREADY_PRESENT=()
for pkg in "${ALL_PKGS[@]}"; do
    # dpkg-query returns non-zero if not installed
    if dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "install ok installed"; then
        ALREADY_PRESENT+=("$pkg")
    else
        MISSING+=("$pkg")
    fi
done

info "Packages already installed: ${#ALREADY_PRESENT[@]}"
info "Packages to install: ${#MISSING[@]}"

if [[ ${#MISSING[@]} -eq 0 ]]; then
    info "All packages already present — nothing to do."
    exit 0
fi

# Respect dry-run
DRY_RUN=${DRY_RUN:-false}
if $DRY_RUN; then
    info "[DRY-RUN] Would install: ${MISSING[*]}"
    exit 0
fi

# Update apt once
info "Running apt-get update..."
apt-get update -y

# Install missing packages
info "Installing packages: ${MISSING[*]}"
apt-get install "${MISSING[@]}" -y

# Save the list of packages this run installed (for rollback)
printf "%s\n" "${MISSING[@]}" > "${INSTALLED_LIST}"
chmod 600 "${INSTALLED_LIST}"
info "Installed packages recorded to ${INSTALLED_LIST}"

# optional: apt-get autoremove or clean (not removing by default)
 apt-get autoremove -y

info "01-software.sh: completed successfully."
