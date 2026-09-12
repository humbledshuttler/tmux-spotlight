#!/usr/bin/env bash
# Render the session strip shown at the top of the popup: every session on one
# line, centred, with the one being browsed highlighted.
#
# Usage: session-strip.sh <active-index> <width> <session-name>...
set -u

active="${1:-0}"
width="${2:-0}"
shift 2 2>/dev/null || true

[ "$#" -gt 1 ] || exit 0    # a single session needs no strip

dim=$'\033[38;5;244m'
on=$'\033[7m'
reset=$'\033[0m'

out=''
plain=''
i=0
for name in "$@"; do
	if [ "$i" -gt 0 ]; then
		out="$out$dim · $reset"
		plain="$plain · "
	fi
	if [ "$i" -eq "$active" ]; then
		out="$out$on $name $reset"
		plain="$plain $name "
	else
		out="$out$dim$name$reset"
		plain="$plain$name"
	fi
	i=$((i + 1))
done

out="$dim←$reset $out $dim→$reset"
plain="← $plain →"

pad=$(((width - ${#plain}) / 2))
[ "$pad" -gt 0 ] || pad=0
printf '%*s%s\n' "$pad" '' "$out"
