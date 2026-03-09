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

# ── 2. Install CLAWSY.md (agent instructions) ────────────────────────────────
mkdir -p "$WORKSPACE"
curl -fsSL "$REPO_RAW/server/templates/CLAWSY.md" -o "$WORKSPACE/CLAWSY.md" 2>/dev/null
echo "   ✅ CLAWSY.md installed" >&2

# ── 3. Install clawsy-pair.sh (auto-approve helper) ──────────────────────────
mkdir -p "$TOOLS_DIR"
curl -fsSL "$REPO_RAW/tools/clawsy-pair.sh" -o "$TOOLS_DIR/clawsy-pair.sh" 2>/dev/null
chmod +x "$TOOLS_DIR/clawsy-pair.sh"
echo "   ✅ clawsy-pair.sh installed" >&2

# ── 4. Restart gateway (plugin becomes active) ───────────────────────────────
if command -v openclaw &>/dev/null; then
  openclaw gateway restart >/dev/null 2>&1 &
  sleep 3
  echo "   ✅ Gateway restarted" >&2
fi

# ── 5. Generate pairing link + start auto-approve watcher ────────────────────
if command -v openclaw &>/dev/null; then
  # Wait for gateway to be ready (retry up to 5x with 2s delay)
  SETUP_CODE=""
  for attempt in 1 2 3 4 5; do
    SETUP_CODE=$(openclaw qr --json 2>/dev/null \
      | python3 -c "import json,sys; print(json.load(sys.stdin)['setupCode'])" 2>/dev/null || true)
    [[ -n "$SETUP_CODE" ]] && break
    echo "   ⏳ Waiting for gateway to be ready (attempt $attempt/5)..." >&2
    sleep 2
  done

  if [[ -n "$SETUP_CODE" ]]; then
    # Start auto-approve watcher with retry-verify (up to 3 attempts)
    PAIR_PID=""
    for _retry in 1 2 3; do
      bash "$TOOLS_DIR/clawsy-pair.sh" --timeout 300 >/dev/null 2>&1 &
      PAIR_PID=$!
      sleep 1
      if kill -0 "$PAIR_PID" 2>/dev/null; then
        echo "   ✅ Auto-approve watcher started (PID $PAIR_PID)" >&2
        break
      fi
      echo "   ⏳ Auto-approve watcher retry $_retry/3..." >&2
      sleep 2
    done
    if ! kill -0 "$PAIR_PID" 2>/dev/null; then
      echo "   ⚠️  Auto-approve watcher failed to start — pairing requires manual approval" >&2
    fi

    LINK_FILE="$WORKSPACE/clawsy-pairing-link.txt"
    GATEWAY_PORT=$(openclaw config get gateway.port 2>/dev/null || echo "18789")

    # ── Multi-scenario gateway URL detection ────────────────────────────────
    # Detects the network situation autonomously and builds a ready-to-forward
    # notify_msg for each scenario. No user input required. No "read the file".
    SETUP_RESULT=$(SETUP_CODE="$SETUP_CODE" GATEWAY_PORT="$GATEWAY_PORT" \
      SSH_CONNECTION="${SSH_CONNECTION:-}" python3 << 'PYEOF'
import json, base64, subprocess, os, sys, re

port = os.environ.get('GATEWAY_PORT', '18789')

# Decode setup code to extract token
raw = os.environ.get('SETUP_CODE', '')
try:
    decoded = json.loads(base64.b64decode(raw + '==').decode())
    token = decoded.get('token', '')
except Exception:
    print(json.dumps({"error": "decode_failed", "type": "manual_required",
                      "notify_msg": (
                          "🦞 Clawsy Setup: Pairing-Code konnte nicht dekodiert werden.\n\n"
                          "Sage deinem Human:\n"
                          "\"Bitte führe folgenden Befehl auf dem Server aus und "
                          "schicke mir die Ausgabe:\n"
                          "  openclaw qr --json\""
                      )}))
    sys.exit(0)

def make_code(url, token):
    payload = json.dumps({"url": url, "token": token}, separators=(',', ':'))
    return base64.b64encode(payload.encode()).decode().rstrip('=')

def is_private_ip(ip):
    parts = ip.split('.')
    if len(parts) != 4:
        return False
    try:
        a, b = int(parts[0]), int(parts[1])
        return (a == 10 or
                (a == 172 and 16 <= b <= 31) or
                (a == 192 and b == 168) or
                a == 127)
    except ValueError:
        return False

# Scenario 0: preconfigured remote.url (non-loopback)
try:
    r = subprocess.run(['openclaw', 'config', 'get', 'gateway.remote.url'],
                       capture_output=True, text=True, timeout=5)
    configured = r.stdout.strip()
    if configured and not any(x in configured for x in ['127.0.0.1', 'localhost', '0.0.0.0']):
        code = make_code(configured, token)
        link = f"clawsy://pair?code={code}"
        msg = (f"🦞 Clawsy ist bereit!\n\n"
               f"Sage deinem Human:\n"
               f"Klicke auf deinem Mac diesen Link:\n"
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
    if ts_ip and r.returncode == 0 and re.match(r'^\d+\.\d+\.\d+\.\d+$', ts_ip):
        url = f"ws://{ts_ip}:{port}"
        code = make_code(url, token)
        link = f"clawsy://pair?code={code}"
        msg = (f"🦞 Clawsy ist bereit! (via Tailscale)\n\n"
               f"Sage deinem Human:\n"
               f"Klicke auf deinem Mac diesen Link:\n"
               f"  {link}")
        print(json.dumps({"type": "tailscale", "url": url, "code": code, "notify_msg": msg}))
        sys.exit(0)
except Exception:
    pass

# Scenario 2: LAN IP — prefer 192.168.x.x, then 10.x.x.x, then 172.16-31.x.x
try:
    r = subprocess.run(['hostname', '-I'], capture_output=True, text=True, timeout=5)
    ips = r.stdout.strip().split()
    # Filter: only private, non-loopback, valid IPv4
    def ip_priority(ip):
        if not re.match(r'^\d+\.\d+\.\d+\.\d+$', ip): return 99
        parts = ip.split('.')
        a, b = int(parts[0]), int(parts[1])
        if a == 192 and b == 168: return 0   # most common home LAN
        if a == 10: return 1                 # corporate / Pi LAN
        if a == 172 and 16 <= b <= 31: return 2
        return 99
    candidates = [ip for ip in ips
                  if re.match(r'^\d+\.\d+\.\d+\.\d+$', ip)
                  and is_private_ip(ip) and not ip.startswith('127.')]
    candidates.sort(key=ip_priority)
    if candidates:
        lan_ip = candidates[0]
        url = f"ws://{lan_ip}:{port}"
        code = make_code(url, token)
        link = f"clawsy://pair?code={code}"
        msg = (f"🦞 Clawsy ist bereit!\n\n"
               f"Sage deinem Human:\n"
               f"Klicke auf deinem Mac diesen Link:\n"
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
           f"1. Öffne ein Terminal auf deinem Mac und führe diesen Befehl aus:\n"
           f"   {ssh_cmd}\n\n"
           f"2. Lass das Terminal offen — dann klicke diesen Link:\n"
           f"   {link}\n\n"
           f"(Der Auto-Approve-Watcher läuft bereits. Nach dem Klick ist alles erledigt.)")
    print(json.dumps({"type": "ssh-tunnel", "url": url, "code": code, "notify_msg": msg,
                      "ssh_host": ssh_host, "ssh_user": ssh_user, "ssh_port": port}))
    sys.exit(0)

# Scenario 4: Public IP (VPS / cloud server)
# Try a few external IP services — use the first that responds with a valid public IP.
pub_ip = None
for svc in ['https://api.ipify.org', 'https://ifconfig.me/ip', 'https://icanhazip.com']:
    try:
        r = subprocess.run(
            ['curl', '-fsSL', '--connect-timeout', '3', '--max-time', '5', svc],
            capture_output=True, text=True, timeout=8)
        candidate = r.stdout.strip()
        if r.returncode == 0 and re.match(r'^\d+\.\d+\.\d+\.\d+$', candidate) \
                and not is_private_ip(candidate):
            pub_ip = candidate
            break
    except Exception:
        pass

if pub_ip:
    url = f"ws://{pub_ip}:{port}"
    code = make_code(url, token)
    link = f"clawsy://pair?code={code}"
    msg = (f"🦞 Clawsy ist bereit! (öffentliche IP erkannt)\n\n"
           f"Sage deinem Human:\n"
           f"Klicke auf deinem Mac diesen Link:\n"
           f"  {link}\n\n"
           f"(Hinweis: Port {port} muss in der Firewall freigegeben sein.)")
    print(json.dumps({"type": "public-ip", "url": url, "code": code, "notify_msg": msg}))
    sys.exit(0)

# Scenario 5: Fallback — no external address found.
# Build a local-only link (works if Clawsy and OpenClaw are on the same machine),
# but give the agent a concrete question so the human can unblock the situation.
url = f"ws://127.0.0.1:{port}"
code = make_code(url, token)
link_local = f"clawsy://pair?code={code}"
msg = (f"🦞 Clawsy Setup — ich brauche kurz die Hilfe deines Humans.\n\n"
       f"Frage deinen Human:\n"
       f"\"Läuft OpenClaw auf dem gleichen Mac wie Clawsy?\"\n\n"
       f"→ JA (gleicher Mac):\n"
       f"  Klicke diesen Link:\n"
       f"  {link_local}\n\n"
       f"→ NEIN (anderes Gerät, z.B. Raspberry Pi / Server):\n"
       f"  Bitte gib mir die IP-Adresse des Geräts.\n"
       f"  Ich baue dann sofort den Pairing-Link.")
print(json.dumps({"type": "local", "url": url, "code": code, "notify_msg": msg}))
PYEOF
    )

    SETUP_TYPE=$(echo "$SETUP_RESULT" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print(d.get('type','unknown'))" 2>/dev/null \
      || echo "unknown")
    PATCHED_CODE=$(echo "$SETUP_RESULT" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print(d.get('code',''))" 2>/dev/null || echo "")
    FINAL_CODE="${PATCHED_CODE:-$SETUP_CODE}"
    LINK="clawsy://pair?code=${FINAL_CODE}"

    case "$SETUP_TYPE" in
      preconfigured|tailscale|lan|public-ip)
        echo "$LINK" > "$LINK_FILE"
        echo "   ✅ Pairing link saved  [${SETUP_TYPE}]: $LINK_FILE" >&2
        echo "" >&2
        echo "🎉 Clawsy Server installed!" >&2
        echo "   $LINK"
        ;;

      ssh-tunnel)
        SSH_HOST=$(echo "$SETUP_RESULT" | python3 -c \
          "import json,sys; d=json.load(sys.stdin); print(d.get('ssh_host',''))" 2>/dev/null \
          || echo "")
        SSH_USER=$(echo "$SETUP_RESULT" | python3 -c \
          "import json,sys; d=json.load(sys.stdin); print(d.get('ssh_user',''))" 2>/dev/null \
          || echo "$(whoami)")
        cat > "$LINK_FILE" << LINKEOF
PAIRING_LINK=$LINK
SSH_TUNNEL_REQUIRED=true
SSH_COMMAND=ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}

Dein Human muss zuerst auf seinem Mac einen SSH-Tunnel starten:
  ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}
Terminal offen lassen, dann diesen Link klicken:
  $LINK
LINKEOF
        echo "   ✅ Pairing instructions saved  [ssh-tunnel]: $LINK_FILE" >&2
        echo "" >&2
        echo "🎉 Clawsy Server installed!" >&2
        echo "   ⚠️  SSH tunnel required on Mac:" >&2
        echo "   ssh -L ${GATEWAY_PORT}:localhost:${GATEWAY_PORT} ${SSH_USER}@${SSH_HOST}" >&2
        echo "   Then click: $LINK" >&2
        ;;

      local|*)
        cat > "$LINK_FILE" << LOCALEOF
SETUP_TYPE=manual_required
PAIRING_LINK_LOCAL=$LINK

Kein externes Netzwerk automatisch erkannt.
Agent-Frage an Human: Läuft OpenClaw auf dem gleichen Mac wie Clawsy?
- JA: Oben stehender Link funktioniert direkt.
- NEIN: Human muss IP-Adresse des Geräts nennen.
LOCALEOF
        echo "   ⚠️  No external address detected — awaiting human input" >&2
        echo "   Instructions saved: $LINK_FILE" >&2
        echo "" >&2
        echo "⚠️  Clawsy Server installed — one question needed for pairing." >&2
        echo "   See: $LINK_FILE" >&2
        ;;
    esac

    # ── 6. Notify agent via system event ────────────────────────────────────
    # The Python block above built a complete, actionable notify_msg for each
    # scenario. Send it now so the agent wakes up and forwards it directly to
    # the human — no file reading, no guessing.
    NOTIFY_MSG=$(echo "$SETUP_RESULT" | python3 -c \
      "import json,sys; d=json.load(sys.stdin); print(d.get('notify_msg',''))" 2>/dev/null \
      || echo "")

    if [[ -n "$NOTIFY_MSG" ]]; then
      openclaw system event \
        --text "$NOTIFY_MSG" \
        --mode now \
        2>/dev/null || true
      echo "   ✅ Agent notified via system event" >&2
    fi

    echo "" >&2
    echo "✅ Done. Pairing info: $LINK_FILE" >&2
  else
    echo "" >&2
    echo "⚠️  Clawsy Server installed, but gateway didn't become ready in time." >&2
    echo "   Run manually: openclaw qr --json" >&2
  fi
else
  echo "⚠️  openclaw not in PATH. Is OpenClaw installed?" >&2
  exit 1
fi
