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

# True when the running tmux is at least the given version.
tmux_version_at_least() {
	local want="$1" have
	have="$(tmux -V | sed 's/[^0-9.]//g')"
	[ "$have" = "$want" ] || printf '%s\n%s\n' "$want" "$have" | sort -C -V
}

# Quote a value for the shell command handed to display-popup.
shell_quote() { printf '%q' "$1"; }
