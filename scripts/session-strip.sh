#!/usr/bin/env bash
# Render the session strip shown at the top of the popup: every session on one
# line, the one being browsed highlighted.
#
# Usage: session-strip.sh <active-index> <session-name>...
set -u

active="${1:-0}"
shift || true

[ "$#" -gt 1 ] || exit 0    # a single session needs no strip

dim=$'\033[38;5;244m'
active_style=$'\033[7m'
reset=$'\033[0m'

out="$dim←$reset "
i=0
for name in "$@"; do
	[ "$i" -eq 0 ] || out="$out$dim · $reset"
	if [ "$i" -eq "$active" ]; then
		out="$out$active_style $name $reset"
	else
		out="$out$dim$name$reset"
	fi
	i=$((i + 1))
done
printf '%s %s→%s\n' "$out" "$dim" "$reset"
