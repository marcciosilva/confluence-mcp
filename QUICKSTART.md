# Quick Start Guide

Get your Confluence Knowledge Base running in 5 minutes!

## Prerequisites Checklist

- [ ] Python 3.8+ installed (`python3 --version`)
- [ ] Confluence account with API access
- [ ] Gemini CLI installed (https://github.com/google-gemini/gemini-cli)

## Step 1: Get Your Confluence API Token (2 minutes)

1. Go to: https://id.atlassian.com/manage-profile/security/api-tokens
2. Click **"Create API token"**
3. Name it: "Gemini Knowledge Base"
4. **Copy the token** (you won't see it again!)
5. Keep it handy for the next step

## Step 2: Clone and Install (3 minutes)

```bash
# Clone this repository
git clone <your-repo-url>
cd confluence-knowledge-base

# Run the interactive installer
./install.sh
```

## Step 3: Follow the Wizard

The wizard will ask you:

### 1. Confluence URL
```
Enter your Confluence URL (e.g., https://yourcompany.atlassian.net):
URL: https://yourcompany.atlassian.net
```

### 2. Your Email
```
Enter your Confluence email address:
Email: you@company.com
```

### 3. API Token
```
Enter your Confluence API token:
API Token: [paste the token from Step 1]
```

### 4. Which Spaces to Index

The wizard will show all your spaces:

```
Found 8 space(s):

Space Key:   ENG
Name:        Engineering
Type:        global

Space Key:   DEVOPS
Name:        DevOps & Infrastructure
Type:        global

Space Key:   PRODUCT
Name:        Product Documentation
Type:        global

...

Which spaces do you want to include in your knowledge base?
Spaces: ENG,DEVOPS
```

**Tips:**
- Include: Technical, Engineering, DevOps, API docs
- Skip: Personal spaces (~username), Meeting notes, HR

### 5. Build Index

```
Do you want to build the index now? (recommended) (y/n): y
```

Wait 1-2 minutes while it indexes your docs.

## Step 4: Start Using It!

```bash
# Start Gemini CLI
gemini
```

```
> How does our authentication system work?

> What's the deployment process for production?

> Explain our API rate limits
```

**That's it!** Gemini will automatically use your documentation to answer questions.

## Verify It's Working

Check that the MCP server is loaded:

```
> /mcp
```

You should see:
```
confluence-kb: Connected ✓
```

## What Happens Behind the Scenes

1. **Install script**:
   - Installs Python packages (ChromaDB, sentence-transformers, etc.)
   - Saves your credentials to `~/.confluence_mcp.env`
   - Tests connection to Confluence
   - Discovers available spaces

2. **Space selection**:
   - You choose which spaces to index
   - Only those spaces are downloaded

3. **Index building**:
   - Downloads all pages from selected spaces
   - Converts HTML to clean text
   - Splits into chunks (~1000 characters each)
   - Creates vector embeddings for semantic search
   - Stores in local ChromaDB at `~/.confluence_mcp/index/`

4. **Gemini integration**:
   - Adds MCP server config to `~/.gemini/settings.json`
   - Gemini can now call the knowledge base tools

## Common Issues

### "Python 3 not found"

Install Python 3:
- **macOS**: `brew install python3`
- **Linux**: `sudo apt install python3 python3-pip`

### "Gemini CLI not found"

Install from: https://github.com/google-gemini/gemini-cli

The installer will still work - you'll just need to manually add the config to `~/.gemini/settings.json`

### "Connection failed: 401 Unauthorized"

Your API token is invalid or expired. Generate a new one and run `./install.sh` again.

### "No spaces found"

You might not have access to any Confluence spaces. Contact your admin.

## Next Steps

### When Documentation Changes

Reindex manually:
```bash
source ~/.confluence_mcp.env
python3 confluence_knowledge_base.py
```

Or ask Gemini:
```
> Reindex the Confluence documentation
```

### Set Up Automatic Weekly Updates

See `REINDEXING_GUIDE.md` for cron job setup.

### Customize Configuration

Edit `~/.confluence_mcp.env` to:
- Add/remove spaces
- Change credentials
- Add custom settings

Then rebuild the index.

## Example Conversations

### Architecture Questions
```
> How is our microservices architecture structured?

> What databases do we use and for what purposes?

> Explain our event-driven architecture
```

### Operations Questions
```
> How do I deploy to production?

> What's the rollback procedure?

> Where are the deployment logs?
```

### API Questions
```
> What are the authentication endpoints?

> Show me the rate limiting rules

> How do I paginate API results?
```

## Getting Help

- **Detailed setup**: See `KNOWLEDGE_BASE_SETUP.md`
- **Reindexing strategies**: See `REINDEXING_GUIDE.md`
- **Main README**: See `README.md`

---

**You're all set!** Start asking questions about your systems and let your Confluence docs do the talking.
