#!/bin/sh
# Shared helpers for FreeBSD Wayfire fleet scripts.
# SPDX-License-Identifier: MIT
#
# Soft-skip semantics: a host that does not answer SSH, or that is under heavy
# load (kernel tests, etc.), is DEFERRED — never treated as permanently failed
# or removed from the matrix.

set -eu

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

FLEET_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIR="${FLEET_LOG_DIR:-/tmp/wayfire-fleet-logs}"
mkdir -p "$LOG_DIR"

# Host roles (user matrix). Unreachable hosts stay in the list.
DESKTOP_HOSTS="${DESKTOP_HOSTS:-freedev001 freedev002 freedev003 freedev004 freedev009}"
TRANSIENT_HOSTS="${TRANSIENT_HOSTS:-freedev005 freedev006 freedev008}"
DOMAIN="${FLEET_DOMAIN:-cloudbsd.org}"

# Soft-skip thresholds
SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-8}"
SSH_ATTEMPTS="${SSH_ATTEMPTS:-2}"
# Defer when 1-min load average exceeds ncpu * this factor
LOAD_DEFER_FACTOR="${LOAD_DEFER_FACTOR:-2.0}"

# Stack packages (pkg names as published from cloudbsd-ports — never source builds)
STACK_PKGS="${STACK_PKGS:-wayfire wayfire-plugins-extra wf-shell wf-config wcm}"
# Optional companion packages for a complete desktop
DESKTOP_PKGS="${DESKTOP_PKGS:-ly seatd virtual_oss dbus}"

PASS=0
FAIL=0
DEFER=0
SKIP=0

log()   { printf '%s\n' "$*"; }
pass()  { printf 'PASS  %s\n' "$*"; PASS=$((PASS + 1)); }
fail()  { printf 'FAIL  %s\n' "$*" >&2; FAIL=$((FAIL + 1)); }
defer() { printf 'DEFER %s\n' "$*"; DEFER=$((DEFER + 1)); }
skip()  { printf 'SKIP  %s\n' "$*"; SKIP=$((SKIP + 1)); }
section() { printf '\n======== %s ========\n' "$*"; }

host_fqdn() {
	case "$1" in
		*.*) printf '%s\n' "$1" ;;
		*)   printf '%s.%s\n' "$1" "$DOMAIN" ;;
	esac
}

# Run a remote command. Exit 99 = unreachable (caller should DEFER).
# Usage: remote_sh HOST 'script...'
remote_sh() {
	_host=$(host_fqdn "$1")
	shift
	ssh -o BatchMode=yes \
	    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
	    -o ConnectionAttempts="$SSH_ATTEMPTS" \
	    -o StrictHostKeyChecking=accept-new \
	    "$_host" "$@"
}

# Probe host. Prints: ok|unreachable|busy
# busy = reachable but load too high for installs/tests
probe_host() {
	_host=$1
	_out=$(remote_sh "$_host" 'hostname; sysctl -n hw.ncpu; uptime' 2>/tmp/wayfire-fleet-ssh.err) || {
		printf 'unreachable\n'
		return 0
	}
	_ncpu=$(printf '%s\n' "$_out" | sed -n '2p')
	_load=$(printf '%s\n' "$_out" | sed -n '3p' | sed -n 's/.*load averages: \([0-9.][0-9.]*\).*/\1/p')
	if [ -z "$_ncpu" ] || [ -z "$_load" ]; then
		printf 'ok\n'
		return 0
	fi
	# awk compare load vs ncpu * factor
	_busy=$(awk -v load="$_load" -v ncpu="$_ncpu" -v f="$LOAD_DEFER_FACTOR" \
		'BEGIN { print (load > (ncpu * f)) ? 1 : 0 }')
	if [ "$_busy" = 1 ]; then
		printf 'busy\n'
		return 0
	fi
	printf 'ok\n'
}

require_root_remote() {
	_host=$1
	remote_sh "$_host" 'id -u' | grep -qx 0 && return 0
	# Prefer doas/sudo for root ops
	remote_sh "$_host" 'doas -n true 2>/dev/null || sudo -n true 2>/dev/null'
}

elevate() {
	# Prefix for remote privileged commands
	if remote_sh "$1" 'id -u' 2>/dev/null | grep -qx 0; then
		printf '%s\n' ""
	elif remote_sh "$1" 'doas -n true' 2>/dev/null; then
		printf '%s\n' "doas"
	elif remote_sh "$1" 'sudo -n true' 2>/dev/null; then
		printf '%s\n' "sudo -n"
	else
		printf '%s\n' "sudo"
	fi
}

summary() {
	section "SUMMARY"
	printf 'pass=%s fail=%s defer=%s skip=%s\n' "$PASS" "$FAIL" "$DEFER" "$SKIP"
	# Deferred hosts are not failures — kernel tests / unreachable for now
	[ "$FAIL" -eq 0 ]
}
