#!/bin/sh
# Configure Virtual OSS (pkg/base binary) for a FreeBSD Wayfire seat.
# Soft-skips unreachable/busy hosts.
#
# Usage: configure-voss.sh HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

HOSTS=${*:-}
[ -n "$HOSTS" ] || { echo "usage: $0 HOST [HOST ...]" >&2; exit 2; }

for h in $HOSTS; do
	section "configure-voss $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable|invalid) defer "$h $state — retry later"; continue ;;
		busy) defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate_mode "$h")
	validate_elev_mode "$elev" || { defer "$h invalid elev_mode"; continue; }
	logf=$(log_path_for_host "$h" configure-voss)
	set +e
	remote_sh "$h" "env elev_mode='$elev' sh -s" >"$logf" 2>&1 <<'EOS'
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
if ! [ -x /usr/sbin/virtual_oss ] \
    && ! [ -x /usr/local/sbin/virtual_oss ] \
    && ! [ -x /usr/local/bin/virtual_oss ]; then
  run pkg install -y virtual_oss
fi
run sysrc -f /boot/loader.conf cuse_load=YES 2>/dev/null || true
kldstat -q -m cuse || run kldload cuse 2>/dev/null || true
HW=
for cand in /dev/dsp0 /dev/dsp1 /dev/dsp2 /dev/dsp3 /dev/dsp4 /dev/dsp5; do
  if [ -e "$cand" ]; then HW=$cand; break; fi
done
if [ -z "$HW" ]; then
  run kldload snd_hda 2>/dev/null || true
  sleep 1
  for cand in /dev/dsp0 /dev/dsp1 /dev/dsp2; do
    if [ -e "$cand" ]; then HW=$cand; break; fi
  done
fi
[ -n "$HW" ] || HW=/dev/null
run service virtual_oss stop 2>/dev/null || true
pkill -x virtual_oss 2>/dev/null || true
ARGS="-S -C 2 -c 2 -r 48000 -b 16 -s 1024 -f /dev/dsp -P $HW -R /dev/null -l dsp -t dsp.ctl"
run sysrc virtual_oss_enable=YES
run sysrc virtual_oss_configs=dsp
run sysrc virtual_oss_dsp="$ARGS"
run service virtual_oss start 2>/dev/null || run service virtual_oss onestart
sleep 1
if service virtual_oss status >/dev/null 2>&1 || pgrep -x virtual_oss >/dev/null 2>&1; then
  echo "VOSS_OK backend=$HW"
else
  echo "VOSS_FAIL"; exit 1
fi
EOS
	rc=$?
	set -e
	cat "$logf"
	if [ "$rc" -eq 0 ] && grep -q VOSS_OK "$logf"; then
		pass "$h virtual_oss configured"
	else
		fail "$h virtual_oss configure failed (rc=$rc)"
	fi
done

summary
