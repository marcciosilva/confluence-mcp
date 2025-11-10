#!/usr/bin/env python3
"""
Confluence Knowledge Base MCP Server
Downloads Confluence documentation, creates vector embeddings, and provides
semantic search capabilities for natural language Q&A with Gemini CLI.
"""

import os
import json
import requests
from typing import List, Dict, Any, Optional
from pathlib import Path
import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer
from mcp.server.fastmcp import FastMCP
from bs4 import BeautifulSoup
import time

# Initialize FastMCP server
mcp = FastMCP("Confluence Knowledge Base")

# Configuration
CONFLUENCE_URL = os.getenv("CONFLUENCE_URL")
CONFLUENCE_EMAIL = os.getenv("CONFLUENCE_EMAIL")
CONFLUENCE_API_TOKEN = os.getenv("CONFLUENCE_API_TOKEN")
SPACES_TO_INDEX = os.getenv("CONFLUENCE_SPACES", "").split(",")  # Comma-separated space keys
INDEX_PATH = Path.home() / ".confluence_mcp" / "index"
CHUNK_SIZE = 1000  # Characters per chunk
CHUNK_OVERLAP = 200  # Overlap between chunks


class ConfluenceIndexer:
    """Handles downloading and indexing Confluence content."""

    def __init__(self, url: str, email: str, api_token: str):
        self.url = url.rstrip('/')
        self.auth = (email, api_token)
        self.base_api = f"{self.url}/wiki/rest/api"

    def fetch_all_pages(self, space_keys: List[str]) -> List[Dict[str, Any]]:
        """Fetch all pages from specified spaces."""
        all_pages = []

        for space_key in space_keys:
            if not space_key.strip():
                continue

            print(f"Fetching pages from space: {space_key}")
            start = 0
            limit = 50

            while True:
                params = {
                    "spaceKey": space_key,
                    "start": start,
                    "limit": limit,
                    "expand": "body.storage,version,space"
                }

                response = requests.get(
                    f"{self.base_api}/content",
                    auth=self.auth,
                    params=params,
                    headers={"Accept": "application/json"}
                )
                response.raise_for_status()

                data = response.json()
                results = data.get("results", [])

                if not results:
                    break

                for page in results:
                    all_pages.append({
                        "id": page["id"],
                        "title": page["title"],
                        "space": page["space"]["key"],
                        "content": page["body"]["storage"]["value"],
                        "url": f"{self.url}/wiki{page['_links']['webui']}",
                        "version": page["version"]["number"]
                    })

                print(f"  Fetched {len(results)} pages (total: {len(all_pages)})")

                if len(results) < limit:
                    break

                start += limit
                time.sleep(0.5)  # Rate limiting

        print(f"Total pages fetched: {len(all_pages)}")
        return all_pages

    @staticmethod
    def clean_html(html_content: str) -> str:
        """Convert HTML to plain text."""
        soup = BeautifulSoup(html_content, 'html.parser')

        # Remove script and style elements
        for script in soup(["script", "style"]):
            script.decompose()

        # Get text
        text = soup.get_text(separator='\n')

        # Clean up whitespace
        lines = (line.strip() for line in text.splitlines())
        chunks = (phrase.strip() for line in lines for phrase in line.split("  "))
        text = '\n'.join(chunk for chunk in chunks if chunk)

        return text

    @staticmethod
    def chunk_text(text: str, chunk_size: int, overlap: int) -> List[str]:
        """Split text into overlapping chunks."""
        chunks = []
        start = 0

        while start < len(text):
            end = start + chunk_size
            chunk = text[start:end]

            # Try to break at sentence boundary
            if end < len(text):
                last_period = chunk.rfind('.')
                last_newline = chunk.rfind('\n')
                break_point = max(last_period, last_newline)

                if break_point > chunk_size * 0.5:  # Only break if we're past halfway
                    chunk = chunk[:break_point + 1]
                    end = start + break_point + 1

            chunks.append(chunk.strip())
            start = end - overlap

        return [c for c in chunks if c]  # Filter empty chunks


class VectorStore:
    """Manages vector embeddings and similarity search."""

    def __init__(self, persist_directory: Path):
        self.persist_directory = persist_directory
        self.persist_directory.mkdir(parents=True, exist_ok=True)

        # Initialize ChromaDB
        self.client = chromadb.PersistentClient(
            path=str(persist_directory),
            settings=Settings(anonymized_telemetry=False)
        )

        # Initialize embedding model
        print("Loading embedding model...")
        self.embedding_model = SentenceTransformer('all-MiniLM-L6-v2')

        # Get or create collection
        self.collection = self.client.get_or_create_collection(
            name="confluence_docs",
            metadata={"hnsw:space": "cosine"}
        )

    def index_pages(self, pages: List[Dict[str, Any]], chunk_size: int, overlap: int):
        """Index pages into vector store."""
        print(f"Indexing {len(pages)} pages...")

        # Clear existing collection
        self.client.delete_collection("confluence_docs")
        self.collection = self.client.create_collection(
            name="confluence_docs",
            metadata={"hnsw:space": "cosine"}
        )

        all_chunks = []
        all_metadata = []
        all_ids = []

        for page in pages:
            # Clean HTML content
            clean_text = ConfluenceIndexer.clean_html(page["content"])

            # Create chunks
            chunks = ConfluenceIndexer.chunk_text(clean_text, chunk_size, overlap)

            # Prepare metadata for each chunk
            for i, chunk in enumerate(chunks):
                chunk_id = f"{page['id']}_chunk_{i}"
                all_chunks.append(chunk)
                all_metadata.append({
                    "page_id": page["id"],
                    "page_title": page["title"],
                    "space": page["space"],
                    "url": page["url"],
                    "chunk_index": i,
                    "total_chunks": len(chunks)
                })
                all_ids.append(chunk_id)

        print(f"Created {len(all_chunks)} chunks from {len(pages)} pages")
        print("Generating embeddings...")

        # Add to collection in batches
        batch_size = 100
        for i in range(0, len(all_chunks), batch_size):
            batch_chunks = all_chunks[i:i + batch_size]
            batch_metadata = all_metadata[i:i + batch_size]
            batch_ids = all_ids[i:i + batch_size]

            self.collection.add(
                documents=batch_chunks,
                metadatas=batch_metadata,
                ids=batch_ids
            )
            print(f"  Indexed {min(i + batch_size, len(all_chunks))}/{len(all_chunks)} chunks")

        print("Indexing complete!")

    def search(self, query: str, n_results: int = 5) -> List[Dict[str, Any]]:
        """Search for relevant chunks."""
        results = self.collection.query(
            query_texts=[query],
            n_results=n_results
        )

        chunks = []
        for i in range(len(results['documents'][0])):
            chunks.append({
                "content": results['documents'][0][i],
                "metadata": results['metadatas'][0][i],
                "distance": results['distances'][0][i] if 'distances' in results else None
            })

        return chunks


# Initialize components
print("Initializing Confluence Knowledge Base...")
indexer = ConfluenceIndexer(CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN)
vector_store = VectorStore(INDEX_PATH)

# Check if index exists, otherwise build it
index_metadata_file = INDEX_PATH / "metadata.json"
needs_reindex = True

if index_metadata_file.exists():
    with open(index_metadata_file, 'r') as f:
        metadata = json.load(f)
        print(f"Found existing index with {metadata.get('total_pages', 0)} pages")
        print(f"Spaces: {metadata.get('spaces', [])}")

        # Check if spaces match
        if set(metadata.get('spaces', [])) == set(SPACES_TO_INDEX):
            needs_reindex = False
            print("Index is up to date!")

if needs_reindex:
    print("\nBuilding index...")
    pages = indexer.fetch_all_pages(SPACES_TO_INDEX)
    vector_store.index_pages(pages, CHUNK_SIZE, CHUNK_OVERLAP)

    # Save metadata
    with open(index_metadata_file, 'w') as f:
        json.dump({
            "total_pages": len(pages),
            "spaces": SPACES_TO_INDEX,
            "indexed_at": time.time()
        }, f)

    print(f"\nIndexed {len(pages)} pages from spaces: {SPACES_TO_INDEX}")


# MCP Resources - Provide context on demand
@mcp.resource("confluence://knowledge-base")
def get_knowledge_base_info() -> str:
    """Provides information about the Confluence knowledge base."""
    if index_metadata_file.exists():
        with open(index_metadata_file, 'r') as f:
            metadata = json.load(f)

        return f"""Confluence Knowledge Base Status:
- Total Pages: {metadata.get('total_pages', 0)}
- Spaces Indexed: {', '.join(metadata.get('spaces', []))}
- Last Indexed: {time.ctime(metadata.get('indexed_at', 0))}

This knowledge base contains your team's documentation from Confluence.
You can ask natural language questions about your systems, and I'll search
the documentation to provide accurate answers.
"""
    return "Knowledge base not initialized yet."


# MCP Tools
@mcp.tool()
def ask_documentation(question: str, num_sources: int = 5) -> str:
    """
    Search the Confluence knowledge base for information relevant to a question.
    This retrieves the most relevant documentation chunks to answer domain-specific questions.

    Args:
        question: The question to ask about your systems/documentation
        num_sources: Number of relevant document chunks to retrieve (default 5)

    Returns:
        Relevant documentation content with source references
    """
    try:
        # Search vector store
        results = vector_store.search(question, n_results=num_sources)

        if not results:
            return "No relevant documentation found for this question."

        # Format response
        output = [f"Found {len(results)} relevant documentation sections:\n"]

        for i, result in enumerate(results, 1):
            metadata = result['metadata']
            content = result['content']

            output.append(f"\n--- Source {i}: {metadata['page_title']} (Space: {metadata['space']}) ---")
            output.append(f"URL: {metadata['url']}")
            output.append(f"\nContent:\n{content}\n")

        return "\n".join(output)

    except Exception as e:
        return f"Error searching knowledge base: {str(e)}"


@mcp.tool()
def reindex_confluence() -> str:
    """
    Re-download and re-index all Confluence documentation.
    Use this when documentation has been updated.

    Returns:
        Status of the reindexing operation
    """
    try:
        print("\nReindexing Confluence documentation...")
        pages = indexer.fetch_all_pages(SPACES_TO_INDEX)
        vector_store.index_pages(pages, CHUNK_SIZE, CHUNK_OVERLAP)

        # Save metadata
        with open(index_metadata_file, 'w') as f:
            json.dump({
                "total_pages": len(pages),
                "spaces": SPACES_TO_INDEX,
                "indexed_at": time.time()
            }, f)

        return f"Successfully reindexed {len(pages)} pages from spaces: {', '.join(SPACES_TO_INDEX)}"

    except Exception as e:
        return f"Error reindexing: {str(e)}"


if __name__ == "__main__":
    # Validate configuration
    if not all([CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN]):
        raise ValueError(
            "Missing required environment variables: "
            "CONFLUENCE_URL, CONFLUENCE_EMAIL, CONFLUENCE_API_TOKEN"
        )

    if not SPACES_TO_INDEX or not SPACES_TO_INDEX[0]:
        raise ValueError(
            "Missing CONFLUENCE_SPACES environment variable. "
            "Set it to comma-separated space keys (e.g., 'TEAM,DOCS,ENG')"
        )

    print("\n" + "="*60)
    print("Confluence Knowledge Base MCP Server Ready!")
    print("="*60)

    # Start the MCP server
    mcp.run()
