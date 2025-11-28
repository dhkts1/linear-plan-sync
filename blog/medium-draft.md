# From AI Plans to Linear Tickets: Building a Claude Code Hook That Bridges AI and Project Management

*Automate your dev workflow by syncing Claude Code plans directly to Linear*

---

## The Problem: Great Plans, Lost Context

If you're using Claude Code for development, you've probably experienced this: Claude helps you plan a complex feature, creates a thoughtful implementation roadmap, you approve it... and then what?

The plan lives in a markdown file somewhere. Maybe you copy-paste it into a Linear ticket. Maybe you forget about it entirely. Either way, there's a gap between the AI-assisted planning phase and your project management workflow.

What if that gap could close automatically?

## What We're Building

A Claude Code hook that triggers whenever you exit plan mode. It:

1. Reads your approved plan
2. Extracts the ticket ID from your git branch
3. Posts the plan as a comment to a Linear ticket
4. Creates a "mirror ticket" if needed for documentation

The result: Every plan Claude helps you create becomes part of your Linear project history—automatically.

## Understanding Claude Code Hooks

Claude Code has an event-driven hooks system that lets you run custom scripts at specific points in its lifecycle. The key events include:

- **PreToolUse**: Before a tool executes (can block or modify)
- **PostToolUse**: After a tool completes (for side effects)
- **UserPromptSubmit**: When you send a message
- **Stop**: When Claude finishes responding

For our use case, we'll use `PostToolUse` with a matcher for `ExitPlanMode`—this fires when you approve a plan and return to normal execution.

Hooks receive context via stdin as JSON:

```json
{
  "tool_name": "ExitPlanMode",
  "cwd": "/path/to/your/project",
  "tool_input": {...}
}
```

## The Implementation

### Hook Configuration

First, add the hook to your `~/.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "ExitPlanMode",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/sync-to-linear.sh"
          }
        ]
      }
    ]
  }
}
```

### The Sync Script

The script handles several tasks:

**1. Configuration Loading**

```bash
CONFIG_FILE="${HOME}/.claude/linear-sync.json"

load_config() {
  if [ -f "$CONFIG_FILE" ]; then
    TEAM_ID=$(jq -r '.teamId // empty' "$CONFIG_FILE")
    CREATE_MIRROR=$(jq -r '.createMirrorTickets // true' "$CONFIG_FILE")
    # ... more config
  else
    # Fallback to environment variables
    TEAM_ID="${LINEAR_TEAM_ID:-}"
  fi

  # API key always from environment (security best practice)
  API_KEY="${LINEAR_API_KEY:-}"
}
```

**2. Plan File Detection**

Claude Code stores plans in different locations depending on context:

```bash
find_plan_file() {
  local cwd="$1"

  # Try worktree-specific plan first
  local git_root
  git_root=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null)

  if [ -f "$git_root/.claude/plan.md" ]; then
    echo "$git_root/.claude/plan.md"
    return 0
  fi

  # Fallback to most recent global plan
  ls -t ~/.claude/plans/*.md 2>/dev/null | head -1
}
```

**3. Ticket ID Extraction**

We parse the git branch name to find ticket IDs:

```bash
extract_ticket_id() {
  local branch
  branch=$(git branch --show-current 2>/dev/null)

  # Case-insensitive match for PREFIX-NUMBER pattern
  echo "$branch" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]'
}
```

This handles branches like:
- `feature/TOK-1234-add-auth` → `TOK-1234`
- `eng-567-fix-bug` → `ENG-567`
- `main` → `NO-TICKET`

**4. Linear GraphQL API**

Linear uses GraphQL. We wrap calls in a helper:

```bash
linear_graphql() {
  local query="$1"
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$query"
}
```

Creating a mirror ticket:

```bash
create_mirror_ticket() {
  local title="$1"
  linear_graphql "$(jq -n --arg title "$title" --arg teamId "$TEAM_ID" '{
    query: "mutation($title: String!, $teamId: String!) {
      issueCreate(input: { title: $title, teamId: $teamId }) {
        success
        issue { id identifier }
      }
    }",
    variables: {title: $title, teamId: $teamId}
  }')"
}
```

**5. Posting the Plan**

Finally, we post the plan as a comment with proper formatting:

```bash
local comment_body="## Implementation Plan

$plan_content

---
_Synced from Claude Code_"

post_comment "$mirror_id" "$comment_body"
```

## Setting It Up

### 1. Get Your Linear API Key

1. Go to [Linear Settings > API](https://linear.app/settings/api)
2. Create a Personal API Key
3. Export it:
   ```bash
   export LINEAR_API_KEY="lin_api_xxxxxxxxxxxxx"
   ```

### 2. Find Your Team ID

In Linear: Settings > Teams > [Your Team] > Copy the ID from the URL.

### 3. Create the Config

```json
// ~/.claude/linear-sync.json
{
  "teamId": "your-team-uuid-here",
  "createMirrorTickets": true,
  "ticketTitleFormat": "{TICKET_ID}: Plan Documentation"
}
```

### 4. Install the Plugin

```bash
claude plugin install dhkts1/linear-plan-sync
```

Or manually add the hook to your settings.

## The Result

Now when you work with Claude Code:

```
You: "Help me plan adding OAuth2 authentication"

Claude: [enters plan mode, creates detailed implementation plan]

You: [approve the plan]

Claude: [exits plan mode]

Hook: ✓ Plan synced to TOK-1234: Plan Documentation
      https://linear.app/your-team/issue/TOK-1234#comment-abc123
```

Your Linear ticket now has the full implementation plan as a comment—with timestamps, formatted markdown, and a link back to the context.

## Extending the Pattern

This same pattern works for other integrations:

- **Jira**: Swap the GraphQL calls for Jira REST API
- **Notion**: Create pages in a plans database
- **GitHub Issues**: Add plans as issue comments
- **Slack**: Post plan summaries to a channel

You could also use `PreToolUse` hooks for:
- Blocking dangerous operations
- Enforcing coding standards
- Requiring confirmation for destructive actions

## Security Considerations

A few important notes:

1. **API keys**: Always use environment variables, never hardcode
2. **Hook execution**: Hooks run with your user permissions—validate inputs
3. **Script paths**: Use absolute paths or `$CLAUDE_PROJECT_DIR`
4. **Sensitive files**: Skip `.env`, credentials, and `.git/` directories

## Get the Plugin

The full plugin is available on GitHub:

**[github.com/dhkts1/linear-plan-sync](https://github.com/dhkts1/linear-plan-sync)**

Install with:
```bash
claude plugin install dhkts1/linear-plan-sync
```

---

*Have ideas for other Claude Code hooks? I'd love to hear them—drop a comment or open an issue on the repo.*
