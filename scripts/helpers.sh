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

# True when the installed fzf is at least the given version.
fzf_at_least() {
	local have
	have="$(fzf --version 2>/dev/null | awk '{print $1}')"
	[ -n "$have" ] && printf '%s\n%s\n' "$1" "$have" | sort -C -V
}

# Breathing room inside the popup: rows, then columns, on each side.
# fzf grew --padding in 0.35.
SPOTLIGHT_PAD_ROWS=0
SPOTLIGHT_PAD_COLS=0
if fzf_at_least 0.35.0; then
	SPOTLIGHT_PAD_ROWS=1
	SPOTLIGHT_PAD_COLS=2
fi

# fzf rules a line under the prompt from 0.34 on. It frames the query as a
# search field, so it is wanted -- but it costs a row the popup has to budget.
SPOTLIGHT_SEPARATOR_ROWS=0
fzf_at_least 0.34.0 && SPOTLIGHT_SEPARATOR_ROWS=1

# The header is always two lines: the session strip (blank with one session)
# and a blank line that sets the query apart from it.
SPOTLIGHT_HEADER_ROWS=2

export SPOTLIGHT_PAD_ROWS SPOTLIGHT_PAD_COLS SPOTLIGHT_SEPARATOR_ROWS SPOTLIGHT_HEADER_ROWS
