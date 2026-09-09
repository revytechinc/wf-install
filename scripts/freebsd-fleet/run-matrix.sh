#!/bin/sh
# Drive the full freedev Wayfire matrix.
#
# Roles:
#   desktop   (001 002 003 004 009) — persistent Ly + VOSS + Wayfire
#   transient (005 006 008)         — install, validate, uninstall clean
#
# Unreachable or high-load hosts are DEFERRED (kernel tests, etc.), never
# dropped from the matrix. Re-run until everything is PASS.
#
# Usage:
#   run-matrix.sh              # both roles
#   run-matrix.sh desktop
#   run-matrix.sh transient
#   run-matrix.sh preflight    # checks only
set -eu

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$DIR/lib/common.sh"

MODE=${1:-all}

section "matrix probe"
for h in $DESKTOP_HOSTS $TRANSIENT_HOSTS; do
	state=$(probe_host "$h")
	printf '  %-14s %s\n' "$h" "$state"
done

case "$MODE" in
	preflight)
		"$DIR/preflight.sh" --role all
		;;
	desktop)
		"$DIR/e2e-desktop.sh" $DESKTOP_HOSTS
		;;
	transient)
		"$DIR/e2e-transient.sh" $TRANSIENT_HOSTS
		;;
	all)
		"$DIR/e2e-desktop.sh" $DESKTOP_HOSTS
		"$DIR/e2e-transient.sh" $TRANSIENT_HOSTS
		;;
	*)
		echo "usage: $0 [all|desktop|transient|preflight]" >&2
		exit 2
		;;
esac
