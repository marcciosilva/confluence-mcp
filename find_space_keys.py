#!/usr/bin/env python3
"""
Quick script to list all Confluence spaces you have access to.
Helps you find space keys for the CONFLUENCE_SPACES configuration.
"""

import os
import requests
from typing import List, Dict

# Configuration from environment
CONFLUENCE_URL = os.getenv("CONFLUENCE_URL")
CONFLUENCE_EMAIL = os.getenv("CONFLUENCE_EMAIL")
CONFLUENCE_API_TOKEN = os.getenv("CONFLUENCE_API_TOKEN")


def list_all_spaces() -> List[Dict[str, str]]:
    """Fetch all accessible Confluence spaces."""
    url = f"{CONFLUENCE_URL.rstrip('/')}/wiki/rest/api/space"
    auth = (CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN)

    all_spaces = []
    start = 0
    limit = 100

    while True:
        params = {
            "start": start,
            "limit": limit,
            "expand": "description.plain,homepage"
        }

        response = requests.get(
            url,
            auth=auth,
            params=params,
            headers={"Accept": "application/json"}
        )
        response.raise_for_status()

        data = response.json()
        results = data.get("results", [])

        if not results:
            break

        for space in results:
            all_spaces.append({
                "key": space["key"],
                "name": space["name"],
                "type": space["type"],
                "description": space.get("description", {}).get("plain", {}).get("value", "N/A")
            })

        if len(results) < limit:
            break

        start += limit

    return all_spaces


def main():
    # Validate configuration
    if not all([CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN]):
        print("Error: Missing required environment variables")
        print("\nPlease set:")
        print("  export CONFLUENCE_URL=\"https://yourcompany.atlassian.net\"")
        print("  export CONFLUENCE_EMAIL=\"you@company.com\"")
        print("  export CONFLUENCE_API_TOKEN=\"your-api-token\"")
        return

    print("Fetching your Confluence spaces...\n")

    try:
        spaces = list_all_spaces()

        if not spaces:
            print("No spaces found or you don't have access to any spaces.")
            return

        print(f"Found {len(spaces)} space(s):\n")
        print("=" * 80)

        for space in spaces:
            print(f"\nSpace Key:   {space['key']}")
            print(f"Name:        {space['name']}")
            print(f"Type:        {space['type']}")
            if space['description'] != "N/A":
                desc = space['description'][:100] + "..." if len(space['description']) > 100 else space['description']
                print(f"Description: {desc}")
            print("-" * 80)

        # Show configuration example
        print("\n" + "=" * 80)
        print("Configuration Example:")
        print("=" * 80)

        # Suggest commonly named spaces
        common_spaces = [s['key'] for s in spaces if s['type'] != 'personal'][:5]

        if common_spaces:
            print(f"\nexport CONFLUENCE_SPACES=\"{','.join(common_spaces)}\"")
        else:
            all_keys = [s['key'] for s in spaces]
            print(f"\nexport CONFLUENCE_SPACES=\"{','.join(all_keys[:3])}\"")

        print("\nTip: Exclude personal spaces (starting with ~) unless needed")

    except requests.exceptions.RequestException as e:
        print(f"Error connecting to Confluence: {e}")
        print("\nCheck that:")
        print("  1. CONFLUENCE_URL is correct")
        print("  2. Your API token is valid")
        print("  3. You have internet connectivity")


if __name__ == "__main__":
    main()
