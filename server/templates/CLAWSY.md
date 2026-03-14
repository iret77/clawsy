# CLAWSY.md — Clawsy Integration (v0.9.33)

Clawsy is a macOS companion app for OpenClaw. It gives your agent access to the user's Mac: screenshots, clipboard, camera, files, and live task progress.

## Common Mistakes

| Mistake | Correct |
|---|---|
| `file.list` with `{"path": "."}` | `file.list` with **no params** (root) or `{"subPath": "folder/"}` |
| `file.set` with plain text content | `file.set` content is **always Base64-encoded** |
| `file.get` with `{"path": "..."}` | `file.get` uses `{"name": "filename.txt"}` |
| `file.exists` with `{"name": "..."}` | `file.exists` uses `{"path": "filename.txt"}` |
| `file.rename` moving to a new dir | `file.rename` changes name only (same dir); use `file.move` for paths |
| Writing `.agent_status.json` to shared folder | Obsolete since v0.5.6 — use `agent.status` via `sessions_send` |

---

## File API Reference

All file operations are sandboxed to the shared folder (default: `~/Documents/Clawsy`). Path traversal is rejected.

### List Files

```python
# Root directory (NO parameters)
nodes(action="invoke", invokeCommand="file.list")

# Subdirectory
nodes(action="invoke", invokeCommand="file.list",
      invokeParamsJson='{"subPath": "reports/"}')

# Recursive (all files, max depth 5)
nodes(action="invoke", invokeCommand="file.list",
      invokeParamsJson='{"recursive": true}')
```

### Read / Write Files

```python
# Read a file (returns base64-encoded content)
nodes(action="invoke", invokeCommand="file.get",
      invokeParamsJson='{"name": "report.pdf"}')

# Write a file (content MUST be base64-encoded)
nodes(action="invoke", invokeCommand="file.set",
      invokeParamsJson='{"name": "output.txt", "content": "<base64-encoded>"}')
```

### Check / Inspect Files

```python
# Check if file exists → {"exists": true/false}
nodes(action="invoke", invokeCommand="file.exists",
      invokeParamsJson='{"path": "report.pdf"}')

# Get metadata (size, dates, type; supports glob)
nodes(action="invoke", invokeCommand="file.stat",
      invokeParamsJson='{"path": "report.pdf"}')
```

### Create / Delete

```python
# Create directory (creates intermediate dirs)
nodes(action="invoke", invokeCommand="file.mkdir",
      invokeParamsJson='{"name": "folder/subfolder"}')

# Delete file or directory
nodes(action="invoke", invokeCommand="file.delete",
      invokeParamsJson='{"name": "old-file.txt"}')

# Remove directory (including non-empty)
nodes(action="invoke", invokeCommand="file.rmdir",
      invokeParamsJson='{"name": "old-folder"}')
```

### Move / Copy / Rename

```python
# Move (supports glob in source)
nodes(action="invoke", invokeCommand="file.move",
      invokeParamsJson='{"source": "old/path.txt", "destination": "new/path.txt"}')

# Copy (supports glob in source)
nodes(action="invoke", invokeCommand="file.copy",
      invokeParamsJson='{"source": "original.txt", "destination": "backup.txt"}')

# Rename (name only, same directory)
nodes(action="invoke", invokeCommand="file.rename",
      invokeParamsJson='{"path": "old-name.txt", "newName": "new-name.txt"}')
```

### Batch Operations

```python
nodes(action="invoke", invokeCommand="file.batch",
      invokeParamsJson='{"ops": [{"op": "copy", "source": "a.txt", "destination": "b.txt"}, {"op": "move", "source": "c.txt", "destination": "d.txt"}]}')
```

### Large Files (> 200 KB)

The `nodes` tool has a payload limit (~512 KB). For files larger than ~200 KB, use chunked transfer with `file.get.chunk` / `file.set.chunk`. These commands split files into smaller pieces and reassemble them automatically.

**Uploading a large file (agent to Mac):**

```python
import base64

# 1. Read the local file and split into ~150 KB chunks
chunk_size = 150 * 1024  # 150 KB per chunk (safe margin under 512 KB limit)
with open("large-file.pdf", "rb") as f:
    data = f.read()

total_chunks = (len(data) + chunk_size - 1) // chunk_size

for i in range(total_chunks):
    chunk = base64.b64encode(data[i * chunk_size : (i + 1) * chunk_size]).decode()
    nodes(action="invoke", invokeCommand="file.set.chunk",
          invokeParamsJson=json.dumps({
              "name": "large-file.pdf",
              "chunk": chunk,
              "index": i,
              "total": total_chunks
          }))
# Clawsy assembles the final file after the last chunk arrives.
```

**Downloading a large file (Mac to agent):**

```python
import base64, json

# 1. Get file info to determine chunk count
result = nodes(action="invoke", invokeCommand="file.stat",
               invokeParamsJson='{"path": "large-file.pdf"}')
file_size = result["size"]
chunk_size = 150 * 1024
total_chunks = (file_size + chunk_size - 1) // chunk_size

# 2. Download each chunk
chunks = []
for i in range(total_chunks):
    result = nodes(action="invoke", invokeCommand="file.get.chunk",
                   invokeParamsJson=json.dumps({
                       "name": "large-file.pdf",
                       "index": i,
                       "chunkSize": chunk_size
                   }))
    chunks.append(base64.b64decode(result["chunk"]))

# 3. Reassemble
with open("large-file.pdf", "wb") as f:
    f.write(b"".join(chunks))
```

> **Important:** Use the `nodes` tool-call API (not the `openclaw nodes invoke` CLI). The CLI has reliability issues with large payloads and may time out. All examples above use tool calls which are routed directly through the gateway.

---

## Mission Control Protocol

Clawsy displays agent status in its Mission Control UI via WebSocket events.

### agent.info — Header Identity (send on session start + every heartbeat, TTL: 45 min)

```python
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.info","payload":{"agentName":"<AGENT_NAME>","model":"<YOUR_MODEL>","updatedAt":"<ISO-UTC>"}}')
```

### agent.status — Task Progress (send during active work)

```python
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.status","payload":{"agentName":"<AGENT_NAME>","title":"Building feature X","progress":0.5,"statusText":"Running tests..."}}')
```

- `progress`: Float `0.0`-`1.0`. At `1.0`, task auto-removes after 10 seconds.
- **Timeout errors are normal.** The event is delivered when Clawsy is connected. Do not retry.

> **Note:** The short session key `clawsy-service` works in most configurations. If it fails to resolve, use the fully qualified key (`agent:<agentId>:clawsy-service`). See the "clawsy-service Session" section below for details.

### Subagent Snippet

Include this in every subagent task prompt:

```
## Clawsy Mission Control (MANDATORY)
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.status","payload":{"agentName":"<label>","title":"<task>","progress":<0.0-1.0>,"statusText":"<details>"}}')
Start=0.05 | Mid=0.5 | Done=1.0
```

---

## Other Capabilities

| Command | Usage |
|---|---|
| `screen.capture` | `nodes(action="invoke", invokeCommand="screen.capture")` |
| `clipboard.read` | `nodes(action="invoke", invokeCommand="clipboard.read")` |
| `clipboard.write` | `nodes(action="invoke", invokeCommand="clipboard.write", invokeParamsJson='{"text": "..."}')` |
| `camera.list` | `nodes(action="invoke", invokeCommand="camera.list")` |
| `camera.snap` | `nodes(action="invoke", invokeCommand="camera.snap", invokeParamsJson='{"facing": "front"}')` |
| `location.get` | `nodes(action="invoke", invokeCommand="location.get")` |

Most commands require user approval on the Mac side (allow once / allow 1 hour / deny).

---

## clawsy-service Session

Screenshots, clipboard events, camera photos, and Quick Send messages arrive in the `clawsy-service` session — not in the main chat.

```python
sessions_history(sessionKey="clawsy-service", limit=10)
```

> **Session key resolution:** The short key `clawsy-service` may or may not resolve depending on your gateway configuration. If it does not work, use the fully qualified session key instead. The full key follows the pattern `agent:<agentId>:clawsy-service` (e.g., `agent:main:clawsy-service`). You can find the correct key by checking `sessions_list` for a session containing `clawsy-service`.

Look for `clawsy_envelope` messages with `type`: `"screenshot"`, `"clipboard"`, `"camera"`, `"quick_send"`.

---

## Quick Send Envelope Format

When the user sends a message via the global hotkey:

```json
{
  "clawsy_envelope": {
    "type": "quick_send",
    "content": "The user's message",
    "version": "0.9.33",
    "localTime": "2026-03-14T10:30:00Z",
    "tz": "Europe/Berlin",
    "telemetry": {
      "deviceName": "MacBook Pro",
      "batteryLevel": 0.75,
      "isCharging": true,
      "thermalState": 0,
      "activeApp": "Safari",
      "moodScore": 70,
      "isUnusualHour": false
    }
  }
}
```

**Telemetry hints:** `thermalState > 1` = overheating | `batteryLevel < 0.2` = low battery | `moodScore < 40` = user stressed | `isUnusualHour` = odd hours

---

## Finding the Clawsy Node

```python
nodes(action="status")
# Look for platform="macos", connected=true
```

---

## Setup & Pairing

For first-time setup, pairing, and install scripts, see the full SKILL.md:
`~/.openclaw/workspace/skills/clawsy-server/SKILL.md`

**HEARTBEAT.md snippet:**

```markdown
## Clawsy (every heartbeat)
sessions_send(sessionKey="clawsy-service", timeoutSeconds=3,
  message='{"kind":"agent.info","payload":{"agentName":"<NAME>","model":"<MODEL>","updatedAt":"<ISO-UTC>"}}')
# If the short key fails, use the fully qualified key: agent:<agentId>:clawsy-service
```
