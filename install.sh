#!/bin/bash
# Local Documentation Knowledge Base MCP Server - Interactive Setup Wizard

set -e

# Colors for better UX
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HOME/.docs_mcp.env"
GEMINI_SETTINGS="$HOME/.gemini/settings.json"
VENV_DIR="$SCRIPT_DIR/venv"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Local Documentation Knowledge Base - Setup Wizard           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check prerequisites
echo -e "${BLUE}[1/5] Checking prerequisites...${NC}"

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

# Step 2: Create virtual environment and install dependencies
echo -e "${BLUE}[2/5] Setting up virtual environment...${NC}"

if [ -d "$VENV_DIR" ]; then
    echo -e "${YELLOW}Virtual environment already exists${NC}"
else
    echo "Creating virtual environment..."
    python3 -m venv "$VENV_DIR"
    echo -e "${GREEN}✓ Virtual environment created${NC}"
fi

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

echo "Installing Python dependencies..."
echo "This may take a few minutes..."

pip install -q --upgrade pip
pip install -q -r "$SCRIPT_DIR/requirements.txt"

echo -e "${GREEN}✓ Dependencies installed in virtual environment${NC}"
echo ""

# Step 3: Configure documentation directory
echo -e "${BLUE}[3/5] Configuring documentation directory...${NC}"
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

# Gather directory path if not already set
if [ -z "$DOCS_DIRECTORY" ]; then
    echo "Enter the path to your documentation directory:"
    echo "This directory should contain your PDF, TXT, or MD files."
    echo ""
    echo "Examples:"
    echo "  - $HOME/Documents/company-docs"
    echo "  - /path/to/your/documentation"
    echo ""
    read -e -p "Directory path: " DOCS_DIRECTORY

    # Expand tilde if present
    DOCS_DIRECTORY="${DOCS_DIRECTORY/#\~/$HOME}"

    # Save to env file
    cat > "$ENV_FILE" << EOF
export DOCS_DIRECTORY="$DOCS_DIRECTORY"
EOF

    chmod 600 "$ENV_FILE"
    echo -e "${GREEN}✓ Configuration saved to $ENV_FILE${NC}"
else
    echo -e "${GREEN}✓ Using directory from $ENV_FILE${NC}"
fi

export DOCS_DIRECTORY

echo ""

# Step 4: Validate directory
echo -e "${BLUE}[4/5] Validating documentation directory...${NC}"

if [ ! -d "$DOCS_DIRECTORY" ]; then
    echo -e "${RED}✗ Directory does not exist: $DOCS_DIRECTORY${NC}"
    echo ""
    echo "Please create the directory or specify a different path."
    echo "Run this script again to retry."
    exit 1
fi

if [ ! -r "$DOCS_DIRECTORY" ]; then
    echo -e "${RED}✗ No read access to directory: $DOCS_DIRECTORY${NC}"
    echo ""
    echo "Please check directory permissions."
    exit 1
fi

# Count supported files
FILE_COUNT=$(find "$DOCS_DIRECTORY" -type f \( -iname "*.pdf" -o -iname "*.txt" -o -iname "*.md" \) 2>/dev/null | wc -l | tr -d ' ')

if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}⚠ No PDF, TXT, or MD files found in $DOCS_DIRECTORY${NC}"
    echo ""
    echo "The server will start but no documents will be loaded."
    echo "Add files to the directory and run reindex_documents() from the MCP tools."
    echo ""
    read -p "Continue anyway? (y/n): " continue_empty
    if [[ ! "$continue_empty" =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✓ Found $FILE_COUNT supported file(s)${NC}"
fi

echo ""

# Step 5: Build initial index
echo -e "${BLUE}[5/5] Building knowledge base index...${NC}"
echo ""

if [ "$FILE_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}Skipping index build (no files found)${NC}"
    echo ""
else
    read -p "Do you want to build the index now? (recommended) (y/n): " build_now

    if [[ "$build_now" =~ ^[Yy]$ ]]; then
        echo ""
        echo "Indexing in progress..."
        source "$VENV_DIR/bin/activate"
        python3 "$SCRIPT_DIR/confluence_knowledge_base.py" 2>&1 | head -n 50

        if [ ${PIPESTATUS[0]} -eq 0 ]; then
            echo -e "${GREEN}✓ Index built successfully${NC}"
        else
            echo -e "${YELLOW}⚠ Index build encountered issues, but you can continue${NC}"
        fi
    else
        echo -e "${YELLOW}Skipping index build. Run this command later:${NC}"
        echo "  source $ENV_FILE && $VENV_DIR/bin/python $SCRIPT_DIR/confluence_knowledge_base.py"
    fi
fi

echo ""

# Configure Gemini CLI / Claude Code
echo -e "${BLUE}Configuring MCP client...${NC}"
echo ""

# Create Gemini settings directory if it doesn't exist
mkdir -p "$(dirname "$GEMINI_SETTINGS")"

# Check if settings.json exists
if [ ! -f "$GEMINI_SETTINGS" ]; then
    # Create new settings.json
    cat > "$GEMINI_SETTINGS" << EOF
{
  "mcpServers": {
    "docs-kb": {
      "command": "$VENV_DIR/bin/python",
      "args": ["$SCRIPT_DIR/confluence_knowledge_base.py"],
      "env": {
        "DOCS_DIRECTORY": "$DOCS_DIRECTORY"
      },
      "timeout": 60000
    }
  }
}
EOF
    echo -e "${GREEN}✓ Created MCP client configuration${NC}"
else
    # Settings file exists - merge automatically
    echo -e "${YELLOW}Existing settings.json found${NC}"
    echo "Merging docs-kb into existing configuration..."

    # Backup existing settings
    cp "$GEMINI_SETTINGS" "$GEMINI_SETTINGS.backup"
    echo -e "${GREEN}✓ Backed up to $GEMINI_SETTINGS.backup${NC}"

    # Use Python to merge the JSON
    source "$VENV_DIR/bin/activate"
    python3 << PYTHON_EOF
import json
import sys

settings_file = "$GEMINI_SETTINGS"

try:
    # Read existing settings
    with open(settings_file, 'r') as f:
        settings = json.load(f)

    # Ensure mcpServers exists
    if 'mcpServers' not in settings:
        settings['mcpServers'] = {}

    # Add docs-kb server
    settings['mcpServers']['docs-kb'] = {
        "command": "$VENV_DIR/bin/python",
        "args": ["$SCRIPT_DIR/confluence_knowledge_base.py"],
        "env": {
            "DOCS_DIRECTORY": "$DOCS_DIRECTORY"
        },
        "timeout": 60000
    }

    # Write back
    with open(settings_file, 'w') as f:
        json.dump(settings, f, indent=2)

    sys.exit(0)
except Exception as e:
    print(f"Error merging settings: {e}", file=sys.stderr)
    sys.exit(1)
PYTHON_EOF

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Added docs-kb to existing configuration${NC}"
    else
        echo -e "${RED}✗ Failed to merge configuration${NC}"
        echo "You can restore from backup: $GEMINI_SETTINGS.backup"
    fi
fi

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! 🎉                          ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}Your Local Documentation Knowledge Base is ready!${NC}"
echo ""
echo "Next steps:"
echo ""
echo "1. Add documentation files to your directory:"
echo "   ${BLUE}$DOCS_DIRECTORY${NC}"
echo "   (Supports: PDF, TXT, MD files)"
echo ""
echo "2. Start your MCP client (Gemini CLI / Claude Code)"
echo ""
echo "3. Verify the MCP server is loaded:"
echo "   For Gemini CLI: ${BLUE}/mcp${NC}"
echo "   For Claude Code: Check MCP status"
echo ""
echo "4. Ask questions about your documentation:"
echo "   ${BLUE}What are the deployment procedures?${NC}"
echo "   ${BLUE}Explain the API architecture${NC}"
echo ""
echo "Configuration saved to:"
echo "  • $ENV_FILE"
echo "  • $GEMINI_SETTINGS"
echo ""
echo "To reindex when documentation is updated:"
echo "  Use the ${BLUE}reindex_documents()${NC} tool from your MCP client"
echo "  Or run: ${BLUE}$VENV_DIR/bin/python $SCRIPT_DIR/confluence_knowledge_base.py${NC}"
echo ""
echo "Virtual environment location: $VENV_DIR"
echo ""
