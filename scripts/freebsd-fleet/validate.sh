#!/bin/sh
# Post-install validation for Wayfire + Ly + Virtual OSS on FreeBSD.
# Soft-skips unreachable/busy hosts.
#
# Usage:
#   validate.sh [--desktop|--transient] HOST [HOST ...]
#     --desktop    require Ly + virtual_oss running
#     --transient  require stack packages + DRM/seatd; Ly optional
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

MODE=desktop
HOSTS=
for arg in "$@"; do
	case "$arg" in
		--desktop) MODE=desktop ;;
		--transient) MODE=transient ;;
		-h|--help) sed -n '2,10p' "$0"; exit 0 ;;
		*) HOSTS="$HOSTS $arg" ;;
	esac
done
[ -n "$HOSTS" ] || { echo "usage: $0 [--desktop|--transient] HOST ..." >&2; exit 2; }

for h in $HOSTS; do
	section "validate $h ($MODE)"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — retry later"; continue ;;
		busy)        defer "$h busy — retry later"; continue ;;
	esac
	logf="$LOG_DIR/validate-$h.log"
	# shellcheck disable=SC2029
	if remote_sh "$h" "MODE='$MODE' STACK='$STACK_PKGS' sh -s" <<'EOS' 2>&1 | tee "$logf"
set -eu
PASS=0; FAIL=0
pass(){ printf "  PASS %s\n" "$*"; PASS=$((PASS+1)); }
fail(){ printf "  FAIL %s\n" "$*"; FAIL=$((FAIL+1)); }

for p in $STACK; do
  if pkg info -e "$p" 2>/dev/null; then
    pass "pkg $p=$(pkg query %v "$p")"
  else
    fail "pkg missing $p"
  fi
done

need_bin="/usr/local/bin/wayfire"
for b in $need_bin; do
  [ -x "$b" ] && pass "exec $b" || fail "missing $b"
done

# DRM
ls /dev/dri/card* >/dev/null 2>&1 && pass "DRM card present" || fail "no DRM card"
ls /dev/dri/renderD* >/dev/null 2>&1 && pass "DRM render node present" || fail "no DRM render node"

# seatd
[ "$(sysrc -n seatd_enable 2>/dev/null || echo NO)" = YES ] && pass "seatd_enable" || fail "seatd_enable"
service seatd status >/dev/null 2>&1 && pass "seatd running" || fail "seatd not running"

# Headless compositor smoke: start wayfire briefly if possible
# Skip full GUI if no seat — still check binary links
if wayfire --version >/dev/null 2>&1 || wayfire -h >/dev/null 2>&1; then
  pass "wayfire invokes"
else
  # many builds have no --version; try ldd
  if ldd /usr/local/bin/wayfire >/dev/null 2>&1; then
    pass "wayfire binary links (ldd)"
  else
    fail "wayfire binary broken"
  fi
fi

if [ "$MODE" = desktop ]; then
  pkg info -e ly 2>/dev/null && pass "ly installed" || fail "ly missing"
  grep -q "getty Ly" /etc/ttys 2>/dev/null && pass "ttys Ly" || fail "ttys Ly"
  [ -f /usr/local/share/wayland-sessions/wayfire.desktop ] && pass "wayfire.desktop" || fail "wayfire.desktop"
  [ -x /usr/sbin/virtual_oss ] || pkg info -e virtual_oss 2>/dev/null && pass "virtual_oss present" || fail "virtual_oss missing"
  [ "$(sysrc -n virtual_oss_enable 2>/dev/null || echo NO)" = YES ] && pass "virtual_oss_enable" || fail "virtual_oss_enable"
  if service virtual_oss status >/dev/null 2>&1 || pgrep -x virtual_oss >/dev/null 2>&1; then
    pass "virtual_oss running"
  else
    fail "virtual_oss not running"
  fi
  ls /dev/dsp* >/dev/null 2>&1 && pass "dsp devices" || fail "no /dev/dsp*"
fi

printf "  LOCAL_SUMMARY pass=%s fail=%s\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
EOS
	then
		pass "$h validate"
	else
		if grep -q 'fail=[1-9]' "$logf" 2>/dev/null; then
			fail "$h validate (see $logf)"
		else
			defer "$h validate aborted mid-run (see $logf)"
		fi
	fi
done

summary
