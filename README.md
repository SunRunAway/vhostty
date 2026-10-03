<p align="center"><img src="docs/icon.png" width="128" alt="Vhostty icon"></p>

<h1 align="center">Vhostty</h1>

<p align="center"><b>A vertical-tab terminal built for Claude Code</b></p>

<p align="center">English · <a href="README.zh-CN.md">简体中文</a></p>

Vhostty is a native macOS terminal for running several Claude Code sessions at once. Each session is a card in the left sidebar, and the card shows Claude's state (working / waiting for permission / waiting for input / done), the current branch, the worktree and the PR, so you don't have to switch to each one to check on it.

The terminal engine is [Ghostty](https://ghostty.org) (libghostty), and it uses your existing Ghostty config. The app shell is written in SwiftUI/AppKit, with no web technology involved.

> Vhostty = **V**ertical + G**hostty**: Ghostty's tabs, turned on their side and moved into a sidebar.

<p align="center"><img src="docs/screenshot.png" alt="Vhostty with two projects: session cards showing status, branch, worktree and PR"></p>

The interface follows your system language (English or Simplified Chinese).

## Features

- **Projects on the left**: each project is bound to a directory.
- **Session cards under each project**: each session is one Claude Code terminal. A card has 4 lines:
  1. The session title, from Claude's auto-generated title or `/rename`, with a status icon in front
  2. The current branch
  3. The worktree name, or 「主工作区」 (main worktree) when not in a worktree
  4. The PR number, e.g. `#123`, colored by state: open green / merged purple / closed red. Click it to open the PR in your browser
- **New session**: `cd`s into the project directory and starts `claude`. When claude exits, the terminal stays in your shell.
- **Live status**:
  - Spinner = Claude is working
  - ✋ = waiting for you to approve a permission
  - Green dot = waiting for your input
  - Blue dot = finished in the background and you haven't looked yet
  - Hollow circle = not started
- **Background notifications**: these are Claude Code's own terminal notifications (it sends OSC 9/777 once it detects Ghostty), so your notification settings in Claude are respected. When the session isn't selected or the window is in the background, Vhostty turns them into macOS system notifications; clicking one jumps to that session. Claude usually only notifies after finishing and waiting about 60 seconds for you, but the blue dot on the card and the Dock badge update immediately (via hooks).
- **Session history**: each project lists its recent Claude sessions; click one to resume it with `claude --resume`.
- **Autosave**: all session cards are saved on quit. On next launch a session is only restored when you click its card, so you don't get a pile of claude processes starting at once.
- **Bottom shell**: every session can pull up a plain shell below Claude (⌘J or ⌃`), in the same directory Claude is currently in. The divider between the two is draggable, and whether the panel is open is saved with the session.
- **Reuses your Ghostty config**: reads your Ghostty config (fonts, theme, keybindings) from `~/.config/ghostty/config` or `~/Library/Application Support/com.mitchellh.ghostty/config`.

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| ⌘T | New Claude session in the current project |
| ⇧⌘O | Add project |
| ⌘W | Close the current session (asks first if Claude is still running) |
| ⌘1…9 | Switch to the Nth session |
| ⇧⌘[ / ⇧⌘] | Previous / next session |
| ⌃⌘S | Show/hide the sidebar |
| ⌘J / ⌃` | Show/hide the bottom shell |
| ⌥⌘↑ / ⌥⌘↓ | Focus Claude / focus the bottom shell |
| ⌘+ / ⌘- / ⌘0 | Increase / decrease / reset font size |

Right-click a session card or a project for more actions. Session cards can also be dragged to reorder.

## Building

You only need the Command Line Tools and zig; **Xcode is not required**.

```bash
brew install zig          # needs 0.15.2 (required by Ghostty 1.3.1)
git clone --recursive https://github.com/SunRunAway/vhostty.git
cd vhostty
make                      # the first build compiles libghostty, about 5 minutes
make install              # copies to /Applications/Vhostty.app
```

## Development

How it works, how the build avoids Xcode, and how to debug are covered in [DEVELOPER.md](DEVELOPER.md) (in Chinese).
