#!/usr/bin/env bash
# Shared helpers for tmux-spotlight.

# Read a tmux user option, falling back to a default when unset or empty.
spotlight_option() {
	local option="$1" default="$2" value
	value="$(tmux show-option -gqv "$option" 2>/dev/null)"
	if [ -n "$value" ]; then
		printf '%s' "$value"
	else
		printf '%s' "$default"
	fi
}
