#!/bin/bash
# Test script to verify Confluence Knowledge Base installation

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$HOME/.confluence_mcp.env"
INDEX_DIR="$HOME/.confluence_mcp/index"
GEMINI_SETTINGS="$HOME/.gemini/settings.json"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║   Confluence Knowledge Base - Installation Test               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

PASSED=0
FAILED=0

# Test 1: Check Python
echo -n "Testing Python installation... "
if command -v python3 &> /dev/null; then
    VERSION=$(python3 --version | cut -d' ' -f2)
    echo -e "${GREEN}✓ Python $VERSION${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Python 3 not found${NC}"
    ((FAILED++))
fi

# Test 2: Check dependencies
echo -n "Testing Python dependencies... "
MISSING_DEPS=()

for pkg in fastmcp chromadb sentence-transformers beautifulsoup4; do
    if ! python3 -c "import ${pkg/_/-}" 2>/dev/null; then
        MISSING_DEPS+=("$pkg")
    fi
done

if [ ${#MISSING_DEPS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ All packages installed${NC}"
    ((PASSED++))
else
    echo -e "${RED}✗ Missing: ${MISSING_DEPS[*]}${NC}"
    echo "   Run: pip3 install -r requirements.txt"
    ((FAILED++))
fi

# Test 3: Check configuration file
echo -n "Testing configuration file... "
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
    if [ -n "$CONFLUENCE_URL" ] && [ -n "$CONFLUENCE_EMAIL" ] && [ -n "$CONFLUENCE_API_TOKEN" ] && [ -n "$CONFLUENCE_SPACES" ]; then
        echo -e "${GREEN}✓ Configuration found${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ Configuration incomplete${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}✗ No configuration file${NC}"
    echo "   Run: ./install.sh"
    ((FAILED++))
fi

# Test 4: Check Confluence connection
if [ -n "$CONFLUENCE_URL" ]; then
    echo -n "Testing Confluence connection... "
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

    if [ "$TEST_RESULT" = "SUCCESS" ]; then
        echo -e "${GREEN}✓ Connected to $CONFLUENCE_URL${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ Connection failed: $TEST_RESULT${NC}"
        ((FAILED++))
    fi
fi

# Test 5: Check index
echo -n "Testing knowledge base index... "
if [ -d "$INDEX_DIR" ] && [ -f "$INDEX_DIR/metadata.json" ]; then
    METADATA=$(cat "$INDEX_DIR/metadata.json")
    PAGE_COUNT=$(echo "$METADATA" | python3 -c "import sys, json; print(json.load(sys.stdin).get('total_pages', 0))")
    SPACES=$(echo "$METADATA" | python3 -c "import sys, json; print(','.join(json.load(sys.stdin).get('spaces', [])))")
    echo -e "${GREEN}✓ Index exists ($PAGE_COUNT pages from $SPACES)${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ Index not built${NC}"
    echo "   Run: source $ENV_FILE && python3 $SCRIPT_DIR/confluence_knowledge_base.py"
    # Don't count as failure - might be intentional
fi

# Test 6: Check Gemini CLI
echo -n "Testing Gemini CLI... "
if command -v gemini &> /dev/null; then
    echo -e "${GREEN}✓ Gemini CLI installed${NC}"
    ((PASSED++))
else
    echo -e "${YELLOW}⚠ Gemini CLI not found${NC}"
    echo "   Install from: https://github.com/google-gemini/gemini-cli"
    # Don't count as failure
fi

# Test 7: Check Gemini settings
echo -n "Testing Gemini configuration... "
if [ -f "$GEMINI_SETTINGS" ]; then
    if grep -q "confluence-kb" "$GEMINI_SETTINGS" 2>/dev/null; then
        echo -e "${GREEN}✓ MCP server configured${NC}"
        ((PASSED++))
    else
        echo -e "${YELLOW}⚠ MCP server not in settings.json${NC}"
        echo "   Add configuration manually - see README.md"
    fi
else
    echo -e "${YELLOW}⚠ No Gemini settings.json${NC}"
    echo "   Will be created on first Gemini CLI run"
fi

# Summary
echo ""
echo "════════════════════════════════════════════════════════════════"
echo "Test Results: $PASSED passed, $FAILED failed"
echo "════════════════════════════════════════════════════════════════"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All critical tests passed!${NC}"
    echo ""
    echo "Your Confluence Knowledge Base is ready to use."
    echo ""
    echo "Start Gemini CLI:"
    echo "  $ gemini"
    echo ""
    echo "Verify MCP server:"
    echo "  > /mcp"
    echo ""
    echo "Ask a question:"
    echo "  > How does our authentication system work?"
    echo ""
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    echo "Please fix the issues above and run ./install.sh"
    echo ""
    exit 1
fi
