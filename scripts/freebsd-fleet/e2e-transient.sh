#!/bin/sh
# Transient e2e: install → validate → uninstall completely.
# For servers (005/006/008): must leave NO wayfire stack packages behind.
# Soft-skips unreachable/busy hosts.
#
# Usage: e2e-transient.sh HOST [HOST ...]
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/lib/common.sh"

HOSTS=${*:-$TRANSIENT_HOSTS}
[ -n "$HOSTS" ] || { echo "usage: $0 HOST ..." >&2; exit 2; }

for h in $HOSTS; do
	section "e2e-transient $h"
	state=$(probe_host "$h")
	case "$state" in
		unreachable) defer "$h unreachable — keep in matrix, retry later"; continue ;;
		busy)        defer "$h busy — keep in matrix, retry later"; continue ;;
	esac

	# Always attempt cleanup on EXIT for this host if we installed
	INSTALLED=0
	cleanup_host() {
		if [ "$INSTALLED" -eq 1 ]; then
			log "cleanup: uninstalling stack on $h"
			"$DIR/uninstall-stack.sh" --purge-config "$h" || true
		fi
	}
	# Note: trap per-iteration is tricky in sh; cleanup explicitly below

	if ! "$DIR/preflight.sh" "$h"; then
		# preflight FAIL is hard; DEFER-only still exits 0
		if [ $? -ne 0 ]; then
			fail "$h preflight hard-fail — skip install"
			continue
		fi
	fi

	if "$DIR/install-stack.sh" "$h"; then
		INSTALLED=1
	else
		fail "$h install failed"
		"$DIR/uninstall-stack.sh" --purge-config "$h" || true
		continue
	fi

	if ! "$DIR/validate.sh" --transient "$h"; then
		fail "$h validate failed"
	fi

	if "$DIR/uninstall-stack.sh" --purge-config "$h"; then
		# Confirm absence
		if remote_sh "$h" "pkg info -e wayfire 2>/dev/null && exit 1; echo CLEAN"; then
			pass "$h e2e clean (stack removed)"
		else
			fail "$h still has wayfire after uninstall"
		fi
	else
		fail "$h uninstall failed — host may still have packages"
	fi
	INSTALLED=0
done

summary
