#!/bin/sh
# Persistent desktop setup: Ly + Virtual OSS + Wayfire stack.
# For 001/002/003/004/009 — leaves software installed and configured.
# Soft-skips unreachable/busy hosts (do not write them off).
#
# Usage: e2e-desktop.sh HOST [HOST ...]
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/lib/common.sh"

HOSTS=${*:-$DESKTOP_HOSTS}
[ -n "$HOSTS" ] || { echo "usage: $0 HOST ..." >&2; exit 2; }

for h in $HOSTS; do
	section "e2e-desktop $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — keep in matrix, retry later"; continue ;;
		busy)        defer "$h busy — keep in matrix, retry later"; continue ;;
	esac

	"$DIR/preflight.sh" "$h" || true

	"$DIR/configure-ly.sh" "$h" || { fail "$h Ly configure"; continue; }
	"$DIR/configure-voss.sh" "$h" || { fail "$h VOSS configure"; continue; }
	"$DIR/install-stack.sh" --desktop "$h" || { fail "$h stack install"; continue; }
	"$DIR/validate.sh" --desktop "$h" || { fail "$h validate"; continue; }
	pass "$h desktop stack complete"
done

summary
