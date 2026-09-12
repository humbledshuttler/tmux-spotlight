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
# shellcheck source-path=SCRIPTDIR source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

# A client is addressed with -c; -t takes a pane, and silently resolves to
# nothing for a tty, which would leave the caps on the 80x24 fallback.
client="${1:-}"
if [ -n "$client" ]; then
	read -r max_cols max_rows <<<"$(tmux display-message -p -c "$client" '#{client_width} #{client_height}' 2>/dev/null)"
fi
if [ -z "${max_cols:-}" ]; then
	read -r max_cols max_rows <<<"$(tmux display-message -p '#{client_width} #{client_height}' 2>/dev/null)"
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
	strip_cells=$(( ${#strip} + SPOTLIGHT_PAD_COLS * 2 ))
fi

# borders (2) + fzf's pointer gutter (2) + padding on each side + a column
# of breathing room
cols=$((widest + 5 + SPOTLIGHT_PAD_COLS * 2))
[ "$((strip_cells + 6))" -gt "$cols" ] && cols=$((strip_cells + 6))
[ "$cols" -lt 40 ] && cols=40
[ "$cols" -gt $((max_cols * 9 / 10)) ] && cols=$((max_cols * 9 / 10))

# borders (2) + prompt (1) + header + separator + padding above and below +
# one row per window, plus a few empty slots so the list is not wedged
# against its own last row
extra="$(spotlight_option '@spotlight-extra-rows' '4')"
rows=$((deepest + extra + 3 + SPOTLIGHT_HEADER_ROWS + SPOTLIGHT_SEPARATOR_ROWS
	+ SPOTLIGHT_PAD_ROWS * 2))
[ "$rows" -lt 6 ] && rows=6
[ "$rows" -gt $((max_rows * 4 / 5)) ] && rows=$((max_rows * 4 / 5))

printf '%s %s\n' "$cols" "$rows"
