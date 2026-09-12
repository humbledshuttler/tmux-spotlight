#!/usr/bin/env bash
# tmux-spotlight -- Spotlight-style fuzzy window switcher.
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

# True when the running tmux is at least the given version.
tmux_version_at_least() {
	local want="$1" have
	have="$(tmux -V | sed 's/[^0-9.]//g')"
	[ "$have" = "$want" ] || printf '%s\n%s\n' "$want" "$have" | sort -C -V
}

key="$(spotlight_option '@spotlight-key' 'w')"
width="$(spotlight_option '@spotlight-width' '70%')"
height="$(spotlight_option '@spotlight-height' '60%')"
border="$(spotlight_option '@spotlight-border' 'rounded')"
title="$(spotlight_option '@spotlight-title' ' spotlight ')"

# -EE: close the popup when the script exits cleanly, but keep it open on a
# non-zero exit so errors stay readable.
popup_args=(-EE -w "$width" -h "$height")
if tmux_version_at_least 3.3; then
	popup_args+=(-b "$border" -T "#[align=centre]$title")
fi

# The popup pane is session-less, so hand the script its caller's session and
# client. tmux expands these formats when the key is pressed.
tmux bind-key "$key" display-popup "${popup_args[@]}" \
	"TMUX_SPOTLIGHT_SESSION='#{session_name}' TMUX_SPOTLIGHT_CLIENT='#{client_tty}' '$CURRENT_DIR/scripts/spotlight.sh'"
