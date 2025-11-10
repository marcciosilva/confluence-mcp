#!/bin/bash
# Quick setup script for Confluence Knowledge Base MCP Server

set -e

echo "==================================================="
echo "Confluence Knowledge Base MCP Server - Setup"
echo "==================================================="
echo ""

# Check if Python is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed"
    exit 1
fi

echo "✓ Python 3 found: $(python3 --version)"
echo ""

# Install dependencies
echo "Installing dependencies..."
pip install -q -r requirements.txt
echo "✓ Dependencies installed"
echo ""

# Check for environment variables
echo "Checking configuration..."

if [ -z "$CONFLUENCE_URL" ]; then
    echo ""
    echo "Please set the following environment variables:"
    echo ""
    echo "export CONFLUENCE_URL=\"https://yourcompany.atlassian.net\""
    echo "export CONFLUENCE_EMAIL=\"you@company.com\""
    echo "export CONFLUENCE_API_TOKEN=\"your-api-token\""
    echo "export CONFLUENCE_SPACES=\"TEAM,DOCS,ENG\""
    echo ""
    echo "Or create a .env file with these values."
    exit 1
fi

echo "✓ CONFLUENCE_URL: $CONFLUENCE_URL"
echo "✓ CONFLUENCE_EMAIL: $CONFLUENCE_EMAIL"
echo "✓ CONFLUENCE_API_TOKEN: [set]"
echo "✓ CONFLUENCE_SPACES: $CONFLUENCE_SPACES"
echo ""

# Build index
echo "Building initial index..."
echo "This may take a few minutes depending on your documentation size..."
echo ""

python3 confluence_knowledge_base.py &
SERVER_PID=$!

# Wait for indexing to complete (check log output)
sleep 5

echo ""
echo "==================================================="
echo "Setup Complete!"
echo "==================================================="
echo ""
echo "Next steps:"
echo "1. Add this to your ~/.gemini/settings.json:"
echo ""
cat << 'EOF'
{
  "mcpServers": {
    "confluence-kb": {
      "command": "python3",
      "args": ["/Users/marcciosilva/dev/work/peya/confluence_knowledge_base.py"],
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
echo "2. Start Gemini CLI and ask questions:"
echo "   $ gemini"
echo "   > How does our authentication system work?"
echo ""
echo "Index location: ~/.confluence_mcp/index/"
echo ""
