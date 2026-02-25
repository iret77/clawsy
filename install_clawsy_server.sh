#!/bin/bash

# 🦞 Clawsy Server Installer v0.3.2
# The "Super Easy" setup for OpenClaw hosts.

set -e

# Colors for the lobster vibe
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${RED}🦞 Clawsy Server Installer v0.3.2${NC}"
echo -e "${BLUE}Preparing your OpenClaw host for Mac interaction...${NC}\n"

WORKSPACE_DIR="${HOME}/.openclaw/workspace"

if [ ! -d "$WORKSPACE_DIR" ]; then
    echo -e "${RED}Error: OpenClaw workspace not found at ${WORKSPACE_DIR}${NC}"
    echo "Please make sure OpenClaw is installed and running."
    exit 1
fi

cd "$WORKSPACE_DIR"

# 1. Create memory directory if missing
mkdir -p memory

# 2. Update HEARTBEAT.md
echo -e "${GREEN}Adding Mood Analysis to HEARTBEAT.md...${NC}"
if [ ! -f "HEARTBEAT.md" ]; then
    touch HEARTBEAT.md
fi

# Append Task 2 if not already present
if ! grep -q "clawsy_mood" HEARTBEAT.md; then
    cat >> HEARTBEAT.md << 'EOF'

# --- CLAWSY SECTION START ---
# TASK: Semantic Mood Analysis for Clawsy Ecosystem.
# [INSTRUCTION for LLM]: 
# 1. Read the most recent messages from the user in this session.
# 2. Analyze: Tonalitiy (relaxed/stressed), Wording (formal/casual), and Error/Typos.
# 3. Determine a "semantic_mood" string (e.g., "relaxed", "focused", "stressed", "tired").
# 4. Write the result as a compact JSON object into `memory/clawsy_mood.json`.
# Format: {"semantic_mood": "...", "analyzed_at": "ISO-TIMESTAMP", "confidence": 0.0-1.0}
# --- CLAWSY SECTION END ---
EOF
fi

# 3. Update AGENTS.md for Awareness
echo -e "${GREEN}Teaching your Agent about Clawsy in AGENTS.md...${NC}"
if [ ! -f "AGENTS.md" ]; then
    touch AGENTS.md
fi

if ! grep -q "clawsy_envelope" AGENTS.md; then
    cat >> AGENTS.md << 'EOF'

## 🦞 Clawsy Integration (Mac Companion)
- **Context Awareness:** Clawsy (Mac App) sends metadata in messages wrapped in a `clawsy_envelope` JSON object.
- **Mood Data:** Check `memory/clawsy_mood.json` for current semantic mood analysis.
- **Workflow:** When you see a `clawsy_envelope` (Active App, Battery, Thermal), use this data to tailor your response tone and depth.
EOF
fi

# 4. Create placeholder for mood
if [ ! -f "memory/clawsy_mood.json" ]; then
    echo '{"semantic_mood": "neutral", "analyzed_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'", "confidence": 0.5}' > memory/clawsy_mood.json
fi

echo -e "\n${GREEN}✅ Server-side setup complete!${NC}"
echo -e "Your OpenClaw Agent is now 'Clawsy-aware'. 🦞✨"
echo -e "Next step: Install the Clawsy Mac App and connect to this host."
