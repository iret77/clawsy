# Clawsy — Server Setup (OpenClaw Side)

Clawsy is a Mac client that connects to your OpenClaw Gateway. This guide covers everything needed on the **server side** to make it work.

---

## Prerequisites

- **OpenClaw** installed and running ([github.com/openclaw/openclaw](https://github.com/openclaw/openclaw))
- Gateway accessible from your Mac (hostname or IP, default port `18789`)
- Your OpenClaw **auth token**

### Finding Your Token

```bash
# View your OpenClaw configuration
openclaw config get

# The token is the "token" or "authToken" field in your config
# You can also check openclaw.json directly
cat ~/.openclaw/openclaw.json | grep token
```

The token you need is the **master token** (also called auth token or server token) — the same one used to authenticate agents and nodes.

---

## Connecting Clawsy

### 1. On the Mac

1. Download and install [Clawsy](https://github.com/iret77/clawsy/releases/latest)
2. Open Clawsy → Settings
3. Enter:
   - **Gateway Host:** Your OpenClaw server hostname or IP (e.g., `myserver.example.com` or `192.168.1.100`)
   - **Gateway Port:** `18789` (default)
   - **Token:** Your OpenClaw auth token
4. Click Connect

### 2. Approve the Pairing Request

On first connect, Clawsy sends a pairing request. You must approve it:

```bash
# List all nodes (look for a pending pairing request)
openclaw nodes

# Approve the request
openclaw nodes approve <requestId>
```

If you use the OpenClaw web dashboard, the pairing request appears there too.

After approval, Clawsy receives a device token and reconnects automatically. The pairing is persistent — you only do this once per host.

### 3. Verify Connection

```bash
# Check that Clawsy appears as a connected node
openclaw nodes
# → Should show a node with platform="macos" and status="connected"
```

---

## Configuring Your Agent

Your agent needs to know Clawsy is installed so it can send status updates and use Clawsy's capabilities.

### Option A: Tell Your Agent Directly

Send this message to your agent:

```
Clawsy (macOS companion app) is now installed and connected.
Read the Clawsy skill (SKILL.md in the clawsy-server skill) for integration details.
Add Clawsy heartbeat entries to HEARTBEAT.md — send agent.info and agent.status
to clawsy-service every heartbeat.
```

### Option B: Add to AGENTS.md

Add this section to your workspace `AGENTS.md`:

```markdown
## Clawsy Integration
Clawsy (macOS companion) is installed. On every heartbeat:
1. Send agent.info to clawsy-service (name + model + timestamp)
2. Send agent.status for any active task (title + progress + statusText)
Read the clawsy skill SKILL.md for exact formats and all capabilities.
```

### Option C: Add to HEARTBEAT.md

Add this snippet to your agent's `HEARTBEAT.md`:

```markdown
## Clawsy (every heartbeat)
Send agent.info to clawsy-service:
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.info","payload":{"agentName":"<NAME>","model":"<MODEL>","updatedAt":"<ISO-UTC>"}}')

If actively working, send agent.status:
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.status","payload":{"agentName":"<NAME>","title":"<TASK>","progress":<0.0-1.0>,"statusText":"<DETAILS>"}}')
```

Replace `<NAME>` with your agent's name, `<MODEL>` with the current LLM model.

---

## What the Agent Can Do

Once connected, the agent uses the `nodes` tool to interact with Clawsy:

| Command | Description |
|---|---|
| `screen.capture` | Take a screenshot |
| `clipboard.read` | Read clipboard content |
| `clipboard.write` | Write text to clipboard |
| `camera.snap` | Take a camera photo |
| `camera.list` | List available cameras |
| `file.list` | List shared folder contents |
| `file.get` | Read a file |
| `file.set` | Write a file |
| `location.get` | Get device location |

All user-data commands require approval on the Mac side.

---

## Troubleshooting

### Clawsy Can't Connect

1. **Check the hostname/IP:** Can your Mac reach the server? Try `ping <hostname>` or `curl http://<hostname>:18789/status`
2. **Check the port:** Is `18789` open? Firewalls, security groups, or NAT may block it
3. **Check the token:** Make sure the token in Clawsy matches your OpenClaw config
4. **Enable SSH fallback:** In Clawsy Settings, enable SSH Fallback. Import your SSH key and set the SSH user. This tunnels through SSH when direct WebSocket fails

### Pairing Request Not Appearing

- Make sure Clawsy shows "Connecting" or "Pairing" status (not "Disconnected")
- Run `openclaw nodes` — if no pending request, Clawsy may not have reached the gateway
- Check OpenClaw gateway logs for connection attempts

### Agent Not Showing in Mission Control

- Agent must send `agent.info` to `clawsy-service` — without this, the header stays empty
- Agent must send `agent.status` for tasks to appear
- Verify with: `sessions_history(sessionKey="clawsy-service", limit=5)` — are events being sent?
- Timeout on `sessions_send` is normal and expected

### Token Mismatch After Gateway Restart

Known issue: If the gateway doesn't persist `paired.json`, device tokens may be lost after restart. Clawsy handles this automatically — it detects `AUTH_TOKEN_MISMATCH`, clears the stored device token, and reconnects with the master token.

### Clawsy Extensions Not Working

| Extension | Fix |
|---|---|
| **FinderSync** | System Settings → Privacy & Security → Extensions → Finder → enable Clawsy |
| **Share Extension** | Move Clawsy.app to `/Applications` (won't work from Downloads) |
| **Global Hotkeys** | System Settings → Privacy & Security → Accessibility → enable Clawsy |

---

## Multi-Host Setup (v0.7.0+)

Clawsy supports multiple OpenClaw gateways. Each host is independently configured with its own token, connection, and shared folder.

**To add another host:**
1. In Clawsy, click the **+** button in the header
2. Enter the second gateway's host, port, and token
3. Approve the pairing request on that gateway
4. Both connections run simultaneously with color-coded labels

Use this for: dev/prod separation, work/personal instances, or connecting to multiple teams.
