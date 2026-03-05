# Clawsy Connection Architecture

Developer reference for the WebSocket connection, device authentication, and pairing flow.

## Connection Flow

```
connect()
  → try WSS direct (wss://host:port)
    → SUCCESS (.connected) → performHandshake(nonce)
      → Server verifies device signature
      → Server checks pairing
        → PAIRED + key matches → hello-ok ✅
        → NOT_PAIRED → see "Pairing" below
    → TIMEOUT (watchdog) → handleConnectionFailure()
      → SSH fallback available? → startSshTunnel() → connect() via tunnel
      → No SSH? → scheduleRetry() with exponential backoff
    → ERROR (.error) → handleConnectionFailure() → same as timeout
    → DISCONNECT (.disconnected, handshake incomplete) → handleConnectionFailure()
```

## Device Auth Signature

The signature is computed over a pipe-delimited payload:
```
v2|deviceId|clientId|clientMode|role|scopes|ts|token|nonce
```

The server reconstructs this payload from the connect params and verifies the signature.
**If any value differs between the signed payload and connect params → signature rejected.**

All shared values (role, clientMode, scopes, clientId, platform) are defined as static
constants on `NetworkManager`. Both `performHandshake()` and the connect request reference
these same constants. Never define them separately.

## Pairing

### SSH tunnel = localhost = auto-approved

The OpenClaw Gateway auto-approves pairing for localhost connections.
SSH tunnels terminate on the server → gateway sees `127.0.0.1` → auto-approve.

When NOT_PAIRED arrives over direct WSS and SSH fallback is available, Clawsy
automatically reconnects via SSH tunnel. The pairing completes without user intervention.

### Per-host signing keys

Each host profile has its own Ed25519 keypair. The deviceId is derived from the public key:
`SHA256(publicKey.rawRepresentation)`. This means:
- Each host = unique deviceId
- Re-pairing is required when keys change (e.g., fresh host profile)

## Handling Server-Initiated Disconnects

WebSocket `.disconnected` events during an incomplete handshake (e.g., server closes
with code 1008 after NOT_PAIRED) are treated as connection failures. This ensures
SSH fallback triggers even when the WSS transport itself connected successfully.

## Debugging

1. **Check the debug log** (Settings → Debug Log)
2. **DEVICE_AUTH_SIGNATURE_INVALID** → Signature/params mismatch. Verify the shared constants.
3. **NOT_PAIRED** → Device key not recognized. Should auto-resolve via SSH tunnel.
   Without SSH: manual re-pair via `openclaw nodes approve <requestId>`.
4. **AUTH_TOKEN_MISMATCH** → Stale deviceToken. Auto-clears and retries.
5. **STATUS_SSH_USER_MISSING** → SSH fallback enabled but no SSH user configured.
