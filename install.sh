#!/bin/bash
# Confluence Knowledge Base MCP Server - Interactive Setup Wizard

set -e

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HOME/.confluence_mcp.env"
GEMINI_SETTINGS="$HOME/.gemini/settings.json"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Confluence Knowledge Base MCP Server - Setup Wizard         ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}[1/7] Checking prerequisites...${NC}"

if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Error: Python 3 is not installed${NC}"
    echo "Please install Python 3.8 or higher"
    exit 1
fi

PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
echo -e "${GREEN}✓ Python ${PYTHON_VERSION} found${NC}"

if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}Error: pip3 is not installed${NC}"
    exit 1
fi

echo -e "${GREEN}✓ pip3 found${NC}"
echo ""

# Step 2: Install dependencies
echo -e "${BLUE}[2/7] Installing Python dependencies...${NC}"
echo "This may take a few minutes..."

pip3 install -q --upgrade pip
pip3 install -q -r "$SCRIPT_DIR/requirements.txt"

echo -e "${GREEN}✓ Dependencies installed${NC}"
echo ""

# Step 3: Gather Confluence credentials
echo -e "${BLUE}[3/7] Configuring Confluence connection...${NC}"
echo ""

# Check if config already exists
if [ -f "$ENV_FILE" ]; then
    echo -e "${YELLOW}Found existing configuration at $ENV_FILE${NC}"
    read -p "Do you want to use the existing configuration? (y/n): " use_existing
    if [[ "$use_existing" =~ ^[Yy]$ ]]; then
        source "$ENV_FILE"
        echo -e "${GREEN}✓ Using existing configuration${NC}"
    else
        rm "$ENV_FILE"
    fi
fi

# Gather credentials if not already set
if [ -z "$CONFLUENCE_URL" ]; then
    echo "Enter your Confluence URL (e.g., https://yourcompany.atlassian.net):"
    read -p "URL: " CONFLUENCE_URL

    echo ""
    echo "Enter your Confluence email address:"
    read -p "Email: " CONFLUENCE_EMAIL

    echo ""
    echo "Enter your Confluence API token:"
    echo -e "${YELLOW}Get it from: https://id.atlassian.com/manage-profile/security/api-tokens${NC}"
    read -sp "API Token: " CONFLUENCE_API_TOKEN
    echo ""

    # Save to env file
    cat > "$ENV_FILE" << EOF
export CONFLUENCE_URL="$CONFLUENCE_URL"
export CONFLUENCE_EMAIL="$CONFLUENCE_EMAIL"
export CONFLUENCE_API_TOKEN="$CONFLUENCE_API_TOKEN"
EOF

    chmod 600 "$ENV_FILE"
    echo -e "${GREEN}✓ Credentials saved to $ENV_FILE${NC}"
else
    echo -e "${GREEN}✓ Using credentials from $ENV_FILE${NC}"
fi

echo ""

# Step 4: Test connection and discover spaces
echo -e "${BLUE}[4/7] Testing Confluence connection...${NC}"

export CONFLUENCE_URL
export CONFLUENCE_EMAIL
export CONFLUENCE_API_TOKEN

# Test connection
TEST_RESULT=$(python3 -c "
import requests
import sys
try:
    url = '$CONFLUENCE_URL/wiki/rest/api/space?limit=1'
    auth = ('$CONFLUENCE_EMAIL', '$CONFLUENCE_API_TOKEN')
    response = requests.get(url, auth=auth, timeout=10)
    if response.status_code == 200:
        print('SUCCESS')
        sys.exit(0)
    else:
        print(f'HTTP {response.status_code}')
        sys.exit(1)
except Exception as e:
    print(f'ERROR: {e}')
    sys.exit(1)
" 2>&1)

if [ "$TEST_RESULT" != "SUCCESS" ]; then
    echo -e "${RED}✗ Connection failed: $TEST_RESULT${NC}"
    echo ""
    echo "Please check:"
    echo "  1. Your Confluence URL is correct"
    echo "  2. Your API token is valid"
    echo "  3. You have internet connectivity"
    echo ""
    echo "Run this script again to retry."
    exit 1
fi

echo -e "${GREEN}✓ Connection successful${NC}"
echo ""

# Step 5: Discover and select spaces
echo -e "${BLUE}[5/7] Discovering Confluence spaces...${NC}"
echo ""

# Run space discovery
SPACES_OUTPUT=$(python3 "$SCRIPT_DIR/find_space_keys.py" 2>&1)

if [ $? -ne 0 ]; then
    echo -e "${RED}Error discovering spaces:${NC}"
    echo "$SPACES_OUTPUT"
    exit 1
fi

echo "$SPACES_OUTPUT"
echo ""

# Extract space keys for selection
SPACE_KEYS=$(echo "$SPACES_OUTPUT" | grep "^Space Key:" | awk '{print $3}')
SPACE_ARRAY=()
while IFS= read -r line; do
    SPACE_ARRAY+=("$line")
done <<< "$SPACE_KEYS"

if [ ${#SPACE_ARRAY[@]} -eq 0 ]; then
    echo -e "${RED}No spaces found${NC}"
    exit 1
fi

echo -e "${YELLOW}Found ${#SPACE_ARRAY[@]} space(s)${NC}"
echo ""

# Interactive space selection
echo "Which spaces do you want to include in your knowledge base?"
echo ""
echo "Recommendations:"
echo "  ✓ Include: Engineering, DevOps, Technical Documentation"
echo "  ✗ Skip: Personal spaces (~username), Meeting Notes, HR/Admin"
echo ""
echo "Enter space keys separated by commas (e.g., ENG,DEVOPS,TEAM)"
echo "Or press Enter to include all non-personal spaces"
echo ""

read -p "Spaces: " SELECTED_SPACES

# If empty, use all non-personal spaces
if [ -z "$SELECTED_SPACES" ]; then
    SELECTED_SPACES=$(echo "$SPACE_KEYS" | grep -v "^~" | tr '\n' ',' | sed 's/,$//')
    echo -e "${YELLOW}Selected all non-personal spaces: $SELECTED_SPACES${NC}"
fi

# Save to env file
echo "export CONFLUENCE_SPACES=\"$SELECTED_SPACES\"" >> "$ENV_FILE"
export CONFLUENCE_SPACES="$SELECTED_SPACES"

echo ""
echo -e "${GREEN}✓ Selected spaces: $SELECTED_SPACES${NC}"
echo ""

# Step 6: Build initial index
echo -e "${BLUE}[6/7] Building knowledge base index...${NC}"
echo "This may take a few minutes depending on the amount of documentation."
echo ""

read -p "Do you want to build the index now? (recommended) (y/n): " build_now

if [[ "$build_now" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Indexing in progress..."
    python3 "$SCRIPT_DIR/confluence_knowledge_base.py" 2>&1 | grep -E "(Fetching|Indexing|Created|Loading|complete|Ready)"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Index built successfully${NC}"
    else
        echo -e "${YELLOW}⚠ Index build encountered issues, but you can continue${NC}"
    fi
else
    echo -e "${YELLOW}Skipping index build. Run this command later:${NC}"
    echo "  source $ENV_FILE && python3 $SCRIPT_DIR/confluence_knowledge_base.py"
fi

echo ""

# Step 7: Configure Gemini CLI
echo -e "${BLUE}[7/7] Configuring Gemini CLI...${NC}"
echo ""

# Check if Gemini CLI is installed
if ! command -v gemini &> /dev/null; then
    echo -e "${YELLOW}⚠ Gemini CLI not found${NC}"
    echo ""
    echo "Install Gemini CLI from: https://github.com/google-gemini/gemini-cli"
    echo ""
    echo "After installation, add this to ~/.gemini/settings.json:"
    echo ""
    cat << EOF
{
  "mcpServers": {
    "confluence-kb": {
      "command": "python3",
      "args": ["$SCRIPT_DIR/confluence_knowledge_base.py"],
      "env": {
        "CONFLUENCE_URL": "$CONFLUENCE_URL",
        "CONFLUENCE_EMAIL": "$CONFLUENCE_EMAIL",
        "CONFLUENCE_API_TOKEN": "$CONFLUENCE_API_TOKEN",
        "CONFLUENCE_SPACES": "$CONFLUENCE_SPACES"
      },
      "timeout": 60000
    }
  }
}
EOF
    echo ""
else
    echo -e "${GREEN}✓ Gemini CLI found${NC}"

    # Create Gemini settings directory if it doesn't exist
    mkdir -p "$(dirname "$GEMINI_SETTINGS")"

    # Check if settings.json exists
    if [ ! -f "$GEMINI_SETTINGS" ]; then
        # Create new settings.json
        cat > "$GEMINI_SETTINGS" << EOF
{
  "mcpServers": {
    "confluence-kb": {
      "command": "python3",
      "args": ["$SCRIPT_DIR/confluence_knowledge_base.py"],
      "env": {
        "CONFLUENCE_URL": "$CONFLUENCE_URL",
        "CONFLUENCE_EMAIL": "$CONFLUENCE_EMAIL",
        "CONFLUENCE_API_TOKEN": "$CONFLUENCE_API_TOKEN",
        "CONFLUENCE_SPACES": "$CONFLUENCE_SPACES"
      },
      "timeout": 60000
    }
  }
}
EOF
        echo -e "${GREEN}✓ Created Gemini CLI configuration${NC}"
    else
        # Settings file exists - need to merge
        echo -e "${YELLOW}⚠ Gemini settings.json already exists${NC}"
        echo ""
        echo "Add this to your ~/.gemini/settings.json mcpServers section:"
        echo ""
        cat << EOF
"confluence-kb": {
  "command": "python3",
  "args": ["$SCRIPT_DIR/confluence_knowledge_base.py"],
  "env": {
    "CONFLUENCE_URL": "$CONFLUENCE_URL",
    "CONFLUENCE_EMAIL": "$CONFLUENCE_EMAIL",
    "CONFLUENCE_API_TOKEN": "$CONFLUENCE_API_TOKEN",
    "CONFLUENCE_SPACES": "$CONFLUENCE_SPACES"
  },
  "timeout": 60000
}
EOF
        echo ""
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! 🎉                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Your Confluence Knowledge Base is ready!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Start Gemini CLI:"
echo "   ${BLUE}gemini${NC}"
echo ""
echo "2. Verify the MCP server is loaded:"
echo "   ${BLUE}/mcp${NC}"
echo ""
echo "3. Ask questions about your documentation:"
echo "   ${BLUE}How does our authentication system work?${NC}"
echo "   ${BLUE}What are the deployment procedures?${NC}"
echo "   ${BLUE}Explain our API rate limits${NC}"
echo ""
echo "Configuration saved to:"
echo "  • $ENV_FILE"
echo "  • $GEMINI_SETTINGS"
echo ""
echo "To reindex when documentation is updated:"
echo "  ${BLUE}source $ENV_FILE && python3 $SCRIPT_DIR/confluence_knowledge_base.py${NC}"
echo ""
echo "For help, see: $SCRIPT_DIR/KNOWLEDGE_BASE_SETUP.md"
echo ""
