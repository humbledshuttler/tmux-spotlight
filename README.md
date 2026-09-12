# tmux-spotlight

A Spotlight-style window switcher for tmux. `prefix + w` opens a popup that
lists your windows and filters them as you type, with fuzzy matching — instead
of making you walk a tree with the arrow keys.

```
╭────────────────────── spotlight ─────────────────────╮
│  ← alpha ·  beta  · gamma →                          │
│❯ bui                                                 │
│▶ * 1  build              zsh  1 pane                 │
╰──────────────────────────────────────────────────────╯
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
- [fzf](https://github.com/junegunn/fzf)

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

## Options

Set any of these in `~/.tmux.conf` *before* the plugin is loaded.

| Option | Default | Description |
| --- | --- | --- |
| `@spotlight-key` | `w` | Key, pressed after the prefix, that opens the switcher. |
| `@spotlight-width` | `70%` | Popup width. |
| `@spotlight-height` | `60%` | Popup height. |
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

`spotlight.tmux` binds your key to `display-popup -EE` running
`scripts/spotlight.sh`. That script builds a tab-delimited list with
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
