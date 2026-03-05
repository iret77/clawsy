# Clawsy Connection Architecture — Lessons & Invariants

> Written after the 2026-03-05 connection incident. Read this before touching auth or connection code.

## The Connection Flow

```
User clicks "Verbinden"
  → connect() [connectionAttemptCount=0, isUsingSshTunnel=false]
    → try WSS direct (wss://host:port)
      → SUCCESS (.connected) → performHandshake(nonce)
        → Server verifies signature
        → Server checks pairing
          → PAIRED + key matches → hello-ok ✅
          → NOT_PAIRED or key mismatch → see "Pairing Flow" below
      → TIMEOUT (watchdog) → handleConnectionFailure()
        → SSH fallback available? → startSshTunnel() → connect() again
        → No SSH? → scheduleRetry() with exponential backoff
      → ERROR (.error) → handleConnectionFailure() → same as timeout
      → DISCONNECT (.disconnected) → if !handshakeComplete → handleConnectionFailure()
```

## The Three Invariants

### 1. Signature payload = connect params (NEVER duplicate values)

The device auth signature is computed over a pipe-delimited payload:
```
v2|deviceId|clientId|clientMode|role|scopes|ts|token|nonce
```

The server reconstructs this payload from the connect params the client sends.
**If any value differs between signature and params → DEVICE_AUTH_SIGNATURE_INVALID.**

**Fix (2026-03-05):** All shared values (role, clientMode, scopes, clientId, platform)
are defined as static constants on `NetworkManager`. Both `performHandshake()` and the
connect request reference these same constants. There is no way for them to diverge.

### 2. SSH tunnel = localhost = auto-approved pairing

The OpenClaw Gateway auto-approves pairing for localhost connections (`silent: true`).
SSH tunnels terminate on the server → gateway sees `127.0.0.1` → auto-approve.

**This means:** When NOT_PAIRED arrives over direct WSS, the smartest move is to
reconnect via SSH tunnel. The pairing will be auto-approved without human intervention.

**Fix (2026-03-05):** The NOT_PAIRED handler now checks if SSH fallback is available.
If yes, it disconnects and reconnects via SSH tunnel instead of waiting for manual approval.

### 3. .disconnected ≠ .error but can still mean failure

WebSocket events:
- `.error` → connection failed → triggers `handleConnectionFailure()` → SSH fallback
- `.disconnected` → clean close → previously did NOT trigger fallback

But a server-initiated disconnect during handshake (e.g., NOT_PAIRED, close 1008) is
functionally a connection failure. The user didn't get connected.

**Fix (2026-03-05):** `.disconnected` now calls `handleConnectionFailure()` when
`isHandshakeComplete == false && isPairing == false`.

## Per-Host Signing Keys

Since v0.7.2, each host profile has its own Ed25519 keypair. This means:
- Changing hosts = new deviceId
- Re-pairing required when keys change
- Old `paired.json` entries become stale

The deviceId is `SHA256(publicKey.rawRepresentation)` — deterministic from the key.

## Known Server-Side Issue

The Gateway's `pending.json` file and its in-memory state can diverge. A pending
pairing request may exist in the file but not be visible via `nodes pending` or
approvable via `nodes approve`. Gateway restart reloads the file but creates a
window where Clawsy needs to reconnect.

**Workaround:** The SSH auto-pairing strategy makes this moot — localhost connections
bypass the pending queue entirely.

## Debugging Checklist

When Clawsy can't connect:

1. **Check the debug log** (Settings → scroll down → Debug Log)
2. **DEVICE_AUTH_SIGNATURE_INVALID** → Signature/params mismatch. Check that the
   constants in `performHandshake()` match the connect params.
3. **NOT_PAIRED** → Device key not recognized. Should auto-resolve via SSH tunnel.
   If no SSH: manual re-pair needed.
4. **AUTH_TOKEN_MISMATCH** → Stale deviceToken. App auto-clears and retries.
5. **WSS Timeout + no SSH** → Check sshUser is set in host profile.
6. **STATUS_SSH_USER_MISSING** → SSH fallback configured but no SSH user set.
