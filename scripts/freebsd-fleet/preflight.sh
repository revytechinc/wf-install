#!/bin/sh
# Preflight checks for a FreeBSD Wayfire seat.
# Soft-skips unreachable / overloaded hosts (kernel tests, etc.).
#
# Usage:
#   preflight.sh [host ...]
#   preflight.sh --role desktop|transient|all
#
# Exit 0 if every checked host is PASS or DEFER (no hard FAIL).
# Exit 1 only on FAIL.
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

ROLE=
HOSTS=
while [ $# -gt 0 ]; do
	case "$1" in
		--role)
			shift
			ROLE=${1:-}
			;;
		--role=*)
			ROLE=${1#--role=}
			;;
		-h|--help)
			sed -n '2,12p' "$0"
			exit 0
			;;
		*)
			HOSTS="$HOSTS $1"
			;;
	esac
	shift
done

case "$ROLE" in
	desktop)   HOSTS="$DESKTOP_HOSTS" ;;
	transient) HOSTS="$TRANSIENT_HOSTS" ;;
	all)       HOSTS="$DESKTOP_HOSTS $TRANSIENT_HOSTS" ;;
	"")        ;;
	*)         echo "unknown role: $ROLE" >&2; exit 2 ;;
esac
HOSTS=${HOSTS:-$DESKTOP_HOSTS $TRANSIENT_HOSTS}

# Remote preflight body — runs on the target
# shellcheck disable=SC2016
REMOTE_PREFLIGHT='
set -eu
PASS=0; FAIL=0
pass(){ printf "  PASS %s\n" "$*"; PASS=$((PASS+1)); }
fail(){ printf "  FAIL %s\n" "$*"; FAIL=$((FAIL+1)); }

echo "host=$(hostname) uname=$(uname -mrs)"

# GPU / display class
GPU=$(pciconf -lv 2>/dev/null | awk "
  /class = .display/ || /subclass.*=.*VGA/ || /subclass.*=.*3D/ { want=1 }
  want && /vendor/ { v=\$0 }
  want && /device/ { print v \" | \" \$0; want=0 }
" | head -5)
if [ -n "$GPU" ]; then
  pass "display GPU present"
  printf "%s\n" "$GPU" | sed "s/^/    /"
else
  fail "no display-class PCI device (Matrox BMC alone may not drive Wayfire well)"
fi

# DRM nodes
if ls /dev/dri/card* /dev/dri/renderD* >/dev/null 2>&1; then
  pass "DRM nodes under /dev/dri"
  ls /dev/dri 2>/dev/null | sed "s/^/    /"
else
  fail "no /dev/dri nodes — load nvidia-drm / i915kms / drm-kmod as appropriate"
fi

# seatd
if pkg info -e seatd 2>/dev/null; then
  pass "seatd package installed ($(pkg query %v seatd))"
else
  fail "seatd package missing"
fi
if [ "$(sysrc -n seatd_enable 2>/dev/null || true)" = "YES" ]; then
  pass "seatd_enable=YES"
else
  fail "seatd_enable is not YES"
fi
if service seatd status >/dev/null 2>&1; then
  pass "seatd running"
else
  fail "seatd not running"
fi

# Ly (expected on most desktops; advisory on transient servers)
if pkg info -e ly 2>/dev/null; then
  pass "ly package installed ($(pkg query %v ly))"
  if [ -x /usr/local/bin/ly ]; then
    pass "ly binary present"
  else
    fail "ly package without /usr/local/bin/ly"
  fi
  if grep -q "getty Ly" /etc/ttys 2>/dev/null; then
    pass "getty Ly configured in /etc/ttys"
  else
    fail "no getty Ly line in /etc/ttys"
  fi
  if grep -q "^Ly:" /etc/gettytab 2>/dev/null; then
    pass "gettytab Ly: entry present"
  else
    fail "gettytab missing Ly: entry"
  fi
  if [ -f /usr/local/etc/ly/config.ini ]; then
    pass "ly config.ini present"
  else
    fail "missing /usr/local/etc/ly/config.ini"
  fi
else
  echo "  INFO ly not installed (ok for transient server hosts)"
fi

# Wayland session desktop file
if [ -f /usr/local/share/wayland-sessions/wayfire.desktop ]; then
  pass "wayfire.desktop session file present"
  # Prefer session-launch wrapper when available
  if grep -q wayfire-session-launch /usr/local/share/wayland-sessions/wayfire.desktop 2>/dev/null; then
    pass "wayfire.desktop uses wayfire-session-launch"
  else
    echo "  INFO wayfire.desktop Exec= is plain wayfire (wrapper preferred when packaged)"
  fi
else
  echo "  INFO wayfire.desktop not installed yet"
fi

# Groups for the invoking user (or mlapointe)
U=${SUDO_USER:-${USER:-mlapointe}}
id "$U" >/dev/null 2>&1 || U=mlapointe
G=$(id -Gn "$U" 2>/dev/null || true)
echo "  INFO user=$U groups=$G"
echo "$G" | tr " " "\n" | grep -qx video && pass "user $U in video" || fail "user $U not in video"
echo "$G" | tr " " "\n" | grep -qx wheel && pass "user $U in wheel" || echo "  INFO user $U not in wheel"

# Audio / virtual_oss
if pkg info -e virtual_oss 2>/dev/null || [ -x /usr/sbin/virtual_oss ]; then
  pass "virtual_oss present"
else
  fail "virtual_oss missing"
fi
if [ "$(sysrc -n virtual_oss_enable 2>/dev/null || echo NO)" = "YES" ]; then
  pass "virtual_oss_enable=YES"
else
  echo "  INFO virtual_oss_enable not YES (will configure on desktop install)"
fi
if service virtual_oss onestatus >/dev/null 2>&1 || service virtual_oss status >/dev/null 2>&1; then
  pass "virtual_oss running"
else
  echo "  INFO virtual_oss not running"
fi
if ls /dev/dsp* >/dev/null 2>&1; then
  pass "OSS dsp device(s) present"
  ls /dev/dsp* 2>/dev/null | sed "s/^/    /" | head -8
else
  echo "  INFO no /dev/dsp* yet (cuse/snd loaded?)"
fi

# dbus
if [ "$(sysrc -n dbus_enable 2>/dev/null || echo NO)" = "YES" ]; then
  pass "dbus_enable=YES"
else
  echo "  INFO dbus_enable not YES"
fi

printf "  LOCAL_SUMMARY pass=%s fail=%s\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
'

for h in $HOSTS; do
	section "preflight $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable)
			defer "$h unreachable (may be mid kernel-test / net blip) — keep in matrix"
			continue
			;;
		busy)
			defer "$h reachable but load high — defer installs/tests"
			continue
			;;
	esac
	logf="$LOG_DIR/preflight-$h.log"
	if remote_sh "$h" "$REMOTE_PREFLIGHT" 2>&1 | tee "$logf"; then
		pass "$h preflight"
	else
		# If remote reported LOCAL_SUMMARY with fails, count as fail
		if grep -q 'LOCAL_SUMMARY' "$logf" && grep -q 'fail=[1-9]' "$logf"; then
			fail "$h preflight (see $logf)"
		else
			# unexpected ssh/script abort while host was "ok" — still soft if connection died mid-flight
			defer "$h preflight aborted mid-run (see $logf)"
		fi
	fi
done

summary
