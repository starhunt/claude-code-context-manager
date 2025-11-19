#!/usr/bin/env python3
"""
Claude Context Tool Cleaner
===========================
도구 사용 기록(Tool Use + Tool Result)을 정리하여 컨텍스트를 확보하고 토큰을 절약하는 스크립트입니다.
삭제된 메시지 사이의 UUID 체인(parentUuid -> uuid)을 자동으로 복구하여 세션 무결성을 유지합니다.

주요 기능:
1. tool_use와 tool_result 쌍을 ID 기반으로 매칭하여 삭제
2. 삭제된 메시지로 인해 끊어진 UUID 체인 자동 복구 (재귀적 부모 탐색)
3. 원본 파일 백업 (.bak) 생성
4. 실행 결과 통계 출력

사용법:
    python3 context-tool-cleaner.py <transcript_path>
"""

import json
import sys
import os
import shutil
from typing import List, Dict, Set, Optional

class Message:
    def __init__(self, data: dict):
        self.data = data
        self.uuid = data.get('uuid')
        self.parent_uuid = data.get('parentUuid')
        self.type = data.get('type')
        self.content = data.get('message', {}).get('content', [])
        # tool_use_id 추출 (tool_result의 경우)
        self.tool_use_id_ref = None
        # tool_id 추출 (tool_use의 경우)
        self.tool_ids = []

        self._parse_content()

    def _parse_content(self):
        if isinstance(self.content, list):
            for item in self.content:
                if item.get('type') == 'tool_use':
                    self.tool_ids.append(item.get('id'))
                elif item.get('type') == 'tool_result':
                    # tool_result는 보통 하나의 메시지에 하나씩 있지만, 여러 개일 수도 있음
                    # 여기서는 tool_use_id를 수집
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

        # 1. Tool ID 매핑
        tool_use_map: Dict[str, Message] = {}    # tool_id -> message
        tool_result_map: Dict[str, Message] = {} # tool_use_id -> message

        for msg in self.messages:
            for tid in msg.tool_ids:
                tool_use_map[tid] = msg

            if msg.tool_use_id_ref:
                tool_result_map[msg.tool_use_id_ref] = msg

        # 2. 쌍 찾기 및 삭제 대상 선정
        # tool_use와 tool_result가 모두 존재하는 쌍만 삭제
        for tid, use_msg in tool_use_map.items():
            if tid in tool_result_map:
                result_msg = tool_result_map[tid]

                # 이미 삭제 목록에 없으면 추가
                if use_msg.uuid not in removed_uuids:
                    removed_uuids.add(use_msg.uuid)

                if result_msg.uuid not in removed_uuids:
                    removed_uuids.add(result_msg.uuid)
                    tool_pairs_removed += 1

        # 3. 체인 복구
        repaired_links = 0
        final_messages = []

        for msg in self.messages:
            # 삭제될 메시지는 건너뜀
            if msg.uuid in removed_uuids:
                continue

            original_parent = msg.parent_uuid
            current_parent = original_parent

            # 부모가 삭제 목록에 있다면, 그 부모의 부모를 계속 추적 (재귀적 탐색)
            # while 루프를 사용하여 삭제되지 않은 조상을 찾음
            while current_parent in removed_uuids:
                parent_msg = self.uuid_map.get(current_parent)
                if not parent_msg:
                    # 부모를 찾을 수 없음 (루트이거나 데이터 유실)
                    # 이 경우 연결을 끊거나 유지할 수 밖에 없음.
                    # 여기서는 마지막으로 확인된 부모 유지
                    break
                current_parent = parent_msg.parent_uuid

            # 부모가 변경되었다면 업데이트
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
                backup_path = f"{self.filepath}.bak"
                shutil.copy2(self.filepath, backup_path)
                print(f"📦 Backup created: {backup_path}")

            with open(self.filepath, 'w', encoding='utf-8') as f:
                for msg in messages:
                    f.write(json.dumps(msg.data) + '\n')
            return True
        except Exception as e:
            print(f"Error saving file: {e}", file=sys.stderr)
            return False

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 context-tool-cleaner.py <transcript_path>", file=sys.stderr)
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
