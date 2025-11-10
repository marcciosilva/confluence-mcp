#!/bin/bash
# Helper script to add confluence-kb to existing Gemini settings.json

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
ENV_FILE="$HOME/.confluence_mcp.env"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "Adding Confluence KB to Gemini settings..."
echo ""

# Load environment
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: Configuration file not found at $ENV_FILE${NC}"
    echo "Run ./install.sh first"
    exit 1
fi

source "$ENV_FILE"

# Check if settings.json exists
if [ ! -f "$GEMINI_SETTINGS" ]; then
    echo -e "${RED}Error: Gemini settings.json not found${NC}"
    echo "Expected location: $GEMINI_SETTINGS"
    exit 1
fi

# Backup existing settings
cp "$GEMINI_SETTINGS" "$GEMINI_SETTINGS.backup"
echo -e "${GREEN}✓ Backed up existing settings to $GEMINI_SETTINGS.backup${NC}"

# Use Python to merge the JSON
python3 << EOF
import json
import sys

settings_file = "$GEMINI_SETTINGS"
script_dir = "$SCRIPT_DIR"
venv_python = f"{script_dir}/venv/bin/python"
confluence_url = "$CONFLUENCE_URL"
confluence_email = "$CONFLUENCE_EMAIL"
confluence_token = "$CONFLUENCE_API_TOKEN"
confluence_spaces = "$CONFLUENCE_SPACES"

# Read existing settings
with open(settings_file, 'r') as f:
    settings = json.load(f)

# Ensure mcpServers exists
if 'mcpServers' not in settings:
    settings['mcpServers'] = {}

# Add confluence-kb server
settings['mcpServers']['confluence-kb'] = {
    "command": venv_python,
    "args": [f"{script_dir}/confluence_knowledge_base.py"],
    "env": {
        "CONFLUENCE_URL": confluence_url,
        "CONFLUENCE_EMAIL": confluence_email,
        "CONFLUENCE_API_TOKEN": confluence_token,
        "CONFLUENCE_SPACES": confluence_spaces
    },
    "timeout": 60000
}

# Write back
with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("✓ Added confluence-kb to settings.json")
EOF

echo -e "${GREEN}✓ Configuration updated successfully${NC}"
echo ""
echo "Your settings.json now includes both:"
echo "  • peyaServer"
echo "  • confluence-kb"
echo ""
echo "Restart Gemini CLI to load the new server:"
echo "  $ gemini"
echo "  > /mcp"
echo ""
