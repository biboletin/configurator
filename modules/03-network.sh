#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# 03-network.sh - atomic iptables rules builder + install
# - Builds a canonical iptables-restore file and applies it atomically
# - Backs up existing rules to /var/backups/iptables/
# - Respects DRY_RUN variable if set
# - Must run as root

# Minimal logging helpers if not provided
if ! declare -f info >/dev/null 2>&1; then
    info()  { printf '%s [INFO] %s\n'  "$(date --iso-8601=seconds)" "$*"; }
    warn()  { printf '%s [WARN] ⚠️ %s\n'  "$(date --iso-8601=seconds)" "$*"; }
    err()   { printf '%s [ERROR] ❌ %s\n' "$(date --iso-8601=seconds)" "$*"; }
    die()   { err "$*"; exit 1; }
fi

# Ensure root
if [ "$(id -u)" -ne 0 ]; then
    die "03-network.sh must be run as root."
fi

# Load env if not already loaded
ENV_FILE="${ENV_FILE:-./config/env.sh}"
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
else
    warn "Environment file ${ENV_FILE} not found. Proceeding if variables are set in environment."
fi

# Respect DRY_RUN if exported; default false
DRY_RUN=${DRY_RUN:-false}

# Required variables - fail if missing
: "${MAIN_NETWORK_INTERFACE:?MAIN_NETWORK_INTERFACE is required (set in env.sh)}"
: "${LOOPBACK:-lo}"
: "${SSH:-22}"
: "${HTTP:-80}"
: "${HTTPS:-443}"
TODAY=${TODAY:-$(date +%F)}
BACKUP_DIR="/var/backups/iptables"
mkdir -p "$BACKUP_DIR"

CLOUDFLARE_IP_LIST="${CLOUDFLARE_IP_LIST:-$HOME/Documents/cloudflare-ips.txt}"
IS_ROUTER="${IS_ROUTER:-false}"
SECOND_NETWORK_INTERFACE="${SECOND_NETWORK_INTERFACE:-}"

# safe default for SERVER_IP
SERVER_IP="${SERVER_IP:-127.0.0.1}"
EXTERNAL_IP="${EXTERNAL_IP:-}"

# helper wrapper to run or echo commands
run() {
    if $DRY_RUN; then
        info "[DRY-RUN] $*"
    else
        bash -c "$*"
    fi
}

# backup current rules (iptable-save)
backup_rules() {
    timestamp=$(date +%Y%m%d_%H%M%S)
    mkdir -p "$BACKUP_DIR"
    info "Backing up current iptables to ${BACKUP_DIR}/rules.v4.${timestamp}.bak"
    if $DRY_RUN; then
        info "[DRY-RUN] iptables-save > ${BACKUP_DIR}/rules.v4.${timestamp}.bak"
    else
        iptables-save > "${BACKUP_DIR}/rules.v4.${timestamp}.bak"
    fi
}

# Build iptables-restore style rules file in a temp file
build_rules_file() {
    TMP_RULES="$(mktemp)"
    cat > "$TMP_RULES" <<EOF
*filter
:INPUT DROP [0:0]
:FORWARD DROP [0:0]
:OUTPUT DROP [0:0]
:LOGGING - [0:0]
:PORTSCAN - [0:0]
EOF

    # Always accept loopback and established connections
    cat >> "$TMP_RULES" <<'EOF'
# Allow loopback
-A INPUT -i lo -j ACCEPT
-A OUTPUT -o lo -j ACCEPT

# Allow established/related
-A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
-A OUTPUT -m conntrack --ctstate ESTABLISHED -j ACCEPT
EOF

    # Always keep SSH accessible — allow new connections to SSH on MAIN_INTERFACE
    cat >> "$TMP_RULES" <<EOF
# Allow SSH (new+established)
-A INPUT -i ${MAIN_NETWORK_INTERFACE} -p tcp -m tcp --dport ${SSH} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
-A OUTPUT -o ${MAIN_NETWORK_INTERFACE} -p tcp -m tcp --sport ${SSH} -m conntrack --ctstate ESTABLISHED -j ACCEPT
EOF

    # Allow HTTP/HTTPS
    cat >> "$TMP_RULES" <<EOF
# Allow HTTP/HTTPS
-A INPUT -i ${MAIN_NETWORK_INTERFACE} -p tcp -m multiport --dports ${HTTP},${HTTPS} -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
-A OUTPUT -o ${MAIN_NETWORK_INTERFACE} -p tcp -m multiport --sports ${HTTP},${HTTPS} -m conntrack --ctstate ESTABLISHED -j ACCEPT
EOF

    # Allow time sync (NTP)
    cat >> "$TMP_RULES" <<EOF
# Time sync (NTP)
-A OUTPUT -o ${MAIN_NETWORK_INTERFACE} -p udp --dport 123 -m conntrack --ctstate NEW -j ACCEPT
-A INPUT -i ${MAIN_NETWORK_INTERFACE} -p udp --sport 123 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
EOF

    # ICMP: allow ping but rate-limit
    cat >> "$TMP_RULES" <<'EOF'
# ICMP rate-limited
-A INPUT -p icmp -m limit --limit 1/second --limit-burst 5 -j ACCEPT
EOF

    # Basic protections (invalid packets)
    cat >> "$TMP_RULES" <<'EOF'
# Drop invalid and malformed packets
-A INPUT -m conntrack --ctstate INVALID -j LOG --log-prefix "INVALID_PKT: " --log-level 4
-A INPUT -m conntrack --ctstate INVALID -j DROP
EOF

    # SYN flood mitigation + connlimit for HTTP/HTTPS (configurable)
    cat >> "$TMP_RULES" <<EOF
# SYN flood / connlimit protections
-A INPUT -p tcp --syn -m multiport --dports ${HTTP},${HTTPS} -m connlimit --connlimit-above 50 --connlimit-mask 32 -j REJECT --reject-with tcp-reset
-A INPUT -p tcp --syn -m connlimit --connlimit-above 20 --dports ${HTTP},${HTTPS} -j REJECT --reject-with tcp-reset
EOF

    # Portscan detection chain
    cat >> "$TMP_RULES" <<'EOF'
# PORTSCAN chain rules
-A PORTSCAN -m recent --name portscan --set -j LOG --log-prefix "PORTSCAN: " --log-level 4
-A PORTSCAN -j DROP
# Common scan patterns sent to PORTSCAN
-A INPUT -p tcp --tcp-flags ALL NONE -j PORTSCAN
-A INPUT -p tcp --tcp-flags ALL ALL -j PORTSCAN
-A INPUT -p tcp --tcp-flags SYN,RST SYN,RST -j PORTSCAN
-A INPUT -p tcp --tcp-flags SYN,FIN SYN,FIN -j PORTSCAN
-A INPUT -p tcp --tcp-flags FIN FIN -j PORTSCAN
-A INPUT -p tcp --tcp-flags ACK,FIN FIN -j PORTSCAN
-A INPUT -p tcp --tcp-flags ACK,PSH PSH -j PORTSCAN
-A INPUT -p tcp --tcp-flags ACK,URG URG -j PORTSCAN
EOF

    # Custom Cloudflare whitelist - if file exists
    if [[ -f "${CLOUDFLARE_IP_LIST}" ]]; then
        while IFS= read -r ip || [[ -n "$ip" ]]; do
            ip=$(echo "$ip" | tr -d '\r\n' | sed -e 's/#.*//;s/^[[:space:]]*//;s/[[:space:]]*$//')
            [[ -z "$ip" ]] && continue
            cat >> "$TMP_RULES" <<EOF
# Allow via Cloudflare
-A INPUT -p tcp -s ${ip} -m multiport --dports ${HTTP},${HTTPS} -j ACCEPT
EOF
        done < "$CLOUDFLARE_IP_LIST"
    else
        info "Cloudflare IP list not found at ${CLOUDFLARE_IP_LIST}, skipping CF whitelist"
    fi

    # Optional router NAT / forwarding rules (if IS_ROUTER)
    if [[ "${IS_ROUTER}" == "true" && -n "${SECOND_NETWORK_INTERFACE}" ]]; then
        cat >> "$TMP_RULES" <<EOF
# NAT / forwarding for router mode
-A FORWARD -i ${SECOND_NETWORK_INTERFACE} -o ${MAIN_NETWORK_INTERFACE} -m conntrack --ctstate NEW,RELATED,ESTABLISHED -j ACCEPT
-A FORWARD -i ${MAIN_NETWORK_INTERFACE} -o ${SECOND_NETWORK_INTERFACE} -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
EOF
    fi

    # Prevent spoofing: drop bogon/private ranges on INPUT except loopback and allowed internal
    spoofing=(
        "10.0.0.0/8"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "127.0.0.0/8"
        "192.0.2.0/24"
        "192.168.0.0/16"
        "224.0.0.0/4"
        "240.0.0.0/5"
        "0.0.0.0/8"
    )
    for r in "${spoofing[@]}"; do
        echo "-A INPUT -s ${r} -j DROP" >> "$TMP_RULES"
    done

    # Final logging and drop rules
    cat >> "$TMP_RULES" <<'EOF'
# Log and drop at end
-A INPUT -j LOGGING
-A LOGGING -m limit --limit 3/min -j LOG --log-prefix "DROP: " --log-level 4
-A LOGGING -j DROP
COMMIT
EOF

    echo "$TMP_RULES"
}

# Apply rules atomically using iptables-restore
apply_rules() {
    TMP_RULES_FILE="$1"
    if $DRY_RUN; then
        info "[DRY-RUN] Would apply rules with iptables-restore from $TMP_RULES_FILE"
        sed -n '1,200p' "$TMP_RULES_FILE" | sed -n '1,200p'  # show head as confirmation
    else
        info "Applying new rules with iptables-restore (atomic apply)"
        # Use iptables-restore to replace the ruleset
        iptables-restore < "$TMP_RULES_FILE"
    fi
}

# Save rules to persistent file for iptables-persistent
save_persistent() {
    if $DRY_RUN; then
        info "[DRY-RUN] Would save rules to /etc/iptables/rules.v4"
    else
        iptables-save > /etc/iptables/rules.v4
        info "Saved rules to /etc/iptables/rules.v4"
    fi
}

# MAIN EXECUTION FLOW
info "03-network.sh starting (DRY_RUN=${DRY_RUN})"
backup_rules

TMP="$(build_rules_file)"
# build_rules_file prints temp filename; we created TMP_RULES via mktemp inside function; capture its path
# but above function returned path via echo, so TMP contains the temp file path
TMP_FILE="$TMP"

# Offer a safety pause if not dry-run (optional)
if ! $DRY_RUN; then
    info "Applying firewall rules will replace the current ruleset. This may impact connectivity."
    sleep 1
fi

apply_rules "$TMP_FILE"

# Persist for iptables-persistent if available
save_persistent

# Cleanup temp
if [[ -f "$TMP_FILE" ]]; then
    rm -f "$TMP_FILE"
fi

info "03-network.sh completed successfully."
