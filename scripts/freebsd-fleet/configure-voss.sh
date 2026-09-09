#!/bin/sh
# Configure Virtual OSS for a FreeBSD Wayfire desktop seat.
# Idempotent. Soft-skips unreachable/busy hosts.
#
# Usage: configure-voss.sh HOST [HOST ...]
set -eu

. "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/lib/common.sh"

HOSTS=${*:-}
[ -n "$HOSTS" ] || { echo "usage: $0 HOST [HOST ...]" >&2; exit 2; }

# shellcheck disable=SC2016
REMOTE='
set -eu
ELEV="$1"
run() { if [ -n "$ELEV" ]; then $ELEV "$@"; else "$@"; fi; }

if ! pkg info -e virtual_oss 2>/dev/null && [ ! -x /usr/sbin/virtual_oss ]; then
  run pkg install -y virtual_oss >/tmp/voss-pkg-install.log 2>&1 || {
    echo "virtual_oss install failed"; exit 1
  }
fi

run sysrc -f /boot/loader.conf cuse_load=YES 2>/dev/null || true
kldstat -q -m cuse || run kldload cuse 2>/dev/null || true

HW=
for cand in /dev/dsp0 /dev/dsp1 /dev/dsp2 /dev/dsp3 /dev/dsp4 /dev/dsp5; do
  [ -e "$cand" ] || continue
  HW=$cand
  break
done
if [ -z "$HW" ]; then
  run kldload snd_hda 2>/dev/null || true
  sleep 1
  for cand in /dev/dsp0 /dev/dsp1 /dev/dsp2; do
    [ -e "$cand" ] || continue
    HW=$cand
    break
  done
fi
[ -n "$HW" ] || HW=/dev/null

run service virtual_oss stop 2>/dev/null || true
pkill -x virtual_oss 2>/dev/null || true

ARGS="-S -C 2 -c 2 -r 48000 -b 16 -s 1024 -f /dev/dsp -P $HW -R /dev/null -l dsp -t dsp.ctl"
run sysrc virtual_oss_enable=YES
run sysrc virtual_oss_configs=dsp
run sysrc "virtual_oss_dsp=$ARGS"
run service virtual_oss start 2>/dev/null || run service virtual_oss onestart

sleep 1
if service virtual_oss status >/dev/null 2>&1 || pgrep -x virtual_oss >/dev/null 2>&1; then
  echo "VOSS_OK backend=$HW"
  ls -la /dev/dsp /dev/dsp.ctl 2>/dev/null || ls /dev/dsp* 2>/dev/null | head -10
else
  echo "VOSS_FAIL args=$ARGS" >&2
  exit 1
fi
'

for h in $HOSTS; do
	section "configure-voss $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — retry later"; continue ;;
		busy)        defer "$h busy — retry later"; continue ;;
	esac
	elev=$(elevate "$h" || true)
	if remote_sh "$h" "set -- '$elev'; $REMOTE" 2>&1 | tee "$LOG_DIR/configure-voss-$h.log"; then
		pass "$h virtual_oss configured"
	else
		fail "$h virtual_oss configure failed"
	fi
done

summary
