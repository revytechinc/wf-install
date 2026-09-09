#!/bin/sh
# Shared helpers for FreeBSD Wayfire fleet scripts.
# SPDX-License-Identifier: MIT
#
# Soft-skip semantics: a host that does not answer SSH, or that is under heavy
# load (kernel tests, etc.), is DEFERRED — never treated as permanently failed
# or removed from the matrix.
#
# Packages arrive only via pkg (cloudbsd-ports → poudriere → pkg install).

set -eu

export PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/sbin:/usr/local/bin

FLEET_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
LOG_DIR="${FLEET_LOG_DIR:-/tmp/wayfire-fleet-logs}"
mkdir -p "$LOG_DIR"

# Host roles — override via env (do not bake secrets here).
DESKTOP_HOSTS="${DESKTOP_HOSTS:-freedev001 freedev002 freedev003 freedev004 freedev009}"
TRANSIENT_HOSTS="${TRANSIENT_HOSTS:-freedev005 freedev006 freedev008}"
DOMAIN="${FLEET_DOMAIN:-cloudbsd.org}"

SSH_CONNECT_TIMEOUT="${SSH_CONNECT_TIMEOUT:-8}"
SSH_ATTEMPTS="${SSH_ATTEMPTS:-2}"
LOAD_DEFER_FACTOR="${LOAD_DEFER_FACTOR:-2.0}"
# Prefer StrictHostKeyChecking=yes with an existing known_hosts; accept-new only
# when FLEET_SSH_ACCEPT_NEW=1 for bootstrap.
SSH_STRICT="${FLEET_SSH_STRICT:-yes}"
[ "${FLEET_SSH_ACCEPT_NEW:-0}" = 1 ] && SSH_STRICT=accept-new

STACK_PKGS="${STACK_PKGS:-wayfire wayfire-plugins-extra wf-shell wf-config wcm}"
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

# Reject host tokens that can break paths or ssh option parsing.
validate_host_token() {
	case "$1" in
		''|-*|*/*|*..*|*[!A-Za-z0-9._-]*)
			echo "invalid host token: $1" >&2
			return 1
			;;
	esac
}

validate_pkg_name() {
	case "$1" in
		''|-*|*[!A-Za-z0-9._+-]*)
			echo "invalid package name: $1" >&2
			return 1
			;;
	esac
}

validate_pkg_list() {
	for _p in $1; do
		validate_pkg_name "$_p" || return 1
	done
}

# Closed sets for values embedded in remote "env …='$val'" strings.
validate_elev_mode() {
	case "$1" in
		none|doas|sudo|sudo_n) ;;
		*)
			echo "invalid elev_mode: $1" >&2
			return 1
			;;
	esac
}

validate_purge_flag() {
	case "$1" in
		0|1) ;;
		*)
			echo "invalid purge flag: $1" >&2
			return 1
			;;
	esac
}

validate_fleet_mode() {
	case "$1" in
		desktop|transient|stack) ;;
		*)
			echo "invalid fleet MODE: $1" >&2
			return 1
			;;
	esac
}

host_fqdn() {
	validate_host_token "$1" || return 1
	case "$1" in
		*.*) printf '%s\n' "$1" ;;
		*)   printf '%s.%s\n' "$1" "$DOMAIN" ;;
	esac
}

log_path_for_host() {
	validate_host_token "$1" || return 1
	printf '%s/%s-%s.log\n' "$LOG_DIR" "$2" "$1"
}

# remote_sh HOST command...
remote_sh() {
	_host=$(host_fqdn "$1") || return 1
	shift
	ssh -o BatchMode=yes \
	    -o ConnectTimeout="$SSH_CONNECT_TIMEOUT" \
	    -o ConnectionAttempts="$SSH_ATTEMPTS" \
	    -o "StrictHostKeyChecking=$SSH_STRICT" \
	    -- "$_host" "$@"
}


elevate_mode() {
	if remote_sh "$1" 'id -u' 2>/dev/null | grep -qx 0; then
		printf '%s\n' "none"
	elif remote_sh "$1" 'doas -n true' 2>/dev/null; then
		printf '%s\n' "doas"
	elif remote_sh "$1" 'sudo -n true' 2>/dev/null; then
		printf '%s\n' "sudo_n"
	else
		printf '%s\n' "sudo"
	fi
}

# Probe host. Prints: ok|unreachable|busy|invalid
probe_host() {
	if ! validate_host_token "$1" 2>/dev/null; then
		printf 'invalid\n'
		return 0
	fi
	_out=$(remote_sh "$1" 'hostname; sysctl -n hw.ncpu; uptime' 2>/tmp/wayfire-fleet-ssh.err) || {
		printf 'unreachable\n'
		return 0
	}
	_ncpu=$(printf '%s\n' "$_out" | sed -n '2p')
	_load=$(printf '%s\n' "$_out" | sed -n '3p' | sed -n 's/.*load averages: \([0-9.][0-9.]*\).*/\1/p')
	if [ -z "$_ncpu" ] || [ -z "$_load" ]; then
		printf 'ok\n'
		return 0
	fi
	_busy=$(awk -v load="$_load" -v ncpu="$_ncpu" -v f="$LOAD_DEFER_FACTOR" \
		'BEGIN { print (load > (ncpu * f)) ? 1 : 0 }')
	if [ "$_busy" = 1 ]; then
		printf 'busy\n'
		return 0
	fi
	printf 'ok\n'
}

# Run CMD logging to FILE; return CMD status (not tee's).
run_logged() {
	_log=$1
	shift
	# shellcheck disable=SC2068
	set +e
	"$@" >"$_log" 2>&1
	_rc=$?
	set -e
	cat "$_log"
	return "$_rc"
}

summary() {
	section "SUMMARY"
	printf 'pass=%s fail=%s defer=%s skip=%s\n' "$PASS" "$FAIL" "$DEFER" "$SKIP"
	[ "$FAIL" -eq 0 ]
}
