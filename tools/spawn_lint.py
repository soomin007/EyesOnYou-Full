# -*- coding: utf-8 -*-
# 스폰 보간 린트(2026-08-25 신설). 프로젝트 루트에서: python tools/spawn_lint.py
# known_issues 함정 감시: 런타임 스폰 노드에 add_child 후 global_position을 대입하면
# 물리 보간이 첫 렌더 프레임을 원점에서 보간해 잔상이 원점→실좌표로 날아간다.
# 규칙: 좌표 대입 직후 reset_physics_interpolation() 호출.
# 휴리스틱: 같은 식별자에 대해 add_child(x) 이후 6줄 안에 x.global_position = 이 있는데
# 그 아래 4줄 안에 x.reset_physics_interpolation()이 없으면 [WARN].
# Control(UI) 노드는 보간 대상이 아니라 오탐일 수 있다 · 보고만 하고 사람이 판별한다.
import glob
import io
import os
import re
import sys


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    warns = 0
    add_re = re.compile(r'(?:^|\s|\.)add_child\((\w+)\)')
    for f in sorted(glob.glob("scripts/*.gd") + glob.glob("tools/*.gd")):
        lines = io.open(f, encoding="utf-8").read().splitlines()
        for i, ln in enumerate(lines):
            m = add_re.search(ln)
            if not m:
                continue
            ident = m.group(1)
            gp_re = re.compile(r'\b%s\.global_position\s*=' % re.escape(ident))
            for j in range(i + 1, min(i + 7, len(lines))):
                if gp_re.search(lines[j]):
                    window = "\n".join(lines[j:j + 5])
                    if ("%s.reset_physics_interpolation" % ident) not in window:
                        print("[WARN] 스폰 보간 %s:%d  add_child(%s) 후 global_position 대입, reset 없음"
                              % (f, j + 1, ident))
                        warns += 1
                    break
    print("[SPAWN-LINT] warns=%d" % warns)
    return 0


if __name__ == "__main__":
    sys.exit(main())
