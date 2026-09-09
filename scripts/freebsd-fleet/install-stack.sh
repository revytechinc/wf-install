#!/bin/sh
# Install Wayfire stack packages on a FreeBSD host (pkg).
# Soft-skips unreachable/busy hosts.
#
# Usage:
#   install-stack.sh [--desktop] HOST [HOST ...]
#     --desktop  also ensure ly/seatd/virtual_oss packages present
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

DESKTOP=0
HOSTS=
for arg in "$@"; do
	case "$arg" in
		--desktop) DESKTOP=1 ;;
		-h|--help) sed -n '2,8p' "$0"; exit 0 ;;
		*) HOSTS="$HOSTS $arg" ;;
	esac
done
[ -n "$HOSTS" ] || { echo "usage: $0 [--desktop] HOST ..." >&2; exit 2; }

PKGS="$STACK_PKGS"
[ "$DESKTOP" -eq 1 ] && PKGS="$PKGS $DESKTOP_PKGS"

for h in $HOSTS; do
	section "install-stack $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — retry later"; continue ;;
		busy)        defer "$h busy (kernel tests?) — retry later"; continue ;;
	esac
	elev=$(elevate "$h")
	logf="$LOG_DIR/install-stack-$h.log"
	# shellcheck disable=SC2029
	if remote_sh "$h" "PKGS='$PKGS' ELEV='$elev' sh -s" <<'EOS' 2>&1 | tee "$logf"
set -eu
run() { if [ -n "$ELEV" ]; then $ELEV "$@"; else "$@"; fi; }
echo "installing: $PKGS"
# shellcheck disable=SC2086
run pkg install -y $PKGS
for p in $PKGS; do
  pkg info -e "$p" || { echo "missing after install: $p"; exit 1; }
  echo "ok $p=$(pkg query %v "$p")"
done
run sysrc seatd_enable=YES >/dev/null
run sysrc dbus_enable=YES >/dev/null
run service seatd start 2>/dev/null || run service seatd onestart 2>/dev/null || true
run service dbus start 2>/dev/null || run service dbus onestart 2>/dev/null || true
echo INSTALL_OK
EOS
	then
		pass "$h stack installed"
	else
		fail "$h stack install failed (see $logf)"
	fi
done

summary
