# -*- coding: utf-8 -*-
# 문구 린트 · 전수 스캔(2026-08-25 신설). 프로젝트 루트에서: python tools/text_lint.py
# 검사 항목:
#   [ERROR] em dash(U+2014) · 어디에도 금지(전역 규칙: 코드·주석·문서·세션 로그 전부).
#   [WARN]  en dash(U+2013) · 규칙 대상은 아니나 em dash와 같은 용도로 새어들기 쉬워 보고.
#   [WARN]  .gd 문자열 리터럴 안의 노출 금지 설계 조어(메모리 player-facing-plain-words).
# 종료 코드: ERROR 있으면 1, 아니면 0. 편집 시점 감지는 tools/hooks/dialogue_watch.py가 맡고,
# 이 도구는 커밋 전/정기 QA의 전수 검사용.
import glob
import io
import os
import sys

BANNED_JARGON = ["격벽", "실체화", "사선", "벽감", "차폐"]

GD_GLOBS = ["scripts/*.gd", "tools/*.gd"]
MD_GLOBS = ["*.md", "docs/**/*.md", "session_logs/*.md"]
PY_GLOBS = ["tools/**/*.py"]


def string_spans(line: str):
    # .gd 한 줄에서 문자열 리터럴 구간만 추출(단순 파서: "..." / '...', 주석 뒤 무시).
    spans = []
    q = None
    start = 0
    for i, ch in enumerate(line):
        if q:
            if ch == q:
                spans.append(line[start:i])
                q = None
        else:
            if ch in ('"', "'"):
                q = ch
                start = i + 1
            elif ch == "#":
                break
    return spans


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    os.chdir(root)
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    errors = 0
    warns = 0
    files = []
    for g in GD_GLOBS + MD_GLOBS + PY_GLOBS:
        files.extend(glob.glob(g, recursive=True))
    for f in sorted(set(files)):
        try:
            lines = io.open(f, encoding="utf-8").read().splitlines()
        except Exception as e:
            print("[WARN] read fail %s: %s" % (f, e))
            warns += 1
            continue
        for num, ln in enumerate(lines, 1):
            if "—" in ln:
                # 자기 참조 예외: 이 린트/훅이 검사 대상 문자를 코드로 다루는 줄.
                if f.replace("\\", "/").endswith(("tools/text_lint.py", "tools/hooks/dialogue_watch.py")):
                    continue
                print("[ERROR] em dash %s:%d" % (f, num))
                errors += 1
            if "–" in ln:
                print("[WARN] en dash %s:%d" % (f, num))
                warns += 1
            if f.endswith(".gd"):
                for s in string_spans(ln):
                    for w in BANNED_JARGON:
                        if w in s:
                            print("[WARN] 조어 '%s' %s:%d : %s" % (w, f, num, s[:60]))
                            warns += 1
    print("[LINT] errors=%d warns=%d" % (errors, warns))
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
