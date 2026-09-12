#!/usr/bin/env bash
# tmux-spotlight -- a Spotlight-style fuzzy window switcher for tmux.
#
# One file, three roles, chosen by the first argument:
#
#   (none)            plugin load: bind the key
#   open <ses> <cli>  measure the content and open a popup that fits it
#   run  <ses> <cli>  the switcher itself, running inside that popup
#
# The key runs `open` rather than `display-popup` directly because a popup's
# size is fixed when it opens and tmux formats cannot measure the longest
# window name. A popup pane belongs to no session, so the calling session and
# client are passed down both times.
set -u

SELF="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/$(basename -- "${BASH_SOURCE[0]}")"

# --- options ----------------------------------------------------------------

# A tmux user option, or the default when it is unset or empty.
opt() {
	local value
	value="$(tmux show-option -gqv "$1" 2>/dev/null)"
	[ -n "$value" ] && printf '%s' "$value" || printf '%s' "$2"
}

# --- fzf capabilities -------------------------------------------------------

fzf_at_least() {
	local have
	have="$(fzf --version 2>/dev/null | awk '{print $1}')"
	[ -n "$have" ] && printf '%s\n%s\n' "$1" "$have" | sort -C -V
}

# Chrome the popup has to budget for, and the flags that produce it.
# --padding arrived in fzf 0.35; the rule under the prompt in 0.34.
PAD_ROWS=0 PAD_COLS=0 SEPARATOR_ROWS=0
fzf_at_least 0.35.0 && { PAD_ROWS=1; PAD_COLS=2; }
fzf_at_least 0.34.0 && SEPARATOR_ROWS=1
HEADER_ROWS=2   # the session strip, and a blank line above the query

# --- the window list --------------------------------------------------------

# One tab-delimited row per window in a session, ready for fzf:
#
#   <target>\t<index + name (searchable)>\t<context (not searchable)>
#
# Widths come from every window on the server so the columns do not shuffle
# when you move along the strip; rows come from the one session asked for.
# fzf runs with --tabstop=1, so the delimiter renders as exactly one space.
list_windows() {
	local session="$1" tab=$'\t'
	tmux list-windows -a -F "#{session_name}:#{window_index}${tab}#{window_index}${tab}#{window_name}${tab}#{pane_current_command}${tab}#{window_panes}${tab}#{?window_active,1,0}${tab}#{pane_current_path}" |
		awk -F'\t' -v home="$HOME" -v context="$(opt @spotlight-context path)" -v want="$session" '
		function shorten(path,   n, parts, out) {
			if (home != "" && index(path, home) == 1)
				path = "~" substr(path, length(home) + 1)
			if (length(path) <= 28) return path
			n = split(path, parts, "/")
			out = (n > 1 ? parts[n - 1] "/" : "") parts[n]
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

			# A pane count only earns its place once there is more than one.
			panes[NR] = ($5 + 0 > 1) ? $5 " panes" : ""
			if (length(panes[NR]) > cw) cw = length(panes[NR])
		}
		END {
			# Attributes, not colours, and never a full reset: fzf styles the
			# row under the cursor by opening an escape before the line, and
			# "\033[0m" here would close it again halfway through. A hardcoded
			# grey has the same problem from the other side -- it survives
			# onto the highlight and disappears into it.
			dim = "\033[2m"; undim = "\033[22m"
			green = "\033[32m"; default_fg = "\033[39m"

			for (i = 1; i <= NR; i++) {
				split(rows[i], f, "\t")
				# A session name cannot contain ":", so the prefix is exact.
				if (substr(f[1], 1, length(want) + 1) != want ":") continue

				marker = (f[6] == "1") ? green "*" default_fg : " "

				# Every column padded to one width: ragged trailing text is
				# what makes a dense list hard to read.
				ctx = (pw > 0) ? sprintf("%-*s", pw, paths[i]) : ""
				if (cw > 0) ctx = ctx sprintf("  %*s", cw, panes[i])

				printf "%s\t%s %s%*s%s   %-*s  \t%s%s%s\n",
					f[1], marker, dim, iw, f[2], undim, nw, f[3], dim, ctx, undim
			}
		}
	'
}

# --- the session strip ------------------------------------------------------

# Every session on one centred line, the one being browsed highlighted.
# Nothing at all when there is only one session.
session_strip() {
	local active="$1" width="$2"
	shift 2
	[ "$#" -gt 1 ] || return 0

	local dim=$'\033[2m' on=$'\033[7m' off=$'\033[27m' undim=$'\033[22m'
	local out='' plain='' i=0 name pad

	for name in "$@"; do
		if [ "$i" -gt 0 ]; then
			out="$out$dim · $undim"
			plain="$plain · "
		fi
		if [ "$i" -eq "$active" ]; then
			out="$out$on $name $off"
			plain="$plain $name "
		else
			out="$out$dim$name$undim"
			plain="$plain$name"
		fi
		i=$((i + 1))
	done
	out="$dim←$undim $out $dim→$undim"
	plain="← $plain →"

	pad=$(((width - ${#plain}) / 2))
	[ "$pad" -gt 0 ] || pad=0
	printf '%*s%s\n' "$pad" '' "$out"
}

# --- sizing -----------------------------------------------------------------

# "<cols> <rows>" for a popup that holds its content. Fixed for the life of
# the popup, so it is measured against the largest session: moving along the
# strip never resizes or clips the list.
popup_size() {
	local client="${1:-}" max_cols='' max_rows='' widest=0 deepest=0
	local name line visible count strip cols rows extra

	# A client is addressed with -c; -t takes a pane and silently resolves to
	# nothing for a tty, which would leave the caps on the 80x24 fallback.
	[ -n "$client" ] &&
		read -r max_cols max_rows <<<"$(tmux display-message -p -c "$client" '#{client_width} #{client_height}' 2>/dev/null)"
	[ -n "$max_cols" ] ||
		read -r max_cols max_rows <<<"$(tmux display-message -p '#{client_width} #{client_height}' 2>/dev/null)"
	max_cols="${max_cols:-80}" max_rows="${max_rows:-24}"

	local sessions
	mapfile -t sessions < <(tmux list-sessions -F '#{session_name}')

	for name in "${sessions[@]}"; do
		while IFS= read -r line; do
			visible="$(printf '%s' "$line" | cut -f2- | sed $'s/\033\\[[0-9;]*m//g' | tr '\t' ' ')"
			[ "${#visible}" -gt "$widest" ] && widest="${#visible}"
		done < <(list_windows "$name")
		count="$(tmux list-windows -t "=$name:" -F x | wc -l)"
		[ "$count" -gt "$deepest" ] && deepest="$count"
	done

	# borders (2) + fzf's pointer gutter (2) + padding + a column of slack
	cols=$((widest + 5 + PAD_COLS * 2))
	strip="$(session_strip 0 0 "${sessions[@]}" | sed $'s/\033\\[[0-9;]*m//g')"
	[ -n "$strip" ] && [ $((${#strip} + 6 + PAD_COLS * 2)) -gt "$cols" ] &&
		cols=$((${#strip} + 6 + PAD_COLS * 2))
	[ "$cols" -lt 40 ] && cols=40
	[ "$cols" -gt $((max_cols * 9 / 10)) ] && cols=$((max_cols * 9 / 10))

	# borders (2) + query (1) + header + rule + padding + a row per window,
	# plus a few empty slots so the list is not wedged against its last row
	extra="$(opt @spotlight-extra-rows 4)"
	rows=$((deepest + extra + 3 + HEADER_ROWS + SEPARATOR_ROWS + PAD_ROWS * 2))
	[ "$rows" -lt 6 ] && rows=6
	[ "$rows" -gt $((max_rows * 4 / 5)) ] && rows=$((max_rows * 4 / 5))

	printf '%s %s\n' "$cols" "$rows"
}

# --- opening ----------------------------------------------------------------

open_popup() {
	local session="${1:-}" client="${2:-}" cols rows args
	read -r cols rows <<<"$(popup_size "$client")"

	# An explicit size wins over the measured one.
	cols="$(opt @spotlight-width "$cols")"
	rows="$(opt @spotlight-height "$rows")"

	# -EE: close on a clean exit, but stay open on an error so it can be read.
	args=(-EE -w "$cols" -h "$rows")
	[ -n "$client" ] && args+=(-c "$client")
	if [ "$(tmux -V | sed 's/[^0-9.]//g')" = 3.2 ]; then :; else
		args+=(-b "$(opt @spotlight-border rounded)" -T "#[align=centre]$(opt @spotlight-title ' spotlight ')")
	fi

	tmux display-popup "${args[@]}" \
		"$(printf '%q %q %q %q' "$SELF" run "$session" "$client")"
}

# --- the switcher ------------------------------------------------------------

run_switcher() {
	local session="${1:-}" client="${2:-}"
	case "$session" in '' | '#{session_name}') session="$(tmux display-message -p '#{session_name}')" ;; esac
	case "$client" in '#{client_tty}') client='' ;; esac

	if ! command -v fzf >/dev/null 2>&1; then
		echo 'tmux-spotlight: fzf is not on PATH.' >&2
		echo 'Install it from https://github.com/junegunn/fzf (or your package manager).' >&2
		echo >&2
		echo 'Press any key to close.' >&2
		read -rsn1 </dev/tty 2>/dev/null
		exit 1
	fi

	local sessions browsing=0 i
	mapfile -t sessions < <(tmux list-sessions -F '#{session_name}')
	[ "${#sessions[@]}" -gt 0 ] || exit 0
	for i in "${!sessions[@]}"; do
		[ "${sessions[$i]}" = "$session" ] && browsing="$i" && break
	done

	# The strip is centred on the popup's own width, inside the padding.
	local width=$(($(tput cols 2>/dev/null || echo 80) - PAD_COLS * 2))

	local info=inline
	fzf_at_least 0.42.0 && info=inline-right

	# shellcheck disable=SC2054  # commas belong to fzf's --color value
	local base=(
		--ansi --delimiter=$'\t'
		--with-nth=2,3
		# --nth indexes the fields --with-nth produced, so 1 is the index+name
		# column: the context column stays visible but unsearchable.
		--nth=1
		--layout=reverse --info="$info" --tabstop=1 --no-multi --cycle
		--print-query --header-first
		--prompt="$(opt @spotlight-prompt '❯ ')"
		--pointer='▶'
		--color="$(opt @spotlight-colors 'bg+:-1,fg+:-1:reverse,hl:cyan,hl+:cyan:bold,pointer:green,prompt:cyan:bold,query:-1:bold,info:8,header:-1,gutter:-1,separator:8')"
	)
	[ "$PAD_ROWS" -gt 0 ] && base+=(--padding="$PAD_ROWS,$PAD_COLS")
	if [ "$(opt @spotlight-preview off)" = on ]; then
		base+=(--preview='tmux capture-pane -ep -t {1} 2>/dev/null | tail -n 200'
			--preview-window="$(opt @spotlight-preview-position right:50%):wrap")
	else
		base+=(--no-preview)
	fi
	# With more than one session the arrows move along the strip: fzf reports
	# them through --expect and the loop redraws for the newly browsed one.
	# shellcheck disable=SC2054  # the comma belongs to fzf's --expect value
	[ "${#sessions[@]}" -gt 1 ] && base+=(--expect=left,right)

	local query='' selection='' strip out status key reply target target_session
	while :; do
		strip="$(session_strip "$browsing" "$width" "${sessions[@]}")"
		# A blank second header line lifts the query clear of the strip; fzf's
		# own rule closes the field off underneath it.
		out="$(list_windows "${sessions[$browsing]}" |
			fzf "${base[@]}" --query="$query" --header="$strip"$'\n ')"
		status=$?
		[ "$status" -eq 130 ] && exit 0   # Esc / Ctrl-C

		mapfile -t reply <<<"$out"
		query="${reply[0]:-}"
		if [ "${#sessions[@]}" -gt 1 ]; then
			key="${reply[1]:-}" selection="${reply[2]:-}"
		else
			key='' selection="${reply[1]:-}"
		fi

		case "$key" in
			left)  browsing=$(((browsing - 1 + ${#sessions[@]}) % ${#sessions[@]})); continue ;;
			right) browsing=$(((browsing + 1) % ${#sessions[@]})); continue ;;
		esac
		[ -n "$selection" ] || exit 0
		break
	done

	target="${selection%%$'\t'*}"
	target_session="${target%:*}"
	# "=" keeps a session named like a number ("0") from being read as an index.
	if [ "$target_session" != "$session" ]; then
		if [ -n "$client" ]; then
			tmux switch-client -c "$client" -t "=$target_session"
		else
			tmux switch-client -t "=$target_session"
		fi
	fi
	tmux select-window -t "=$target"
}

# --- plugin load -------------------------------------------------------------

bind_key() {
	tmux bind-key "$(opt @spotlight-key w)" run-shell -b \
		"$(printf '%q' "$SELF") open '#{session_name}' '#{client_tty}'"
}

main() {
	case "${1:-}" in
		open) shift; open_popup "$@" ;;
		run)  shift; run_switcher "$@" ;;
		*)    bind_key ;;
	esac
}

# Sourced by the tests; run by tmux.
(return 0 2>/dev/null) || main "$@"
