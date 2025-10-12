#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Installer variables and defaults
# -----------------------------------------------------------------------------
ONLY_PRECHECK=false
ONLY_APACHE=false
ONLY_PHP=false
ONLY_BACKUP=false
ONLY_SOFTWARE=false
ONLY_CONFIG=false
ONLY_USERS=false
ONLY_DATABASE=false
ONLY_EMAIL=false
ONLY_SSL=false
ONLY_FIREWALL=false
ONLY_SECURITY=false
ONLY_NETWORK=false

# -----------------------------------------------------------------------------
# Master installer for server/ repo
# -----------------------------------------------------------------------------

# Defaults
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOGFILE="${WORKDIR}/tmp/server-setup.log"
SCRIPTS_DIR="${WORKDIR}/modules"
ENV_FILE="${WORKDIR}/config/env.sh"
DRY_RUN=false
VERBOSE=false
SKIP_CONFIRM=false
SELECT=()   # modules to run (script basenames without extension)
RUN_ALL=true

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
chmod 777 "$LOGFILE"
chown "$(whoami)":"$(id -gn $(whoami))" "$LOGFILE"

# Redirect stdout and stderr to log file, while still printing to console
exec > >(tee -a "$LOGFILE") 2>&1

log()   { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*" ; }
info()  { log "[INFO] $*" ; }
warn()  { log "[WARN] ⚠️  $*" ; }
err()   { log "[ERROR] ❌ $*" ; }
die()   { err "$*"; exit 1 ; }

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
run() {
    if $DRY_RUN; then
        info "[DRY-RUN] $*"
    else
        if $VERBOSE; then
            info "[RUN] $*"
            bash -c "$*"
        else
            bash -c "$*" >/dev/null
        fi
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        die "This script must be run as root (use: sudo ./install.sh)"
    fi
}

confirm() {
    $SKIP_CONFIRM || $DRY_RUN && return 0
    read -r -p "$1 [y/N]: " REPLY
    case "$REPLY" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

load_env() {
    echo "Loading env: $ENV_FILE"
    [[ -f "$ENV_FILE" ]] || die "Environment file not found: $ENV_FILE"

    # shellcheck disable=SC1090
    source "$ENV_FILE"

    # Debug print for testing
    echo
    echo "[DEBUG] Loaded vars:"
    echo "  TODAY=${TODAY:-<unset>}"
    echo "  PASSWORD=${PASSWORD:-<unset>}"
    echo "  EMAIL_ADDR=${EMAIL_ADDR:-<unset>}"
    echo

#    REQUIRED_VARS=(USER GROUP HOME_DIR)
    for var in "${REQUIRED_VARS[@]}"; do
        [[ -z "${!var:-}" ]] && die "Missing required env variable: $var"
    done
    info "Environment loaded successfully from ${ENV_FILE}"
}


discover_scripts() {
    mapfile -t ALL_SCRIPTS < <(find "$SCRIPTS_DIR" -maxdepth 1 -type f -name '[0-9][0-9]*-*.sh' | sort)
    SCRIPTS=()
    for s in "${ALL_SCRIPTS[@]}"; do
        SCRIPTS+=("$(basename "$s")")
    done
}

run_script() {
    local script_path="$1"
    local script_name
    script_name="$(basename "$script_path")"
    info "==== Running ${script_name} ===="

    $DRY_RUN && { info "[DRY-RUN] would execute: $script_path"; return 0; }

    chmod +x "$script_path"

    # Source env AND module in the current shell
    # shellcheck disable=SC1090
    if ! source "$ENV_FILE" || ! source "$script_path"; then
        err "Script failed: $script_name"

        local rollback="${SCRIPTS_DIR}/${script_name%.sh}.rollback.sh"
        if [[ -x "$rollback" ]]; then
            warn "Attempting rollback via $rollback"
            set +e
            # shellcheck disable=SC1090
            source "$rollback" || warn "Rollback failed"
            set -e
        fi
        die "Aborting due to failure in $script_name"
    fi

    info "==== Completed ${script_name} ===="
}

usage() {
    cat <<EOF
Usage: $0 [options] [modules...]
Options:
  --dry-run         Show actions without making changes
  --yes             Skip confirmation prompts
  --verbose         Show command output
  --help            Show this help

  --apache          Setup only apache module
  --php             Setup only php module
  --backup          Create backup before changes
  --software        Install only software packages
  --config          Setup only configuration files
  --users           Setup only users and permissions
  --database        Setup only databases
  --email           Setup only email server
  --ssl             Setup only SSL certificates
  --firewall        Setup only firewall
  --security        Setup only security(file and directory permissions, sysctl hardening)
  --network         Setup only network
  --all             (default) run all modules in order
Modules (optional): script basenames without .sh
EOF
}

# -----------------------------------------------------------------------------
# Parse CLI args
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --yes) SKIP_CONFIRM=true ;;
    	--precheck) ONLY_PRECHECK=true; RUN_ALL=false; SELECT+=("precheck") ;;
    	--apache) ONLY_APACHE=true; RUN_ALL=false; SELECT+=("apache") ;;
    	--php) ONLY_PHP=true; RUN_ALL=false; SELECT+=("php") ;;
    	--backup) ONLY_BACKUP=true; RUN_ALL=false; SELECT+=("backup") ;;
    	--software) ONLY_SOFTWARE=true; RUN_ALL=false; SELECT+=("software") ;;
		--config) ONLY_CONFIG=true; RUN_ALL=false; SELECT+=("config") ;;
		--users) ONLY_USERS=true; RUN_ALL=false; SELECT+=("users") ;;
		--database) ONLY_DATABASE=true; RUN_ALL=false; SELECT+=("database") ;;
		--email) ONLY_EMAIL=true; RUN_ALL=false; SELECT+=("email") ;;
		--ssl) ONLY_SSL=true; RUN_ALL=false; SELECT+=("ssl") ;;
		--firewall) ONLY_FIREWALL=true; RUN_ALL=false; SELECT+=("firewall") ;;
		--security) ONLY_SECURITY=true; RUN_ALL=false; SELECT+=("security") ;;
		--network) ONLY_NETWORK=true; RUN_ALL=false; SELECT+=("network") ;;
		--all) RUN_ALL=true ;;
        --verbose) VERBOSE=true ;;
        --help) usage; exit 0 ;;
        --) shift; break ;;
        -*) die "Unknown option: $1" ;;
        *) SELECT+=("$1"); RUN_ALL=false ;;
    esac
    shift
done

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
require_root
load_env
discover_scripts

# Filter scripts if user selected specific modules
if ! $RUN_ALL; then
    FILTERED=()
    for want in "${SELECT[@]}"; do
        match=$(printf "%s\n" "${SCRIPTS[@]}" | awk -F. -v w="$want" '{n=$1; sub(/^[0-9]+-/, "", n); if(n==w || $1==w) print $0}')
        [[ -z "$match" ]] && die "Module not found: $want"
        while read -r m; do FILTERED+=("$m"); done <<< "$match"
    done
    SCRIPTS=("${FILTERED[@]}")
fi

info "Scripts to run:"
for s in "${SCRIPTS[@]}"; do info " - $s"; done
confirm "Proceed?" || die "User aborted"

for s in "${SCRIPTS[@]}"; do
    run_script "${SCRIPTS_DIR}/${s}"
done

# Finalize
info "Running post-install tasks..."
$DRY_RUN || systemctl daemon-reload || warn "systemctl daemon-reload failed"

info "✅ Installation finished successfully."
warn "Delete the log file if everything is OK."
info "Log file: $LOGFILE"
