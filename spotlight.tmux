#!/usr/bin/env bash
# tmux-spotlight -- Spotlight-style fuzzy window switcher.
set -u

CURRENT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR source=scripts/helpers.sh
. "$CURRENT_DIR/scripts/helpers.sh"

key="$(spotlight_option '@spotlight-key' 'w')"

# The popup is sized to its content, which needs measuring, so the key runs a
# script instead of `display-popup` directly. It also hands the script the
# calling session and client: a popup pane belongs to neither.
tmux bind-key "$key" run-shell -b \
	"$(shell_quote "$CURRENT_DIR/scripts/open.sh") '#{session_name}' '#{client_tty}'"
