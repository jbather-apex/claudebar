# ClaudeBar

macOS menu bar app that shows running Claude Code sessions and flags any that
are waiting on a permission approval or user input.

- **Menu bar icon**: `sparkles` when sessions are running, `moon.zzz` when none,
  `exclamationmark.bubble` + count when any session needs attention.
- **Popover**: per-session title (AI-generated from the transcript), cwd, state
  pill, permission message, and a live "waiting …" timer.
- **Notifications**: native macOS notification the moment a session hits a
  permission prompt or is waiting for input.
- **Click a row / notification**: focuses the iTerm2 or Terminal.app tab running
  that session (matched by tty; best-effort, tmux panes not supported).

## Install

Requires macOS 14+ and the Xcode Command Line Tools (`xcode-select --install`).

```sh
git clone https://github.com/jbather-apex/claudebar.git
cd claudebar
./scripts/install.sh   # builds and installs to /Applications, then launches
```

Building locally means no Gatekeeper/quarantine friction — there's nothing to
right-click-open or notarize. To update, `git pull` and rerun the script.
Turn on **Launch at login** from the popover footer.

## Build & run (development)

```sh
./scripts/make-app.sh
open dist/ClaudeBar.app
```

A real `.app` bundle is required for notifications and launch-at-login;
`swift run` works for UI iteration but disables both.

## How it works

Two data sources reconciled into one session list:

1. **Poll (every 2 s)** — `~/.claude/sessions/<pid>.json`, small per-process
   state files the CLI keeps updated (`sessionId`, `cwd`, `name`, `status`,
   timestamps). Files whose PID is dead are ignored, so killed sessions
   disappear even when no SessionEnd hook fired. Older CLIs omit `status`.
2. **Push (instant)** — hook entries in `~/.claude/settings.json` append each
   hook payload (tagged with `cb_kind` + `cb_ts` via `jq`) to
   `~/Library/Application Support/ClaudeBar/events.jsonl`, which the app tails:
   - `Notification` (`permission_prompt`) → needs permission
   - `Notification` (`idle_prompt|agent_needs_input|elicitation_dialog`) → needs input
   - `Stop` → idle, `SessionStart`/`SessionEnd` → lifecycle

Hooks are optional (polling alone still lists sessions) and are installed from
the popover footer: **Install hooks…** merges the entries into
`~/.claude/settings.json`, preserving everything else and backing up to
`settings.json.claudebar-bak` first. Hooks apply to sessions started afterwards.

## Permissions

- **Notifications** — prompted on first launch.
- **Automation** (control iTerm2/Terminal) — prompted on first jump-to-terminal.
