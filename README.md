# Claude Code Context Manager

**Automatic context cleanup and session management for Claude Code**

This plugin automatically manages your Claude Code context by:
- 🧹 Cleaning up tool use/result pairs to save tokens
- 🔄 Auto-restarting sessions for optimal performance
- 📦 Maintaining backup history with timestamps
- 🔗 Repairing UUID chains for session integrity

## Features

### 1. Automatic Tool History Cleanup
After each tool use (Read, Edit, Grep, etc.), the plugin:
- Waits 4 turns to ensure data is no longer needed
- Removes tool_use and tool_result pairs from transcript
- Repairs UUID parent-child links automatically
- Keeps backups (last 5 with timestamps)

### 2. Smart Session Restart
- **tmux users**: Seamlessly restarts in the same pane
- **Non-tmux users**: Auto-installs tmux and creates new session
- **Context preserved**: Uses `--continue` flag for instant resume

### 3. Token Savings
Real-world example from our tests:
```
📊 Cleanup Results:
   - Removed Tool Pairs: 134
   - Total Messages Removed: 264
   - Repaired UUID Links: 99
   - Message Count: 1037 → 773 (25% reduction!)
```

## Installation

### Quick Install
```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/claude-code-context-manager/main/install.sh | bash
```

### Manual Install
1. Clone the repository:
```bash
cd ~/.claude/plugins
git clone https://github.com/YOUR_USERNAME/claude-code-context-manager.git
```

2. Run the installer:
```bash
cd claude-code-context-manager
chmod +x install.sh
./install.sh
```

3. The installer will:
   - Copy hooks to your project's `.claude/hooks/` directory
   - Set up the state management system
   - Update your `.claude/settings.json` (or create if missing)
   - Make scripts executable

## How It Works

### Countdown System
```
Tool Use → PostToolUse Hook → countdown=5
  ↓
Turn 1: Stop Hook → "4 turns remaining..."
  ↓
Turn 2: Stop Hook → "3 turns remaining..."
  ↓
Turn 3: Stop Hook → "2 turns remaining..."
  ↓
Turn 4: Stop Hook → 🧹 Runs context-tool-cleaner.py → "1 turn remaining..."
  ↓
Turn 5: Stop Hook → 🔄 Restarts session (--continue)
```

### Transcript Cleaning Process
1. **Scan**: Find all tool_use and tool_result pairs
2. **Match**: Pair them by tool_use_id
3. **Remove**: Delete matched pairs from transcript
4. **Repair**: Fix UUID chains (parentUuid → uuid)
5. **Backup**: Save timestamped backup before writing
6. **Cleanup**: Remove old backups (keep last 5)

## Configuration

### Default Settings
The plugin automatically adds these hooks to `.claude/settings.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Read|Edit|Write|Grep|Glob|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/post-tool-use.sh"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/stop-hook.sh"
          }
        ]
      }
    ]
  }
}
```

### Customization

#### Change Countdown Duration
Edit `.claude/hooks/post-tool-use.sh`:
```bash
# Default: 5 turns
jq '.countdown = 5' ...

# Shorter: 3 turns
jq '.countdown = 3' ...
```

#### Adjust Backup Retention
Edit `.claude/hooks/scripts/context-tool-cleaner.py`:
```python
# Default: Keep 5 backups
if len(old_backups) > 5:

# Keep more: 10 backups
if len(old_backups) > 10:
```

#### Change Tool Matchers
Edit `.claude/settings.json`:
```json
"matcher": "Read|Edit|Write"  // Only track these tools
```

## Requirements

- **Claude Code**: Latest version
- **Python 3**: For context-tool-cleaner.py
- **jq**: JSON processor (auto-installed by installer)
- **tmux** (optional): For seamless session restart

### Platform Support
- ✅ macOS (tested)
- ✅ Linux (tested)
- ⚠️ Windows: Requires WSL

## Troubleshooting

### Hook Not Running
```bash
# Check permissions
chmod +x .claude/hooks/*.sh
chmod +x .claude/hooks/scripts/*.py

# Verify settings
cat .claude/settings.json | jq '.hooks'
```

### Backup Files Piling Up
The cleaner automatically keeps only the last 5 backups. If you see more:
```bash
# Manual cleanup
rm .claude-acc-*/projects/**/*.jsonl.bak.*
```

### Session Not Restarting
For non-tmux users, ensure tmux is installed:
```bash
# macOS
brew install tmux

# Linux
sudo apt-get install tmux
```

## Advanced Usage

### Manual Cleanup
You can run the cleaner manually on any transcript:
```bash
python3 .claude/hooks/scripts/context-tool-cleaner.py /path/to/transcript.jsonl
```

### Disable Auto-Restart
Comment out the tmux section in `.claude/hooks/stop-hook.sh`:
```bash
# if [ -n "$TMUX" ]; then
#     ...
# fi
```

## Development

### Project Structure
```
claude-code-context-manager/
├── README.md                    # This file
├── install.sh                   # Installation script
├── .gitignore                   # Git ignore rules
├── settings.example.json        # Example settings
└── hooks/
    ├── post-tool-use.sh        # Triggers countdown
    ├── stop-hook.sh            # Manages countdown & restart
    └── scripts/
        └── context-tool-cleaner.py  # Core cleanup logic
```

### Contributing
Pull requests welcome! Please:
1. Test on your setup
2. Update README if adding features
3. Keep backward compatibility

## License

MIT License - Feel free to use and modify!

## Acknowledgments

Built for the Claude Code community to maximize context window efficiency.

---

**Questions?** Open an issue on GitHub!
