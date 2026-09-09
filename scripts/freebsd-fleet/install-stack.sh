#!/bin/sh
# Install Wayfire stack packages via pkg only (cloudbsd-ports builds).
# Soft-skips unreachable/busy hosts.
#
# Usage: install-stack.sh [--desktop] HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

DESKTOP=0
HOSTS=
for arg in "$@"; do
	case "$arg" in
		--desktop) DESKTOP=1 ;;
		-h|--help) sed -n '2,7p' "$0"; exit 0 ;;
		*) HOSTS="$HOSTS $arg" ;;
	esac
done
[ -n "$HOSTS" ] || { echo "usage: $0 [--desktop] HOST ..." >&2; exit 2; }

PKGS="$STACK_PKGS"
[ "$DESKTOP" -eq 1 ] && PKGS="$PKGS $DESKTOP_PKGS"
validate_pkg_list "$PKGS"

for h in $HOSTS; do
	section "install-stack $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable|invalid) defer "$h $state — retry later"; continue ;;
		busy) defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate_mode "$h")
	validate_elev_mode "$elev" || { defer "$h invalid elev_mode"; continue; }
	logf=$(log_path_for_host "$h" install-stack)

	# PKGS / elev closed-set validated before embedding in remote env string.
	set +e
	remote_sh "$h" "env elev_mode='$elev' pkg_line='$PKGS' sh -s" >"$logf" 2>&1 <<'EOS'
set -eu
run() {
  case "$elev_mode" in
    none) "$@" ;;
    doas) doas "$@" ;;
    sudo_n) sudo -n "$@" ;;
    sudo) sudo "$@" ;;
    *) echo "bad elev_mode=$elev_mode"; exit 2 ;;
  esac
}
# Re-validate every token on the remote side too
set -- $pkg_line
for p in "$@"; do
  case "$p" in
    *[!A-Za-z0-9._+-]*|-*|"") echo "refuse pkg $p"; exit 1 ;;
  esac
done
echo "installing: $*"
run pkg install -y "$@"
for p in "$@"; do
  pkg info -e "$p" || { echo "missing $p"; exit 1; }
  echo "ok $p=$(pkg query %v "$p")"
done
run sysrc seatd_enable=YES >/dev/null
run sysrc dbus_enable=YES >/dev/null
run service seatd start 2>/dev/null || run service seatd onestart 2>/dev/null || true
run service dbus start 2>/dev/null || run service dbus onestart 2>/dev/null || true
echo INSTALL_OK
EOS
	rc=$?
	set -e
	cat "$logf"
	if [ "$rc" -eq 0 ] && grep -q INSTALL_OK "$logf"; then
		pass "$h stack installed"
	else
		fail "$h stack install failed (rc=$rc, see $logf)"
	fi
done

summary
