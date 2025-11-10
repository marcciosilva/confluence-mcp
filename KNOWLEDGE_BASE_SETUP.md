# Confluence Knowledge Base MCP Server

This is a **RAG (Retrieval Augmented Generation)** system that downloads your Confluence documentation, creates vector embeddings, and lets you ask natural language questions through Gemini CLI.

## What This Does

Instead of manually searching Confluence, you have an **AI expert** on your documentation:

```
You: "How does our authentication system work?"
Gemini: [Searches 50-500 pages of docs, finds relevant sections, answers based on your actual documentation]

You: "What are the rate limits for the API?"
Gemini: [Retrieves relevant docs and provides accurate answer]

You: "Explain our deployment process"
Gemini: [Pulls relevant documentation and explains step-by-step]
```

## How It Works

1. **Index Phase** (on first startup):
   - Downloads all pages from specified Confluence spaces
   - Converts HTML to clean text
   - Chunks documents into manageable pieces
   - Creates vector embeddings using sentence-transformers
   - Stores in local ChromaDB vector database

2. **Query Phase** (when you ask questions):
   - Gemini uses the `ask_documentation` tool automatically
   - Your question is converted to a vector embedding
   - Semantic search finds the most relevant doc chunks
   - Retrieved context is used to answer your question accurately

## Setup Instructions

### 1. Install Dependencies

```bash
cd /Users/marcciosilva/dev/work/peya
pip install -r requirements.txt
```

This will install:
- FastMCP - MCP server framework
- ChromaDB - Vector database
- sentence-transformers - For embeddings
- BeautifulSoup - HTML parsing
- torch - Required for embeddings model

### 2. Get Confluence Credentials

**Get your API Token:**
1. Go to https://id.atlassian.com/manage-profile/security/api-tokens
2. Click "Create API token"
3. Name it "Knowledge Base MCP"
4. Copy the token (save it somewhere safe!)

**Find your Space Keys:**
1. Go to your Confluence
2. Navigate to the spaces you want to index
3. Look at the URL: `https://yourcompany.atlassian.net/wiki/spaces/TEAM/...`
4. The space key is `TEAM` in this example

### 3. Configure Environment

Create a `.env` file or export these variables:

```bash
# Your Confluence instance URL
export CONFLUENCE_URL="https://yourcompany.atlassian.net"

# Your email
export CONFLUENCE_EMAIL="you@company.com"

# API token from step 2
export CONFLUENCE_API_TOKEN="your-api-token-here"

# Comma-separated space keys to index
export CONFLUENCE_SPACES="TEAM,DOCS,ENG,PRODUCT"
```

### 4. Build the Index (First Run)

This will download and index all documentation:

```bash
python confluence_knowledge_base.py
```

You'll see output like:
```
Fetching pages from space: TEAM
  Fetched 50 pages (total: 50)
  Fetched 45 pages (total: 95)
Total pages fetched: 95
Created 847 chunks from 95 pages
Loading embedding model...
Generating embeddings...
  Indexed 100/847 chunks
  Indexed 200/847 chunks
  ...
Indexing complete!
```

**This only happens once!** The index is cached in `~/.confluence_mcp/index/`

### 5. Configure Gemini CLI

Add to `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "confluence-kb": {
      "command": "python",
      "args": ["/Users/marcciosilva/dev/work/peya/confluence_knowledge_base.py"],
      "env": {
        "CONFLUENCE_URL": "https://yourcompany.atlassian.net",
        "CONFLUENCE_EMAIL": "you@company.com",
        "CONFLUENCE_API_TOKEN": "your-api-token",
        "CONFLUENCE_SPACES": "TEAM,DOCS,ENG"
      },
      "timeout": 60000
    }
  }
}
```

**Better approach** - Use environment variables for security:

```json
{
  "mcpServers": {
    "confluence-kb": {
      "command": "python",
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
```

Then add to your `~/.bashrc` or `~/.zshrc`:

```bash
export CONFLUENCE_URL="https://yourcompany.atlassian.net"
export CONFLUENCE_EMAIL="you@company.com"
export CONFLUENCE_API_TOKEN="your-token"
export CONFLUENCE_SPACES="TEAM,DOCS,ENG"
```

### 6. Start Using It!

Start Gemini CLI:

```bash
gemini
```

Check the server is loaded:

```
/mcp
```

Now just ask questions naturally:

```
How does our authentication system work?
```

```
What's the process for deploying to production?
```

```
Explain our database migration strategy
```

Gemini will automatically use the knowledge base to answer!

## Usage Examples

### Natural Q&A (Primary Use Case)

Just ask questions - Gemini knows to use the documentation:

```
What are the API rate limits?
How do I configure the logging system?
What's our incident response procedure?
Where are environment variables defined?
```

### Manual Tool Usage

If you want to explicitly search:

```
Use the ask_documentation tool to find information about database backups
```

### Updating the Index

When documentation is updated in Confluence:

```
Reindex the Confluence documentation
```

Or use the tool directly:

```
Use the reindex_confluence tool
```

## Configuration Options

### Chunk Size and Overlap

In `confluence_knowledge_base.py`:

```python
CHUNK_SIZE = 1000  # Characters per chunk (default: 1000)
CHUNK_OVERLAP = 200  # Overlap between chunks (default: 200)
```

- **Larger chunks**: More context, but less precise retrieval
- **Smaller chunks**: More precise, but might miss context
- **More overlap**: Better context continuity, larger index

### Number of Results

When asking questions, you can control how much context is retrieved:

```python
@mcp.tool()
def ask_documentation(question: str, num_sources: int = 5)
```

Default is 5 chunks. More chunks = more context but higher token usage.

### Embedding Model

The default model is `all-MiniLM-L6-v2`:
- Fast and lightweight
- Good quality embeddings
- Works offline

For better quality (slower, larger):

```python
self.embedding_model = SentenceTransformer('all-mpnet-base-v2')
```

## How the RAG Pipeline Works

```
Your Question
    ↓
[Convert to vector embedding]
    ↓
[Semantic search in ChromaDB]
    ↓
[Retrieve top 5 most similar chunks]
    ↓
[Gemini gets chunks as context]
    ↓
[Gemini answers based on retrieved docs]
```

## Index Location

All data is stored in:
```
~/.confluence_mcp/
  ├── index/              # ChromaDB vector database
  └── metadata.json       # Index metadata
```

To rebuild from scratch:
```bash
rm -rf ~/.confluence_mcp
python confluence_knowledge_base.py
```

## Performance Notes

### First Run
- Expect 30-60 seconds for 100 pages
- Embedding generation is the slowest part
- Only happens once!

### Subsequent Runs
- Loads existing index in ~2 seconds
- Queries are very fast (<1 second)

### Memory Usage
- ChromaDB uses ~100-200MB for 500 pages
- Embedding model uses ~100MB RAM

## Troubleshooting

### "No relevant documentation found"

- Your question might be too specific or use different terminology
- Try rephrasing the question
- Check if the relevant pages are actually indexed:
  ```bash
  ls -la ~/.confluence_mcp/index/
  ```

### Slow indexing

- Normal for large doc sets (500+ pages)
- Reduce `CONFLUENCE_SPACES` to only essential spaces
- Run indexing overnight if needed

### "Rate limit exceeded"

The indexer includes 0.5 second delays between API calls, but if you hit limits:

In `confluence_knowledge_base.py`:
```python
time.sleep(0.5)  # Increase to 1.0 or 2.0
```

### Wrong or outdated answers

The index is cached! When docs are updated:

```bash
# Option 1: Use the tool
gemini  # Then say "reindex confluence"

# Option 2: Delete and rebuild
rm -rf ~/.confluence_mcp
python confluence_knowledge_base.py
```

### Import errors

Make sure all dependencies installed:
```bash
pip install --upgrade -r requirements.txt
```

For torch issues on Mac:
```bash
pip install torch --index-url https://download.pytorch.org/whl/cpu
```

## Advanced: Scheduled Reindexing

To keep documentation fresh, set up a cron job:

```bash
# Add to crontab (run daily at 2 AM)
crontab -e

# Add this line:
0 2 * * * cd /Users/marcciosilva/dev/work/peya && /usr/bin/python confluence_knowledge_base.py > /tmp/confluence_reindex.log 2>&1
```

Or create a script `reindex.sh`:

```bash
#!/bin/bash
export CONFLUENCE_URL="https://yourcompany.atlassian.net"
export CONFLUENCE_EMAIL="you@company.com"
export CONFLUENCE_API_TOKEN="your-token"
export CONFLUENCE_SPACES="TEAM,DOCS,ENG"

cd /Users/marcciosilva/dev/work/peya
rm -rf ~/.confluence_mcp
python confluence_knowledge_base.py
```

## Comparison: Old vs New Approach

### Old Approach (Basic Search)
```
You: "How does auth work?"
Gemini: *uses search_confluence tool*
Gemini: "Found 3 pages about auth. Which one do you want?"
You: "Show me the first one"
Gemini: *uses get_page tool*
Gemini: "Here's page 1. Want me to check the others?"
```

### New Approach (Knowledge Base)
```
You: "How does auth work?"
Gemini: *automatically retrieves relevant doc chunks*
Gemini: "Based on your documentation, your auth system uses JWT tokens with..."
```

Much more natural!

## Next Steps

### 1. Add More Spaces
Update `CONFLUENCE_SPACES` and reindex:
```bash
export CONFLUENCE_SPACES="TEAM,DOCS,ENG,PRODUCT,SECURITY"
```

### 2. Improve Retrieval Quality
- Try different embedding models
- Adjust chunk size/overlap
- Increase num_sources for complex questions

### 3. Add Metadata Filtering
Modify the search to filter by space, date, etc.

### 4. Add Caching Layer
Cache frequently asked questions for faster responses.

### 5. Monitor Usage
Add logging to see what questions are being asked.

## Why This is Better Than Confluence Rovo AI

- **Works with any LLM** (Gemini, Claude, etc.)
- **Fully customizable** retrieval and chunking
- **Free** (no Rovo subscription needed)
- **Privacy** - runs locally, data stays on your machine
- **Extensible** - add custom tools, filters, etc.

## Resources

- [Model Context Protocol](https://modelcontextprotocol.io/)
- [FastMCP Documentation](https://github.com/modelcontextprotocol/python-sdk)
- [ChromaDB Documentation](https://docs.trychroma.com/)
- [Sentence Transformers](https://www.sbert.net/)
- [Confluence REST API](https://developer.atlassian.com/cloud/confluence/rest/)
