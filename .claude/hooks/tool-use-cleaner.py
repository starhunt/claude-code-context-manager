#!/usr/bin/env python3
"""
Claude Context Tool Cleaner
===========================
도구 사용 기록(Tool Use + Tool Result)을 정리하여 컨텍스트를 확보하고 토큰을 절약하는 스크립트입니다.
삭제된 메시지 사이의 UUID 체인(parentUuid -> uuid)을 자동으로 복구하여 세션 무결성을 유지합니다.

주요 기능:
1. tool_use와 tool_result 쌍을 ID 기반으로 매칭하여 삭제
2. 삭제된 메시지로 인해 끊어진 UUID 체인 자동 복구 (재귀적 부모 탐색)
3. 원본 파일 백업 (.bak.timestamp) 생성 (최근 5개만 유지)
4. 실행 결과 통계 출력

사용법:
    python3 tool-use-cleaner.py <transcript_path>
"""

import json
import sys
import os
import shutil
import glob
from datetime import datetime
from typing import List, Dict, Set, Optional

class Message:
    def __init__(self, data: dict):
        self.data = data
        self.uuid = data.get('uuid')
        self.parent_uuid = data.get('parentUuid')
        self.type = data.get('type')
        self.content = data.get('message', {}).get('content', [])
        self.tool_use_id_ref = None
        self.tool_ids = []

        self._parse_content()

    def _parse_content(self):
        if isinstance(self.content, list):
            for item in self.content:
                if item.get('type') == 'tool_use':
                    self.tool_ids.append(item.get('id'))
                elif item.get('type') == 'tool_result':
                    tid = item.get('tool_use_id')
                    if tid:
                        self.tool_use_id_ref = tid

    def is_tool_use(self) -> bool:
        return bool(self.tool_ids)

    def is_tool_result(self) -> bool:
        return bool(self.tool_use_id_ref)

class TranscriptCleaner:
    def __init__(self, filepath: str):
        self.filepath = filepath
        self.messages: List[Message] = []
        self.uuid_map: Dict[str, Message] = {}

    def load(self) -> bool:
        if not os.path.exists(self.filepath):
            print(f"Error: File not found: {self.filepath}", file=sys.stderr)
            return False

        try:
            with open(self.filepath, 'r', encoding='utf-8') as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        data = json.loads(line)
                        msg = Message(data)
                        self.messages.append(msg)
                        if msg.uuid:
                            self.uuid_map[msg.uuid] = msg
                    except json.JSONDecodeError:
                        continue
            return True
        except Exception as e:
            print(f"Error loading file: {e}", file=sys.stderr)
            return False

    def clean(self) -> dict:
        removed_uuids: Set[str] = set()
        tool_pairs_removed = 0

        tool_use_map: Dict[str, Message] = {}
        tool_result_map: Dict[str, Message] = {}

        for msg in self.messages:
            for tid in msg.tool_ids:
                tool_use_map[tid] = msg

            if msg.tool_use_id_ref:
                tool_result_map[msg.tool_use_id_ref] = msg

        for tid, use_msg in tool_use_map.items():
            if tid in tool_result_map:
                result_msg = tool_result_map[tid]

                if use_msg.uuid not in removed_uuids:
                    removed_uuids.add(use_msg.uuid)

                if result_msg.uuid not in removed_uuids:
                    removed_uuids.add(result_msg.uuid)
                    tool_pairs_removed += 1

        repaired_links = 0
        final_messages = []

        for msg in self.messages:
            if msg.uuid in removed_uuids:
                continue

            original_parent = msg.parent_uuid
            current_parent = original_parent

            while current_parent in removed_uuids:
                parent_msg = self.uuid_map.get(current_parent)
                if not parent_msg:
                    break
                current_parent = parent_msg.parent_uuid

            if current_parent != original_parent:
                msg.data['parentUuid'] = current_parent
                repaired_links += 1

            final_messages.append(msg)

        return {
            'messages': final_messages,
            'stats': {
                'original_count': len(self.messages),
                'final_count': len(final_messages),
                'removed_messages': len(removed_uuids),
                'removed_pairs': tool_pairs_removed,
                'repaired_links': repaired_links
            }
        }

    def save(self, messages: List[Message], backup=True) -> bool:
        try:
            if backup:
                timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
                backup_path = f"{self.filepath}.bak.{timestamp}"
                shutil.copy2(self.filepath, backup_path)
                print(f"📦 Backup created: {backup_path}")

                backup_pattern = f"{self.filepath}.bak.*"
                old_backups = sorted(glob.glob(backup_pattern), reverse=True)

                if len(old_backups) > 5:
                    for old_backup in old_backups[5:]:
                        try:
                            os.remove(old_backup)
                            print(f"🗑️  Removed old backup: {os.path.basename(old_backup)}")
                        except Exception:
                            pass

            with open(self.filepath, 'w', encoding='utf-8') as f:
                for msg in messages:
                    f.write(json.dumps(msg.data) + '\n')
            return True
        except Exception as e:
            print(f"Error saving file: {e}", file=sys.stderr)
            return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 tool-use-cleaner.py <transcript_path>", file=sys.stderr)
        sys.exit(1)

    filepath = sys.argv[1]
    print(f"🔧 Processing: {filepath}")

    cleaner = TranscriptCleaner(filepath)
    if not cleaner.load():
        sys.exit(1)

    result = cleaner.clean()
    stats = result['stats']

    if stats['removed_messages'] > 0:
        if cleaner.save(result['messages']):
            print(f"✅ Cleanup successful!")
            print(f"   - Removed Tool Pairs: {stats['removed_pairs']}")
            print(f"   - Total Messages Removed: {stats['removed_messages']}")
            print(f"   - Repaired UUID Links: {stats['repaired_links']}")
            print(f"   - Message Count: {stats['original_count']} -> {stats['final_count']}")
        else:
            sys.exit(1)
    else:
        print("ℹ️  No complete tool pairs found to clean.")

if __name__ == "__main__":
    main()
