#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "Check for internet connection ..."

# --- Minimal logging helpers ---
info()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[INFO] $*"; }
warn()  { printf '%s %s\n' "$(date --iso-8601=seconds)" "[WARN] ⚠️ $*"; }
err()   { printf '%s %s\n' "$(date --iso-8601=seconds)" "[ERROR] ❌ $*"; }
die()   { err "$*"; exit 1; }

# --- Function to check internet connectivity ---
check_internet() {
    local test_host="1.1.1.1"
    local timeout=3

    info "Checking internet connection..."
    if ping -c 1 -W "$timeout" "$test_host" >/dev/null 2>&1; then
        info "✅ Internet connection detected."
    else
        err "❌ No internet connection detected. Please check your network."
        return 1
    fi
}

# --- Function to detect OS ---
detect_os() {
    [[ -r /etc/os-release ]] || die "❌ /etc/os-release missing. Cannot detect OS."
    . /etc/os-release
    OS_NAME="$NAME"
    OS_ID="$ID"
    OS_VER="$VERSION_ID"
    info "✅ Detected OS: ${OS_NAME} (${OS_ID} ${OS_VER})"
    [[ "$OS_ID" == "ubuntu" ]] || { warn "Non-Ubuntu OS detected"; confirm "Continue?" || die "Aborted"; }
}

# --- Function to add PHP PPA safely ---
add_php_ppa() {
	# --- Add PHP PPA (Ondřej Surý) safely ---
    PHP_PPA="ppa:ondrej/php"
    if ! grep -Rq "^deb .*$PHP_PPA" /etc/apt/sources.list.d/ /etc/apt/sources.list 2>/dev/null; then
        info "Adding PHP PPA repository (${PHP_PPA})..."
        $DRY_RUN || add-apt-repository -y "$PHP_PPA"
    else
        info "PHP PPA already present — skipping."
    fi

    # --- Refresh repositories after adding ---
    info "Refreshing repositories..."
    $DRY_RUN || apt-get update -qq

    # --- Optional: Verify available PHP versions ---
    if $VERBOSE; then
        info "Available PHP packages:"
        $DRY_RUN || apt-cache search '^php[0-9\.]+$' | awk '{print " -", $1}'
    fi

}

# --- Function to create/update Cloudflare IP list ---
update_cloudflare_ips() {
    local output_file="${CLOUDFLARE_IP_LIST:-$HOME_DIR/Documents/cloudflare-ips.txt}"
    local base_url="https://www.cloudflare.com/ips"

    mkdir -p "$(dirname "$output_file")"

    info "Fetching Cloudflare IP ranges..."
    if $DRY_RUN; then
        info "[DRY-RUN] Would fetch Cloudflare IPs and save to ${output_file}"
        return 0
    fi

    {
        curl -fsSL "${base_url}-v4" || warn "Failed to fetch IPv4 list"
        curl -fsSL "${base_url}-v6" || warn "Failed to fetch IPv6 list"
    } > "$output_file" || warn "Could not write to ${output_file}"

    info "Saved Cloudflare IP list to ${output_file}"
}


# --- Execute checks ---
check_internet || die "Setup aborted — no internet connection."
detect_os || die "Setup aborted — OS detection failed."
add_php_ppa || die "Setup aborted — failed to add PHP PPA."
update_cloudflare_ips || die "Setup aborted — failed to update Cloudflare IP list."