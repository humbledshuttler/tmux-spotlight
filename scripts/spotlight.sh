#!/usr/bin/env bash
# Spotlight-style window switcher. Runs inside a tmux popup.
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=helpers.sh
. "$CURRENT_DIR/helpers.sh"

# The popup pane belongs to no session, so the invoking session and client are
# passed in by the key binding. Fall back to asking tmux if they are missing
# (e.g. when the script is run by hand).
session="${TMUX_SPOTLIGHT_SESSION:-}"
case "$session" in
	'' | '#{session_name}') session="$(tmux display-message -p '#{session_name}')" ;;
esac
client="${TMUX_SPOTLIGHT_CLIENT:-}"
case "$client" in
	'#{client_tty}') client='' ;;
esac

if ! command -v fzf >/dev/null 2>&1; then
	# The binding uses `display-popup -EE`, so the popup stays open on a
	# non-zero exit and this message is readable.
	echo 'tmux-spotlight: fzf is not on PATH.' >&2
	echo 'Install it from https://github.com/junegunn/fzf (or your package manager).' >&2
	echo >&2
	echo 'Press any key to close.' >&2
	read -rsn1 </dev/tty 2>/dev/null
	exit 1
fi

prompt="$(spotlight_option '@spotlight-prompt' '❯ ')"
preview="$(spotlight_option '@spotlight-preview' 'off')"
preview_pos="$(spotlight_option '@spotlight-preview-position' 'right:50%')"
colors="$(spotlight_option '@spotlight-colors' 'bg+:-1,fg+:-1:reverse,hl:cyan,hl+:cyan:bold,pointer:green,prompt:cyan:bold,query:-1:bold,info:8,header:-1,gutter:-1,separator:8')"
SPOTLIGHT_CONTEXT="$(spotlight_option '@spotlight-context' 'path')"
export SPOTLIGHT_CONTEXT

# The strip is centred on the popup's own width, inside the padding.
width="$(($(tput cols 2>/dev/null || echo 80) - SPOTLIGHT_PAD_COLS * 2))"

# --info=inline-right tucks the match counter out of the way; it arrived in
# fzf 0.42.
info='inline'
fzf_at_least 0.42.0 && info='inline-right'

# The strip lists every session; the list below it shows only the session being
# browsed, so a query never reaches across sessions.
mapfile -t sessions < <(tmux list-sessions -F '#{session_name}')
[ "${#sessions[@]}" -gt 0 ] || exit 0

browsing=0
for i in "${!sessions[@]}"; do
	[ "${sessions[$i]}" = "$session" ] && browsing="$i" && break
done

# shellcheck disable=SC2054  # commas belong to fzf's --color value
base_args=(
	--ansi
	--delimiter=$'\t'
	--with-nth=2,3
	# --nth indexes the fields --with-nth produced, so 1 is the index+name
	# column: the context column stays visible but unsearchable.
	--nth=1
	--layout=reverse
	--info="$info"
	--tabstop=1
	--no-multi
	--cycle
	--print-query
	--prompt="$prompt"
	--pointer='▶'
	--color="$colors"
	--header-first
)

# A list packed against the border is hard to read.
[ "$SPOTLIGHT_PAD_ROWS" -gt 0 ] &&
	base_args+=(--padding="$SPOTLIGHT_PAD_ROWS,$SPOTLIGHT_PAD_COLS")

if [ "$preview" = 'on' ]; then
	base_args+=(
		--preview='tmux capture-pane -ep -t {1} 2>/dev/null | tail -n 200'
		--preview-window="$preview_pos:wrap"
	)
else
	base_args+=(--no-preview)
fi

# With more than one session, the arrow keys move along the strip. fzf reports
# them through --expect and this loop redraws for the newly browsed session,
# carrying the query over so "search somewhere else" is one keypress.
if [ "${#sessions[@]}" -gt 1 ]; then
	# shellcheck disable=SC2054  # the comma belongs to fzf's --expect value
	base_args+=(--expect=left,right)
fi

query=''
selection=''
while :; do
	target_session="${sessions[$browsing]}"
	strip="$("$CURRENT_DIR/session-strip.sh" "$browsing" "$((width - 4))" "${sessions[@]}")"

	# A blank second header line lifts the query clear of the strip; fzf's
	# own separator closes the field off underneath it.
	args=("${base_args[@]}" --query="$query" --header="$strip"$'\n ')

	out="$("$CURRENT_DIR/list-windows.sh" "$target_session" | fzf "${args[@]}")"
	status=$?
	[ "$status" -eq 130 ] && exit 0   # Esc / Ctrl-C

	mapfile -t reply <<<"$out"
	query="${reply[0]:-}"
	if [ "${#sessions[@]}" -gt 1 ]; then
		key="${reply[1]:-}"
		selection="${reply[2]:-}"
	else
		key=''
		selection="${reply[1]:-}"
	fi

	case "$key" in
		left)
			browsing=$(((browsing - 1 + ${#sessions[@]}) % ${#sessions[@]}))
			continue
			;;
		right)
			browsing=$(((browsing + 1) % ${#sessions[@]}))
			continue
			;;
	esac

	[ -n "$selection" ] || exit 0
	break
done

target="${selection%%$'\t'*}"
target_session="${target%:*}"

if [ "$target_session" != "$session" ]; then
	if [ -n "$client" ]; then
		tmux switch-client -c "$client" -t "=$target_session"
	else
		tmux switch-client -t "=$target_session"
	fi
fi
# "=" keeps a session named like a number (say "0") from being read as a
# window index.
tmux select-window -t "=$target"
