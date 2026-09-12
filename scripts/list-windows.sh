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

			path = (context == "path" || context == "both") ? shorten($7) : ""
			if (context == "command" || context == "both")
				path = (path == "") ? $4 : $4 "  " path
			paths[NR] = path
			if (length(path) > pw) pw = length(path)

			panes[NR] = ($5 + 0 > 1) ? $5 " panes" : ""
			if (length(panes[NR]) > cw) cw = length(panes[NR])
		}
		END {
			# Attributes, not colours, and never a full reset: fzf styles
			# the row under the cursor by opening an escape before the line,
			# and "\033[0m" here would close it again halfway through. A
			# hardcoded grey has the same problem from the other side --
			# it survives onto the highlight bar and disappears into it.
			dim     = "\033[2m"     # faint, relative to whatever fg applies
			undim   = "\033[22m"
			green   = "\033[32m"
			default = "\033[39m"   # foreground only; leaves bg and attrs
			for (i = 1; i <= NR; i++) {
				split(rows[i], f, "\t")
				# A session name cannot contain ":", so the prefix is exact.
				if (want != "" && substr(f[1], 1, length(want) + 1) != want ":") continue

				marker = (f[6] == "1") ? green "*" default : " "

				# Every column is padded to one width so the eye can run down
				# them: ragged trailing text is what makes a dense list hard
				# to read. Pane counts sit right-aligned in a column of their
				# own rather than trailing each path.
				ctx = ""
				if (pw > 0) ctx = sprintf("%-*s", pw, paths[i])
				if (cw > 0) ctx = ctx sprintf("  %*s", cw, panes[i])

				printf "%s\t%s %s%*s%s   %-*s  \t%s%s%s\n",
					f[1], marker, dim, iw, f[2], undim, nw, f[3],
					dim, ctx, undim
			}
		}
	'
}

# Widths come from every window on the server; rows come from one session.
tmux list-windows -a -F "$FORMAT" | render "$session"
