#!/usr/bin/env bash
# Smoke tests for tmux-spotlight. Runs a throwaway tmux server on its own
# socket and puts a `tmux` wrapper pinned to that socket on PATH, so the tests
# never touch the user's real sessions.
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_TMUX="$(command -v tmux)"
SOCKET="spotlight-test-$$"
BIN="$(mktemp -d)"
WORK="$(mktemp -d)"

pass=0
fail=0

cleanup() {
	"$REAL_TMUX" -L "$SOCKET" kill-server 2>/dev/null
	rm -rf "$BIN" "$WORK"
}
trap cleanup EXIT

# -f /dev/null keeps the test server out of the user's tmux.conf.
printf '#!/usr/bin/env bash\nexec %s -f /dev/null -L %s "$@"\n' "$REAL_TMUX" "$SOCKET" > "$BIN/tmux"
chmod +x "$BIN/tmux"
PATH="$BIN:$PATH"

check() {
	if [ "$2" = "$3" ]; then
		printf '  ok   %s\n' "$1"
		pass=$((pass + 1))
	else
		printf '  FAIL %s\n       expected: [%s]\n       actual:   [%s]\n' "$1" "$2" "$3"
		fail=$((fail + 1))
	fi
}

contains() {
	case "$3" in
		*"$2"*)
			printf '  ok   %s\n' "$1"
			pass=$((pass + 1))
			;;
		*)
			printf '  FAIL %s\n       missing: [%s]\n       in:      [%s]\n' "$1" "$2" "$3"
			fail=$((fail + 1))
			;;
	esac
}

lacks() {
	case "$3" in
		*"$2"*)
			printf '  FAIL %s\n       unexpected: [%s]\n       in:         [%s]\n' "$1" "$2" "$3"
			fail=$((fail + 1))
			;;
		*)
			printf '  ok   %s\n' "$1"
			pass=$((pass + 1))
			;;
	esac
}

strip_ansi() { sed $'s/\033\\[[0-9;]*m//g'; }
field() { cut -f"$1"; }

echo "tmux-spotlight tests ($(tmux -V), socket $SOCKET)"

tmux new-session -d -s alpha -n editor
tmux new-window -t alpha -n server
tmux new-window -t alpha -n 'my long window'
tmux new-session -d -s beta -n notes
tmux new-window -t beta -n build
tmux select-window -t alpha:1

# --- the window list ----------------------------------------------------------
out="$("$ROOT/scripts/list-windows.sh" alpha)"
check 'list: one line per window' '3' "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
check 'list: targets' 'alpha:0 alpha:1 alpha:2' \
	"$(printf '%s\n' "$out" | field 1 | tr '\n' ' ' | sed 's/ $//')"
check 'list: only the named session' '' "$(printf '%s\n' "$out" | field 1 | grep beta)"
contains 'list: window name is searchable' 'my long window' \
	"$(printf '%s\n' "$out" | field 2 | strip_ansi | tr '\n' '|')"
contains 'list: window index is searchable' '2' \
	"$(printf '%s\n' "$out" | sed -n 3p | field 2 | strip_ansi)"
contains 'list: active window marked' '*' \
	"$(printf '%s\n' "$out" | sed -n 2p | field 2 | strip_ansi)"
check 'list: inactive windows unmarked' '' \
	"$(printf '%s\n' "$out" | sed -n 1p | field 2 | strip_ansi | grep '\*')"
check 'list: searchable column padded to one width' '1' \
	"$(printf '%s\n' "$out" | field 2 | strip_ansi | awk '{print length($0)}' | sort -u | wc -l | tr -d ' ')"
contains 'list: context shows pane count' '1 pane' \
	"$(printf '%s\n' "$out" | sed -n 1p | field 3 | strip_ansi)"
check 'list: other session listed on request' '2' \
	"$("$ROOT/scripts/list-windows.sh" beta | wc -l | tr -d ' ')"

tmux split-window -t alpha:0
contains 'list: context pluralises pane count' '2 panes' \
	"$("$ROOT/scripts/list-windows.sh" alpha | sed -n 1p | field 3 | strip_ansi)"

# --- the session strip ---------------------------------------------------------
strip="$("$ROOT/scripts/session-strip.sh" 0 alpha beta)"
contains 'strip: lists every session' 'alpha' "$(printf '%s' "$strip" | strip_ansi)"
contains 'strip: lists every session (2)' 'beta' "$(printf '%s' "$strip" | strip_ansi)"
contains 'strip: shows the arrow affordance' '←' "$(printf '%s' "$strip" | strip_ansi)"
contains 'strip: highlights the browsed session' $'\033[7m alpha ' "$strip"
lacks 'strip: does not highlight the others' $'\033[7m beta ' "$strip"
contains 'strip: highlight follows the index' $'\033[7m beta ' \
	"$("$ROOT/scripts/session-strip.sh" 1 alpha beta)"
check 'strip: hidden when there is only one session' '' "$("$ROOT/scripts/session-strip.sh" 0 alpha)"

# --- fuzzy matching (needs a real fzf) ----------------------------------------
if command -v fzf >/dev/null 2>&1; then
	filter() {
		"$ROOT/scripts/list-windows.sh" alpha \
			| fzf --ansi --delimiter=$'\t' --with-nth=2,3 --nth=1 --filter="$1" \
			| field 1 | tr '\n' ' ' | sed 's/ $//'
	}
	check 'fuzzy: exact name' 'alpha:1' "$(filter server)"
	check 'fuzzy: subsequence match' 'alpha:2' "$(filter mlw)"
	check 'fuzzy: gappy subsequence' 'alpha:2' "$(filter ylong)"
	check 'fuzzy: index match' 'alpha:1' "$(filter 1)"
	check 'fuzzy: no match' '' "$(filter zzzznope)"
	check 'fuzzy: context column is not searchable' '' "$(filter '2 panes')"
else
	printf '  skip fuzzy matching tests (fzf not on PATH)\n'
fi

# --- the switcher loop ---------------------------------------------------------
# A stub fzf replays one canned response per invocation and records the
# arguments it was given, so the loop can be driven without a terminal.
STUB="$(mktemp -d)"
cat > "$STUB/fzf" <<'STUBSH'
#!/usr/bin/env bash
cat > /dev/null
n=$(( $(cat "$TEST_DIR/n" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$TEST_DIR/n"
printf '%s\n' "$@" > "$TEST_DIR/args.$n"
cat "$TEST_DIR/resp.$n" 2>/dev/null
exit "$(cat "$TEST_DIR/rc.$n" 2>/dev/null || echo 0)"
STUBSH
chmod +x "$STUB/fzf"

# Each response is query, then the --expect key, then the selected line.
respond() { printf '%s\n' "$2" "$3" "$4" > "$WORK/resp.$1"; }
run_switcher() {
	rm -f "$WORK/n" "$WORK"/resp.* "$WORK"/args.* "$WORK"/rc.*
	local n=1
	while [ "$#" -gt 0 ]; do
		respond "$n" "$1" "$2" "$3"
		shift 3
		n=$((n + 1))
	done
	PATH="$STUB:$PATH" TEST_DIR="$WORK" TMUX_SPOTLIGHT_SESSION=alpha \
		"$ROOT/scripts/spotlight.sh" 2>/dev/null
}
args_of() { cat "$WORK/args.$1"; }
# The strip marks the browsed session with reverse video; match it raw.
browsed_in() { grep -c -- "--header=.*$(printf '\033')\[7m $2 " "$WORK/args.$1" 2>/dev/null || true; }

tmux select-window -t alpha:0
run_switcher '' '' "$(printf 'alpha:2\tx\tx')"
check 'loop: Enter selects the window' '2' "$(tmux display-message -p -t alpha '#{window_index}')"
check 'loop: browsing starts on the calling session' '1' "$(browsed_in 1 alpha)"

tmux select-window -t alpha:0
run_switcher 'serv' 'right' '' '' '' "$(printf 'beta:1\tx\tx')"
check 'loop: right arrow browses the next session' '1' "$(browsed_in 2 beta)"
check 'loop: query carries across sessions' '--query=serv' "$(args_of 2 | grep -- '--query=')"
check 'loop: the new list is the new session' 'beta' \
	"$(tmux display-message -p -t beta '#{session_name}')"

run_switcher '' 'left' '' '' '' "$(printf 'alpha:0\tx\tx')"
check 'loop: left arrow wraps to the last session' '1' "$(browsed_in 2 beta)"

before="$(tmux display-message -p -t alpha '#{window_index}')"
printf '130\n' > "$WORK/rc.1"
PATH="$STUB:$PATH" TEST_DIR="$WORK" TMUX_SPOTLIGHT_SESSION=alpha "$ROOT/scripts/spotlight.sh"
check 'loop: Esc changes nothing' "$before" "$(tmux display-message -p -t alpha '#{window_index}')"

run_switcher '' '' ''
check 'loop: empty selection changes nothing' "$before" "$(tmux display-message -p -t alpha '#{window_index}')"

rm -rf "$STUB"

# --- cross-session switching needs a real client ------------------------------
script -qfc "$BIN/tmux attach -t alpha" /dev/null >/dev/null 2>&1 &
attach_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
	client_tty="$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -1)"
	[ -n "$client_tty" ] && break
	sleep 0.2
done
if [ -n "${client_tty:-}" ]; then
	STUB="$(mktemp -d)"
	# shellcheck disable=SC2016  # $TEST_PICK is expanded by the stub, not here
	printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "%%s\\n" "" "" "$TEST_PICK"\n' > "$STUB/fzf"
	chmod +x "$STUB/fzf"
	PATH="$STUB:$PATH" TEST_PICK="$(printf 'beta:0\tx\tx')" \
		TMUX_SPOTLIGHT_SESSION=alpha TMUX_SPOTLIGHT_CLIENT="$client_tty" \
		"$ROOT/scripts/spotlight.sh"
	check 'picking another session switches the client' 'beta' \
		"$(tmux display-message -p -t "$client_tty" '#{client_session}')"
	rm -rf "$STUB"
else
	printf '  skip cross-session switch test (no client attached)\n'
fi
kill "$attach_pid" 2>/dev/null

# --- fzf missing --------------------------------------------------------------
NOFZF="$(mktemp -d)"
for c in awk sed cut sort tr wc grep bash cat; do
	[ -x "$(command -v "$c")" ] && ln -sf "$(command -v "$c")" "$NOFZF/$c"
done
ln -sf "$BIN/tmux" "$NOFZF/tmux"
out="$(env -i PATH="$NOFZF" HOME="$HOME" TMUX_SPOTLIGHT_SESSION=alpha bash "$ROOT/scripts/spotlight.sh" 2>&1 </dev/null)"
rc=$?
check 'missing fzf exits non-zero' '1' "$rc"
contains 'missing fzf explains why' 'fzf is not on PATH' "$out"
contains 'missing fzf points at the install' 'github.com/junegunn/fzf' "$out"
rm -rf "$NOFZF"

# --- plugin entry point -------------------------------------------------------
"$ROOT/spotlight.tmux"
binding="$(tmux list-keys -T prefix | awk '$2 == "-T" && $4 == "w"')"
contains 'prefix + w opens a popup' 'display-popup' "$binding"
contains 'prefix + w runs the switcher' 'scripts/spotlight.sh' "$binding"
contains 'binding passes the calling session' 'session_name' "$binding"

tmux set-option -g @spotlight-key 'C-w'
"$ROOT/spotlight.tmux"
binding="$(tmux list-keys -T prefix | awk '$2 == "-T" && $4 == "C-w"')"
contains 'custom key is honoured' 'display-popup' "$binding"
tmux set-option -gu @spotlight-key

tmux set-option -g @spotlight-width '42%'
"$ROOT/spotlight.tmux"
binding="$(tmux list-keys -T prefix | awk '$2 == "-T" && $4 == "w"')"
contains 'custom width is honoured' '42%' "$binding"

# --- options ------------------------------------------------------------------
read_option() { bash -c ". '$ROOT/scripts/helpers.sh'; spotlight_option '$1' '$2'"; }
check 'option falls back to default' 'w' "$(read_option @spotlight-key w)"
tmux set-option -g @spotlight-key 'W'
check 'option override wins' 'W' "$(read_option @spotlight-key w)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
