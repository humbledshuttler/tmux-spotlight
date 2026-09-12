# tmux-spotlight

A Spotlight-style window switcher for tmux. `prefix + w` opens a popup that
lists your windows and filters them as you type, with fuzzy matching — instead
of making you walk a tree with the arrow keys.

```
╭───────────────────────── spotlight ─────────────────────────╮
│                   ←  0  · nuks · woot →                     │
│❯ expl                                                       │
│▶    6  explore redesign          ~/repo/my-dot-files        │
╰─────────────────────────────────────────────────────────────╯
```

Typing matches against the window **index** and **name**, so `mlw` finds
`my long window` and `3` jumps to window 3. `Enter` switches, `Esc` closes.

## Sessions

The strip along the top lists every session, with the one you are browsing
highlighted. `←` and `→` move along it and the list below follows, so a query
only ever matches windows in the highlighted session — no nested list to walk.

Your query survives the move, which makes `→` a quick "try the next session"
rather than a fresh start. Picking a window in another session switches you to
that session and window in one step. The strip is hidden when only one session
exists.

Note that `←`/`→` therefore no longer move the cursor within your query;
`Ctrl-b` and `Ctrl-f` still do.

## Requirements

- tmux 3.2 or newer (3.3+ for the rounded border and title)
- [fzf](https://github.com/junegunn/fzf) — 0.42+ gets a tidier match counter,
  older versions work fine

## Install

With [TPM](https://github.com/tmux-plugins/tpm), add to `~/.tmux.conf`:

```tmux
set -g @plugin 'humbledshuttler/tmux-spotlight'
```

then press `prefix + I`.

Without TPM, clone it and run it from `~/.tmux.conf`:

```tmux
run-shell ~/path/to/tmux-spotlight/spotlight.tmux
```

## Layout

The popup is measured before it opens, not set to a percentage of your screen:
it is exactly as tall as the deepest session's window list and as wide as the
longest row, capped at 80% of the client's height and 90% of its width. A
session with three windows gets a small popup; nothing is padded out with empty
rows.

Columns are padded against every window on the server rather than per session,
so moving along the strip does not shuffle the layout underneath you.

## Options

Set any of these in `~/.tmux.conf` *before* the plugin is loaded.

| Option | Default | Description |
| --- | --- | --- |
| `@spotlight-key` | `w` | Key, pressed after the prefix, that opens the switcher. |
| `@spotlight-width` | measured | Popup width, in cells or as a percentage. Overrides the measured width. |
| `@spotlight-height` | measured | Popup height, in cells or as a percentage. Overrides the measured height. |
| `@spotlight-context` | `path` | The dim column after the window name: `path`, `command`, `both`, or `none`. A pane count is appended when a window has more than one pane. |
| `@spotlight-colors` | see below | fzf `--color` spec. The default paints matches cyan and the pointer green, and leaves backgrounds alone so it sits on any theme. |
| `@spotlight-border` | `rounded` | Popup border style (any tmux `popup-border-lines` value). |
| `@spotlight-title` | `` ` spotlight ` `` | Popup title. |
| `@spotlight-preview` | `off` | `on` shows a live preview of the highlighted window's active pane. Costs list width, so it is off by default. |
| `@spotlight-preview-position` | `right:50%` | fzf `--preview-window` position, used when the preview is on. |

Example:

```tmux
set -g @spotlight-key 'Space'
set -g @spotlight-preview 'on'
set -g @plugin 'humbledshuttler/tmux-spotlight'
```

## How it works

`spotlight.tmux` binds your key to `scripts/open.sh`, which measures the
content with `scripts/popup-size.sh` and opens a `display-popup -EE` of exactly
that size running `scripts/spotlight.sh`. The binding goes through a script
because a popup's size is fixed when it opens and tmux formats cannot measure
the longest window name.

`scripts/spotlight.sh` builds a tab-delimited list with
`scripts/list-windows.sh` — `target`, a searchable `index + name` column, and an
unsearchable context column — and pipes it to fzf with `--nth` pointed at the
searchable column, so the pane command and pane count stay visible without
polluting your matches. The pick is turned back into `select-window` (plus
`switch-client` when the window lives in another session).

Session switching is a loop rather than an fzf `reload` binding: `--expect`
reports `left`/`right`, and the script relaunches fzf for the newly browsed
session, carrying the query over with `--query` and redrawing the strip from
`scripts/session-strip.sh`. It costs a redraw per keypress, but it works on any
fzf new enough to have `--expect` instead of requiring a recent `transform-header`.

Two small details keep the layout honest: `--tabstop=1` makes the field
delimiter render as exactly one space, so a row's width on screen is the width
that was measured, and `--no-separator` reclaims the row newer fzf rules off
under the prompt.

A popup pane belongs to no session, so the key binding passes the calling
session and client to the script as `TMUX_SPOTLIGHT_SESSION` and
`TMUX_SPOTLIGHT_CLIENT`.

## Tests

```sh
tests/run.sh
```

The suite starts a throwaway tmux server on its own socket with
`-f /dev/null`, so it never touches your sessions or your config. Fuzzy-matching
tests are skipped when fzf is not on `PATH`. The switcher loop is driven through
a stub fzf that replays canned responses and records the arguments it was
given, so session cycling, query carry-over and selection are all covered
without a terminal.

## License

MIT
