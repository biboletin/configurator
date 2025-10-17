#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

echo "Check for internet connection ..."

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


detect_os() {
    [[ -r /etc/os-release ]] || die "❌ /etc/os-release missing. Cannot detect OS."
    . /etc/os-release
    OS_NAME="$NAME"
    OS_ID="$ID"
    OS_VER="$VERSION_ID"
    info "✅ Detected OS: ${OS_NAME} (${OS_ID} ${OS_VER})"
    [[ "$OS_ID" == "ubuntu" ]] || { warn "Non-Ubuntu OS detected"; confirm "Continue?" || die "Aborted"; }
}

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
check_internet || die "Setup aborted — no internet connection."
detect_os || die "Setup aborted — OS detection failed."
add_php_ppa || die "Setup aborted — failed to add PHP PPA."