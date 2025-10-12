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

check_internet || die "Setup aborted — no internet connection."
