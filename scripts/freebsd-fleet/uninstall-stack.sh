#!/bin/sh
# Completely remove Wayfire stack packages (transient e2e hosts).
# Does NOT remove ly/seatd/dbus by default.
#
# Usage: uninstall-stack.sh [--purge-config] HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

PURGE=0
HOSTS=
for arg in "$@"; do
	case "$arg" in
		--purge-config) PURGE=1 ;;
		-h|--help) sed -n '2,8p' "$0"; exit 0 ;;
		*) HOSTS="$HOSTS $arg" ;;
	esac
done
[ -n "$HOSTS" ] || { echo "usage: $0 [--purge-config] HOST ..." >&2; exit 2; }
validate_pkg_list "$STACK_PKGS"

for h in $HOSTS; do
	section "uninstall-stack $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable|invalid) defer "$h $state — retry later"; continue ;;
		busy) defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate_mode "$h")
	logf=$(log_path_for_host "$h" uninstall-stack)
	set +e
	remote_sh "$h" env elev_mode="$elev" pkg_line="$STACK_PKGS" purge="$PURGE" sh -s >"$logf" 2>&1 <<'EOS'
set -eu
run() {
  case "$elev_mode" in
    none) "$@" ;;
    doas) doas "$@" ;;
    sudo_n) sudo -n "$@" ;;
    sudo) sudo "$@" ;;
    *) echo "bad elev_mode"; exit 2 ;;
  esac
}
pkill -x wayfire 2>/dev/null || true
pkill -x wf-panel 2>/dev/null || true
pkill -x wf-background 2>/dev/null || true
pkill -x wf-dock 2>/dev/null || true
sleep 1
set -- $pkg_line
rev=
for p in "$@"; do
  case "$p" in
    *[!A-Za-z0-9._+-]*|-*|"") echo "refuse $p"; exit 1 ;;
  esac
  rev="$p $rev"
done
for p in $rev; do
  if pkg info -e "$p" 2>/dev/null; then
    run pkg delete -y "$p" || run pkg remove -y "$p"
    echo "removed $p"
  else
    echo "absent $p"
  fi
done
for p in "$@"; do
  if pkg info -e "$p" 2>/dev/null; then
    echo "still installed $p"; exit 1
  fi
done
if [ "$purge" = 1 ]; then
  run rm -rf /usr/local/etc/wayfire /usr/local/etc/wf-shell \
    /usr/local/share/wayland-sessions/wayfire.desktop 2>/dev/null || true
fi
run pkg autoremove -y 2>/dev/null || true
echo UNINSTALL_OK
EOS
	rc=$?
	set -e
	cat "$logf"
	if [ "$rc" -eq 0 ] && grep -q UNINSTALL_OK "$logf"; then
		pass "$h stack fully removed"
	else
		fail "$h uninstall failed (rc=$rc)"
	fi
done

summary
