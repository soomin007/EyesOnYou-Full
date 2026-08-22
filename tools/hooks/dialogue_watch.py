# -*- coding: utf-8 -*-
# 대사 변경 감지 훅(PostToolUse · Edit/Write) — .gd 파일 편집에 한국어 "문자열"(주석 제외)이
# 포함되면, 커밋 전 무맥락 대사 검수(서브에이전트) 루틴을 상기시키는 컨텍스트를 주입한다.
# 배경: 대사 품질 지적이 반복(2026-08-22 "근본적인 방법으로 처리해줘") — 규칙 문서는 세션
# 시작에만 읽혀 작성 시점에 재소환되지 않는 것이 원인. 이 훅이 작성 시점의 트립와이어다.
import json
import re
import sys


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    tool_input = payload.get("tool_input") or {}
    path = str(tool_input.get("file_path", ""))
    if not path.endswith(".gd"):
        return
    text = str(tool_input.get("new_string", "")) + "\n" + str(tool_input.get("content", ""))
    hangul_in_quotes = re.compile(r'"[^"\n]*[가-힣][^"\n]*"')
    hit = False
    for line in text.splitlines():
        stripped = line.lstrip()
        if stripped.startswith("#"):
            continue  # 주석만 있는 줄은 노출 문자열이 아니다
        if hangul_in_quotes.search(line):
            hit = True
            break
    if not hit:
        return
    reminder = (
        "[대사 검수 루틴] 이 편집에 한국어 문자열이 들어 있습니다. 플레이어에게 노출되는 "
        "대사·문구라면, 커밋 전에 반드시 무맥락 대사 검수를 실행하십시오: 서브에이전트(Task)에 "
        "① 신규/수정된 줄 전체 ② 각 줄이 나오는 화면에 실제로 그려진 것 목록 ③ 화자·상황 "
        "한 줄 설명만 주고, CLAUDE.md '대사 검수 루틴'의 체크리스트로 각 줄 PASS/FAIL 판정을 "
        "받아야 합니다. FAIL은 고치고 재검. UI 라벨·디버그 문자열 등 대사가 아니면 무시해도 "
        "됩니다."
    )
    # ensure_ascii=True — Windows 파이썬 stdout이 cp949라 한글 원문 출력이 깨진다(실측).
    # JSON \uXXXX 이스케이프는 소비 측에서 항상 올바르게 복원된다.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": reminder,
        },
        "suppressOutput": True,
    }, ensure_ascii=True))


if __name__ == "__main__":
    main()
