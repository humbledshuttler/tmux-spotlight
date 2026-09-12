# tmux-spotlight

A Spotlight-style window switcher for tmux. `prefix + w` opens a popup that
lists your windows and filters them as you type, with fuzzy matching — instead
of making you walk a tree with the arrow keys.

```
╭────────────────────── spotlight ─────────────────────╮
│  windows: alpha                                      │
│❯ ser                                                 │
│▶   1  server             zsh  1 pane                 │
╰──────────────────────────────────────────────────────╯
```

Typing matches against the window **index** and **name**, so `mlw` finds
`my long window` and `3` jumps to window 3. `Enter` switches, `Esc` closes.

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
| `@spotlight-scope` | `session` | `session` lists the current session's windows; `server` lists every window of every session and switches sessions as needed. |
| `@spotlight-width` | `70%` | Popup width. |
| `@spotlight-height` | `60%` | Popup height. |
| `@spotlight-border` | `rounded` | Popup border style (any tmux `popup-border-lines` value). |
| `@spotlight-title` | `` ` spotlight ` `` | Popup title. |
| `@spotlight-preview` | `off` | `on` shows a live preview of the highlighted window's active pane. Costs list width, so it is off by default. |
| `@spotlight-preview-position` | `right:50%` | fzf `--preview-window` position, used when the preview is on. |

Example:

```tmux
set -g @spotlight-key 'Space'
set -g @spotlight-scope 'server'
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

A popup pane belongs to no session, so the key binding passes the calling
session and client to the script as `TMUX_SPOTLIGHT_SESSION` and
`TMUX_SPOTLIGHT_CLIENT`.

## Tests

```sh
tests/run.sh
```

The suite starts a throwaway tmux server on its own socket with
`-f /dev/null`, so it never touches your sessions or your config. Fuzzy-matching
tests are skipped when fzf is not on `PATH`.

## License

MIT
