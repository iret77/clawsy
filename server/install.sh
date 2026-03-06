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
PLUGIN_TMP="/tmp/clawsy-bridge-$$.ts"

echo "🦞 Clawsy Server Setup" >&2
echo "   Workspace: $WORKSPACE" >&2

# ── 1. Install clawsy-bridge gateway plugin ───────────────────────────────────
if command -v openclaw &>/dev/null; then
  # Check if already installed and active
  PLUGIN_STATUS=$(openclaw plugins info clawsy-bridge 2>/dev/null || true)
  if echo "$PLUGIN_STATUS" | grep -q "enabled: true"; then
    echo "   ✅ clawsy-bridge already installed" >&2
  else
    curl -fsSL "$REPO_RAW/server/clawsy-bridge.ts" -o "$PLUGIN_TMP" 2>/dev/null
    openclaw plugins install "$PLUGIN_TMP" >/dev/null 2>&1
    rm -f "$PLUGIN_TMP"
    echo "   ✅ clawsy-bridge plugin installed" >&2
  fi
else
  echo "   ⚠️  openclaw not found in PATH — skipping plugin install" >&2
fi

# ── 2. Install CLAWSY.md (agent instructions) ─────────────────────────────────
mkdir -p "$WORKSPACE"
curl -fsSL "$REPO_RAW/CLAWSY.md" -o "$WORKSPACE/CLAWSY.md" 2>/dev/null
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
  SETUP_CODE=$(openclaw qr --setup-code-only 2>/dev/null)
  if [[ -n "$SETUP_CODE" ]]; then
    # Start auto-approve watcher in background (approves when user clicks link)
    bash "$TOOLS_DIR/clawsy-pair.sh" --timeout 300 >/dev/null 2>&1 &
    echo "" >&2
    echo "🎉 Clawsy is ready! Send this link to the user:" >&2
    echo "" >&2
    # The clawsy:// link is printed to STDOUT for easy capture by the agent
    echo "clawsy://pair?code=${SETUP_CODE}"
  else
    echo "⚠️  Could not generate setup code. Gateway may still be restarting." >&2
    echo "   Try manually: openclaw qr --setup-code-only" >&2
    exit 1
  fi
else
  echo "⚠️  openclaw not in PATH. Is OpenClaw installed?" >&2
  exit 1
fi
