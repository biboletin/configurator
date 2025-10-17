#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# --- Logging helpers ---
if ! declare -f info >/dev/null 2>&1; then
    info()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[INFO] $*"; }
    warn()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[WARN] ⚠️ $*"; }
    die()   { printf '%s %s\n' "$(date --iso-8601=seconds)" "[ERROR] ❌ $*"; exit 1; }
fi

# --- Root check ---
if [[ "$(id -u)" -ne 0 ]]; then
    die "Must be run as root."
fi

# --- Environment ---
ENV_FILE="${ENV_FILE:-./config/env.sh}"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    . "$ENV_FILE"
else
    warn "Environment file not found: ${ENV_FILE}"
fi

# --- Config ---
SSHD_CONFIG="${SSHD_CONFIG:-/etc/ssh/sshd_config}"
BACKUP_FILE="${SSHD_CONFIG}.bak.$(date +%s)"
cp "$SSHD_CONFIG" "$BACKUP_FILE" && info "Backup saved: $BACKUP_FILE"

# --- Helper to set/update key=value ---
set_sshd_config_var() {
    local key="$1"
    local value="$2"
    local file="$SSHD_CONFIG"

    [[ -f "$file" ]] || { warn "$file not found"; return; }

    if grep -qE "^[#\s]*${key}\b" "$file"; then
        info "Updating ${key} → ${value}"
        sed -i "s|^[#\s]*${key}\b.*|${key} ${value}|" "$file"
    else
        info "Adding ${key} ${value}"
        echo "${key} ${value}" >> "$file"
    fi
}

# --- SSH Hardening ---
info "Hardening SSH configuration in ${SSHD_CONFIG}..."

set_sshd_config_var "Port" "${SSH_PORT:-22}"
set_sshd_config_var "Protocol" "2"
#set_sshd_config_var "ListenAddress" "0.0.0.0"
#set_sshd_config_var "ListenAddress" "::"

set_sshd_config_var "LoginGraceTime" "30s"
set_sshd_config_var "MaxSessions" "5"

set_sshd_config_var "PermitRootLogin" "no"
set_sshd_config_var "PasswordAuthentication" "no"
set_sshd_config_var "PubkeyAuthentication" "yes"
set_sshd_config_var "ChallengeResponseAuthentication" "no"
set_sshd_config_var "UsePAM" "yes"
set_sshd_config_var "X11Forwarding" "no"

set_sshd_config_var "HostbasedAuthentication" "no"
set_sshd_config_var "IgnoreRhosts" "yes"
set_sshd_config_var "PermitEmptyPasswords" "no"
set_sshd_config_var "AllowAgentForwarding" "no"
set_sshd_config_var "PrintMotd" "no"
set_sshd_config_var "TCPKeepAlive" "yes"
set_sshd_config_var "Compression" "delayed"
set_sshd_config_var "Banner" "/etc/issue.net"

set_sshd_config_var "AllowTcpForwarding" "no"
set_sshd_config_var "MaxAuthTries" "3"
set_sshd_config_var "ClientAliveInterval" "300"
set_sshd_config_var "ClientAliveCountMax" "0"
set_sshd_config_var "LogLevel" "VERBOSE"
set_sshd_config_var "Ciphers" "aes256-ctr,aes192-ctr,aes128-ctr"
set_sshd_config_var "MACs" "hmac-sha2-256,hmac-sha2-512"
set_sshd_config_var "KexAlgorithms" "curve25519-sha256@libssh.org,diffie-hellman-group-exchange-sha256"

set_sshd_config_var "AllowUsers" "${SSH_ALLOW_USERS:-bibo}"
set_sshd_config_var "AllowGroups" "${SSH_ALLOW_GROUPS:-bibo}"

# --- Validate & Reload ---
if sshd -t -f "$SSHD_CONFIG"; then
    info "sshd_config syntax OK ✅"
    systemctl reload sshd
else
    warn "Invalid SSH config. Restoring backup..."
    cp "$BACKUP_FILE" "$SSHD_CONFIG"
    die "sshd_config validation failed."
fi
