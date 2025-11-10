#!/usr/bin/env python3
"""
Confluence MCP Server
Provides Gemini CLI with access to Confluence documentation through MCP protocol.
"""

import os
import requests
from typing import Optional, List, Dict, Any
from mcp.server.fastmcp import FastMCP

# Initialize FastMCP server
mcp = FastMCP("Confluence Documentation")

# Configuration from environment variables
CONFLUENCE_URL = os.getenv("CONFLUENCE_URL")  # e.g., https://your-domain.atlassian.net
CONFLUENCE_EMAIL = os.getenv("CONFLUENCE_EMAIL")
CONFLUENCE_API_TOKEN = os.getenv("CONFLUENCE_API_TOKEN")

# Confluence API client setup
class ConfluenceClient:
    def __init__(self, url: str, email: str, api_token: str):
        self.url = url.rstrip('/')
        self.auth = (email, api_token)
        self.base_api = f"{self.url}/wiki/rest/api"

    def search_pages(self, query: str, space_key: Optional[str] = None, limit: int = 10) -> List[Dict[str, Any]]:
        """Search for pages in Confluence."""
        params = {
            "cql": f"text ~ \"{query}\"" + (f" AND space = {space_key}" if space_key else ""),
            "limit": limit
        }

        response = requests.get(
            f"{self.base_api}/content/search",
            auth=self.auth,
            params=params,
            headers={"Accept": "application/json"}
        )
        response.raise_for_status()

        results = response.json().get("results", [])
        return [
            {
                "id": page["id"],
                "title": page["title"],
                "type": page["type"],
                "url": f"{self.url}/wiki{page['_links']['webui']}",
                "space": page.get("space", {}).get("key", "")
            }
            for page in results
        ]

    def get_page_content(self, page_id: str, format: str = "view") -> Dict[str, Any]:
        """Get page content by ID."""
        params = {"expand": f"body.{format},version,space"}

        response = requests.get(
            f"{self.base_api}/content/{page_id}",
            auth=self.auth,
            params=params,
            headers={"Accept": "application/json"}
        )
        response.raise_for_status()

        data = response.json()
        return {
            "id": data["id"],
            "title": data["title"],
            "content": data["body"][format]["value"],
            "version": data["version"]["number"],
            "url": f"{self.url}/wiki{data['_links']['webui']}",
            "space": data.get("space", {}).get("key", "")
        }

    def list_spaces(self, limit: int = 25) -> List[Dict[str, str]]:
        """List all accessible spaces."""
        params = {"limit": limit}

        response = requests.get(
            f"{self.base_api}/space",
            auth=self.auth,
            params=params,
            headers={"Accept": "application/json"}
        )
        response.raise_for_status()

        results = response.json().get("results", [])
        return [
            {
                "key": space["key"],
                "name": space["name"],
                "type": space["type"]
            }
            for space in results
        ]

    def get_space_pages(self, space_key: str, limit: int = 50) -> List[Dict[str, Any]]:
        """Get all pages in a space."""
        params = {
            "spaceKey": space_key,
            "limit": limit,
            "expand": "version"
        }

        response = requests.get(
            f"{self.base_api}/content",
            auth=self.auth,
            params=params,
            headers={"Accept": "application/json"}
        )
        response.raise_for_status()

        results = response.json().get("results", [])
        return [
            {
                "id": page["id"],
                "title": page["title"],
                "url": f"{self.url}/wiki{page['_links']['webui']}"
            }
            for page in results
        ]


# Initialize Confluence client
confluence = ConfluenceClient(CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN)


# MCP Tools
@mcp.tool()
def search_confluence(query: str, space_key: str = None, limit: int = 10) -> str:
    """
    Search Confluence documentation for pages matching the query.

    Args:
        query: Search query text
        space_key: Optional space key to limit search (e.g., "TEAM", "DOCS")
        limit: Maximum number of results to return (default 10)

    Returns:
        List of matching pages with titles, URLs, and IDs
    """
    try:
        results = confluence.search_pages(query, space_key, limit)

        if not results:
            return f"No pages found for query: '{query}'"

        output = [f"Found {len(results)} page(s) for '{query}':\n"]
        for i, page in enumerate(results, 1):
            output.append(f"{i}. {page['title']}")
            output.append(f"   Space: {page['space']}")
            output.append(f"   URL: {page['url']}")
            output.append(f"   ID: {page['id']}\n")

        return "\n".join(output)
    except Exception as e:
        return f"Error searching Confluence: {str(e)}"


@mcp.tool()
def get_confluence_page(page_id: str) -> str:
    """
    Retrieve the full content of a Confluence page by its ID.

    Args:
        page_id: The Confluence page ID (from search results)

    Returns:
        The page title, content, and metadata
    """
    try:
        page = confluence.get_page_content(page_id)

        output = [
            f"Title: {page['title']}",
            f"Space: {page['space']}",
            f"Version: {page['version']}",
            f"URL: {page['url']}",
            "\n--- Content ---\n",
            page['content']
        ]

        return "\n".join(output)
    except Exception as e:
        return f"Error retrieving page: {str(e)}"


@mcp.tool()
def list_confluence_spaces() -> str:
    """
    List all Confluence spaces you have access to.

    Returns:
        List of available spaces with their keys and names
    """
    try:
        spaces = confluence.list_spaces()

        if not spaces:
            return "No spaces found or accessible"

        output = [f"Found {len(spaces)} space(s):\n"]
        for space in spaces:
            output.append(f"• {space['name']} ({space['key']}) - {space['type']}")

        return "\n".join(output)
    except Exception as e:
        return f"Error listing spaces: {str(e)}"


@mcp.tool()
def list_space_pages(space_key: str, limit: int = 50) -> str:
    """
    List all pages in a specific Confluence space.

    Args:
        space_key: The space key (e.g., "TEAM", "DOCS")
        limit: Maximum number of pages to return (default 50)

    Returns:
        List of pages in the space with titles, IDs, and URLs
    """
    try:
        pages = confluence.get_space_pages(space_key, limit)

        if not pages:
            return f"No pages found in space: {space_key}"

        output = [f"Found {len(pages)} page(s) in space '{space_key}':\n"]
        for i, page in enumerate(pages, 1):
            output.append(f"{i}. {page['title']}")
            output.append(f"   ID: {page['id']}")
            output.append(f"   URL: {page['url']}\n")

        return "\n".join(output)
    except Exception as e:
        return f"Error listing pages in space: {str(e)}"


if __name__ == "__main__":
    # Validate configuration
    if not all([CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN]):
        raise ValueError(
            "Missing required environment variables: "
            "CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN"
        )

    # Start the MCP server
    mcp.run()
