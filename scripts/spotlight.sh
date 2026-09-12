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

scope="$(spotlight_option '@spotlight-scope' 'session')"
prompt="$(spotlight_option '@spotlight-prompt' '❯ ')"
preview="$(spotlight_option '@spotlight-preview' 'off')"
preview_pos="$(spotlight_option '@spotlight-preview-position' 'right:50%')"

# shellcheck disable=SC2054  # commas belong to fzf's --color value
fzf_args=(
	--ansi
	--delimiter=$'\t'
	--with-nth=2,3
	# --nth indexes the fields --with-nth produced, so 1 is the index+name
	# column: the context column stays visible but unsearchable.
	--nth=1
	--layout=reverse
	--info=inline
	--no-multi
	--cycle
	--prompt="$prompt"
	--pointer='▶'
	--color='pointer:green,prompt:blue,info:8'
	--header="$([ "$scope" = server ] && echo 'windows: all sessions' || echo "windows: $session")"
	--header-first
)

if [ "$preview" = 'on' ]; then
	fzf_args+=(
		--preview='tmux capture-pane -ep -t {1} 2>/dev/null | tail -n 200'
		--preview-window="$preview_pos:wrap"
	)
else
	fzf_args+=(--no-preview)
fi

selection="$("$CURRENT_DIR/list-windows.sh" "$scope" "$session" | fzf "${fzf_args[@]}")" || exit 0
[ -n "$selection" ] || exit 0

target="${selection%%$'\t'*}"
target_session="${target%:*}"

if [ "$target_session" != "$session" ]; then
	if [ -n "$client" ]; then
		tmux switch-client -c "$client" -t "$target_session"
	else
		tmux switch-client -t "$target_session"
	fi
fi
tmux select-window -t "$target"
