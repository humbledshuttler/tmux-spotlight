#!/usr/bin/env bash
# Emit one tab-delimited line per window, ready to feed to fzf:
#
#   <target>\t<index + name (searchable)>\t<context (not searchable)>
#
# Usage: list-windows.sh <scope: session|server> <session-name>
set -u

scope="${1:-session}"
session="${2:-}"

TAB=$'\t'
FORMAT="#{session_name}:#{window_index}${TAB}#{window_index}${TAB}#{window_name}${TAB}#{pane_current_command}${TAB}#{window_panes}${TAB}#{?window_active,1,0}${TAB}#{session_name}"

if [ "$scope" = "server" ]; then
	tmux list-windows -a -F "$FORMAT"
else
	tmux list-windows -t "$session" -F "$FORMAT"
fi | awk -F'\t' -v scope="$scope" '
	{ lines[NR] = $0
	  if (length($2) > iw) iw = length($2)
	  if (length($3) > nw) nw = length($3)
	  if (length($7) > sw) sw = length($7)
	}
	END {
		dim   = "\033[38;5;244m"
		bold  = "\033[1m"
		green = "\033[32m"
		reset = "\033[0m"
		for (i = 1; i <= NR; i++) {
			split(lines[i], f, "\t")
			marker = (f[6] == "1") ? green "*" reset : " "
			panes  = (f[5] == "1") ? "1 pane" : f[5] " panes"
			ctx    = f[4] "  " dim panes reset
			if (scope == "server")
				name = sprintf("%-*s %s%-*s%s", sw, f[7], bold, nw, f[3], reset)
			else
				name = sprintf("%s%-*s%s", bold, nw, f[3], reset)
			printf "%s\t%s %s%*s%s  %s\t%s\n", f[1], marker, dim, iw, f[2], reset, name, ctx
		}
	}
'
