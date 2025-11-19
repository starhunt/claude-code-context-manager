#!/bin/bash

CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/hooks/scripts/cleanup-state.json"
SCRIPT_DIR="$CLAUDE_PROJECT_DIR/.claude/hooks/scripts"

# Read stdin
HOOK_INPUT=$(cat)
SESSION_ID=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')

# Check if state file exists
if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

# Read state
COUNTDOWN=$(jq -r '.countdown // 0' "$STATE_FILE")

# Handle countdown
case $COUNTDOWN in
    0)
        # Do nothing
        exit 0
        ;;
    5)
        # Update state
        jq '.countdown = 4' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

        echo "(is NOT error)" >&2
        echo "┌─────────────────────────────────────────────────────────────────────┐" >&2
        echo "│   Tool pairs will be removed and session will restart in 4 turns.   │" >&2
        echo "└─────────────────────────────────────────────────────────────────────┘" >&2
        exit 1
        ;;
    4)
        # Update state
        jq '.countdown = 3' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

        echo "(is NOT error)" >&2
        echo "┌─────────────────────────────────────────────────────────────────────┐" >&2
        echo "│   Tool pairs will be removed and session will restart in 3 turns.   │" >&2
        echo "└─────────────────────────────────────────────────────────────────────┘" >&2
        exit 1
        ;;
    3)
        # Update state
        jq '.countdown = 2' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

        echo "(is NOT error)" >&2
        echo "┌─────────────────────────────────────────────────────────────────────┐" >&2
        echo "│   Tool pairs will be removed and session will restart in 2 turns.   │" >&2
        echo "└─────────────────────────────────────────────────────────────────────┘" >&2
        exit 1
        ;;
    2)
        # Run Context Tool Cleaner
        if [ -f "$SCRIPT_DIR/context-tool-cleaner.py" ] && [ -n "$TRANSCRIPT_PATH" ]; then
            echo "(is NOT error)" >&2
            echo "───────────────────────────────────────────────────────────────────────" >&2
            echo "🧹 Running context-tool-cleaner..." >&2
            python3 "$SCRIPT_DIR/context-tool-cleaner.py" "$TRANSCRIPT_PATH" >&2
        fi

        # Update state
        jq '.countdown = 1' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "                 🔄 Session will restart next turn. 🔄    " >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        exit 1
        ;;
    1)
        # Update state first
        jq '.countdown = 0' "$STATE_FILE" > "$STATE_FILE.tmp" && mv "$STATE_FILE.tmp" "$STATE_FILE"

        # tmux restart with --continue
        if [ -n "$TMUX" ]; then
            PANE="${TMUX_PANE}"
            (
                sleep 1.0
                tmux send-keys -t "$PANE" C-c
                sleep 0.3
                tmux send-keys -t "$PANE" C-c
                sleep 0.5
                tmux send-keys -t "$PANE" Up
                sleep 0.3
                # Add --continue flag
                tmux send-keys -t "$PANE" " --continue"
                sleep 0.2
                tmux send-keys -t "$PANE" Enter
            ) &
        fi

        echo "(is NOT error)" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "🔄 Restarting session in 1s (--continue)..." >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        exit 1
        ;;
esac

exit 0
