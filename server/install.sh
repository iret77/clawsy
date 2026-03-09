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

    LINK_FILE="$WORKSPACE/clawsy-pairing-link.txt"
    GATEWAY_PORT=$(openclaw config get gateway.port 2>/dev/null || echo "18789")

    # ── Multi-scenario gateway URL detection + code patching ────────────────
    # Python detects scenario, patches the code with the correct URL, and
    # builds a ready-to-forward notify_msg for the agent to send to the human.
    SETUP_RESULT=$(SETUP_CODE="$SETUP_CODE" GATEWAY_PORT="$GATEWAY_PORT" \
      SSH_CONNECTION="${SSH_CONNECTION:-}" python3 << 'PYEOF'
import json, base64, subprocess, os, sys

port = os.environ.get('GATEWAY_PORT', '18789')

# Decode setup code
raw = os.environ.get('SETUP_CODE', '')
try:
    decoded = json.loads(base64.b64decode(raw + '==').decode())
    token = decoded.get('token', '')
except Exception:
    print(json.dumps({"error": "decode_failed", "type": "manual_required"}))
    sys.exit(0)

def make_code(url, token):
    payload = json.dumps({"url": url, "token": token}, separators=(',', ':'))
    return base64.b64encode(payload.encode()).decode().rstrip('=')

# Scenario 0: preconfigured remote.url (non-loopback)
try:
    r = subprocess.run(['openclaw', 'config', 'get', 'gateway.remote.url'],
                       capture_output=True, text=True, timeout=5)
    configured = r.stdout.strip()
    if configured and not any(x in configured for x in ['127.0.0.1', 'localhost', '0.0.0.0']):
        code = make_code(configured, token)
        link = f"clawsy://pair?code={code}"
        msg = (f"🦞 Clawsy ist bereit!\n"
               f"Sage deinem Human: Klicke auf deinem Mac diesen Link:\n"
               f"  {link}")
        print(json.dumps({"type": "preconfigured", "url": configured,
                          "code": code, "notify_msg": msg}))
        sys.exit(0)
except Exception:
    pass

# Scenario 1: Tailscale
try:
    r = subprocess.run(['tailscale', 'ip', '-4'], capture_output=True, text=True, timeout=5)
    ts_ip = r.stdout.strip()
    if ts_ip and r.returncode == 0:
        url = f"ws://{ts_ip}:{port}"
        code = make_code(url, token)
        link = f"clawsy://pair?code={code}"
        msg = (f"🦞 Clawsy ist bereit!\n"
               f"Sage deinem Human: Klicke auf deinem Mac diesen Link:\n"
               f"  {link}")
        print(json.dumps({"type": "tailscale", "url": url, "code": code, "notify_msg": msg}))
        sys.exit(0)
except Exception:
    pass

# Scenario 2: LAN IP (non-loopback)
try:
    r = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
    ips = r.stdout.strip().split()
    lan_ip = next((ip for ip in ips if not ip.startswith('127.')), None)
    if lan_ip:
        url = f"ws://{lan_ip}:{port}"
        code = make_code(url, token)
        link = f"clawsy://pair?code={code}"
        msg = (f"🦞 Clawsy ist bereit!\n"
               f"Sage deinem Human: Klicke auf deinem Mac diesen Link:\n"
               f"  {link}")
        print(json.dumps({"type": "lan", "url": url, "code": code, "notify_msg": msg}))
        sys.exit(0)
except Exception:
    pass

# Scenario 3: SSH session → tunnel instructions
ssh_conn = os.environ.get('SSH_CONNECTION', '')
if ssh_conn:
    parts = ssh_conn.split()
    ssh_host = parts[2] if len(parts) >= 3 else ''
    ssh_user = os.environ.get('USER', os.environ.get('LOGNAME', 'openclaw'))
    url = f"ws://127.0.0.1:{port}"
    code = make_code(url, token)
    link = f"clawsy://pair?code={code}"
    ssh_cmd = f"ssh -L {port}:localhost:{port} {ssh_user}@{ssh_host}"
    msg = (f"🦞 Clawsy ist bereit zum Pairen!\n\n"
           f"Sage deinem Human:\n"
           f"Öffne ein Terminal auf deinem Mac und führe diesen Befehl aus:\n"
           f"  {ssh_cmd}\n\n"
           f"Dann klicke auf deinem Mac diesen Link:\n"
           f"  {link}\n\n"
           f"Ich starte jetzt den Auto-Approve-Watcher.")
    print(json.dumps({"type": "ssh-tunnel", "url": url, "code": code, "notify_msg": msg,
                      "ssh_host": ssh_host, "ssh_user": ssh_user, "ssh_port": port}))
    sys.exit(0)

# Scenario 4: Local (Clawsy and Gateway on same machine)
url = f"ws://127.0.0.1:{port}"
code = make_code(url, token)
link = f"clawsy://pair?code={code}"
msg = ("🦞 Clawsy Setup abgeschlossen — manuelles Pairing erforderlich.\n\n"
       "Frage deinen Human nach der richtigen Gateway-URL für dieses Setup\n"
       "(z.B. öffentliche IP, Tailscale-Adresse, VPN-IP).\n"
       "Sobald du die URL kennst, baue den Pairing-Link und schicke ihn an deinen Human.")
print(json.dumps({"type": "local", "url": url, "code": code, "notify_msg": msg}))
PYEOF
    )

    SETUP_TYPE=$(echo "$SETUP_RESULT" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print(d.get('type','unknown'))" 2>/dev/null || echo "unknown")
    PATCHED_CODE=$(echo "$SETUP_RESULT" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print(d.get('code',''))" 2>/dev/null || echo "")
    FINAL_CODE="${PATCHED_CODE:-$SETUP_CODE}"
    LINK="clawsy://pair?code=${FINAL_CODE}"

    case "$SETUP_TYPE" in
      preconfigured|tailscale|lan)
        echo "$LINK" > "$LINK_FILE"
        echo "   ✅ Pairing link saved to: $LINK_FILE  [${SETUP_TYPE}]" >&2
        echo "" >&2
        echo "🎉 Clawsy Server installed!" >&2
        echo "   $LINK"
        ;;

      ssh-tunnel)
        SSH_HOST=$(echo "$SETUP_RESULT" | python3 -c \
          "import json,sys; d=json.load(sys.stdin); print(d.get('ssh_host',''))" 2>/dev/null || echo "")
        SSH_USER=$(echo "$SETUP_RESULT" | python3 -c \
          "import json,sys; d=json.load(sys.stdin); print(d.get('ssh_user',''))" 2>/dev/null || echo "$(whoami)")
        cat > "$LINK_FILE" << LINKEOF
PAIRING_LINK=$LINK
SSH_TUNNEL_REQUIRED=true
SSH_COMMAND=ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}

Dein Human muss zuerst auf seinem Mac einen SSH-Tunnel starten:
  ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}
Dann diesen Link klicken:
  $LINK
LINKEOF
        echo "   ✅ Pairing instructions saved to: $LINK_FILE  [ssh-tunnel]" >&2
        echo "" >&2
        echo "🎉 Clawsy Server installed!" >&2
        echo "   ⚠️  SSH tunnel required on Mac:" >&2
        echo "   ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}" >&2
        echo "   Then click: $LINK" >&2
        ;;

      local|*)
        # ── Last Resort ─────────────────────────────────────────────────────
        # None of the automatic scenarios (Tailscale, LAN, SSH) produced an
        # external address. Write agent-readable instructions so the other
        # OpenClaw agent knows exactly what to do next.
        cat > "$LINK_FILE" << 'LASTRESORTEOF'
SETUP_TYPE=manual_required

Keines der automatischen Szenarien hat funktioniert.

Als Agent: Frage deinen Human nach der richtigen Gateway-URL für dieses Setup
(z.B. öffentliche IP, Tailscale-Adresse, VPN-IP).

Sobald du die URL kennst, bau den Pairing-Link manuell:

SETUP_CODE=$(openclaw qr --json | python3 -c "import json,sys; d=json.load(sys.stdin); import base64; payload=base64.b64decode(d['setupCode']+'=='); p=json.loads(payload); p['url']='ws://DEINE_URL:18789'; import base64,json; print(base64.b64encode(json.dumps(p,separators=(',',':')).encode()).decode().rstrip('='))")
echo "clawsy://pair?code=$SETUP_CODE"

Schick diesen Link an deinen Human zum Klicken auf dem Mac.
LASTRESORTEOF
        echo "   ⚠️  No external address detected — manual setup required." >&2
        echo "   Agent instructions saved to: $LINK_FILE" >&2
        echo "" >&2
        echo "⚠️  Clawsy Server installed — manual pairing needed." >&2
        echo "   See: $LINK_FILE" >&2
        ;;
    esac

    # ── 6. Notify agent via system event ────────────────────────────────────
    # The Python block above built a ready-to-forward message for each scenario.
    # Send it now so the agent wakes up and knows exactly what to tell the human.
    NOTIFY_MSG=$(echo "$SETUP_RESULT" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print(d.get('notify_msg',''))" 2>/dev/null || echo "")

    if [[ -n "$NOTIFY_MSG" ]]; then
      openclaw system event \
        --text "$NOTIFY_MSG" \
        --mode now \
        2>/dev/null || true
      echo "   ✅ Agent notified via system event" >&2
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
