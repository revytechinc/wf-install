#!/bin/sh
# Ensure Ly is installed and wired for Wayfire on FreeBSD (pkg only).
# Soft-skips unreachable/busy hosts.
#
# Usage: configure-ly.sh HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

HOSTS=${*:-}
[ -n "$HOSTS" ] || { echo "usage: $0 HOST [HOST ...]" >&2; exit 2; }

for h in $HOSTS; do
	section "configure-ly $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable|invalid) defer "$h $state — retry later"; continue ;;
		busy) defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate_mode "$h")
	logf=$(log_path_for_host "$h" configure-ly)
	set +e
	remote_sh "$h" env elev_mode="$elev" sh -s >"$logf" 2>&1 <<'EOS'
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
run pkg install -y ly seatd
run sysrc seatd_enable=YES
run sysrc dbus_enable=YES
run service seatd start 2>/dev/null || run service seatd onestart 2>/dev/null || true
run service dbus start 2>/dev/null || run service dbus onestart 2>/dev/null || true
grep -q "^Ly:" /etc/gettytab || { echo "gettytab missing Ly:"; exit 1; }
if ! grep -q "getty Ly" /etc/ttys 2>/dev/null; then
  run cp -a /etc/ttys /etc/ttys.bak.wayfire-fleet
  run sed -i "" -e "s|^ttyv1[[:space:]].*|ttyv1	\"/usr/libexec/getty Ly\"		xterm	onifexists secure|" /etc/ttys
fi
CFG=/usr/local/etc/ly/config.ini
if [ -f "$CFG" ]; then
  run cp -a "$CFG" "$CFG.bak.wayfire-fleet" 2>/dev/null || true
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
U=${SUDO_USER:-${USER:-mlapointe}}
id "$U" >/dev/null 2>&1 || U=mlapointe
run pw groupmod video -m "$U" 2>/dev/null || true
run pw groupmod operator -m "$U" 2>/dev/null || true
echo LY_CONFIGURED
EOS
	rc=$?
	set -e
	cat "$logf"
	if [ "$rc" -eq 0 ] && grep -q LY_CONFIGURED "$logf"; then
		pass "$h Ly configured"
	else
		fail "$h Ly configure failed (rc=$rc)"
	fi
done

summary
