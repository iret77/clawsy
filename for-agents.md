# Clawsy — For OpenClaw Agents

If you are an OpenClaw agent, this file tells you how to use Clawsy.

## What is Clawsy?

Clawsy is a native macOS companion app (v1.0) that gives you direct access to your human's Mac via the OpenClaw gateway. It connects as a **node** using Protocol V3.

**Capabilities:** screenshots, clipboard, files, camera, Quick Send messages.

## How It Works

Clawsy registers as a node on the gateway. You invoke its capabilities via `node.invoke`:

```
nodes(action="invoke", nodeId="<CLAWSY_NODE_ID>", command="<COMMAND>", params={...})
```

The node ID is the Clawsy device's SHA256 fingerprint. You can find connected nodes via `nodes(action="status")`.

## Commands

### Screenshots

```python
# Full screen capture
nodes(action="invoke", nodeId=NODE_ID, command="screen.capture", params={})

# Interactive area selection (user picks region)
nodes(action="invoke", nodeId=NODE_ID, command="screen.capture", params={"interactive": true})
```

**Response:** `{"format": "jpeg", "base64": "<base64-encoded-image>"}`

The user sees an approval dialog before the screenshot is taken.

### Clipboard

```python
# Read clipboard (requires user approval)
nodes(action="invoke", nodeId=NODE_ID, command="clipboard.read", params={})
# Response: {"text": "clipboard content"}

# Write to clipboard (no approval needed)
nodes(action="invoke", nodeId=NODE_ID, command="clipboard.write", params={"text": "content to write"})
# Response: {"ok": true}
```

### Files

All file operations work within the **Shared Folder** only (sandboxed). Paths are relative to the shared folder root.

```python
# List files
nodes(action="invoke", nodeId=NODE_ID, command="file.list", params={})
nodes(action="invoke", nodeId=NODE_ID, command="file.list", params={"subPath": "subfolder/"})

# Read file (returns base64)
nodes(action="invoke", nodeId=NODE_ID, command="file.get", params={"subPath": "report.pdf"})
# Response: {"base64": "<base64-encoded-content>"}

# Write file (content must be base64)
nodes(action="invoke", nodeId=NODE_ID, command="file.set", params={"subPath": "output.txt", "content": "<base64>"})

# Create directory
nodes(action="invoke", nodeId=NODE_ID, command="file.mkdir", params={"subPath": "new-folder"})

# Delete file
nodes(action="invoke", nodeId=NODE_ID, command="file.delete", params={"subPath": "old-file.txt"})

# Check existence
nodes(action="invoke", nodeId=NODE_ID, command="file.exists", params={"subPath": "file.txt"})
# Response: {"exists": true, "isDirectory": false}

# Get file metadata
nodes(action="invoke", nodeId=NODE_ID, command="file.stat", params={"subPath": "file.txt"})
# Response: {"exists": true, "isDirectory": false, "size": 1234, "modified": "2026-03-26T..."}
```

### Camera

```python
nodes(action="invoke", nodeId=NODE_ID, command="camera.snap", params={})
# Response: {"format": "jpeg", "base64": "<base64>", "device": "FaceTime HD Camera"}
```

The user sees a preview and can approve or deny.

## Common Mistakes

| Mistake | Correct |
|---|---|
| Using `path` instead of `subPath` | Always use `subPath` for file commands |
| Sending plain text to `file.set` | Content must be **Base64-encoded** |
| Not decoding `file.get` response | Response `base64` field needs Base64 decoding |
| Retrying after node timeout | Don't retry — the user may have denied |
| Not checking node status first | Run `nodes(action="status")` before invoking |

## Pre-Flight Check

Before using Clawsy commands, verify the node is online:

```python
result = nodes(action="status")
# Look for a node with clientId "clawsy-macos" and status "connected"
```

If the node is not connected, tell your human: "Clawsy doesn't seem to be connected. Can you check the Clawsy menu bar icon?"

## What the User Sees

- **Screenshots/Camera:** Approval dialog with preview before sending
- **Clipboard read:** Preview of clipboard content, user can approve or deny
- **Clipboard write:** Content is written silently (user sees a notification)
- **Files:** Operations within the shared folder happen silently
- **Quick Send:** User pushes text to you via ⌘⇧K — arrives as a `clawsy_envelope` event

## Setup

Clawsy v1.0 uses Protocol V3 and pairs automatically with the gateway. No manual `sessions_send` setup needed. The node declares its capabilities at connect time.
