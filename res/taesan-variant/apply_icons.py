#!/usr/bin/env python3
"""수신 전용 빌드의 아이콘을 덮어쓴다(DSK-01·DSK-10).

res/taesan-variant/incoming-icons/ 아래 파일(오른쪽 위 ↓ 배지 아이콘 — res/taesan-icon/gen_icons.py --variant incoming)을
저장소의 같은 상대 경로에 복사한다. 대상 파일이 하나라도 없으면(경로가 바뀌면) 아무것도 복사하지 않고 멈춘다.
수신 전용 빌드(TAESAN_VARIANT=incoming)는 cargo·Flutter 빌드 전에 이것을 실행해야 한다 — build.rs 가 확인한다.
작업 트리의 추적 파일을 바꾸므로 빌드마다 새로 만드는 체크아웃(CI, 로컬 빌드 스크립트의 worktree)에서 쓴다.
공용 작업 폴더(VS Code 실행)에서는 vscode-prelaunch.sh 가 다음 양방향 실행 전에 되돌린다. 바뀐 아이콘은 커밋하지 않는다.

사용(어느 폴더에서나):
  python3 res/taesan-variant/apply_icons.py
"""

import filecmp
import os
import shutil
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
SRC = os.path.join(ROOT, "res", "taesan-variant", "incoming-icons")


def main() -> int:
    pairs = []
    for d, _, files in os.walk(SRC):
        for f in sorted(files):
            if f.startswith("."):  # .DS_Store 등
                continue
            src = os.path.join(d, f)
            dst = os.path.join(ROOT, os.path.relpath(src, SRC))
            if not os.path.isfile(dst):
                print(f"덮어쓸 대상이 없다: {os.path.relpath(dst, ROOT)}", file=sys.stderr)
                return 1
            pairs.append((src, dst))
    if not pairs:
        print(f"수신 전용 아이콘이 없다: {SRC}", file=sys.stderr)
        return 1
    copied = 0
    for src, dst in pairs:
        # 이미 같으면 쓰지 않는다(수정 시각을 그대로 둬 증분 빌드가 바뀐 파일로 보지 않게).
        if filecmp.cmp(src, dst, shallow=False):
            continue
        shutil.copyfile(src, dst)
        copied += 1
    print(f"수신 전용 아이콘 {len(pairs)}개 중 {copied}개를 덮어썼다(나머지는 이미 같다)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
