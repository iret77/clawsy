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

# 4. Register Gateway plugin in openclaw.json
OPENCLAW_CONFIG="$OPENCLAW_HOME/openclaw.json"
PLUGIN_SRC="$SCRIPT_DIR/gateway-plugin.js"
PLUGIN_DEST="$OPENCLAW_HOME/plugins/clawsy-bridge.js"
EXTENSIONS_DIR="$OPENCLAW_HOME/extensions/clawsy-bridge"
PLUGIN_JSON_SRC="$SCRIPT_DIR/../skills/clawsy-bridge/openclaw.plugin.json"

if [ -f "$OPENCLAW_CONFIG" ] && [ -f "$PLUGIN_SRC" ]; then
  mkdir -p "$OPENCLAW_HOME/plugins"
  cp "$PLUGIN_SRC" "$PLUGIN_DEST"
  echo "✅ Gateway plugin copied to $PLUGIN_DEST"

  # Create extensions directory entry with manifest
  mkdir -p "$EXTENSIONS_DIR"
  cp "$PLUGIN_DEST" "$EXTENSIONS_DIR/index.js"

  # Copy or create openclaw.plugin.json in extensions dir
  if [ -f "$PLUGIN_JSON_SRC" ]; then
    cp "$PLUGIN_JSON_SRC" "$EXTENSIONS_DIR/openclaw.plugin.json"
  else
    cat > "$EXTENSIONS_DIR/openclaw.plugin.json" << 'MANIFEST'
{
  "id": "clawsy-bridge",
  "name": "Clawsy Bridge",
  "description": "Routes Clawsy events to agent context and responds to server probes.",
  "version": "1.0.0",
  "configSchema": { "type": "object", "additionalProperties": false, "properties": {} }
}
MANIFEST
  fi

  # Add to plugins.entries in openclaw.json using Node.js
  node -e "
    const fs = require('fs');
    const config = JSON.parse(fs.readFileSync('$OPENCLAW_CONFIG', 'utf8'));
    if (!config.plugins) config.plugins = {};
    if (!config.plugins.entries) config.plugins.entries = {};
    if (!config.plugins.load) config.plugins.load = {};
    if (!config.plugins.load.paths) config.plugins.load.paths = [];

    // Add to load.paths if not already there
    const pluginPath = '$EXTENSIONS_DIR';
    if (!config.plugins.load.paths.includes(pluginPath)) {
      config.plugins.load.paths.push(pluginPath);
    }

    // Enable in entries
    config.plugins.entries['clawsy-bridge'] = { enabled: true };

    fs.writeFileSync('$OPENCLAW_CONFIG', JSON.stringify(config, null, 2));
    console.log('✅ clawsy-bridge registered in openclaw.json');
  " 2>/dev/null && echo "✅ openclaw.json updated" || echo "⚠️  Could not auto-update openclaw.json — add manually"

  # Restart gateway
  if command -v openclaw &>/dev/null; then
    echo "🔄 Restarting OpenClaw gateway..."
    openclaw gateway restart
    echo "✅ Gateway restarted"
  else
    echo "⚠️  Please restart OpenClaw gateway: openclaw gateway restart"
  fi
fi

echo ""
echo "🦞 Done! Next steps:"
echo "   1. Install Clawsy on your Mac: https://github.com/iret77/clawsy/releases/latest"
echo "   2. Connect Clawsy to this server"
echo "   3. Tell your agent: 'Clawsy is installed. Read the clawsy skill.'"
