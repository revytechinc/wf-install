#!/bin/sh
# Ensure Ly is installed and wired for Wayfire on FreeBSD.
# Idempotent. Soft-skips unreachable/busy hosts.
#
# Usage: configure-ly.sh HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

HOSTS=${*:-}
[ -n "$HOSTS" ] || { echo "usage: $0 HOST [HOST ...]" >&2; exit 2; }

# shellcheck disable=SC2016
REMOTE='
set -eu
ELEV="$1"
run() { if [ -n "$ELEV" ]; then $ELEV "$@"; else "$@"; fi; }

run pkg install -y ly seatd >/tmp/ly-pkg-install.log 2>&1 || {
  echo "pkg install ly/seatd failed — see /tmp/ly-pkg-install.log"
  exit 1
}

run sysrc seatd_enable=YES
run sysrc dbus_enable=YES
run service seatd start 2>/dev/null || run service seatd onestart 2>/dev/null || true
run service dbus start 2>/dev/null || run service dbus onestart 2>/dev/null || true

# gettytab Ly entry (stock ly package usually ships this; ensure present)
if ! grep -q "^Ly:" /etc/gettytab 2>/dev/null; then
  echo "ERROR: gettytab missing Ly: — ly package incomplete" >&2
  exit 1
fi

# Bind ttyv1 to Ly getty if not already
if ! grep -q "getty Ly" /etc/ttys 2>/dev/null; then
  run cp -a /etc/ttys /etc/ttys.bak.wayfire-fleet
  # Prefer ttyv1 (common FreeBSD desktop convention)
  run sed -i "" -e "s|^ttyv1[[:space:]].*|ttyv1	\"/usr/libexec/getty Ly\"		xterm	onifexists secure|" /etc/ttys
fi

# ly config: point at wayland sessions, tty=1
CFG=/usr/local/etc/ly/config.ini
if [ -f "$CFG" ]; then
  run cp -a "$CFG" "$CFG.bak.wayfire-fleet" 2>/dev/null || true
  # Ensure waylandsessions path
  if grep -q "^waylandsessions" "$CFG"; then
    run sed -i "" -e "s|^waylandsessions.*|waylandsessions = /usr/local/share/wayland-sessions|" "$CFG"
  else
    echo "waylandsessions = /usr/local/share/wayland-sessions" | run tee -a "$CFG" >/dev/null
  fi
  if grep -q "^tty[[:space:]]*=" "$CFG"; then
    run sed -i "" -e "s|^tty[[:space:]]*=.*|tty = 1|" "$CFG"
  else
    echo "tty = 1" | run tee -a "$CFG" >/dev/null
  fi
fi

# Desktop user groups
U=${SUDO_USER:-${USER:-mlapointe}}
id "$U" >/dev/null 2>&1 || U=mlapointe
run pw groupmod video -m "$U" 2>/dev/null || true
run pw groupmod operator -m "$U" 2>/dev/null || true

echo "LY_CONFIGURED host=$(hostname) user=$U"
'

for h in $HOSTS; do
	section "configure-ly $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — retry later"; continue ;;
		busy)        defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate "$h" || true)
	if remote_sh "$h" "ELEV='$elev'; $REMOTE" "'$elev'" 2>&1 | tee "$LOG_DIR/configure-ly-$h.log"; then
		pass "$h Ly configured"
	else
		fail "$h Ly configure failed"
	fi
done

summary
