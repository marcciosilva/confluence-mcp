# Confluence MCP Server for Gemini CLI

This MCP server allows Gemini CLI to access and query your Confluence documentation, enabling your team to ask questions about your systems and get answers from your documentation.

## Features

- **Search Confluence**: Find pages by keyword across all spaces or specific spaces
- **Retrieve Page Content**: Get full page content by ID
- **List Spaces**: See all accessible Confluence spaces
- **Browse Space Pages**: List all pages within a specific space

## Prerequisites

1. **Confluence Cloud Account** with API access
2. **Confluence API Token** - Generate at https://id.atlassian.com/manage-profile/security/api-tokens
3. **Python 3.8+** installed
4. **Gemini CLI** installed

## Setup Instructions

### 1. Install Dependencies

```bash
cd /Users/marcciosilva/dev/work/peya
pip install -r requirements.txt
```

### 2. Configure Environment Variables

Create a `.env` file or export these variables:

```bash
export CONFLUENCE_URL="https://your-domain.atlassian.net"
export CONFLUENCE_EMAIL="your-email@company.com"
export CONFLUENCE_API_TOKEN="your-api-token-here"
```

**To get your API token:**
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Give it a name (e.g., "Gemini MCP Server")
4. Copy the token (you won't see it again!)

### 3. Test the Server

Run the server standalone to verify it works:

```bash
python confluence_mcp_server.py
```

### 4. Configure Gemini CLI

Add the MCP server to your Gemini CLI settings at `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "confluence": {
      "command": "python",
      "args": ["/Users/marcciosilva/dev/work/peya/confluence_mcp_server.py"],
      "env": {
        "CONFLUENCE_URL": "https://your-domain.atlassian.net",
        "CONFLUENCE_EMAIL": "your-email@company.com",
        "CONFLUENCE_API_TOKEN": "your-api-token-here"
      },
      "timeout": 30000
    }
  }
}
```

**Security Note**: Never commit your API token! Consider using environment variables:

```json
{
  "mcpServers": {
    "confluence": {
      "command": "python",
      "args": ["/Users/marcciosilva/dev/work/peya/confluence_mcp_server.py"],
      "env": {
        "CONFLUENCE_URL": "$CONFLUENCE_URL",
        "CONFLUENCE_EMAIL": "$CONFLUENCE_EMAIL",
        "CONFLUENCE_API_TOKEN": "$CONFLUENCE_API_TOKEN"
      },
      "timeout": 30000
    }
  }
}
```

Then export the variables in your shell:

```bash
export CONFLUENCE_URL="https://your-domain.atlassian.net"
export CONFLUENCE_EMAIL="your-email@company.com"
export CONFLUENCE_API_TOKEN="your-api-token"
```

### 5. Start Using It!

Start Gemini CLI and verify the server is loaded:

```bash
gemini
```

Then use the `/mcp` command to check status:

```
/mcp
```

## Usage Examples

### Search for documentation

```
Search for information about our authentication system
```

Gemini will automatically use the `search_confluence` tool.

### Ask specific questions

```
How does our deployment pipeline work?
```

```
What are the API rate limits for our service?
```

```
Show me documentation about database migrations
```

### List available spaces

```
What Confluence spaces do we have?
```

### Browse a specific space

```
Show me all pages in the TEAM space
```

### Get specific page content

```
Get the content of page ID 123456789
```

## Available Tools

The MCP server exposes these tools to Gemini:

1. **search_confluence** - Search for pages by keyword
   - `query`: Search text
   - `space_key`: (Optional) Limit to specific space
   - `limit`: Max results (default 10)

2. **get_confluence_page** - Retrieve full page content
   - `page_id`: The Confluence page ID

3. **list_confluence_spaces** - List all accessible spaces
   - No parameters

4. **list_space_pages** - List pages in a space
   - `space_key`: The space key (e.g., "TEAM")
   - `limit`: Max results (default 50)

## Troubleshooting

### "Missing required environment variables" error

Make sure you've set all three environment variables:
- CONFLUENCE_URL
- CONFLUENCE_EMAIL
- CONFLUENCE_API_TOKEN

### "401 Unauthorized" error

Your API token may be invalid or expired. Generate a new one at:
https://id.atlassian.com/manage-profile/security/api-tokens

### "Connection refused" or timeout

Check that:
- Your CONFLUENCE_URL is correct
- You have internet connectivity
- Your firewall allows outbound HTTPS connections

### MCP server not showing in Gemini CLI

1. Check your settings.json syntax is valid JSON
2. Verify the path to confluence_mcp_server.py is correct
3. Restart Gemini CLI
4. Use `/mcp` command to see server status

## Advanced: Go Implementation

If you prefer Go for better performance, here's a basic structure:

```go
package main

import (
    "github.com/modelcontextprotocol/go-sdk/mcp"
)

// Implementation would follow similar structure
// See: https://github.com/modelcontextprotocol/go-sdk
```

The official Go SDK is stable (v1.0.0) but requires more boilerplate than FastMCP.

## Notes on Confluence Rovo AI

You mentioned Confluence's Rovo AI. While Rovo provides AI capabilities within Confluence itself, it doesn't expose an API for external integrations like this. This MCP server approach gives you more flexibility:

- Use any LLM (Gemini, Claude, etc.)
- Customize the tools and responses
- Integrate with other systems via MCP
- Control your data and processing

## Next Steps

1. **Add Caching**: Implement local caching to reduce API calls and speed up responses
2. **Add More Tools**:
   - Get page attachments
   - Search by labels
   - Get page comments
   - Export to PDF
3. **Error Handling**: Add retry logic and better error messages
4. **Rate Limiting**: Implement rate limiting to avoid hitting API limits
5. **Multi-Space Search**: Add ability to search across multiple specific spaces

## Resources

- [Gemini CLI MCP Documentation](https://google-gemini.github.io/gemini-cli/docs/tools/mcp-server.html)
- [FastMCP Documentation](https://github.com/modelcontextprotocol/python-sdk)
- [Confluence REST API](https://developer.atlassian.com/cloud/confluence/rest/v2/)
- [Model Context Protocol Spec](https://modelcontextprotocol.io/)
