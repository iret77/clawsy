# 🦞 Clawsy

> **The secure, lightweight bridge between your Mac and OpenClaw.**
> Share clipboard and screenshots safely with on-demand permission control.

![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Platform: macOS](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)
![Swift](https://img.shields.io/badge/Swift-5.9-orange.svg)

**Clawsy** is a native macOS companion app for [OpenClaw](https://github.com/openclaw/openclaw) agents. It allows your isolated agent (running on a VPS or container) to interact with your local Mac workflow—but strictly on your terms.

## ✨ Features

*   **🔒 Secure by Default:** No always-on screen sharing. No silent clipboard reading.
*   **📸 On-Demand Screenshots:** Agent requests a screenshot -> You get a native macOS dialog to Allow/Deny.
*   **📋 Clipboard Sharing:** Push your clipboard to the agent, or let the agent write to your clipboard (with approval).
*   **🚀 Lightning Fast:** Native Swift app, communicates via WebSocket (e.g., over Tailscale).
*   **☁️ Private:** Peer-to-Peer connection. No third-party cloud servers.

## 🛠️ Setup

### 1. Agent Side (Server)
Clawsy needs a counterpart running on your OpenClaw agent. Use the local `clawsy-server` skill:

```bash
# Start the server (runs in background via skill)
python3 skills/clawsy-server/scripts/server.py --port 8765
```

### 2. Mac Side (Client)
1.  Download the latest release from [Releases](https://github.com/iret77/clawsy/releases).
2.  Drag `Clawsy.app` to your Applications folder.
3.  **First Launch:**
    *   Right-click (or Control-click) on `Clawsy.app`.
    *   Select **Open**.
    *   Click **Open** in the dialog.
    *   *(Why? Clawsy is currently not notarized by Apple because we are a free open source project. This manual step is required only once.)*
4.  Click the ⚙️ icon and enter your Agent's WebSocket URL (e.g., `ws://100.x.y.z:8765`).
5.  Click **Connect**.

## 🛡️ Privacy & Security

Clawsy is built with a "Privacy First" philosophy:

*   **No Analytics:** We don't track you.
*   **Direct Connection:** Data flows directly between your Mac and your Agent.
*   **User Consent:** Sensitive actions (Screen/Clipboard) always require explicit approval via system dialogs.

See [PRIVACY.md](PRIVACY.md) for details.

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
