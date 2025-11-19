#!/bin/bash

CLAUDE_PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
STATE_FILE="$CLAUDE_PROJECT_DIR/.claude/hooks/state.json"
SCRIPT_DIR="$CLAUDE_PROJECT_DIR/.claude/hooks/"

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
        if [ -f "$SCRIPT_DIR/tool-use-cleaner.py" ] && [ -n "$TRANSCRIPT_PATH" ]; then
            echo ":" >&2
            echo "───────────────────────────────────────────────────────────────────────" >&2
            echo "🧹 Running tool-use-cleaner..." >&2
            python3 "$SCRIPT_DIR/tool-use-cleaner.py" "$TRANSCRIPT_PATH" >&2
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
                tmux send-keys -t "$PANE" "claude --dangerously-skip-permissions  --resume $SESSION_ID"
                sleep 0.2
                tmux send-keys -t "$PANE" Enter
            ) &
        fi

        echo ":" >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        echo "🔄 Restarting session in 1s (--resume $SESSION_ID)..." >&2
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" >&2
        exit 1
        ;;
esac

exit 0
