# Confluence Knowledge Base MCP Server

An MCP server that turns your Confluence documentation into an AI-powered knowledge base for Gemini CLI. Ask natural language questions about your systems and get answers from your actual documentation.

## Quick Start

### One-Command Setup

```bash
git clone <this-repo>
cd confluence-knowledge-base
./install.sh
```

The interactive wizard will:
1. ✅ Install dependencies
2. ✅ Ask for your Confluence credentials
3. ✅ Discover your spaces
4. ✅ Help you choose which spaces to index
5. ✅ Build the initial knowledge base
6. ✅ Configure Gemini CLI automatically

### What You'll Need

Before running the installer:

1. **Confluence API Token**
   - Go to: https://id.atlassian.com/manage-profile/security/api-tokens
   - Click "Create API token"
   - Copy the token (you won't see it again!)

2. **Your Confluence URL**
   - Example: `https://yourcompany.atlassian.net`

3. **Python 3.8+** installed

4. **Gemini CLI** installed
   - Install from: https://github.com/google-gemini/gemini-cli

## Usage

Once installed, just start Gemini CLI and ask questions:

```bash
gemini
```

```
> How does our authentication system work?

> What's the process for deploying to production?

> Explain our database migration strategy

> What are the API rate limits?
```

Gemini will **automatically** retrieve relevant documentation and answer your questions!

## How It Works

```
1. Your Confluence docs → Downloaded and indexed (one-time)
2. You ask a question → Semantic search finds relevant chunks
3. Gemini gets context → Answers based on YOUR docs
```

### Technologies Used

- **FastMCP** - MCP server framework
- **ChromaDB** - Local vector database
- **sentence-transformers** - Semantic search
- **Confluence REST API** - Documentation retrieval

## Project Structure

```
confluence-knowledge-base/
├── install.sh                          # Interactive setup wizard
├── confluence_knowledge_base.py        # Main MCP server
├── confluence_kb_with_staleness.py    # Version with auto-reindex
├── find_space_keys.py                 # Space discovery utility
├── requirements.txt                    # Python dependencies
├── KNOWLEDGE_BASE_SETUP.md            # Detailed setup guide
└── README.md                          # This file
```

## Configuration

After installation, configuration is stored in:

- **Credentials**: `~/.confluence_mcp.env`
- **Index**: `~/.confluence_mcp/index/`
- **Gemini Config**: `~/.gemini/settings.json`

### Updating Documentation

When your Confluence docs are updated:

**Option 1: Ask Gemini**
```
> Reindex the Confluence documentation
```

**Option 2: Command line**
```bash
source ~/.confluence_mcp.env
python3 confluence_knowledge_base.py
```

**Option 3: Automated (Weekly)**

Set up a cron job (see `REINDEXING_GUIDE.md`)

## Customization

### Change indexed spaces

Edit `~/.confluence_mcp.env`:

```bash
export CONFLUENCE_SPACES="ENG,DEVOPS,TEAM"
```

Then rebuild the index.

### Adjust chunk size

In `confluence_knowledge_base.py`:

```python
CHUNK_SIZE = 1000      # Default: 1000 characters
CHUNK_OVERLAP = 200    # Default: 200 characters
```

### Change embedding model

For better quality (slower, larger):

```python
self.embedding_model = SentenceTransformer('all-mpnet-base-v2')
```

## Troubleshooting

### "Connection failed"

Check that:
- Your Confluence URL is correct
- Your API token is valid
- You have internet connectivity

### "No spaces found"

You might not have access to any Confluence spaces. Ask your admin for access.

### Slow indexing

Normal for large documentation sets (500+ pages). Reduce spaces or run overnight.

### Wrong/outdated answers

Your index is cached! Reindex when docs are updated:

```bash
rm -rf ~/.confluence_mcp
./install.sh
```

## Advanced Usage

### Manual space discovery

```bash
source ~/.confluence_mcp.env
python3 find_space_keys.py
```

### Staleness detection

Use the enhanced version with automatic staleness warnings:

```bash
# In ~/.gemini/settings.json, change the args to:
"args": ["confluence_kb_with_staleness.py"]
```

Add environment variables:
```bash
export MAX_INDEX_AGE_DAYS=7
export AUTO_REINDEX=true
```

### Scheduled reindexing

See `REINDEXING_GUIDE.md` for cron job setup.

## FAQ

**Q: Does this modify my Confluence documentation?**
A: No, it's read-only. It only downloads and indexes content.

**Q: Where is my data stored?**
A: Locally in `~/.confluence_mcp/index/`. Nothing is sent to external services except Gemini API calls.

**Q: How much does it cost?**
A: The MCP server is free. You only pay for Gemini API usage (queries to the AI).

**Q: Can I use this with Claude instead of Gemini?**
A: Yes! MCP is a standard protocol. Just configure Claude Desktop to use this MCP server.

**Q: How often should I reindex?**
A: Depends on how often your docs are updated. Weekly is common. Daily if very active.

**Q: Can I exclude certain pages?**
A: Not by default, but you can modify `confluence_knowledge_base.py` to filter by title, label, etc.

**Q: What about attachments/PDFs?**
A: Currently only page content is indexed. Attachments could be added with additional code.

## Documentation

- `KNOWLEDGE_BASE_SETUP.md` - Comprehensive setup guide
- `REINDEXING_GUIDE.md` - Strategies for keeping docs fresh

## Contributing

Feel free to:
- Add features (write capabilities, attachment support, etc.)
- Improve chunking strategies
- Add better error handling
- Create additional tools

## License

[Your license here]

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review the detailed guides in `/docs`
3. Open an issue on GitHub

---

**Ready to get started?** Just run:

```bash
./install.sh
```
