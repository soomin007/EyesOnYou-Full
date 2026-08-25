# 대사집 통합 작업 지시서 (2026-08-15 사용자 지시 · 착수 대기)

> 지시 원문 요지: 어차피 영어판을 만들 거니 **한국어 원문을 대사집에 함께 저장**하고,
> 여러 파일에 퍼진 대사를 **한 폴더로 모아 분류 + 인덱스 파일**로 빠르게 오갈 수 있게 할 것.

## 1. 목표와 원칙

- 산출물: `docs/dialogue/` 폴더 + `docs/dialogue/INDEX.md`(인덱스 = 카테고리 → 파일 → 섹션).
- 각 항목 포맷(표 또는 리스트):
  - **원문(한국어)** 전문 · 화자 · 맥락(언제 나오는가) · **코드 위치**(`파일.gd 함수명` 기준,
    라인 번호는 스테일해지므로 함수/상수명 앵커 우선) · EN 열(비워둠 · 번역 세션에서 채움).
- 진실 관계: **코드가 진실**, 대사집은 i18n 외부화(TranslationServer CSV, backlog 기존 항목)의
  전 단계 수집본. CSV 외부화가 끝나면 CSV가 진실이 되고 대사집은 원문 아카이브로 남는다.
  대사를 코드에서 수정하면 대사집도 같이 갱신(커밋 체크리스트에 포함).
- `dialogue_review.md`(어투 규약·수정 이력)는 그대로 두고, 대사집은 **전문 수록**이 역할.
  중복이 아니라 축이 다름: review=규약/이력, collection=원문 전량.

## 2. 파일 분류(안)

- `INDEX.md` · 전체 지도 + 화자 색/문법 요약(시안 VEIL·바이올렛 ?·시스템).
- `veil_ingame.md` · 스테이지 내 VEIL 자막(진입/함정/저격/재밍/붕괴/특별 개체/평화주의 등).
- `rival.md` · 라이벌(?) 전체: 14-1 페이즈·가짜 클리어·유인(LURE)·막4 문턱·다회차 변형.
- `briefing_routes.md` · 브리핑(밴드 3종×15) + RouteData veil_comment/entry_comment 전량 +
  루트맵 추천 사유(REC_REASON).
- `endings.md` · 엔딩 9종 본문 + 에필로그 + 크레딧 스팅어.
- `story_docs.md` · 인트로 의뢰 문서(INTRO_CONTRACT), 회수 문서, ??? 방, 14-2 터널 비트.
- `ui.md` · 타이틀/설정/사망/레벨업/도전방/튜토리얼/스킬 설명/도감(BestiaryData).
- 디버그 전용 문구(연습장 패널 등)는 제외(번역 대상 아님) · INDEX에 제외 목록만 명시.

## 3. 수집 방법

1. 인벤토리 스윕: `rg -n "[가-힣]" scripts/*.gd` 로 한글 포함 라인 전수 → 유저 노출 문자열만
   선별(주석 제외). 알려진 소스: Stage(최다)·VeilDialogue·RouteData·MapData(route_lines)·
   EndingResolver·Enemy·Briefing·CoreTunnel·Credits·Death·Title·Tutorial·DisposalChoiceOverlay·
   ReentryOverlay·ArcturusDocumentOverlay·BestiaryData·SkillTreeData·LevelUpOverlay·RouteMap·
   Settings·MissionObjective·GameInfo.
2. 분류 기입은 서브에이전트 분담 가능(파일별). 단 선별 기준(유저 노출 여부)은 예시로 명확히.
3. 완료 검증: 스윕 라인 수 vs 대사집 수록 수 대조표를 INDEX 말미에 남긴다(누락 추적).

## 4. 함께 처리(내일 구현 목록)

- **14-1 보스전 사망 = P1 리셋**(사용자 확정 2026-08-15): 페이즈 체크포인트 폐지 방향.
  앵커: `Death.gd _restart_stage()`(SPACE 재시도 → STAGE 전환)에서
  `current_route_id == "route_core_recovery"`면 `rival_phase_reached = 0`.
  주의: `_init_rival_boss`의 체크포인트 분기(rival_phase_reached>=1)와 연습장 페이즈 직행
  버튼(`PlaygroundOverlay._on_ch14_phase`)은 유지 · 리셋은 사망 경로에서만.
- **난이도·사망 페널티 재검토(설계 논의)**: "죽어도 불이익 없음 + 획득 XP 유지 = 과친절"
  문제 제기. 후보: 스테이지 사망 시 해당 스테이지 획득 XP 일부 상실 / 사망 횟수에 따른
  보상 감소 / 현행 유지 + 보스전만 리셋. 엔딩 stats·실력 추적(recent_stage_deaths)과의
  상호작용 확인 필요. 사용자와 방향 합의 후 구현.
- **P2→P3 전환 재보고 확인 대기**: 에디터 재시작 후 재현 여부. 재현 시 수집 정보 =
  진입 버튼 종류·마지막 노드 격파 직후 화면·무적/강제 엘리트 상태(세션 로그 08-14 세션 8).
- **최종보스전 리워크**(`final_boss_rework.md`) 열린 결정 3건 확정 대기.
