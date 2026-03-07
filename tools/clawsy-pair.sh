#!/bin/bash
# clawsy-pair.sh — Generiert einen Clawsy Deep-Link und wartet auf das Pairing
#
# Wird vom Agenten aufgerufen wenn ein User "pair clawsy" schreibt.
# Gibt den Deep-Link aus und wartet automatisch auf das Pairing-Request,
# das approved wird sobald der User den Link klickt.
#
# Usage:
#   ./clawsy-pair.sh              → gibt Link aus, wartet auf Pairing (120s)
#   ./clawsy-pair.sh --link-only  → gibt nur den Deep-Link aus, kein Watcher
#   ./clawsy-pair.sh --timeout 60 → kürzerer Timeout
#
# Output (line by line):
#   LINK=clawsy://pair?code=...
#   WAITING
#   APPROVED=<deviceId>   (wenn approved)
#   TIMEOUT               (wenn nicht approved in Zeit)
#   ERROR=<msg>           (bei Fehler)

set -euo pipefail

TIMEOUT=120
LINK_ONLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --link-only) LINK_ONLY=true; shift ;;
    --timeout)   TIMEOUT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# 1. Setup-Code generieren
SETUP_CODE=$(openclaw qr --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['setupCode'])" 2>/dev/null)
if [[ -z "$SETUP_CODE" ]]; then
  echo "ERROR=Failed to generate setup code (is OpenClaw gateway running?)"
  exit 1
fi

DEEP_LINK="clawsy://pair?code=${SETUP_CODE}"
echo "LINK=${DEEP_LINK}"

if $LINK_ONLY; then
  exit 0
fi

echo "WAITING"

# 2. Warte auf Pairing-Request (polling)
START=$(date +%s)
APPROVED=""

while true; do
  NOW=$(date +%s)
  ELAPSED=$((NOW - START))
  if [[ $ELAPSED -ge $TIMEOUT ]]; then
    echo "TIMEOUT"
    exit 1
  fi

  # Lese pending devices als JSON
  PENDING_JSON=$(openclaw devices list --json 2>/dev/null)
  PENDING=$(echo "$PENDING_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
pending = data.get('pending', [])
# Nimm den neuesten Request (letzter Eintrag)
if pending:
    req = pending[-1]
    print(req.get('requestId', ''))
" 2>/dev/null || true)

  if [[ -n "$PENDING" ]]; then
    # Auto-approve — retry kurz falls Gateway noch nicht bereit
    for i in 1 2 3; do
      RESULT=$(openclaw devices approve "$PENDING" 2>&1)
      if echo "$RESULT" | grep -q "Approved\|approved"; then
        echo "APPROVED=${PENDING}"
        exit 0
      fi
      # "unknown requestId" → noch nicht registriert, kurz warten
      sleep 1
    done
  fi

  sleep 2
done
