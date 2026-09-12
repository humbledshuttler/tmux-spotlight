#!/usr/bin/env bash
# Open the switcher popup, sized to its content.
#
# The key binding runs this rather than `display-popup` directly: a popup's
# size is fixed when it opens and tmux formats cannot measure the longest
# window name, so the measuring happens here.
#
# Usage: open.sh <session-name> <client-tty>
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

session="${1:-}"
client="${2:-}"

read -r cols rows <<<"$("$CURRENT_DIR/popup-size.sh" "$client")"

# An explicit size wins over the measured one.
cols="$(spotlight_option '@spotlight-width' "$cols")"
rows="$(spotlight_option '@spotlight-height' "$rows")"

border="$(spotlight_option '@spotlight-border' 'rounded')"
title="$(spotlight_option '@spotlight-title' ' spotlight ')"

popup_args=(-EE -w "$cols" -h "$rows")
[ -n "$client" ] && popup_args+=(-c "$client")
if tmux_version_at_least 3.3; then
	popup_args+=(-b "$border" -T "#[align=centre]$title")
fi

tmux display-popup "${popup_args[@]}" \
	"TMUX_SPOTLIGHT_SESSION=$(shell_quote "$session") TMUX_SPOTLIGHT_CLIENT=$(shell_quote "$client") $(shell_quote "$CURRENT_DIR/spotlight.sh")"
