#!/usr/bin/env node
import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'fs';
import { join } from 'path';

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  tool_name: string;
  hook_event_name: string;
}

interface CleanupState {
  countdown: number;
  session_id: string;
  last_tool?: string;
}

async function main() {
  try {
    // Read stdin
    const input = readFileSync(0, 'utf-8');
    const data: HookInput = JSON.parse(input);

    const projectDir = process.env.CLAUDE_PROJECT_DIR || process.cwd();
    const stateDir = join(projectDir, '.claude', 'hooks');
    const stateFile = join(stateDir, 'state.json');

    // Create state directory if needed
    if (!existsSync(stateDir)) {
      mkdirSync(stateDir, { recursive: true });
    }

    // Read or initialize state
    let state: CleanupState;
    if (existsSync(stateFile)) {
      try {
        state = JSON.parse(readFileSync(stateFile, 'utf-8'));
      } catch {
        state = { countdown: 0, session_id: '' };
      }
    } else {
      state = {
        countdown: 0,
        session_id: ''
      };
    }

    // Update state: Set countdown to 4 (3 warning turns + 1 action turn)
    state.countdown = 4;
    state.session_id = data.session_id;
    state.last_tool = data.tool_name;

    // Save state
    writeFileSync(stateFile, JSON.stringify(state, null, 2));

    process.exit(0);
  } catch (err) {
    console.error(`PostToolUse Hook Error: ${err}`,);
    process.exit(1);
  }
}

main();
