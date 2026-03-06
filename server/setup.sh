#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Auto-detect OpenClaw
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
WORKSPACE="${OPENCLAW_WORKSPACE:-$OPENCLAW_HOME/workspace}"

echo "🦞 Clawsy Server Setup"
echo "   OpenClaw Home: $OPENCLAW_HOME"
echo "   Workspace: $WORKSPACE"

# 1. Create cache directory
mkdir -p "$WORKSPACE/clawsy-cache"

# 2. Install systemd service (if systemd available)
if command -v systemctl &>/dev/null; then
  # Create service file dynamically (portable!)
  SERVICE_FILE="/etc/systemd/system/clawsy-monitor.service"
  NODE_PATH=$(command -v node)
  MONITOR_SCRIPT="$SCRIPT_DIR/monitor.mjs"

  # Detect the user running OpenClaw
  OPENCLAW_USER=$(stat -c '%U' "$OPENCLAW_HOME" 2>/dev/null || echo "$USER")

  sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Clawsy Monitor — Event cache for OpenClaw agents
After=network.target

[Service]
Type=simple
User=$OPENCLAW_USER
ExecStart=$NODE_PATH $MONITOR_SCRIPT
Restart=always
RestartSec=5
Environment=OPENCLAW_HOME=$OPENCLAW_HOME
Environment=OPENCLAW_WORKSPACE=$WORKSPACE
Environment=NODE_NO_WARNINGS=1

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl daemon-reload
  sudo systemctl enable clawsy-monitor
  sudo systemctl restart clawsy-monitor
  echo "✅ clawsy-monitor service installed and running"
else
  echo "⚠️  No systemd found. Run monitor manually:"
  echo "   node $SCRIPT_DIR/monitor.mjs"
fi

# 3. Copy CLAWSY.md template to workspace (if not exists)
if [ ! -f "$WORKSPACE/CLAWSY.md" ] && [ -f "$SCRIPT_DIR/templates/CLAWSY.md" ]; then
  cp "$SCRIPT_DIR/templates/CLAWSY.md" "$WORKSPACE/CLAWSY.md"
  echo "✅ CLAWSY.md installed in workspace"
fi

# 4. Register Gateway plugin (clawsy-bridge) in openclaw.json
OPENCLAW_CONFIG="$OPENCLAW_HOME/openclaw.json"
PLUGIN_SRC="$SCRIPT_DIR/gateway-plugin.js"
PLUGIN_DEST="$OPENCLAW_HOME/plugins/clawsy-bridge.js"

if [ -f "$OPENCLAW_CONFIG" ] && [ -f "$PLUGIN_SRC" ]; then
  mkdir -p "$OPENCLAW_HOME/plugins"
  cp "$PLUGIN_SRC" "$PLUGIN_DEST"

  # Check if plugin is already registered
  if ! grep -q "clawsy-bridge" "$OPENCLAW_CONFIG" 2>/dev/null; then
    echo ""
    echo "⚠️  Manual step required: Register the Gateway plugin in openclaw.json"
    echo "   Add this to plugins.entries in $OPENCLAW_CONFIG:"
    echo ""
    echo '     "clawsy-bridge": {'
    echo '       "enabled": true,'
    echo "       \"path\": \"$PLUGIN_DEST\""
    echo '     }'
    echo ""
    echo "   Then restart OpenClaw: openclaw gateway restart"
  else
    echo "✅ Gateway plugin already registered"
  fi
fi

echo ""
echo "🦞 Done! Next steps:"
echo "   1. Install Clawsy on your Mac: https://github.com/iret77/clawsy/releases/latest"
echo "   2. Register the Gateway plugin (see above) and restart OpenClaw"
echo "   3. Connect Clawsy to this server"
echo "   4. Tell your agent: 'Clawsy is installed. Read the clawsy skill.'"
