<h1 align="center">Clawsy</h1>

<p align="center">
  <strong>Your AI agent, fully wired into your Mac.</strong><br>
  A native menu bar app that gives <a href="https://github.com/openclaw/openclaw">OpenClaw</a> agents real-world reach — screen, clipboard, camera, files — while keeping you in control.
</p>

<p align="center">
  <img src="https://img.shields.io/github/v/release/iret77/clawsy?label=version&color=blue" alt="Version"/>
  <img src="https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey" alt="Platform"/>
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License"/>
  <img src="https://github.com/iret77/clawsy/actions/workflows/build.yml/badge.svg" alt="Build"/>
</p>

<p align="center">
  <img src="docs/screenshots/00-hero.png" width="100%" alt="Clawsy — menu bar app on macOS desktop"/>
</p>

---

## What It Does

Clawsy sits in your menu bar and acts as a secure bridge between your Mac and your OpenClaw agent. Your agent can see your screen, read your clipboard, manage files, and track its own tasks — all with your explicit approval.

Nothing happens behind your back. Every screenshot, clipboard read, or file write requires your permission.

---

## Requirements

- **macOS 14+** (Sonoma / Sequoia), Apple Silicon or Intel
- **OpenClaw instance** — running and accessible from your Mac ([github.com/openclaw/openclaw](https://github.com/openclaw/openclaw))

---

## Getting Started

### Recommended: Let Your Agent Handle It

Send this to your OpenClaw agent:

> **Install the Clawsy macOS companion: `clawhub install clawsy` — then read the SKILL.md and follow the IMMEDIATE ACTION section.**

Your agent installs the skill, reads the setup instructions, and sends you the download link and setup code in one message.

---

### Already Have Clawsy Installed?

If you downloaded Clawsy separately:

1. Launch Clawsy and click **Add Host**
2. A setup prompt is copied to your clipboard automatically
3. Send the prompt to your agent via any channel (chat, Telegram, Slack, ...)
4. Your agent responds with a setup code — paste it back into Clawsy

Done. Clawsy connects, and the agent receives the full skill reference automatically.

---

### Manual Setup (Advanced)

For full manual control over every setting:

1. Download **Clawsy.app.zip** from the [latest release](https://github.com/iret77/clawsy/releases/latest)
2. Unzip, drag to `/Applications`, remove quarantine:
   ```bash
   xattr -cr /Applications/Clawsy.app
   ```
3. Launch Clawsy — the onboarding assistant walks you through permissions
4. Open **Settings** → enter **Gateway Host**, **Port** (`18789`), and **Token**
5. Approve the pairing request on your server:
   ```bash
   openclaw devices list
   openclaw devices approve <requestId>
   ```

The agent receives the full skill reference automatically after connection.

---

## Multi-Host Support

Clawsy can connect to **multiple OpenClaw gateways simultaneously**. Each host gets:

- Its own connection, token, and device pairing
- A color-coded label in the host switcher bar
- An isolated shared folder (no cross-contamination)
- Independent Mission Control task tracking

**To add a host:** Click the **+** button in the Clawsy header or go to Settings → Add Host.

Use this when you run separate OpenClaw instances (e.g., work vs. personal, dev vs. prod).

---

## Features at a Glance

| Feature | Description |
|---|---|
| **Screenshot & Camera** | Full-screen or area screenshots, camera snap with preview |
| **Clipboard Sync** | Push/pull clipboard content between Mac and agent |
| **File Sync** | Shared folder with bidirectional file transfer |
| **FinderSync Extension** | Right-click folders in Finder to configure `.clawsy` rules |
| **Share Extension** | Share from any app directly to your agent |
| **Mission Control** | Real-time task view of your agent's activity |
| **Multi-Host** | Connect to multiple OpenClaw gateways with color-coded switching |
| **Auto-Update** | Background update checks with one-click install |
| **SSH Tunnel Fallback** | Automatic encrypted tunnel when direct connection fails |
| **Quick Send** | Global hotkey (`⌘⇧K`) to message your agent from anywhere |
| **.clawsy Rules** | File-event automation with glob matching and agent/notify actions |

---

## Key Features

### ⚡ Quick Send

A global hotkey (`⌘⇧K`) opens a floating panel anywhere on your Mac. Type a message to your agent without switching apps.

<p align="center">
  <img src="docs/screenshots/06-quicksend.png" width="480" alt="Quick Send panel"/>
</p>

### 📋 Clipboard, Screen & Camera

Push your clipboard to the agent silently. Let the agent request a screenshot or camera frame. Every request goes through a permission dialog — allow once, for an hour, or deny.

### 📁 Shared Folder & Automation Rules

A local folder syncs with your agent's workspace. Drop a `.clawsy` rule file into any subfolder to define triggers — *"when a PDF is added, summarize it"*. Right-click any folder in Finder to configure rules via the **FinderSync Extension**.

### 🔗 Share Extension

Share files, text, or URLs from any macOS app directly to your agent via the system Share menu.

### 📊 Mission Control

See what your agent is doing, in real time.

<p align="center">
  <img src="docs/screenshots/04-missioncontrol.png" width="340" alt="Mission Control — live task view"/>
</p>

Agents push task status via WebSocket. Clawsy shows progress bars, task names, and status text instantly.

### 🔒 SSH Tunnel Fallback

Can't reach your gateway directly? Clawsy automatically falls back to an SSH tunnel — encrypted, zero-config if you have `~/.ssh` keys set up.

### 🔒 You Stay in Control

Every file write, screenshot, or clipboard read requires your approval.

<p align="center">
  <img src="docs/screenshots/05-filesync.png" width="380" alt="File sync permission dialog"/>
</p>

---

## Settings

Open the Clawsy menu → **Settings**:

<p align="center">
  <img src="docs/screenshots/02-settings.png" width="380" alt="Settings"/>
</p>

| Setting | Description |
|---|---|
| **Gateway Host** | Your OpenClaw server hostname or IP |
| **Gateway Port** | Default: `18789` |
| **Token** | Your OpenClaw auth token |
| **SSH Fallback** | Auto-tunnels via SSH if direct connection fails |
| **Shared Folder** | Local folder synced with your agent (default: `~/Documents/Clawsy`) |

---

## Agent Integration

Once paired, your agent uses the `nodes` tool to interact with Clawsy:

```python
# Take a screenshot
nodes(action="invoke", invokeCommand="screen.capture")

# Read the clipboard
nodes(action="invoke", invokeCommand="clipboard.read")

# Write to clipboard
nodes(action="invoke", invokeCommand="clipboard.write",
      invokeParamsJson='{"text": "Hello from your agent"}')

# Camera snap
nodes(action="invoke", invokeCommand="camera.snap",
      invokeParamsJson='{"facing": "front"}')

# List files in shared folder
nodes(action="invoke", invokeCommand="file.list",
      invokeParamsJson='{"path": "."}')

# Read a file
nodes(action="invoke", invokeCommand="file.get",
      invokeParamsJson='{"name": "report.pdf"}')

# Write a file
nodes(action="invoke", invokeCommand="file.set",
      invokeParamsJson='{"name": "notes.txt", "content": "<base64>"}')

# Move, copy, rename files
nodes(action="invoke", invokeCommand="file.move",
      invokeParamsJson='{"source": "old.txt", "destination": "new.txt"}')
nodes(action="invoke", invokeCommand="file.copy",
      invokeParamsJson='{"source": "a.txt", "destination": "b.txt"}')
nodes(action="invoke", invokeCommand="file.rename",
      invokeParamsJson='{"path": "old-name.txt", "newName": "new-name.txt"}')

# File info and batch operations
nodes(action="invoke", invokeCommand="file.stat",
      invokeParamsJson='{"path": "report.pdf"}')
nodes(action="invoke", invokeCommand="file.exists",
      invokeParamsJson='{"path": "report.pdf"}')
nodes(action="invoke", invokeCommand="file.batch",
      invokeParamsJson='{"ops": [{"op": "copy", "source": "a.txt", "destination": "b.txt"}]}')
```

Available commands: `screen.capture`, `clipboard.read`, `clipboard.write`, `camera.list`, `camera.snap`, `file.list`, `file.get`, `file.set`, `file.get.chunk`, `file.set.chunk`, `file.move`, `file.copy`, `file.rename`, `file.stat`, `file.exists`, `file.batch`, `file.delete`, `file.rmdir`, `file.mkdir`, `location.get`

> Full command reference and agent integration: [SKILL.md](SKILL.md)

---

## Build from Source

```bash
git clone https://github.com/iret77/clawsy.git
cd clawsy
./build.sh
# → Clawsy.app lands in .build/app/
```

Requires Swift 5.9+ (Xcode Command Line Tools). CI builds run automatically on every tagged release via GitHub Actions.

---

## License

MIT — see [LICENSE](LICENSE).
