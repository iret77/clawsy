#!/bin/bash
# Clawsy Server Install Script
# Installs the server-side components for the Clawsy Mac companion app.
# No sudo required. Runs in ~10 seconds.
#
# Usage (agent executes this after user request):
#   curl -fsSL https://raw.githubusercontent.com/iret77/clawsy/main/server/install.sh | bash
#
# Output: A clawsy:// deep link that the user can click to connect their Mac app.

set -euo pipefail

REPO_RAW="https://raw.githubusercontent.com/iret77/clawsy/main"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
WORKSPACE="${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME/workspace}"
TOOLS_DIR="$WORKSPACE/tools"

echo "🦞 Clawsy Server Setup" >&2
echo "   Workspace: $WORKSPACE" >&2

# ── 1. Install clawsy-bridge gateway plugin ──────────────────────────────────
if command -v openclaw &>/dev/null; then
  EXTENSIONS_DIR="$OPENCLAW_HOME/extensions"
  mkdir -p "$EXTENSIONS_DIR"

  # Check if already installed with correct ID
  if [[ -f "$EXTENSIONS_DIR/clawsy-bridge.ts" ]] && [[ -f "$EXTENSIONS_DIR/openclaw.plugin.json" ]]; then
    echo "   ✅ clawsy-bridge already installed" >&2
  else
    curl -fsSL "$REPO_RAW/server/clawsy-bridge.ts" -o "$EXTENSIONS_DIR/clawsy-bridge.ts" 2>/dev/null
    curl -fsSL "$REPO_RAW/server/openclaw.plugin.json" -o "$EXTENSIONS_DIR/openclaw.plugin.json" 2>/dev/null
    echo "   ✅ clawsy-bridge plugin installed" >&2
  fi

  # Cleanup: remove any broken clawsy-bridge-XXXXX entries from config
  python3 -c "
import json, re, os, sys
cfg_path = os.path.expanduser('~/.openclaw/openclaw.json')
if not os.path.exists(cfg_path): sys.exit(0)
with open(cfg_path) as f: cfg = json.load(f)
entries = cfg.get('plugins', {}).get('entries', {})
to_remove = [k for k in entries if re.match(r'clawsy-bridge-\d+', k)]
for k in to_remove: del entries[k]
if to_remove:
    with open(cfg_path, 'w') as f: json.dump(cfg, f, indent=2)
    print(f'   Cleaned up broken plugin entries: {to_remove}', file=sys.stderr)
" 2>&1 || true
else
  echo "   ⚠️  openclaw not found in PATH — skipping plugin install" >&2
fi

# ── 2. Install CLAWSY.md (agent instructions) ─────────────────────────────────
mkdir -p "$WORKSPACE"
curl -fsSL "$REPO_RAW/server/templates/CLAWSY.md" -o "$WORKSPACE/CLAWSY.md" 2>/dev/null
echo "   ✅ CLAWSY.md installed" >&2

# ── 3. Install clawsy-pair.sh (auto-approve helper) ──────────────────────────
mkdir -p "$TOOLS_DIR"
curl -fsSL "$REPO_RAW/tools/clawsy-pair.sh" -o "$TOOLS_DIR/clawsy-pair.sh" 2>/dev/null
chmod +x "$TOOLS_DIR/clawsy-pair.sh"
echo "   ✅ clawsy-pair.sh installed" >&2

# ── 4. Restart gateway (plugin becomes active) ────────────────────────────────
if command -v openclaw &>/dev/null; then
  openclaw gateway restart >/dev/null 2>&1 &
  sleep 3  # Give gateway time to restart before generating the setup code
  echo "   ✅ Gateway restarted" >&2
fi

# ── 5. Generate pairing link + start auto-approve watcher ────────────────────
if command -v openclaw &>/dev/null; then
  # Wait for gateway to be ready after restart (retry up to 5x with 2s delay)
  SETUP_CODE=""
  for attempt in 1 2 3 4 5; do
    SETUP_CODE=$(openclaw qr --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['setupCode'])" 2>/dev/null || true)
    [[ -n "$SETUP_CODE" ]] && break
    echo "   ⏳ Waiting for gateway to be ready (attempt $attempt/5)..." >&2
    sleep 2
  done

  if [[ -n "$SETUP_CODE" ]]; then
    # Start auto-approve watcher in background (approves when user clicks link)
    bash "$TOOLS_DIR/clawsy-pair.sh" --timeout 300 >/dev/null 2>&1 &

    LINK="clawsy://pair?code=${SETUP_CODE}"
    LINK_FILE="$WORKSPACE/clawsy-pairing-link.txt"

    # Detect if gateway is loopback-only (Mac can't reach it directly)
    GATEWAY_URL=$(openclaw config get gateway.remote.url 2>/dev/null || echo "")
    NEEDS_SSH_TUNNEL=false
    if [[ -z "$GATEWAY_URL" ]] || echo "$GATEWAY_URL" | grep -qE "127\.0\.0\.1|localhost"; then
      NEEDS_SSH_TUNNEL=true
    fi

    # Get SSH connection info for tunnel instructions
    SSH_HOST=""
    SSH_USER=$(whoami)
    GATEWAY_PORT=$(openclaw config get gateway.port 2>/dev/null || echo "18789")
    [[ -n "${SSH_CONNECTION:-}" ]] && SSH_HOST=$(echo "$SSH_CONNECTION" | awk '{print $3}')
    [[ -z "$SSH_HOST" ]] && SSH_HOST=$(hostname -f 2>/dev/null || hostname)

    if $NEEDS_SSH_TUNNEL; then
      # Include SSH tunnel instructions alongside the link
      cat > "$LINK_FILE" << LINKEOF
PAIRING_LINK=$LINK
SSH_TUNNEL_REQUIRED=true
SSH_COMMAND=ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}

Dein Human muss zuerst auf seinem Mac einen SSH-Tunnel starten:
  ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}
Dann diesen Link klicken:
  $LINK
LINKEOF
      echo "   ✅ Pairing instructions saved to: $LINK_FILE" >&2
    else
      echo "$LINK" > "$LINK_FILE"
      echo "   ✅ Pairing link saved to: $LINK_FILE" >&2
    fi

    echo "" >&2
    echo "🎉 Clawsy Server installed!" >&2
    if $NEEDS_SSH_TUNNEL; then
      echo "   ⚠️  Gateway is loopback-only. SSH tunnel required on the Mac:" >&2
      echo "   ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}" >&2
      echo "   Then click: $LINK" >&2
    else
      echo "   $LINK"
    fi
    echo "" >&2
    echo "✅ Done. Instructions saved to: $LINK_FILE" >&2
  else
    # Not fatal — the app may have already handled pairing, or user can run manually
    echo "" >&2
    echo "✅ Clawsy Server installed. Gateway still starting up." >&2
    echo "   To get your pairing link: openclaw qr --json" >&2
  fi
else
  echo "⚠️  openclaw not in PATH. Is OpenClaw installed?" >&2
  exit 1
fi
