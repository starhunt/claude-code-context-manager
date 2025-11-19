#!/bin/bash
set -e

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Claude Code Context Manager - Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Detect project directory
if [ -n "$CLAUDE_PROJECT_DIR" ]; then
    PROJECT_DIR="$CLAUDE_PROJECT_DIR"
else
    PROJECT_DIR="$(pwd)"
fi

echo "📁 Installing to: $PROJECT_DIR"
echo ""

# Check dependencies
echo "🔍 Checking dependencies..."

# Check Python 3
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 not found. Please install Python 3 first."
    exit 1
fi
echo "  ✅ Python 3: $(python3 --version)"

# Check jq (JSON processor)
if ! command -v jq &> /dev/null; then
    echo "⚠️  jq not found. Installing..."

    if command -v brew &> /dev/null; then
        brew install jq
    elif command -v apt-get &> /dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y jq
    else
        echo "❌ Cannot auto-install jq. Please install manually: https://jqlang.github.io/jq/download/"
        exit 1
    fi
fi
echo "  ✅ jq: $(jq --version)"

# Check tmux (optional)
if command -v tmux &> /dev/null; then
    echo "  ✅ tmux: $(tmux -V)"
else
    echo "  ⚠️  tmux not found (optional - will be auto-installed on first use)"
fi

echo ""

# Create directories
echo "📦 Creating directories..."
mkdir -p "$PROJECT_DIR/.claude/hooks/scripts"
echo "  ✅ Created .claude/hooks/scripts/"
echo ""

# Copy hook files
echo "📋 Copying hook files..."

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cp "$SCRIPT_DIR/hooks/post-tool-use.sh" "$PROJECT_DIR/.claude/hooks/"
echo "  ✅ post-tool-use.sh"

cp "$SCRIPT_DIR/hooks/stop-hook.sh" "$PROJECT_DIR/.claude/hooks/"
echo "  ✅ stop-hook.sh"

cp "$SCRIPT_DIR/hooks/scripts/context-tool-cleaner.py" "$PROJECT_DIR/.claude/hooks/scripts/"
echo "  ✅ context-tool-cleaner.py"

echo ""

# Set permissions
echo "🔐 Setting permissions..."
chmod +x "$PROJECT_DIR/.claude/hooks/post-tool-use.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/stop-hook.sh"
chmod +x "$PROJECT_DIR/.claude/hooks/scripts/context-tool-cleaner.py"
echo "  ✅ All scripts are executable"
echo ""

# Initialize state file
echo "⚙️  Initializing state..."
mkdir -p "$PROJECT_DIR/.claude/hooks/scripts"
if [ ! -f "$PROJECT_DIR/.claude/hooks/scripts/cleanup-state.json" ]; then
    echo '{"countdown":0,"session_id":""}' > "$PROJECT_DIR/.claude/hooks/scripts/cleanup-state.json"
    echo "  ✅ Created cleanup-state.json"
else
    echo "  ℹ️  cleanup-state.json already exists (skipping)"
fi
echo ""

# Update settings.json
echo "🔧 Updating settings.json..."

SETTINGS_FILE="$PROJECT_DIR/.claude/settings.json"

if [ ! -f "$SETTINGS_FILE" ]; then
    echo "  📝 Creating new settings.json..."
    cp "$SCRIPT_DIR/settings.example.json" "$SETTINGS_FILE"
    echo "  ✅ Created settings.json"
else
    echo "  📝 Merging with existing settings.json..."

    # Backup existing settings
    cp "$SETTINGS_FILE" "$SETTINGS_FILE.backup.$(date +%Y%m%d-%H%M%S)"

    # Merge hooks configuration
    TEMP_FILE=$(mktemp)

    jq -s '
        .[0] as $existing |
        .[1] as $new |
        $existing |
        .hooks.PostToolUse = ($new.hooks.PostToolUse // []) +
            (($existing.hooks.PostToolUse // []) | map(select(.hooks[0].command | contains("post-tool-use.sh") | not))) |
        .hooks.Stop = ($new.hooks.Stop // []) +
            (($existing.hooks.Stop // []) | map(select(.hooks[0].command | contains("stop-hook.sh") | not)))
    ' "$SETTINGS_FILE" "$SCRIPT_DIR/settings.example.json" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$SETTINGS_FILE"
    echo "  ✅ Merged settings.json (backup created)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✅ Installation Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "  1. Restart your Claude Code session"
echo "  2. Use tools (Read, Edit, etc.) to trigger context cleanup"
echo "  3. Watch for countdown messages in Stop hooks"
echo ""
echo "Configuration:"
echo "  • Settings: $SETTINGS_FILE"
echo "  • Hooks: $PROJECT_DIR/.claude/hooks/"
echo "  • State: $PROJECT_DIR/.claude/hooks/scripts/cleanup-state.json"
echo ""
echo "For more info: https://github.com/professional-ALFIE/claude-code-context-manager"
echo ""
