#!/bin/sh
# Completely remove Wayfire stack packages (for transient e2e hosts).
# Does NOT remove ly/seatd/dbus by default — those are shared desktop infra.
# Soft-skips unreachable/busy hosts.
#
# Usage:
#   uninstall-stack.sh [--purge-config] HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

PURGE=0
HOSTS=
for arg in "$@"; do
	case "$arg" in
		--purge-config) PURGE=1 ;;
		-h|--help) sed -n '2,9p' "$0"; exit 0 ;;
		*) HOSTS="$HOSTS $arg" ;;
	esac
done
[ -n "$HOSTS" ] || { echo "usage: $0 [--purge-config] HOST ..." >&2; exit 2; }

for h in $HOSTS; do
	section "uninstall-stack $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — retry later"; continue ;;
		busy)        defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate "$h")
	logf="$LOG_DIR/uninstall-stack-$h.log"
	# shellcheck disable=SC2029
	if remote_sh "$h" "PKGS='$STACK_PKGS' PURGE='$PURGE' ELEV='$elev' sh -s" <<'EOS' 2>&1 | tee "$logf"
set -eu
run() { if [ -n "$ELEV" ]; then $ELEV "$@"; else "$@"; fi; }

# Stop any live session leftovers (best-effort)
pkill -x wayfire 2>/dev/null || true
pkill -x wf-panel 2>/dev/null || true
pkill -x wf-background 2>/dev/null || true
pkill -x wf-dock 2>/dev/null || true
sleep 1

# Reverse order for deps
rev=
for p in $PKGS; do rev="$p $rev"; done
for p in $rev; do
  if pkg info -e "$p" 2>/dev/null; then
    run pkg delete -y "$p" || run pkg remove -y "$p"
    echo "removed $p"
  else
    echo "absent $p"
  fi
done

# Confirm gone
left=
for p in $PKGS; do
  if pkg info -e "$p" 2>/dev/null; then
    left="$left $p"
  fi
done
if [ -n "$left" ]; then
  echo "still installed:$left" >&2
  exit 1
fi

if [ "$PURGE" = 1 ]; then
  run rm -rf /usr/local/etc/wayfire /usr/local/etc/wf-shell \
    /usr/local/share/wayland-sessions/wayfire.desktop 2>/dev/null || true
  echo "purged system config paths"
fi

# Autoremove orphaned deps pulled only by the stack
run pkg autoremove -y 2>/dev/null || true
echo UNINSTALL_OK
EOS
	then
		pass "$h stack fully removed"
	else
		fail "$h uninstall failed (see $logf)"
	fi
done

summary
