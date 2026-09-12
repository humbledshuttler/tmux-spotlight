#!/usr/bin/env bash
# Smoke tests for tmux-spotlight. Runs a throwaway tmux server on its own
# socket and puts a `tmux` wrapper pinned to that socket on PATH, so the tests
# never touch the user's real sessions.
set -u

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_TMUX="$(command -v tmux)"
SOCKET="spotlight-test-$$"
BIN="$(mktemp -d)"

pass=0
fail=0

cleanup() {
	"$REAL_TMUX" -L "$SOCKET" kill-server 2>/dev/null
	rm -rf "$BIN"
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

strip_ansi() { sed $'s/\033\\[[0-9;]*m//g'; }
field() { cut -f"$1"; }

echo "tmux-spotlight tests ($(tmux -V), socket $SOCKET)"

tmux new-session -d -s alpha -n editor
tmux new-window -t alpha -n server
tmux new-window -t alpha -n 'my long window'
tmux new-session -d -s beta -n notes
tmux select-window -t alpha:1

# --- session scope ------------------------------------------------------------
out="$("$ROOT/scripts/list-windows.sh" session alpha)"
check 'session scope: one line per window' '3' "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
check 'session scope: targets' 'alpha:0 alpha:1 alpha:2' \
	"$(printf '%s\n' "$out" | field 1 | tr '\n' ' ' | sed 's/ $//')"
check 'session scope: other sessions excluded' '' "$(printf '%s\n' "$out" | field 1 | grep beta)"
contains 'session scope: window name is searchable' 'my long window' \
	"$(printf '%s\n' "$out" | field 2 | strip_ansi | tr '\n' '|')"
contains 'session scope: window index is searchable' '2' \
	"$(printf '%s\n' "$out" | sed -n 3p | field 2 | strip_ansi)"
contains 'session scope: active window marked' '*' \
	"$(printf '%s\n' "$out" | sed -n 2p | field 2 | strip_ansi)"
check 'session scope: inactive windows unmarked' '' \
	"$(printf '%s\n' "$out" | sed -n 1p | field 2 | strip_ansi | grep '\*')"
check 'session scope: searchable column is padded to one width' '1' \
	"$(printf '%s\n' "$out" | field 2 | strip_ansi | awk '{print length($0)}' | sort -u | wc -l | tr -d ' ')"
contains 'session scope: context shows pane count' '1 pane' \
	"$(printf '%s\n' "$out" | sed -n 1p | field 3 | strip_ansi)"

tmux split-window -t alpha:0
contains 'context pluralises pane count' '2 panes' \
	"$("$ROOT/scripts/list-windows.sh" session alpha | sed -n 1p | field 3 | strip_ansi)"

# --- server scope -------------------------------------------------------------
out="$("$ROOT/scripts/list-windows.sh" server)"
check 'server scope: every window listed' '4' "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
contains 'server scope: other session included' 'beta:0' "$(printf '%s\n' "$out" | field 1 | tr '\n' ' ')"
contains 'server scope: session name is searchable' 'beta' \
	"$(printf '%s\n' "$out" | grep '^beta' | field 2 | strip_ansi)"

# --- options ------------------------------------------------------------------
read_option() { bash -c ". '$ROOT/scripts/helpers.sh'; spotlight_option '$1' '$2'"; }
check 'option falls back to default' 'w' "$(read_option @spotlight-key w)"
tmux set-option -g @spotlight-key 'W'
check 'option override wins' 'W' "$(read_option @spotlight-key w)"
tmux set-option -gu @spotlight-key

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

# --- fuzzy matching (needs a real fzf) ----------------------------------------
if command -v fzf >/dev/null 2>&1; then
	filter() {
		"$ROOT/scripts/list-windows.sh" session alpha \
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

# --- selection switches windows ------------------------------------------------
STUB="$(mktemp -d)"
# shellcheck disable=SC2016  # $TEST_PICK is expanded by the stub, not here
printf '#!/usr/bin/env bash\ncat >/dev/null\nprintf "%%s\\n" "$TEST_PICK"\n' > "$STUB/fzf"
chmod +x "$STUB/fzf"

pick() { PATH="$STUB:$PATH" TEST_PICK="$1" TMUX_SPOTLIGHT_SESSION=alpha "$ROOT/scripts/spotlight.sh"; }

tmux select-window -t alpha:0
pick "$(printf 'alpha:2\tignored\tignored')"
check 'picking a window selects it' '2' "$(tmux display-message -p -t alpha '#{window_index}')"

pick "$(printf 'alpha:1\tignored\tignored')"
check 'picking another window selects it' '1' "$(tmux display-message -p -t alpha '#{window_index}')"

before="$(tmux display-message -p -t alpha '#{window_index}')"
PATH="$STUB:$PATH" TEST_PICK='' TMUX_SPOTLIGHT_SESSION=alpha "$ROOT/scripts/spotlight.sh"
check 'empty selection changes nothing' "$before" "$(tmux display-message -p -t alpha '#{window_index}')"

# A cross-session pick needs a real client to switch, so attach one on a pty.
script -qfc "$BIN/tmux attach -t alpha" /dev/null >/dev/null 2>&1 &
attach_pid=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do
	client_tty="$(tmux list-clients -F '#{client_tty}' 2>/dev/null | head -1)"
	[ -n "$client_tty" ] && break
	sleep 0.2
done
if [ -n "$client_tty" ]; then
	PATH="$STUB:$PATH" TEST_PICK="$(printf 'beta:0\tignored\tignored')" \
		TMUX_SPOTLIGHT_SESSION=alpha TMUX_SPOTLIGHT_CLIENT="$client_tty" \
		"$ROOT/scripts/spotlight.sh"
	check 'picking another session switches the client' 'beta' \
		"$(tmux display-message -p -t "$client_tty" '#{client_session}')"
else
	printf '  skip cross-session switch test (no client attached)\n'
fi
kill "$attach_pid" 2>/dev/null
rm -rf "$STUB"

# --- fzf missing --------------------------------------------------------------
NOFZF="$(mktemp -d)"
for c in tmux awk sed cut sort tr wc grep bash cat; do
	[ -x "$(command -v "$c")" ] && ln -sf "$(command -v "$c")" "$NOFZF/$c"
done
ln -sf "$BIN/tmux" "$NOFZF/tmux"
out="$(env -i PATH="$NOFZF" HOME="$HOME" TMUX_SPOTLIGHT_SESSION=alpha bash "$ROOT/scripts/spotlight.sh" 2>&1 </dev/null)"
rc=$?
check 'missing fzf exits non-zero' '1' "$rc"
contains 'missing fzf explains why' 'fzf is not on PATH' "$out"
contains 'missing fzf points at the install' 'github.com/junegunn/fzf' "$out"
rm -rf "$NOFZF"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
