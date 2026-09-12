#!/usr/bin/env bash
# tmux-spotlight tests.
#
# Runs a throwaway tmux server on its own socket, with a `tmux` wrapper pinned
# to it on PATH, so nothing here touches the real server or ~/.tmux.conf.
# The plugin is sourced, not run, which is what the guard at its foot is for.
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_TMUX="$(command -v tmux)"
SOCKET="spotlight-test-$$"
WORK="$(mktemp -d)"

pass=0 fail=0
cleanup() { "$REAL_TMUX" -L "$SOCKET" kill-server 2>/dev/null; rm -rf "$WORK"; }
trap cleanup EXIT

printf '#!/usr/bin/env bash\nexec %s -f /dev/null -L %s "$@"\n' "$REAL_TMUX" "$SOCKET" > "$WORK/tmux"
chmod +x "$WORK/tmux"
PATH="$WORK:$PATH"

ok()   { pass=$((pass + 1)); printf '  ok   %s\n' "$1"; }
bad()  { fail=$((fail + 1)); printf '  FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' "$1" "$2" "$3"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has()  { case "$3" in *"$2"*) ok "$1" ;; *) bad "$1" "contains $2" "$3" ;; esac; }
hasnt() { case "$3" in *"$2"*) bad "$1" "no $2" "$3" ;; *) ok "$1" ;; esac; }
plain() { sed $'s/\033\\[[0-9;]*m//g'; }

echo "tmux-spotlight tests ($(tmux -V), socket $SOCKET)"

# shellcheck source-path=SCRIPTDIR/.. source=spotlight.tmux
. "$ROOT/spotlight.tmux"

tmux new-session -d -s alpha -n editor -c "$HOME"
tmux new-window -t '=alpha:' -n server -c "$HOME"
tmux new-window -t '=alpha:' -n 'my long window' -c "$HOME"
tmux split-window -t '=alpha:0'
tmux new-session -d -s beta -n notes -c "$HOME"
tmux new-session -d -s 0 -n zero -c "$HOME"
tmux select-window -t '=alpha:1'

# --- the window list ---------------------------------------------------------
rows="$(list_windows alpha)"
is 'list: one row per window in the session' '3' "$(printf '%s\n' "$rows" | wc -l | tr -d ' ')"
is 'list: targets, in order' 'alpha:0 alpha:1 alpha:2' \
	"$(printf '%s\n' "$rows" | cut -f1 | tr '\n' ' ' | sed 's/ $//')"
hasnt 'list: no other session leaks in' 'beta' "$(printf '%s\n' "$rows" | cut -f1)"
has 'list: name and index are searchable' 'my long window' \
	"$(printf '%s\n' "$rows" | cut -f2 | plain | tr '\n' '|')"
has 'list: the active window is marked' '*' "$(printf '%s\n' "$rows" | sed -n 2p | cut -f2 | plain)"
hasnt 'list: the others are not' '*' "$(printf '%s\n' "$rows" | sed -n 1p | cut -f2 | plain)"
is 'list: columns share one width across sessions' '1' \
	"$({ list_windows alpha; list_windows beta; } | cut -f2 | plain | awk '{print length($0)}' | sort -u | wc -l | tr -d ' ')"
has 'list: context shows the path' '~' "$(printf '%s\n' "$rows" | sed -n 2p | cut -f3 | plain)"
has 'list: and a pane count once a window splits' '2 panes' \
	"$(printf '%s\n' "$rows" | sed -n 1p | cut -f3 | plain)"
hasnt 'list: but not for a single pane' 'pane' "$(printf '%s\n' "$rows" | sed -n 2p | cut -f3 | plain)"
# A session named like a number must not be read as a window index.
has 'list: a numerically named session resolves' 'zero' "$(list_windows 0 | cut -f2 | plain)"

# --- the session strip -------------------------------------------------------
strip="$(session_strip 1 0 alpha beta)"
has 'strip: highlights the session being browsed' $'\033[7m beta ' "$strip"
hasnt 'strip: and only that one' $'\033[7m alpha ' "$strip"
wide="$(session_strip 1 60 alpha beta | plain)"
lead="${wide%%[! ]*}"
is 'strip: centred in the width it is given' "$(((60 - ${#wide} + ${#lead}) / 2))" "${#lead}"
is 'strip: absent when there is only one session' '' "$(session_strip 0 60 alpha)"

# --- popup size --------------------------------------------------------------
# Two clients of sizes we chose, each in its own outer tmux, because only
# new-session can pin a client's size. This is what catches addressing a
# client with -t (which resolves to nothing) instead of -c: get that wrong
# and both answers collapse to the same 80x24 fallback.
OUTER="spotlight-outer-$$"
outer() { "$REAL_TMUX" -f /dev/null -L "$OUTER" "$@"; }
outer new-session -d -s tall -x 200 -y 60 "TERM=xterm-256color $REAL_TMUX -f /dev/null -L $SOCKET attach -t '=alpha:'"
outer new-session -d -s short -x 100 -y 12 "TERM=xterm-256color $REAL_TMUX -f /dev/null -L $SOCKET attach -t '=alpha:'"
for _ in $(seq 1 15); do
	[ "$(tmux list-clients -F x 2>/dev/null | wc -l)" -ge 2 ] && break
	sleep 0.2
done
if [ "$(tmux list-clients -F x 2>/dev/null | wc -l)" -ge 2 ]; then
	tall_tty="$(tmux list-clients -F '#{client_height} #{client_tty}' | sort -rn | head -1)"
	short_tty="$(tmux list-clients -F '#{client_height} #{client_tty}' | sort -n | head -1)"
	read -r _ tall_rows <<<"$(popup_size "${tall_tty##* }")"
	read -r _ short_rows <<<"$(popup_size "${short_tty##* }")"
	windows="$(tmux list-windows -t '=alpha:' -F x | wc -l | tr -d ' ')"
	is 'size: a row per window, plus chrome and empty slots' \
		"$((windows + 7 + HEADER_ROWS + SEPARATOR_ROWS + PAD_ROWS * 2))" "$tall_rows"
	is 'size: a short client caps it at 80% of its height' "$((${short_tty%% *} * 4 / 5))" "$short_rows"
else
	printf '  skip popup size tests (could not attach two sized clients)\n'
fi
outer kill-server 2>/dev/null
tmux detach-client -a 2>/dev/null

# --- fuzzy matching, through the real fzf ------------------------------------
if command -v fzf >/dev/null 2>&1; then
	match() {
		list_windows alpha | fzf --ansi --delimiter=$'\t' --with-nth=2,3 --nth=1 --filter="$1" |
			cut -f1 | tr '\n' ' ' | sed 's/ $//'
	}
	is 'fuzzy: a gappy subsequence finds the window' 'alpha:2' "$(match mlw)"
	is 'fuzzy: the context column is not searchable' '' "$(match '2 panes')"
else
	printf '  skip fuzzy matching tests (fzf not on PATH)\n'
fi

# --- the switcher ------------------------------------------------------------
# A stub fzf replays one canned reply per call -- query, --expect key,
# selection -- and records the arguments it was handed.
cat > "$WORK/fzf" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = --version ] && { echo '0.99.0 (stub)'; exit 0; }
cat > /dev/null
n=$(( $(cat "$WORK/n" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$WORK/n"
printf '%s\n' "$@" > "$WORK/args.$n"
cat "$WORK/reply.$n" 2>/dev/null
STUB
sed -i "s|\$WORK|$WORK|g" "$WORK/fzf"
chmod +x "$WORK/fzf"

switcher() {   # switcher <query> <key> <selection> [<query> <key> <selection>...]
	rm -f "$WORK/n" "$WORK"/reply.* "$WORK"/args.*
	local n=1
	while [ "$#" -gt 0 ]; do
		printf '%s\n' "$1" "$2" "$3" > "$WORK/reply.$n"
		shift 3; n=$((n + 1))
	done
	( run_switcher alpha '' ) 2>/dev/null
}

tmux select-window -t '=alpha:0'
switcher '' '' "$(printf 'alpha:2\tx\tx')"
is 'switcher: Enter selects the window' '2' "$(tmux display-message -p -t '=alpha:' '#{window_index}')"

switcher 'serv' right '' '' '' "$(printf 'beta:0\tx\tx')"
has 'switcher: the arrows browse the next session' $'\033[7m beta ' "$(cat "$WORK/args.2")"
has 'switcher: carrying the query over' '--query=serv' "$(cat "$WORK/args.2")"

before="$(tmux display-message -p -t '=alpha:' '#{window_index}')"
switcher '' '' ''
is 'switcher: an empty selection changes nothing' "$before" \
	"$(tmux display-message -p -t '=alpha:' '#{window_index}')"

# --- fzf missing --------------------------------------------------------------
BARE="$(mktemp -d)"
for c in awk sed cut sort tr wc grep bash cat tput; do
	[ -x "$(command -v "$c")" ] && ln -sf "$(command -v "$c")" "$BARE/$c"
done
ln -sf "$WORK/tmux" "$BARE/tmux"
out="$(env -i PATH="$BARE" HOME="$HOME" bash "$ROOT/spotlight.tmux" run alpha '' 2>&1 </dev/null)"
is 'no fzf: exits non-zero' '1' "$?"
has 'no fzf: says so, and where to get it' 'github.com/junegunn/fzf' "$out"
rm -rf "$BARE"

# --- plugin load --------------------------------------------------------------
bash "$ROOT/spotlight.tmux"
binding="$(tmux list-keys -T prefix | awk '$2 == "-T" && $4 == "w"')"
has 'load: binds the key to the opener' 'spotlight.tmux open' "$binding"
has 'load: passing the calling session and client' 'client_tty' "$binding"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
