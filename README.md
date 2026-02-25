# 🦞 Clawsy

**The secure bridge between your Mac and your OpenClaw agents.**

Clawsy is a native macOS companion app designed to empower your [OpenClaw](https://github.com/openclaw/openclaw) virtual assistants with local context, seamless clipboard synchronization, and proactive system awareness.

![Version](https://img.shields.io/badge/version-0.3.2--alpha-orange)
![Platform](https://img.shields.io/badge/platform-macOS-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

---

## ✨ Core Features

### 🚀 Quick Send
Instant communication with your agent directly from your menu bar. 
*   **Silent Interaction:** Uses `receipt: false` to ensure a clean, distraction-free chat experience.
*   **Rich Metadata:** Automatically attaches context like local time, timezone, and device info.

### 📋 Smart Clipboard Sync
Keep your agent in the loop without cluttering your main chat.
*   **Service Sessions:** Clipboard contents are pushed to a dedicated `clawsy-service` session.
*   **Silent Background Sync:** Contents are stored for future reference but don't trigger intrusive notifications.

### 🧠 Adaptive Mood Engine (v2)
Clawsy understands your workflow rhythm.
*   **Activity-Based Profiling:** Learns when you are most productive instead of judging you by static hours.
*   **Anomaly Detection:** Flags unusual activity patterns (like unexpected 4 AM sessions) as potential stress indicators.
*   **Privacy-First:** All learning happens locally on your device.

### 📡 Extended Telemetry
Provide your agent with high-resolution context (optional):
*   **Active App Detection:** Let your agent know you're stuck in Xcode or busy in a meeting.
*   **Hardware Vitals:** Real-time monitoring of battery levels (⚡️) and thermal states.
*   **Fair Play UI:** A transparent "Last Metadata" view that shows exactly what data is being shared.

---

## 🛠 Installation & Usage

### The Easy Way (Recommended)
As Clawsy is in active development, we recommend using the pre-built binaries:
1. Go to the [Releases](https://github.com/iret77/clawsy/releases) page.
2. Download the latest `.dmg` file.
3. Drag **Clawsy** to your Applications folder.

### Configuration
1. Open Clawsy and enter your **OpenClaw Gateway URL**.
2. Provide your **Agent ID** (default is `main`).
3. (Optional) Enable **Extended Context** in settings for full telemetry features.

---

## 🖥 Server-Side Setup (OpenClaw)

To fully utilize Clawsy's features like Silent Clipboard Sync and Mood Analysis, your OpenClaw host needs to be prepared to handle the incoming data.

### 1. Enable Service Sessions
Clawsy sends technical data (like clipboard syncs) to a dedicated session called `clawsy-service`. Ensure your agent's configuration allowlists this session target.

### 2. Mood Analysis Integration
To let your agent "feel" your mood, you can add a periodic task to your `HEARTBEAT.md` on the OpenClaw host. This allows the agent to analyze your recent interaction tone in the background.

**Recommended `HEARTBEAT.md` snippet:**
```markdown
# TASK: Semantic Mood Analysis for Clawsy Ecosystem.
# 1. Read the most recent messages from the user in this session.
# 2. Analyze: Tonalitiy (relaxed/stressed), Wording (formal/casual), and Error/Typos.
# 3. Write result as JSON to `memory/clawsy_mood.json`.
# Format: {"semantic_mood": "...", "analyzed_at": "ISO-TIMESTAMP", "confidence": 0.9}
```

### 3. Agent Awareness
Add the following instruction to your `AGENTS.md` (or your agent's system prompt) to ensure it knows how to read Clawsy's metadata:
> "Before each turn, check `memory/clawsy_mood.json` and look for `clawsy_envelope` JSON structures in the message history to gain local Mac context (Active App, Battery, etc.)."

---

## 👨‍💻 Development

If you want to contribute or build from source:

### Prerequisites
*   macOS 14.0 or newer
*   Xcode 15.0+ (or Swift Command Line Tools)

### Build Steps
1. **Clone the repo:**
   ```bash
   git clone https://github.com/iret77/clawsy.git
   cd clawsy
   ```
2. **Build and Package:**
   Run the included build script:
   ```bash
   ./build.sh
   ```
   This will compile the Swift code in Release mode and package it into `Clawsy.app` inside the `.build/app/` directory.

---

## 🛡 Privacy & Fair Play
Clawsy is built on the principle of **Fair Play**. We believe that transparency is the foundation of trust between a human and their AI assistant.
*   **No Hidden Data:** Every byte sent to the agent can be inspected in the "Last Metadata" view.
*   **Local Processing:** Telemetry analysis and mood profiling happen entirely on your Mac.
*   **Opt-in Context:** You decide which hardware signals are shared.

---

## 📄 License
Clawsy is released under the **MIT License**. See [LICENSE](LICENSE) for details.

*Developed with 🦞 by CyberClaw (Lead Developer) & Christian.*
