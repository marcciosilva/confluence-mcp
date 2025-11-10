#!/bin/bash
# Test Confluence API access with detailed diagnostics

echo "Confluence API Connection Test"
echo "================================"
echo ""

# Load config
if [ -f ~/.confluence_mcp.env ]; then
    source ~/.confluence_mcp.env
else
    echo "Error: ~/.confluence_mcp.env not found"
    exit 1
fi

echo "Testing with:"
echo "  URL: $CONFLUENCE_URL"
echo "  Email: $CONFLUENCE_EMAIL"
echo "  Spaces: $CONFLUENCE_SPACES"
echo ""

# Detect Confluence type
echo "Detecting Confluence type..."
if [[ "$CONFLUENCE_URL" =~ "atlassian.net" ]]; then
    CONFLUENCE_TYPE="Cloud"
    echo "Detected: Confluence Cloud"
elif [[ "$CONFLUENCE_URL" =~ "atlassian.com" ]]; then
    CONFLUENCE_TYPE="Cloud"
    echo "Detected: Confluence Cloud"
else
    CONFLUENCE_TYPE="Data Center/Server"
    echo "Detected: Confluence Data Center or Server (self-hosted)"
fi
echo ""

# Test 1: Basic connectivity and redirect detection
echo "Test 1: Basic connectivity to Confluence..."
RESPONSE=$(curl -s -L -w "\nHTTP_CODE:%{http_code}\nREDIRECT_URL:%{redirect_url}\nFINAL_URL:%{url_effective}" "$CONFLUENCE_URL/wiki")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
REDIRECT_URL=$(echo "$RESPONSE" | grep "REDIRECT_URL:" | cut -d':' -f2-)
FINAL_URL=$(echo "$RESPONSE" | grep "FINAL_URL:" | cut -d':' -f2-)

echo "HTTP Status: $HTTP_CODE"
if [ -n "$REDIRECT_URL" ]; then
    echo "⚠ Redirect detected to: $REDIRECT_URL"
    if [[ "$REDIRECT_URL" =~ "login" ]] || [[ "$FINAL_URL" =~ "login" ]]; then
        echo "⚠ WARNING: Redirecting to login page - this may indicate SSO/external authentication"
    fi
fi
echo ""

# Test 2: API authentication (get current user)
echo "Test 2: API authentication (get current user)..."
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -u "$CONFLUENCE_EMAIL:$CONFLUENCE_API_TOKEN" \
  "$CONFLUENCE_URL/wiki/rest/api/user/current" \
  -H "Accept: application/json")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo "HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Authentication successful"
    echo "$BODY" | python3 -m json.tool 2>/dev/null | grep -E '"displayName"|"email"' || echo "$BODY"
elif [ "$HTTP_CODE" = "401" ]; then
    echo "✗ Authentication failed - check your email and API token"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "✗ Forbidden - user may not have Confluence license/access"
    echo "Response: $BODY"
else
    echo "✗ Unexpected response"
    echo "Response: $BODY"
fi
echo ""

# Test 3: List all spaces (doesn't require specific space access)
echo "Test 3: List all accessible spaces..."
RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -u "$CONFLUENCE_EMAIL:$CONFLUENCE_API_TOKEN" \
  "$CONFLUENCE_URL/wiki/rest/api/space?limit=5" \
  -H "Accept: application/json")

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo "HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Can list spaces"
    echo "$BODY" | python3 -c "import sys, json; data=json.load(sys.stdin); print('\n'.join([f\"  - {s['key']}: {s['name']}\" for s in data.get('results', [])]))" 2>/dev/null
elif [ "$HTTP_CODE" = "403" ]; then
    echo "✗ Forbidden - check if user has Confluence product access"
    echo "Response: $BODY"
else
    echo "✗ Failed"
    echo "Response: $BODY"
fi
echo ""

# Test 4: Access specific space (if spaces configured)
if [ -n "$CONFLUENCE_SPACES" ]; then
    FIRST_SPACE=$(echo "$CONFLUENCE_SPACES" | cut -d',' -f1)
    echo "Test 4: Access space '$FIRST_SPACE'..."

    RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
      -u "$CONFLUENCE_EMAIL:$CONFLUENCE_API_TOKEN" \
      "$CONFLUENCE_URL/wiki/rest/api/content?spaceKey=$FIRST_SPACE&limit=1" \
      -H "Accept: application/json")

    HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d':' -f2)
    BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

    echo "HTTP Status: $HTTP_CODE"
    if [ "$HTTP_CODE" = "200" ]; then
        echo "✓ Can access space content"
        SIZE=$(echo "$BODY" | python3 -c "import sys, json; print(json.load(sys.stdin).get('size', 0))" 2>/dev/null)
        echo "  Found $SIZE page(s)"
    elif [ "$HTTP_CODE" = "403" ]; then
        echo "✗ Forbidden - check space permissions for user"
        echo "Response: $BODY"
    elif [ "$HTTP_CODE" = "404" ]; then
        echo "✗ Space not found - check space key"
    else
        echo "✗ Failed"
        echo "Response: $BODY"
    fi
    echo ""
fi

# Summary
echo "================================"
echo "Diagnostic Summary"
echo "================================"
echo ""
echo "Confluence Type: $CONFLUENCE_TYPE"
echo ""
echo "Common 302/403 error causes:"
echo "1. SSO/External Authentication (Okta, Google, etc.) - API tokens may need special setup"
echo "2. User doesn't have Confluence license (not a licensed user)"
echo "3. User doesn't have space permissions"
echo "4. API token created by different account than the email"
echo "5. Using PAT instead of API token (Cloud vs Data Center mismatch)"
echo ""
echo "Next steps based on errors:"
echo "- If seeing 302 redirects to login: Your org likely uses SSO - contact admin"
echo "  → Admin needs to enable 'API token authentication' or 'programmatic access'"
echo "  → Or you may need to use OAuth 2.0 instead of API tokens"
echo "- If Test 2 failed (403): Contact admin to grant you Confluence product access"
echo "- If Test 3 failed (403): Your account needs to be a licensed Confluence user"
echo "- If Test 4 failed (403): Admin needs to grant you space permissions"
echo "- If using Data Center/Server: Try Personal Access Token instead of API token"
echo ""
echo "For SSO environments:"
echo "  See: https://support.atlassian.com/organization-administration/docs/enforce-sso/"
echo ""
