#!/bin/bash
# sync-to-linear.sh
# Automatically syncs Claude Code plans to Linear as issue comments
# Part of linear-plan-sync plugin: https://github.com/dhkts1/linear-plan-sync

set -euo pipefail

# Ensure common tools are in PATH
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

# Configuration file path
CONFIG_FILE="${HOME}/.claude/linear-sync.json"

# ============================================================================
# CONFIGURATION
# ============================================================================

# Load configuration from file or environment variables
load_config() {
  local config_api_key=""

  if [ -f "$CONFIG_FILE" ]; then
    TEAM_ID=$(jq -r '.teamId // empty' "$CONFIG_FILE")
    CREATE_MIRROR=$(jq -r '.createMirrorTickets // true' "$CONFIG_FILE")
    TITLE_FORMAT=$(jq -r '.ticketTitleFormat // "{TICKET_ID}: Plan Documentation"' "$CONFIG_FILE")
    COMMENT_HEADER=$(jq -r '.commentHeader // "## Implementation Plan"' "$CONFIG_FILE")
    config_api_key=$(jq -r '.apiKey // empty' "$CONFIG_FILE")
  else
    # Fallback to environment variables
    TEAM_ID="${LINEAR_TEAM_ID:-}"
    CREATE_MIRROR="${LINEAR_CREATE_MIRROR:-true}"
    TITLE_FORMAT="${LINEAR_TITLE_FORMAT:-{TICKET_ID}: Plan Documentation}"
    COMMENT_HEADER="${LINEAR_COMMENT_HEADER:-## Implementation Plan}"
  fi

  # API key priority: env var > config file
  API_KEY="${LINEAR_API_KEY:-$config_api_key}"
}

# ============================================================================
# VALIDATION
# ============================================================================

validate_config() {
  if [ -z "$API_KEY" ]; then
    echo "LINEAR_API_KEY environment variable not set"
    echo "Get your API key from: https://linear.app/settings/api"
    exit 0  # Silent exit - don't fail the hook
  fi

  if [ -z "$TEAM_ID" ]; then
    echo "Linear team ID not configured"
    echo "Set teamId in $CONFIG_FILE or LINEAR_TEAM_ID env var"
    echo "Find your team ID in Linear: Settings > Teams > [Team] > Copy ID"
    exit 0
  fi
}

# ============================================================================
# PLAN FILE DETECTION
# ============================================================================

find_plan_file() {
  local cwd="$1"

  # Try worktree-specific plan first
  local git_root
  git_root=$(cd "$cwd" && git rev-parse --show-toplevel 2>/dev/null || echo "")

  if [ -n "$git_root" ] && [ -f "$git_root/.claude/plan.md" ]; then
    echo "$git_root/.claude/plan.md"
    return 0
  fi

  # Fallback to most recent global plan
  local global_plan
  global_plan=$(ls -t ~/.claude/plans/*.md 2>/dev/null | head -1 || echo "")

  if [ -n "$global_plan" ] && [ -f "$global_plan" ]; then
    echo "$global_plan"
    return 0
  fi

  return 1
}

# ============================================================================
# TICKET ID EXTRACTION
# ============================================================================

extract_ticket_id() {
  local cwd="$1"
  local branch
  branch=$(cd "$cwd" && git branch --show-current 2>/dev/null || echo "")

  # Case-insensitive match for PREFIX-NUMBER pattern
  local ticket_id
  ticket_id=$(echo "$branch" | grep -oiE '[A-Z]+-[0-9]+' | head -1 | tr '[:lower:]' '[:upper:]')

  if [ -z "$ticket_id" ]; then
    ticket_id="$branch"
  fi

  echo "$ticket_id"
}

# ============================================================================
# LINEAR API FUNCTIONS
# ============================================================================

linear_graphql() {
  local query="$1"
  curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "$query"
}

find_mirror_ticket() {
  local ticket_id="$1"
  local response
  response=$(linear_graphql "$(jq -n --arg ticketId "$ticket_id" '{
    query: "query($filter: IssueFilter) { issues(filter: $filter) { nodes { id title identifier } } }",
    variables: {filter: {title: {contains: $ticketId}}}
  }')")

  echo "$response" | jq -r '.data.issues.nodes[0].id // empty'
}

create_mirror_ticket() {
  local title="$1"
  local response
  response=$(linear_graphql "$(jq -n --arg title "$title" --arg teamId "$TEAM_ID" '{
    query: "mutation CreateIssue($title: String!, $teamId: String!) { issueCreate(input: { title: $title, teamId: $teamId }) { success issue { id identifier } } }",
    variables: {title: $title, teamId: $teamId}
  }')")

  local issue_id
  issue_id=$(echo "$response" | jq -r '.data.issueCreate.issue.id // empty')
  local issue_identifier
  issue_identifier=$(echo "$response" | jq -r '.data.issueCreate.issue.identifier // empty')

  if [ -z "$issue_id" ]; then
    local error
    error=$(echo "$response" | jq -r '.errors[0].message // "Unknown error"')
    echo "Failed to create mirror ticket: $error" >&2
    return 1
  fi

  echo "$issue_identifier" >&2
  echo "$issue_id"
}

post_comment() {
  local issue_id="$1"
  local body="$2"

  # Use temp file to avoid JSON escaping issues
  local payload_file
  payload_file=$(mktemp)
  jq -n --arg issueId "$issue_id" --arg body "$body" '{
    query: "mutation($issueId: String!, $body: String!) { commentCreate(input: { issueId: $issueId, body: $body }) { success comment { id url } } }",
    variables: {issueId: $issueId, body: $body}
  }' > "$payload_file"

  local response
  response=$(curl -s -X POST https://api.linear.app/graphql \
    -H "Authorization: $API_KEY" \
    -H "Content-Type: application/json" \
    -d @"$payload_file")

  rm -f "$payload_file"

  local success
  success=$(echo "$response" | jq -r '.data.commentCreate.success // false')

  if [ "$success" = "true" ]; then
    echo "$response" | jq -r '.data.commentCreate.comment.url'
  else
    local error
    error=$(echo "$response" | jq -r '.errors[0].message // .data.commentCreate // "Unknown error"')
    echo "Failed to post comment: $error" >&2
    return 1
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  # Note: API key should be in config file (~/.claude/linear-sync.json)
  # or set as LINEAR_API_KEY environment variable

  # Read JSON input from stdin (PostToolUse provides context)
  local stdin_json
  stdin_json=$(cat)

  # Extract cwd from stdin JSON
  local cwd
  cwd=$(echo "$stdin_json" | jq -r '.cwd // empty' 2>/dev/null)
  cwd="${cwd:-$(pwd)}"

  # Load and validate configuration
  load_config
  validate_config

  # Find plan file
  local plan_file
  if ! plan_file=$(find_plan_file "$cwd"); then
    echo "No plan file found"
    exit 0
  fi

  # Extract ticket ID from branch
  local ticket_id
  ticket_id=$(extract_ticket_id "$cwd")

  # Build mirror ticket title
  local mirror_title
  mirror_title="${TITLE_FORMAT//\{TICKET_ID\}/$ticket_id}"

  # Find or create mirror ticket
  local mirror_id
  mirror_id=$(find_mirror_ticket "$ticket_id")

  if [ -z "$mirror_id" ]; then
    if [ "$CREATE_MIRROR" = "true" ]; then
      echo "Creating mirror ticket: $mirror_title"
      if ! mirror_id=$(create_mirror_ticket "$mirror_title"); then
        exit 1
      fi
    else
      echo "Mirror ticket not found and createMirrorTickets is disabled"
      exit 0
    fi
  fi

  # Read plan and build comment body
  local plan_content
  plan_content=$(cat "$plan_file")

  local comment_body
  comment_body="$COMMENT_HEADER

$plan_content

---
_Synced from Claude Code via [linear-plan-sync](https://github.com/dhkts1/linear-plan-sync)_"

  # Post comment
  local comment_url
  if comment_url=$(post_comment "$mirror_id" "$comment_body"); then
    echo "Plan synced to $mirror_title"
    echo "  $comment_url"
  else
    exit 1
  fi
}

main "$@"
