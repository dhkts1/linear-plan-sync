# linear-plan-sync

A Claude Code plugin that automatically syncs your implementation plans to Linear tickets when you exit plan mode.

## What it does

When you use Claude Code's plan mode and exit with a completed plan, this hook automatically:

1. **Detects your plan file** - Checks for worktree-specific plans first, falls back to global plans
2. **Extracts ticket ID** - Reads your git branch name to find ticket IDs (e.g., `TOK-1234`, `ENG-567`)
3. **Creates/finds mirror ticket** - Finds or creates a "Plan Documentation" ticket in your Linear workspace
4. **Posts plan as comment** - Syncs the full plan content as a formatted comment

## Installation

### Via Claude Code CLI

```bash
claude plugin install dhkts1/linear-plan-sync
```

### Manual Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/dhkts1/linear-plan-sync.git ~/.claude/plugins/linear-plan-sync
   ```

2. Add the hook to your `~/.claude/settings.json`:
   ```json
   {
     "hooks": {
       "PostToolUse": [
         {
           "matcher": "ExitPlanMode",
           "hooks": [
             {
               "type": "command",
               "command": "~/.claude/plugins/linear-plan-sync/hooks/sync-to-linear.sh"
             }
           ]
         }
       ]
     }
   }
   ```

## Configuration

### 1. Get your Linear API Key

1. Go to [Linear Settings > API](https://linear.app/settings/api)
2. Create a new Personal API Key
3. Set it as an environment variable:
   ```bash
   export LINEAR_API_KEY="lin_api_xxxxxxxxxxxxx"
   ```

### 2. Get your Linear Team ID

1. Go to Linear Settings > Teams
2. Click on your team
3. Copy the Team ID from the URL or settings

### 3. Create config file

Copy the example config:

```bash
cp config/linear-sync.example.json ~/.claude/linear-sync.json
```

Edit `~/.claude/linear-sync.json`:

```json
{
  "teamId": "YOUR_LINEAR_TEAM_ID",
  "createMirrorTickets": true,
  "ticketTitleFormat": "{TICKET_ID}: Plan Documentation",
  "commentHeader": "## Implementation Plan"
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `teamId` | string | required | Your Linear team ID |
| `createMirrorTickets` | boolean | `true` | Create mirror tickets if they don't exist |
| `ticketTitleFormat` | string | `"{TICKET_ID}: Plan Documentation"` | Title format for mirror tickets |
| `commentHeader` | string | `"## Implementation Plan"` | Header for plan comments |

### Environment Variables

You can also configure via environment variables (config file takes precedence):

| Variable | Description |
|----------|-------------|
| `LINEAR_API_KEY` | Your Linear API key (required) |
| `LINEAR_TEAM_ID` | Team ID for creating tickets |
| `LINEAR_CREATE_MIRROR` | Whether to create mirror tickets |
| `LINEAR_TITLE_FORMAT` | Title format for mirror tickets |
| `LINEAR_COMMENT_HEADER` | Header for plan comments |

## How it Works

```
┌─────────────────────────────────────────────────────────────┐
│                     Claude Code                              │
│                                                              │
│  1. User enters plan mode                                    │
│  2. Claude creates plan in .claude/plan.md                   │
│  3. User approves plan (ExitPlanMode)                        │
│                          │                                   │
└──────────────────────────┼───────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                   PostToolUse Hook                           │
│                                                              │
│  4. Hook triggers on ExitPlanMode                            │
│  5. Reads plan content                                       │
│  6. Extracts ticket ID from git branch                       │
│                          │                                   │
└──────────────────────────┼───────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                      Linear API                              │
│                                                              │
│  7. Finds/creates mirror ticket                              │
│  8. Posts plan as comment                                    │
│  9. Returns comment URL                                      │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Plan File Detection

The hook looks for plans in this order:

1. **Worktree plan**: `{git_root}/.claude/plan.md`
2. **Global plan**: Most recent file in `~/.claude/plans/*.md`

## Ticket ID Extraction

The hook extracts ticket IDs from your git branch name:

| Branch | Extracted ID |
|--------|--------------|
| `feature/TOK-1234-add-auth` | `TOK-1234` |
| `eng-567-fix-bug` | `ENG-567` |
| `main` | `NO-TICKET` |

## Troubleshooting

### "LINEAR_API_KEY environment variable not set"

Make sure your API key is exported in your shell profile:

```bash
# Add to ~/.zshrc or ~/.bashrc
export LINEAR_API_KEY="lin_api_xxxxxxxxxxxxx"
```

### "Linear team ID not configured"

Create the config file at `~/.claude/linear-sync.json` with your team ID.

### Hook not triggering

1. Check that the hook is in your `settings.json`
2. Verify the script is executable: `chmod +x ~/.claude/plugins/linear-plan-sync/hooks/sync-to-linear.sh`
3. Check Claude Code logs for errors

## Development

### Pre-commit hooks

This repo uses pre-commit hooks to prevent secrets from being committed:

```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually on all files
pre-commit run --all-files
```

## License

MIT - See [LICENSE](LICENSE)

## Contributing

Contributions welcome! Please open an issue or PR.

1. Fork the repo
2. Install pre-commit hooks: `pre-commit install`
3. Make your changes
4. Submit a PR
