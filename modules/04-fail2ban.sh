#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

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
# Ensure Fail2Ban is installed
if ! command -v fail2ban-server >/dev/null 2>&1; then
	die "Fail2Ban is not installed. Please run the software installation module first."
fi


configure "Fail2Ban configuration"

# Paths
JAIL_CONF="/etc/fail2ban/jail.conf"
JAIL_LOCAL="/etc/fail2ban/jail.local"
JAIL_D_DIR="/etc/fail2ban/jail.d"

mkdir -p "$JAIL_D_DIR"

# --- Backup originals (idempotent) ---
backup_file() {
    local file="$1"
    [[ -f "$file" ]] || return
    [[ -f "${file}.bak" ]] && return
    info "Backing up $file -> ${file}.bak"
    $DRY_RUN || cp "$file" "${file}.bak"
}

backup_file "$JAIL_CONF"
backup_file "$JAIL_LOCAL"

# --- Helper to set or append key=value in jail.local ---
set_jail_local_var() {
    local key="$1"
    local value="$2"

    if grep -qE "^\s*#?\s*${key}\s*=" "$JAIL_LOCAL"; then
        info "Updating $key in jail.local"
        $DRY_RUN || sed -i "s|^\s*#\?\s*${key}\s*=.*|${key} = ${value}|" "$JAIL_LOCAL"
    else
        info "Adding $key to jail.local"
        $DRY_RUN || echo "${key} = ${value}" >> "$JAIL_LOCAL"
    fi
}

# --- Global Fail2Ban settings ---
set_jail_local_var "ignoreip" "127.0.0.1/8 ::1 ${INTERNAL_NETWORK} ${EXTERNAL_IP}"
set_jail_local_var "bantime" "-1"
set_jail_local_var "findtime" "10m"
set_jail_local_var "maxretry" "3"
set_jail_local_var "dbfile" "/var/lib/fail2ban/fail2ban.sqlite3"
set_jail_local_var "dbpurgeage" "86400"

# --- Jails definition ---
# Each element: filename|content
declare -a JAILS=(
"sshd.conf|[sshd]
enabled = true
port    = ${SSH}
logpath = %(sshd_log)s
backend = %(sshd_backend)s"

"apache.conf|[apache-auth]
enabled = true
port    = http,https
logpath = %(apache_error_log)s

[apache-badbots]
enabled  = true
port     = http,https
logpath  = %(apache_access_log)s
bantime  = 48h
maxretry = 1

[apache-noscript]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s

[apache-overflows]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-nohome]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-botsearch]
enabled  = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-fakegooglebot]
enabled  = true
port     = http,https
logpath  = %(apache_access_log)s
maxretry = 1
ignorecommand = %(ignorecommands_dir)s/apache-fakegooglebot <ip>

[apache-modsecurity]
enabled = true
port     = http,https
logpath  = %(apache_error_log)s
maxretry = 2

[apache-shellshock]
enabled = true
port    = http,https
logpath = %(apache_error_log)s
maxretry = 1"

"php.conf|[php-url-fopen]
enabled = true
port    = http,https
logpath = %(nginx_access_log)s %(apache_access_log)s"

"apache-common.conf|#
# This supersedes the old and incorrect datepattern regex for older Apache2 instances to make
# it working against Apache 2.4+ ones.
#
# Mariusz B. / mgeeky
#

[DEFAULT]
datepattern = \[(%%d/%%b/%%Y:%%H:%%M:%%S %%z)\]"

"apache-dos.conf|#
# Fail2Ban filter to block repeated web requests ending up with 404 HTTP status.
#
# This matches classic forceful browsing attempts as well as automated crawlers.
#
# Author: Mariusz B. / mgeeky
#

[INCLUDES]
before = apache-common.conf

[Definition]
failregex = <HOST> .+\"(?:GET|POST|HEAD|PUT|DELETE).+HTTP\/\d\.\d\" (?:301|302|303|304|400|401|403|404|405|500) \d+ .+$
ignoreregex ="
)

# --- Write jail.d configs (idempotent) ---
for j in "${JAILS[@]}"; do
    file="${j%%|*}"
    content="${j#*|}"

    target="$JAIL_D_DIR/$file"

    if [[ -f "$target" ]]; then
        info "Skipping existing jail file: $file"
        continue
    fi

    info "Creating jail file: $file"
    $DRY_RUN || echo "$content" > "$target"
done
