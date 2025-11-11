#!/usr/bin/env python3
"""
Local Documentation Knowledge Base MCP Server
Reads documentation from local files (including PDFs), creates vector embeddings,
and provides semantic search capabilities for natural language Q&A with Gemini CLI.
"""

import os
import sys
import json
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
import chromadb
from chromadb.config import Settings
from sentence_transformers import SentenceTransformer
from mcp.server.fastmcp import FastMCP
import time

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastMCP server
mcp = FastMCP("Local Documentation Knowledge Base")

# Configuration
DOCS_DIRECTORY = os.getenv("DOCS_DIRECTORY", "")  # Directory containing documentation files
INDEX_PATH = Path.home() / ".confluence_mcp" / "index"
CHUNK_SIZE = 1000  # Characters per chunk
CHUNK_OVERLAP = 200  # Overlap between chunks


class DocumentLoader:
    """Handles loading and processing local documentation files."""

    def __init__(self, docs_directory: str):
        self.docs_directory = Path(docs_directory) if docs_directory else None

    def load_all_documents(self) -> List[Dict[str, Any]]:
        """Load all documents from the specified directory."""
        if not self.docs_directory:
            logger.error("DOCS_DIRECTORY not specified")
            return []

        if not self.docs_directory.exists():
            logger.error(f"Directory not found: {self.docs_directory}")
            return []

        if not os.access(self.docs_directory, os.R_OK):
            logger.error(f"No read access to directory: {self.docs_directory}")
            return []

        all_documents = []
        supported_extensions = {'.pdf', '.txt', '.md'}

        logger.info(f"Loading documents from: {self.docs_directory}")

        for file_path in self.docs_directory.rglob('*'):
            if file_path.is_file() and file_path.suffix.lower() in supported_extensions:
                try:
                    content = self._load_file(file_path)
                    if content:
                        all_documents.append({
                            "id": str(file_path.relative_to(self.docs_directory)),
                            "title": file_path.stem,
                            "source": "local",
                            "content": content,
                            "path": str(file_path),
                            "extension": file_path.suffix
                        })
                        logger.info(f"  Loaded: {file_path.name}")
                except Exception as e:
                    logger.warning(f"  Failed to load {file_path.name}: {e}")

        logger.info(f"Total documents loaded: {len(all_documents)}")
        return all_documents

    def _load_file(self, file_path: Path) -> str:
        """Load content from a single file based on its type."""
        if file_path.suffix.lower() == '.pdf':
            return self._load_pdf(file_path)
        else:  # .txt, .md, or other text files
            return self._load_text(file_path)

    @staticmethod
    def _load_pdf(file_path: Path) -> str:
        """Extract text from PDF file."""
        try:
            import PyPDF2
            with open(file_path, 'rb') as f:
                reader = PyPDF2.PdfReader(f)
                text_parts = []
                for page in reader.pages:
                    text = page.extract_text()
                    if text:
                        text_parts.append(text)
                return '\n'.join(text_parts)
        except ImportError:
            logger.warning(f"PyPDF2 not installed, skipping PDF: {file_path.name}")
            return ""
        except Exception as e:
            logger.warning(f"Error reading PDF {file_path.name}: {e}")
            return ""

    @staticmethod
    def _load_text(file_path: Path) -> str:
        """Load plain text file."""
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                return f.read()
        except UnicodeDecodeError:
            # Try with latin-1 encoding as fallback
            try:
                with open(file_path, 'r', encoding='latin-1') as f:
                    return f.read()
            except Exception as e:
                logger.warning(f"Error reading text file {file_path.name}: {e}")
                return ""

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

    def index_documents(self, documents: List[Dict[str, Any]], chunk_size: int, overlap: int):
        """Index documents into vector store."""
        logger.info(f"Indexing {len(documents)} documents...")

        # Clear existing collection
        self.client.delete_collection("confluence_docs")
        self.collection = self.client.create_collection(
            name="confluence_docs",
            metadata={"hnsw:space": "cosine"}
        )

        all_chunks = []
        all_metadata = []
        all_ids = []

        for doc in documents:
            # Create chunks from document content
            chunks = DocumentLoader.chunk_text(doc["content"], chunk_size, overlap)

            # Prepare metadata for each chunk
            for i, chunk in enumerate(chunks):
                chunk_id = f"{doc['id']}_chunk_{i}".replace('/', '_').replace('\\', '_')
                all_chunks.append(chunk)
                all_metadata.append({
                    "doc_id": doc["id"],
                    "doc_title": doc["title"],
                    "source": doc["source"],
                    "path": doc["path"],
                    "extension": doc["extension"],
                    "chunk_index": i,
                    "total_chunks": len(chunks)
                })
                all_ids.append(chunk_id)

        logger.info(f"Created {len(all_chunks)} chunks from {len(documents)} documents")
        logger.info("Generating embeddings...")

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
            logger.info(f"  Indexed {min(i + batch_size, len(all_chunks))}/{len(all_chunks)} chunks")

        logger.info("Indexing complete!")

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
logger.info("Initializing Local Documentation Knowledge Base...")
doc_loader = DocumentLoader(DOCS_DIRECTORY)
vector_store = VectorStore(INDEX_PATH)

# Load and index documents on startup
logger.info("Loading documents from local directory...")
documents = doc_loader.load_all_documents()

if not documents:
    logger.warning("No documents were loaded. Please check DOCS_DIRECTORY configuration.")
else:
    logger.info(f"Successfully loaded {len(documents)} document(s)")
    logger.info("Building vector index...")
    vector_store.index_documents(documents, CHUNK_SIZE, CHUNK_OVERLAP)

    # Save metadata
    index_metadata_file = INDEX_PATH / "metadata.json"
    with open(index_metadata_file, 'w') as f:
        json.dump({
            "total_documents": len(documents),
            "docs_directory": str(DOCS_DIRECTORY),
            "indexed_at": time.time()
        }, f)

    logger.info(f"Indexed {len(documents)} document(s) from: {DOCS_DIRECTORY}")


# MCP Resources - Provide context on demand
@mcp.resource("confluence://knowledge-base")
def get_knowledge_base_info() -> str:
    """Provides information about the local documentation knowledge base."""
    index_metadata_file = INDEX_PATH / "metadata.json"
    if index_metadata_file.exists():
        with open(index_metadata_file, 'r') as f:
            metadata = json.load(f)

        return f"""Local Documentation Knowledge Base Status:
- Total Documents: {metadata.get('total_documents', 0)}
- Directory: {metadata.get('docs_directory', 'N/A')}
- Last Indexed: {time.ctime(metadata.get('indexed_at', 0))}

This knowledge base contains your local documentation files.
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

            output.append(f"\n--- Source {i}: {metadata['doc_title']} ({metadata['extension']}) ---")
            output.append(f"Path: {metadata['path']}")
            output.append(f"\nContent:\n{content}\n")

        return "\n".join(output)

    except Exception as e:
        return f"Error searching knowledge base: {str(e)}"


@mcp.tool()
def reindex_documents() -> str:
    """
    Re-load and re-index all local documentation files.
    Use this when documentation has been updated.

    Returns:
        Status of the reindexing operation
    """
    try:
        logger.info("\nReindexing local documentation...")
        documents = doc_loader.load_all_documents()

        if not documents:
            return "No documents found to index. Please check DOCS_DIRECTORY configuration."

        vector_store.index_documents(documents, CHUNK_SIZE, CHUNK_OVERLAP)

        # Save metadata
        index_metadata_file = INDEX_PATH / "metadata.json"
        with open(index_metadata_file, 'w') as f:
            json.dump({
                "total_documents": len(documents),
                "docs_directory": str(DOCS_DIRECTORY),
                "indexed_at": time.time()
            }, f)

        return f"Successfully reindexed {len(documents)} document(s) from: {DOCS_DIRECTORY}"

    except Exception as e:
        return f"Error reindexing: {str(e)}"


if __name__ == "__main__":
    # Check for --index-only flag
    index_only = "--index-only" in sys.argv

    # Validate configuration
    if not DOCS_DIRECTORY:
        logger.warning(
            "DOCS_DIRECTORY environment variable not set. "
            "Server will start but no documents will be loaded."
        )

    logger.info("\n" + "="*60)
    logger.info("Local Documentation Knowledge Base MCP Server Ready!")
    logger.info("="*60)

    # If --index-only flag is set, exit after indexing
    if index_only:
        logger.info("\nIndex-only mode: Exiting after building index.")
        sys.exit(0)

    # Start the MCP server
    mcp.run()
