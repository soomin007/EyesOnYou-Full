# -*- coding: utf-8 -*-
# 대사·문구 감지 훅(PostToolUse · Edit/Write).
# ① .gd 편집에 한국어 "문자열"(주석 제외)이 포함되면 무맥락 대사 검수 루틴을 상기시킨다.
#    배경: 대사 품질 지적 반복(2026-08-22 "근본적인 방법으로 처리해줘") · 규칙 문서는 세션
#    시작에만 읽혀 작성 시점에 재소환되지 않는 것이 원인. 이 훅이 작성 시점의 트립와이어다.
# ② 어떤 파일이든 편집에 em dash(U+2014)가 들어오면 전역 규칙 위반을 즉시 경고한다
#    (2026-08-25 전수 스윕 4500여 건 · 재유입 차단). 전수 스캔은 tools/text_lint.py.
# ③ .gd 문자열에 노출 금지 설계 조어가 들어오면 경고한다(메모리 player-facing-plain-words).
import json
import re
import sys

BANNED_JARGON = ["격벽", "실체화", "사선", "벽감", "차폐"]


def main() -> None:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return
    tool_input = payload.get("tool_input") or {}
    path = str(tool_input.get("file_path", ""))
    text = str(tool_input.get("new_string", "")) + "\n" + str(tool_input.get("content", ""))
    msgs = []
    if "—" in text:
        msgs.append(
            "[문구 린트] 이 편집에 em dash(U+2014)가 들어 있습니다. 전역 규칙 위반입니다. "
            "'·', 쉼표, 마침표, 콜론으로 잇고 연도 범위는 '~'로 바꾸십시오. "
            "전수 검사는 tools/text_lint.py."
        )
    if path.endswith(".gd"):
        hangul_in_quotes = re.compile(r'"[^"\n]*[가-힣][^"\n]*"')
        hit = False
        jargon_hits = []
        for line in text.splitlines():
            stripped = line.lstrip()
            if stripped.startswith("#"):
                continue  # 주석만 있는 줄은 노출 문자열이 아니다
            m = hangul_in_quotes.search(line)
            if m:
                hit = True
                for w in BANNED_JARGON:
                    if w in m.group(0) and w not in jargon_hits:
                        jargon_hits.append(w)
        if hit:
            msgs.append(
                "[대사 검수 루틴] 이 편집에 한국어 문자열이 들어 있습니다. 플레이어에게 노출되는 "
                "대사·문구라면, 커밋 전에 반드시 무맥락 대사 검수를 실행하십시오: 서브에이전트(Task)에 "
                "① 신규/수정된 줄 전체 ② 각 줄이 나오는 화면에 실제로 그려진 것 목록 ③ 화자·상황 "
                "한 줄 설명만 주고, CLAUDE.md '대사 검수 루틴'의 체크리스트로 각 줄 PASS/FAIL 판정을 "
                "받아야 합니다. FAIL은 고치고 재검. UI 라벨·디버그 문자열 등 대사가 아니면 무시해도 "
                "됩니다."
            )
        if jargon_hits:
            msgs.append(
                "[노출 조어 경고] 이 편집의 한국어 문자열에 금지 설계 조어가 보입니다: "
                + ", ".join(jargon_hits)
                + ". 화면에 보이는 것을 일상어로 바꾸십시오(메모리 player-facing-plain-words). "
                "주석·비노출 문자열이면 무시해도 됩니다."
            )
    if not msgs:
        return
    # ensure_ascii=True · Windows 파이썬 stdout이 cp949라 한글 원문 출력이 깨진다(실측).
    # JSON \uXXXX 이스케이프는 소비 측에서 항상 올바르게 복원된다.
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": "\n\n".join(msgs),
        },
        "suppressOutput": True,
    }, ensure_ascii=True))


if __name__ == "__main__":
    main()
