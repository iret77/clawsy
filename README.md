# 🦞 Clawsy

**The secure bridge between your Mac and your OpenClaw agents.**

Clawsy is a native macOS menu bar app that gives your [OpenClaw](https://github.com/openclaw/openclaw) AI agent real-world reach — screenshots, clipboard, camera, files, and more — while keeping you in full control through transparent permission dialogs.

![Version](https://img.shields.io/badge/version-0.4.33-blue)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)
![Build](https://github.com/iret77/clawsy/actions/workflows/build.yml/badge.svg)

---

## 📷 Screenshots

<p align="center">
  <img src="docs/screenshots/01-popover.png" width="240" alt="Main menu"/>
  <img src="docs/screenshots/02-settings.png" width="420" alt="Settings"/>
  <img src="docs/screenshots/03-onboarding.png" width="480" alt="Onboarding"/>
</p>
<p align="center">
  <img src="docs/screenshots/04-missioncontrol.png" width="320" alt="Mission Control"/>
  <img src="docs/screenshots/05-filesync.png" width="440" alt="File Sync dialog"/>
  <img src="docs/screenshots/06-quicksend.png" width="480" alt="Quick Send"/>
</p>

---

## ✨ Features

### 📸 Screenshot & Camera
Send your screen or a photo directly to your agent with one click — or let the agent request it.

### 📋 Clipboard Sync
Push your clipboard to the agent silently, without cluttering the main chat.

### ⚡ Quick Send
A global hotkey (`⌘ ⇧ K`) opens a floating input anywhere on your Mac. Type, send, done.

### 📁 Shared Folder & Automation Rules
A local folder syncs with your agent's workspace. Add `.clawsy` rule files to any subfolder — the built-in **Rule Editor** lets you define triggers like *"when a PDF is added, summarize it"*. No JSON editing required.

### 📊 Mission Control
See what your agent is working on in real time. Agents write their task status to `.agent_status.json` in the shared folder — Clawsy picks it up instantly via FileWatcher.

### 🔒 Fair Play — You Stay in Control
Every file access, screenshot request, or clipboard read triggers a permission dialog. You can allow once, for an hour, or for the rest of the day. Nothing happens behind your back.

---

## 🚀 Installation

1. Go to the [Releases](https://github.com/iret77/clawsy/releases) page
2. Download **Clawsy.app.zip**
3. Unzip and move `Clawsy.app` to `/Applications`
4. Launch Clawsy — the setup assistant guides you through the rest

> **First launch:** Clawsy will ask for Accessibility permission (required for global hotkeys) and optionally enable the Finder extension for right-click folder automation.

---

## ⚙️ Configuration

Open the Clawsy menu → **Einstellungen** (or `⌘,`):

| Setting | Description |
|---|---|
| **Gateway Host** | Your OpenClaw server hostname or IP |
| **Gateway Port** | Default: `18789` |
| **Token** | Your OpenClaw agent token |
| **SSH Fallback** | Auto-tunnel via SSH if direct WSS fails |
| **Shared Folder** | Local folder synced with your agent |

---

## 🤖 Agent Integration

Clawsy connects to OpenClaw as a native node. Once paired, your agent can:

```python
# Take a screenshot
nodes(action="invoke", node="<nodeId>", invokeCommand="screen.capture")

# Read the clipboard
nodes(action="invoke", node="<nodeId>", invokeCommand="clipboard.read")

# Write a file to the shared folder
nodes(action="invoke", node="<nodeId>", invokeCommand="file.set",
      invokeParamsJson='{"name": "hello.txt", "content": "<base64>"}')

# Show task progress in Mission Control
# Write .agent_status.json to shared folder (silent, no dialog)
```

See [CLAWSY.md](CLAWSY.md) for the full agent skill documentation.

---

## 🛠 Build from Source

### Requirements
- macOS 14.0+
- Swift 5.9+ (Xcode Command Line Tools)

### Steps

```bash
git clone https://github.com/iret77/clawsy.git
cd clawsy
./build.sh
# → Clawsy.app lands in .build/app/
```

CI builds run automatically via GitHub Actions on every tagged release.

---

## 🛡 Privacy

All processing happens locally on your Mac. Clawsy never phones home. Every agent interaction requires explicit user approval. See [PRIVACY.md](PRIVACY.md) for details.

---

## 📄 License

MIT — see [LICENSE](LICENSE).
