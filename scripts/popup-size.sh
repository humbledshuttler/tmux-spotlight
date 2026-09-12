#!/usr/bin/env bash
# Work out how big the popup needs to be to hold its content, in cells.
# Prints "<cols> <rows>".
#
# The size is fixed for the life of the popup, so it is measured against the
# largest session: moving along the strip never resizes or clips the list.
#
# Usage: popup-size.sh <client-tty>
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

client="${1:-}"
if [ -n "$client" ]; then
	read -r max_cols max_rows <<<"$(tmux display-message -p -t "$client" '#{client_width} #{client_height}')"
else
	read -r max_cols max_rows <<<"$(tmux display-message -p '#{client_width} #{client_height}')"
fi
max_cols="${max_cols:-80}"
max_rows="${max_rows:-24}"

mapfile -t sessions < <(tmux list-sessions -F '#{session_name}')

# Widest rendered row and deepest window list, across every session.
widest=0
deepest=0
for name in "${sessions[@]}"; do
	while IFS= read -r line; do
		[ -n "$line" ] || continue
		visible="$(printf '%s' "$line" | cut -f2- | sed $'s/\033\\[[0-9;]*m//g' | tr '\t' ' ')"
		[ "${#visible}" -gt "$widest" ] && widest="${#visible}"
	done < <("$CURRENT_DIR/list-windows.sh" "$name")
	count="$(tmux list-windows -t "=$name:" -F x | wc -l)"
	[ "$count" -gt "$deepest" ] && deepest="$count"
done

strip_cells=0
if [ "${#sessions[@]}" -gt 1 ]; then
	strip="$("$CURRENT_DIR/session-strip.sh" 0 0 "${sessions[@]}" | sed $'s/\033\\[[0-9;]*m//g')"
	strip_cells="${#strip}"
fi

# borders (2) + fzf's pointer gutter (2) + a column of breathing room
cols=$((widest + 5))
[ "$((strip_cells + 6))" -gt "$cols" ] && cols=$((strip_cells + 6))
[ "$cols" -lt 40 ] && cols=40
[ "$cols" -gt $((max_cols * 9 / 10)) ] && cols=$((max_cols * 9 / 10))

# borders (2) + prompt (1) + strip (0 or 1) + one row per window
rows=$((deepest + 3))
[ "${#sessions[@]}" -gt 1 ] && rows=$((rows + 1))
[ "$rows" -lt 6 ] && rows=6
[ "$rows" -gt $((max_rows * 4 / 5)) ] && rows=$((max_rows * 4 / 5))

printf '%s %s\n' "$cols" "$rows"
