#!/usr/bin/env bash
# Emit one tab-delimited line per window in a session, ready to feed to fzf:
#
#   <target>\t<index + name (searchable)>\t<context (not searchable)>
#
# Columns are padded to the widest window across ALL sessions, so the layout
# does not jump when you move along the session strip. fzf is run with
# --tabstop=1, which makes the delimiter render as exactly one space.
#
# Usage: list-windows.sh <session-name>
set -u

session="${1:-}"
context="${SPOTLIGHT_CONTEXT:-path}"

TAB=$'\t'
FORMAT="#{session_name}:#{window_index}${TAB}#{window_index}${TAB}#{window_name}${TAB}#{pane_current_command}${TAB}#{window_panes}${TAB}#{?window_active,1,0}${TAB}#{pane_current_path}"

render() {
	awk -F'\t' -v home="$HOME" -v context="$context" -v want="$1" '
		function shorten(path,   n, parts, i, out) {
			if (home != "" && index(path, home) == 1)
				path = "~" substr(path, length(home) + 1)
			if (length(path) <= 28) return path
			n = split(path, parts, "/")
			out = parts[n]
			if (n > 1) out = parts[n - 1] "/" out
			return "…/" out
		}
		{
			rows[NR] = $0
			if (length($2) > iw) iw = length($2)
			if (length($3) > nw) nw = length($3)
		}
		END {
			dim   = "\033[38;5;244m"
			bold  = "\033[1m"
			green = "\033[32m"
			reset = "\033[0m"
			for (i = 1; i <= NR; i++) {
				split(rows[i], f, "\t")
				# A session name cannot contain ":", so the prefix is exact.
				if (want != "" && substr(f[1], 1, length(want) + 1) != want ":") continue

				marker = (f[6] == "1") ? green "*" reset : " "
				ctx = ""
				if (context == "command" || context == "both") ctx = f[4]
				if (context == "path" || context == "both") {
					if (ctx != "") ctx = ctx "  "
					ctx = ctx shorten(f[7])
				}
				# Pane count only when there is more than one -- otherwise it
				# is the same noise on every row.
				if (f[5] + 0 > 1) ctx = (ctx == "" ? "" : ctx "  ") f[5] " panes"

				printf "%s\t%s %s%*s%s  %s%-*s%s \t%s%s%s\n",
					f[1], marker, dim, iw, f[2], reset, bold, nw, f[3], reset,
					dim, ctx, reset
			}
		}
	'
}

# Widths come from every window on the server; rows come from one session.
tmux list-windows -a -F "$FORMAT" | render "$session"
