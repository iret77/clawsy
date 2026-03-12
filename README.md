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

The easiest way to set up Clawsy:

1. **Download & install** Clawsy on your Mac ([latest release](https://github.com/iret77/clawsy/releases/latest))
2. **Tell your OpenClaw agent:**

   > "Install the Clawsy skill from clawhub"

3. Your agent will install everything automatically and send you a pairing link — just click it.

**That's it.** Clawsy connects, your agent gets access to screenshots, clipboard, camera, and files.

---

## Manual Setup (Advanced)

If you prefer to configure everything yourself, follow the steps below.

### 1. Prepare your OpenClaw Gateway

Make sure your OpenClaw instance is running and you have the **Gateway Host**, **Port** (default: `18789`), and **Token** ready.

> 💡 For detailed server-side configuration, see [docs/SERVER_SETUP.md](docs/SERVER_SETUP.md).

### 2. Install Clawsy on your Mac

1. Download **Clawsy.app.zip** from the [latest release](https://github.com/iret77/clawsy/releases/latest)
2. Unzip → drag `Clawsy.app` to `/Applications`
3. Launch Clawsy — the onboarding assistant walks you through permissions

### 3. Connect

4. Open **Settings** → enter your OpenClaw **Gateway Host**, **Port**, and **Token**
5. Clawsy connects and sends a pairing request. **Approve it on your server:**
   ```bash
   # List pending pairing requests
   openclaw devices list

   # Approve (use the request ID shown)
   openclaw devices approve <requestId>
   ```

### 4. Tell your agent

6. Copy-paste this into your chat or add it to your `AGENTS.md`:
   ```
   Clawsy (macOS companion app) is installed and connected.
   Read the Clawsy skill file for full integration details.
   Add to HEARTBEAT.md:
   - Send agent.info to clawsy-service every heartbeat
   - Send agent.status for active tasks
   See: https://github.com/iret77/clawsy/blob/main/for-agents.md
   ```

7. **Done.** Your agent can now take screenshots, read your clipboard, access files, and show live task progress.

---

## Server Setup (OpenClaw Side)

Clawsy is a client — it connects to your OpenClaw Gateway. Your agent needs to know Clawsy exists and how to use it.

### Event Cache (clawsy-monitor)

Clawsy pushes events (clipboard, screenshots, shares) to a `clawsy-service` session. The **clawsy-monitor** watches this session and caches events into a structured `clawsy-context.json` in your workspace so agents can read them efficiently.

#### Automatic Setup

```bash
cd server
./setup.sh
```

This installs `clawsy-monitor` as a systemd service that watches for Clawsy events and caches them in `clawsy-context.json` in your workspace. The setup is fully portable — all paths are auto-detected.

#### Manual Setup

If you don't have systemd, run the monitor directly:

```bash
node server/monitor.mjs
```

#### Environment Variables

| Variable | Default | Description |
|---|---|---|
| `OPENCLAW_HOME` | `~/.openclaw` | OpenClaw home directory |
| `OPENCLAW_AGENT` | `main` | Agent ID |
| `OPENCLAW_WORKSPACE` | `$OPENCLAW_HOME/workspace` | Workspace directory |

### What the Agent Needs

After Clawsy connects, your agent should:

1. **Send `agent.info`** on every heartbeat (shows model name in Clawsy header)
2. **Send `agent.status`** during active work (shows live progress in Mission Control)
3. **Read from `clawsy-service`** session to receive screenshots, clipboard, and camera events

### HEARTBEAT.md Snippet

Add this to your agent's `HEARTBEAT.md`:

```markdown
## Clawsy (every heartbeat)
Send agent.info + agent.status to clawsy-service:
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.info","payload":{"agentName":"<NAME>","model":"<MODEL>","updatedAt":"<ISO-UTC>"}}')
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.status","payload":{"agentName":"<NAME>","title":"Idle","progress":0.0,"statusText":"Waiting"}}')
```

### For Agents Reading This

If you are an OpenClaw agent, read [for-agents.md](for-agents.md) — it has everything you need: exact code, data formats, and integration patterns.

> Full server setup guide: [docs/SERVER_SETUP.md](docs/SERVER_SETUP.md)

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

> For complete agent integration docs, see [for-agents.md](for-agents.md) and [CLAWSY.md](CLAWSY.md).

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
