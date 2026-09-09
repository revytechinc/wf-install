#!/bin/sh
# Post-install validation (pkg-owned stack + seat). Soft-skips busy hosts.
#
# Usage: validate.sh [--desktop|--transient] HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

MODE=desktop
HOSTS=
for arg in "$@"; do
	case "$arg" in
		--desktop) MODE=desktop ;;
		--transient) MODE=transient ;;
		-h|--help) sed -n '2,8p' "$0"; exit 0 ;;
		*) HOSTS="$HOSTS $arg" ;;
	esac
done
[ -n "$HOSTS" ] || { echo "usage: $0 [--desktop|--transient] HOST ..." >&2; exit 2; }
validate_pkg_list "$STACK_PKGS"
validate_fleet_mode "$MODE" || exit 2

for h in $HOSTS; do
	section "validate $h ($MODE)"
	state=$(probe_host "$h")
	case "$state" in
		unreachable|invalid) defer "$h $state — retry later"; continue ;;
		busy) defer "$h busy — retry later"; continue ;;
	esac
	logf=$(log_path_for_host "$h" validate)
	set +e
	remote_sh "$h" "env MODE='$MODE' pkg_line='$STACK_PKGS' sh -s" >"$logf" 2>&1 <<'EOS'
set -eu
PASS=0; FAIL=0
pass(){ printf "  PASS %s\n" "$*"; PASS=$((PASS+1)); }
fail(){ printf "  FAIL %s\n" "$*"; FAIL=$((FAIL+1)); }
set -- $pkg_line
for p in "$@"; do
  case "$p" in
    *[!A-Za-z0-9._+-]*|-*|"") fail "bad pkg token $p"; continue ;;
  esac
  if pkg info -e "$p" 2>/dev/null; then
    pass "pkg $p=$(pkg query %v "$p")"
  else
    fail "pkg missing $p"
  fi
done
[ -x /usr/local/bin/wayfire ] && pass "exec wayfire" || fail "missing wayfire"
ls /dev/dri/card* >/dev/null 2>&1 && pass "DRM card" || fail "no DRM card"
ls /dev/dri/renderD* >/dev/null 2>&1 && pass "DRM render" || fail "no DRM render"
[ "$(sysrc -n seatd_enable 2>/dev/null || echo NO)" = YES ] && pass "seatd_enable" || fail "seatd_enable"
service seatd status >/dev/null 2>&1 && pass "seatd running" || fail "seatd not running"
if ldd /usr/local/bin/wayfire >/dev/null 2>&1; then
  pass "wayfire ldd"
else
  fail "wayfire ldd"
fi
if [ "$MODE" = desktop ]; then
  pkg info -e ly 2>/dev/null && pass "ly" || fail "ly"
  grep -q "getty Ly" /etc/ttys 2>/dev/null && pass "ttys Ly" || fail "ttys Ly"
  [ -f /usr/local/share/wayland-sessions/wayfire.desktop ] && pass "wayfire.desktop" || fail "wayfire.desktop"
  if command -v virtual_oss >/dev/null 2>&1 || pkg info -e virtual_oss 2>/dev/null; then
    pass "virtual_oss present"
  else
    fail "virtual_oss missing"
  fi
  [ "$(sysrc -n virtual_oss_enable 2>/dev/null || echo NO)" = YES ] && pass "virtual_oss_enable" || fail "virtual_oss_enable"
  if service virtual_oss status >/dev/null 2>&1 || pgrep -x virtual_oss >/dev/null 2>&1; then
    pass "virtual_oss running"
  else
    fail "virtual_oss not running"
  fi
fi
printf "  LOCAL_SUMMARY pass=%s fail=%s\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
EOS
	rc=$?
	set -e
	cat "$logf"
	if [ "$rc" -eq 0 ]; then
		pass "$h validate"
	elif grep -q 'fail=[1-9]' "$logf" 2>/dev/null; then
		fail "$h validate (see $logf)"
	else
		defer "$h validate aborted (rc=$rc)"
	fi
done

summary
