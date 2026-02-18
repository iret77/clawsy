# Clawsy Architecture Fix: "Quick Send" Protocol Alignment

## Problem
"Quick Send" messages from Clawsy were not reaching the Agent.
- **Symptom:** `node.event` with `event: "quick_send"` was sent successfully by the Mac, but ignored by the Server.
- **Root Cause:** The OpenClaw Gateway (`server-node-events.ts`) has a hardcoded switch statement for `node.event`. It only handles specific event types (`voice.transcript`, `agent.request`, `exec.finished`, etc.). Unknown events like `quick_send` are silently dropped (default case: `return;`).

## Solution
Instead of using a custom event name (`quick_send`) that requires a custom listener (which can't hear it anyway because it's not broadcast), we must use the **native protocol** supported by the Gateway.

**Protocol:** `agent.request`
**Handler:** Triggers `agentCommand`, effectively sending a message to the Agent as if it came from a user.

## Implementation Details

### Swift (Clawsy)
Change the event emission in `QuickSendView.swift`:

**Old:**
```swift
network.sendEvent(kind: "quick_send", payload: ["text": text])
```

**New:**
```swift
network.sendEvent(kind: "agent.request", payload: [
    "message": text,
    "deliver": true,
    "receipt": true // Optional: requests a receipt confirmation
])
```

### Server (Gateway)
No changes needed. The Gateway natively supports `agent.request`.

## Benefits
1.  **Zero Config:** No need for `listener.js` or custom scripts running on the server.
2.  **Native Integration:** Messages appear directly in the chat session as user input.
3.  **Reliability:** Uses the core Agent bus instead of side-channel events.

## Action Plan
1.  Modify `projects/clawsy/Sources/ClawsyMac/QuickSendView.swift`.
2.  Modify `projects/clawsy/Sources/ClawsyMac/ContentView.swift` (for clipboard push, same logic).
3.  Bump version to `#121`.
4.  Push to GitHub.
