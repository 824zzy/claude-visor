<div align="center">
  <img src="icon.png" alt="Claude Visor" width="128" height="128">
  <h1>Claude Visor</h1>
  <p><strong>Your Claude sessions, always in sight.</strong></p>
  <p>
    A macOS notch overlay for managing multiple Claude Code sessions at a glance.
    <br />
    <br />
    <a href="#build"><img src="https://img.shields.io/badge/macOS-15.6+-black?logo=apple&logoColor=white" alt="macOS 15.6+" /></a>
    <a href="#license"><img src="https://img.shields.io/badge/license-Apache%202.0-blue" alt="License" /></a>
    <a href="https://github.com/824zzy/claude-visor/stargazers"><img src="https://img.shields.io/github/stars/824zzy/claude-visor?style=social" alt="Stars" /></a>
  </p>
</div>

---

> Forked from [Claude Island](https://github.com/farouqaldori/claude-island) with significant enhancements for multi-session workflows.

## Overview

<div align="center">
  <img src="screenshots/menubar-overview.png" alt="Claude Visor menu bar" width="100%" />
  <p><em>Status dots + aggregate summary on the left, live tool activity on the right</em></p>
</div>

## What's Different from Claude Island

Claude Visor adds persistent menu bar content that shows session status and tool activity alongside the notch, designed for power users running 6+ concurrent Claude Code sessions.

**New features:**
- **Persistent notch** -- Stays visible in all states instead of hiding when idle
- **Left side content** -- Status dots with color-coded phase indicators + aggregate summary (e.g., "2 active, 1 pending")
- **Right side content** -- Live tool activity for the highest-priority session (e.g., "Edit auth.ts", "Asking: Which approach?")
- **Dynamic safe widths** -- Content adapts to available menu bar space by detecting app menu and status icon positions via CGWindowList
- **Smart project names** -- Tracks the latest working directory from JSONL messages instead of using the initial cwd
- **Session deduplication** -- Cleans up ghost sessions from /resume, PID reuse, and dead processes
- **External monitor support** -- Notch pill scales to the actual menu bar height instead of using hardcoded dimensions
- **Enriched tool display** -- Extracts domains from URLs, actual question text from AskUserQuestion, and strips redundant prefixes

## Requirements

- macOS 15.6+
- Claude Code CLI
- Xcode (for building from source)

## Build

```bash
xcodebuild -scheme ClaudeVisor -configuration Debug build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# The built app is at:
# ~/Library/Developer/Xcode/DerivedData/ClaudeVisor-*/Build/Products/Debug/Claude Visor.app
```

## How It Works

Claude Visor installs hooks into `~/.claude/hooks/` that communicate session state via a Unix socket. The app listens for events and renders:

1. A notch pill overlay (crab icon + spinner/checkmark) centered at the top of the screen
2. Left side content: colored dots per session + aggregate status summary
3. Right side content: current tool activity for the most important session

The left/right content sits in the visible menu bar areas flanking the hardware notch (on MacBook) or the compact pill (on external monitors). Content width dynamically adjusts based on actual menu bar item positions.

### Session Lifecycle

- Sessions are discovered via hook events from Claude Code
- Stale sessions are pruned every 10 seconds (dead PIDs, duplicate PIDs from /resume)
- The latest working directory is tracked from JSONL messages for accurate project naming

## Permissions

- **Accessibility** -- Required for window interaction (System Settings > Privacy > Accessibility)

## Credits

Forked from [Claude Island](https://github.com/farouqaldori/claude-island) by [@farouqaldori](https://github.com/farouqaldori). Original project licensed under Apache 2.0.

## License

Apache 2.0
