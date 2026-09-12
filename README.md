# tmux-spotlight

A Spotlight-style window switcher for tmux. `prefix + w` opens a popup that
lists your windows and filters them as you type, with fuzzy matching — instead
of making you walk a tree with the arrow keys.

```
╭───────────────────────── spotlight ─────────────────────────╮
│                                                             │
│                   ←  0  · nuks · woot →                     │
│                                                             │
│  ❯ expl                                               1/13  │
│  ─────────────────────────────────────────────────────────  │
│  ▶    6   explore redesign        ~/repo/share              │
│                                                             │
╰─────────────────────────────────────────────────────────────╯
```

Typing matches against the window **index** and **name**, so `mlw` finds
`my long window` and `3` jumps to window 3. `Enter` switches, `Esc` closes.

The query sits in a field of its own — a blank line above it, a rule below —
so it reads as somewhere to type rather than another row of the list.

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
it is as tall as the deepest session's window list plus a few empty slots and
the chrome around it (border, query field, rule, strip, padding), and as wide as
the longest row, capped at 80% of the *attached client's* height and 90% of its
width. A session with three windows gets a small popup rather than a screenful
of blank rows.

Columns are padded against every window on the server rather than per session,
so moving along the strip does not shuffle the layout underneath you — index,
name, path and pane count each line up, and pane counts sit right-aligned in a
column of their own instead of trailing each path at a different place.

The list is inset by a row and two columns where fzf supports `--padding`, and
the measured size accounts for it: a list packed against the border is hard to
read however well its columns line up.

## Options

Set any of these in `~/.tmux.conf` *before* the plugin is loaded.

| Option | Default | Description |
| --- | --- | --- |
| `@spotlight-key` | `w` | Key, pressed after the prefix, that opens the switcher. |
| `@spotlight-width` | measured | Popup width, in cells or as a percentage. Overrides the measured width. |
| `@spotlight-height` | measured | Popup height, in cells or as a percentage. Overrides the measured height. |
| `@spotlight-extra-rows` | `4` | Empty list rows kept below the last window, so the list is not wedged against its own last row. `0` fits it exactly. |
| `@spotlight-context` | `path` | The dim column after the window name: `path`, `command`, `both`, or `none`. A pane count is appended when a window has more than one pane. |
| `@spotlight-colors` | see below | fzf `--color` spec. The default paints matches cyan, the pointer green, and reverses the row under the cursor, which contrasts by construction on any palette. For a subtler bar instead: `bg+:8,fg+:-1:bold,…`. |
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

The whole plugin is one file, `spotlight.tmux`, which takes three roles from
its first argument: no argument binds the key (what TPM runs), `open` measures
and opens the popup, `run` is the switcher inside it. A popup's size is fixed
when it opens and tmux formats cannot measure the longest window name, so the
key runs `open` rather than `display-popup` directly. A popup pane belongs to
no session, so the calling session and client are passed down both times.

The list is tab-delimited — `target`, a searchable `index + name` column, and
an unsearchable context column — and fzf's `--nth` points at the searchable
one, so the path and pane count stay visible without polluting your matches.
The pick is turned back into `select-window`, plus `switch-client` when the
window lives in another session.

Session switching is a loop rather than an fzf `reload` binding: `--expect`
reports `left`/`right`, and the script relaunches fzf for the newly browsed
session, carrying the query over with `--query`. It costs a redraw per
keypress, but works on any fzf with `--expect` instead of needing a recent
enough one for `transform-header`.

Secondary columns are dimmed with the faint *attribute* rather than a grey
colour, and a row never emits a full reset. Both matter for the highlight: fzf
styles the current row by opening an escape before the line, so a `\033[0m` in
the content closes it halfway through, and a hardcoded grey survives onto the
highlight and disappears into it. `--tabstop=1` makes the field delimiter
render as exactly one space, so a row's measured width is its width on screen.

## Tests

```sh
tests/run.sh
```

The suite sources `spotlight.tmux` and calls its functions directly — the
guard at the foot of the file is what lets it be sourced without running — and
drives a throwaway tmux server on its own socket with `-f /dev/null`, so it
never touches your sessions or your config. The switcher loop runs against a
stub fzf that replays canned replies; the sizing tests attach two clients of
sizes they choose, each inside its own outer tmux. Tests needing a real fzf
skip when it is not on `PATH`.

## License

MIT
