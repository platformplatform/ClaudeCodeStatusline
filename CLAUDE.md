# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL: Development Workflow

**NEVER commit or install globally without explicit user approval.**

1. Make changes to `.claude/statusline.sh` in this repository
2. Test the changes locally and verify they work
3. **WAIT for the user to review and explicitly request commit/install**
4. Only then commit and copy to `~/.claude/statusline.sh`

This is a strict requirement. Do not proactively commit or install. Do not ask "should I commit?" - wait for the user to tell you to commit.

## Repository Purpose

This repository maintains a custom Claude Code statusline configuration that displays comprehensive session information including git branch, model details, cost tracking, and usage metrics.

## Project Structure

```
.claude/
├── settings.json    # Claude Code local configuration
└── statusline.sh    # Bash script for statusline display
```

## Claude Code Statusline Architecture

### Configuration
- Local statusline configured in `.claude/settings.json`
- Points to executable script `.claude/statusline.sh`
- Receives JSON session data via stdin

### JSON Input Structure
Claude Code passes a JSON object with this structure:
```json
{
  "session_id": "uuid",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/current/working/directory", 
  "model": {
    "id": "claude-sonnet-4-20250514[1m]",
    "display_name": "Sonnet 4 (with 1M token context)"
  },
  "workspace": {
    "current_dir": "/current/working/directory",
    "project_dir": "/project/root"
  },
  "version": "1.0.96",
  "output_style": {"name": "default"},
  "cost": {
    "total_cost_usd": 0.1355282,
    "total_duration_ms": 67065,
    "total_api_duration_ms": 53178,
    "total_lines_added": 29,
    "total_lines_removed": 25
  },
  "exceeds_200k_tokens": false
}
```

### Statusline Implementation Details

**Available Data:**
- Session cost and duration (from `cost` object)
- Model information (from `model` object)
- Git branch (via `git symbolic-ref --short HEAD`)

**Calculated Metrics:**
- Hourly rate: `total_cost_usd * 3600000 / total_duration_ms`
- Session duration: converted from milliseconds to hours/minutes
- Daily spending: tracked across sessions using temp files in `/tmp/claude_daily_YYYY-MM-DD`

**Locale Handling:**
- System uses comma decimal separator by default
- Script forces `LC_ALL=C` and `LC_NUMERIC=C` for US formatting
- Uses `awk` for reliable decimal formatting instead of `printf`

**Missing Data (Placeholders):**
- Daily/block spending limits
- Context token usage and percentage  
- Block time remaining
These are not provided in Claude Code's JSON and require external tracking or estimation.

## Claude Code SDK Context

The statusline leverages Claude Code's underlying SDK architecture:
- Built on agent harness with optimized Claude integration
- Supports Model Context Protocol (MCP) for extensibility
- Includes session management and error handling
- Provides tool ecosystem for file ops, code execution, web search

## Development Commands

**Test statusline manually:**
```bash
echo '{"model":{"display_name":"Test Model"},"cost":{"total_cost_usd":0.15,"total_duration_ms":60000}}' | .claude/statusline.sh
```

**Reload statusline configuration:**
Use `/statusline` command in Claude Code or restart

**Debug statusline issues:**
```bash
tail -f /tmp/claude_statusline_debug.log  # View debug output (if enabled)
```

## Technical Dependencies

- `jq` (preferred for JSON parsing, falls back to sed)
- `bc` (for floating point calculations)  
- `awk` (for number formatting)
- `git` (for branch detection)

## Statusline Format

Current format displays two lines:
```
📂 {repo_name} | 🌿 {git_branch} | {ccusage_output_with_accurate_pricing}
💬 {last_user_message_with_linebreak_emojis}
```

**Line 1:** Repository name, git branch, and comprehensive usage data from ccusage
**Line 2:** Last user message with ↩ emojis showing original line breaks

## Advanced Features

**User Message Display:**
- Extracts last user message from current session transcript
- Converts multiline messages to single line with ↩ emojis
- Skips "[Request interrupted by user]" messages, showing previous real message
- Truncates to 150 characters with "..." if longer
- Uses Python for reliable newline conversion

**ccusage Integration:**
- Delegates pricing calculations and token estimates to `ccusage statusline`
- Provides accurate model-specific pricing and context window calculations
- Handles different models (Sonnet 4, Sonnet 4 1M, Opus 4.1) correctly

**Terminal Width Management:**
- Auto-detects terminal width via parent shell TTY
- Reserves 25 characters for system messages on the right
- Progressively removes low-priority elements when terminal is narrow
- Truncates user messages to prevent line wrapping