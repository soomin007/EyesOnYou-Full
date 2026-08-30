# Eyes on You 대사집 · INDEX

> 전 유저 노출 대사의 수집본(2026-08-15, `docs/design/dialogue_collection_workorder.md` 기준).
> **코드가 진실** · 이 폴더는 i18n(TranslationServer CSV) 외부화의 전 단계 수집본이다.
> 코드에서 대사를 바꾸면 해당 대사집 파일도 **같은 커밋에서** 갱신한다.
> KO는 코드 문자열 원문 그대로(수정 금지), EN 열은 번역 세션에서 채운다.
> 앵커는 `파일.gd` 함수/상수명 기준(라인 번호 금지). 어투 규약·수정 이력은
> `../design/dialogue_review.md`(축이 다름: review=규약/이력, collection=원문 전량).

## 1. 파일 지도

| 파일 | 내용 | 규모 |
|---|---|---|
| [veil_ingame.md](veil_ingame.md) | 스테이지 내 VEIL 자막: 드론 첫 반응 · 시야 역전 · 붕괴/재밍 경고 · 문/레버/해치 · 특별 개체(황금·엘리트·방패) · 평화주의 · 막3 SENTINEL 보스전 · VeilSight 콜아웃/방향어 · 부록: 환경 라벨 22종(단일 수록처) | ~92 |
| [rival.md](rival.md) | 라이벌(?) 전체: 14-1 P1/P2/P3 · 가짜 클리어 · SENTINEL reveal · 유인(LURE) · 막4 문턱 처리 회상 · 다회차/재진입 반응 · 14-1 내 VEIL 억압 자막 | ~28 |
| [briefing_routes.md](briefing_routes.md) | 오프닝(INTRO_SYSTEM/VEIL·REPLAY 변형) · 재진입 SYS/VEIL · 막 진입 문턱 멘트(ACT_ENTRY_BY_BAND) · 본편 브리핑 15×밴드 3 · 스토리 브리핑 · RouteData 맵 36종(name/description/veil_comment/entry_comment) · REC_REASON · 루트맵 문구 · MapData route_lines | ~306 |
| [endings.md](endings.md) | 처리 선택 4지선다 · 엔딩 9종 제목/본문 · 에필로그 9종 · 크레딧 · 관측 로그 스팅어 | ~46 |
| [story_docs.md](story_docs.md) | 인트로 의뢰 문서(INTRO_CONTRACT) · 회수 리드아웃/VEIL 고백 · ??? 방 전량 · ARCTURUS 아카이브 · server_hall 서버 로그 · 14-2 터널 · 재진입 오버레이 | ~134 |
| [ui.md](ui.md) | 타이틀 · 패치 노트 · 설정 전 탭 · 사망 화면+사망 브리핑 풀 · 레벨업(+오버플로) · 스킬 트리 · 도감 · 튜토리얼 · HUD/도전방 · 터치/가로 유도 · 효과음 자막 · 막 이름(ACTS) | ~280 |

## 2. 화자 요약

| 화자 | 표기 | 문법 |
|---|---|---|
| VEIL(내 조력자) | 시안 | 신뢰 밴드 3어투: cold=격식 작전통신 · thaw=중간 · warm=따뜻한 절제. 전투 콜아웃은 보고체 단문 |
| ? (라이벌 VEIL) | 바이올렛 | 결이 어긋난 정중함(말투 A). 화자명은 항상 "?" |
| SYS / 시스템 | 회백 | 통보체 명사 종결. UI 라벨·경고 |
| 문서 | 지문 | 의뢰 문서·회수 문서·서버 로그 등 디제시스 텍스트 |
| 환경 | 배경 | 구역명 표지판·그래피티(veil_ingame.md 부록) |

## 3. 단일 수록 규칙(중복 금지)

한 문자열은 한 파일에만 원문을 두고, 다른 파일은 포인터만 남긴다. 조정 이력:
- 막 진입 문턱 멘트(ACT_ENTRY_BY_BAND) = **briefing_routes.md §3** (Briefing 화면 출력이므로)
- 재진입 SYS/VEIL 2줄(Briefing._build_lines) = **briefing_routes.md §2** (? 라인만 rival.md)
- 막 이름(GameState.ACTS) = **ui.md**
- 환경 로어 라벨 22종(_add_lore_label 15 + 파라미터형 6 + DefenseCore 코어) = **veil_ingame.md 부록**
- MapData route_lines의 rival 발화 = **briefing_routes.md** (route_lines 전량과 함께)

## 4. 제외 목록(번역 대상 아님)

- 디버그·개발 도구 전용: `PlaygroundOverlay.gd`(연습장) · `DebugOverlay.gd` · `Screenshotter.gd` ·
  `IgShotter.gd` · `Poster*.gd` · `ThumbCanvas.gd` · Settings 디버그 탭 · Title 디버그 해제 토스트 ·
  CoreTunnel 프로토 종료 패널(연습장 전용 5건)
- 코드 내부 문자열: 주석 · print/push_warning/push_error · 그룹명 · 액션명 · 리소스 경로 ·
  글리치 문자셋(GLITCH_CHARS) · `SfxPlayer.gd`(sfx id뿐, 유저 노출 없음)
- 영문 고정 연출 표기("WAVE 1" 등 MapData 배너)는 미수록. 단 유저 노출 영문 디제시스 라벨
  (ONLINE/ACCESS DENIED, MISSION COMPLETE 등)은 번역 불요 후보로 표기하고 수록

## 5. 수록 대조표 (누락 추적)

스윕 기준: `scripts/*.gd`에서 주석 제외, 큰따옴표 문자열 안에 한글이 있는 **라인 수**
(`awk`, 2026-08-15). 수록 수는 **문자열 단위**라 1:1 대응이 아니다(한 라인에 여러 문자열,
여러 라인이 한 문서). 큰 차이가 나는 파일만 추적하면 된다.

| 소스 | 스윕 라인 | 수록처(수록 수) · 비고 |
|---|---|---|
| Stage.gd | 206 | veil_ingame(29+부록 21) · rival(19) · story_docs(109) · ui(19) |
| RouteData.gd | 198 | briefing_routes(163) · 여러 라인 문자열로 스윕>수록 |
| VeilDialogue.gd | 123 | briefing_routes(107) · story_docs(10) · ui(사망 30+레벨업 12) |
| Settings.gd | 103 | ui(58) · 디버그 탭 제외분 큼 |
| MapData.gd | 96 | briefing_routes(route_lines 9) · 나머지는 배너 영문/내부 키 |
| EndingResolver.gd | 70 | endings(24항목·본문 67줄) |
| GameInfo.gd | 47 | ui(46) |
| Tutorial.gd | 37 | ui(25) |
| SkillTreeData.gd | 33 | ui(26) |
| Title.gd | 32 | ui(26) · 디버그 토스트 제외 |
| Accessibility.gd | 32 | ui(32, 효과음 자막 맵) |
| RouteMap.gd | 26 | briefing_routes(25) · rival(유인 4) |
| Credits.gd | 21 | endings(7항목) |
| VeilSight.gd | 18 | veil_ingame(16) |
| GameState.gd | 17 | ui(8) · 나머지 내부 라벨 |
| BestiaryData.gd | 14 | ui(7항목) |
| ReentryOverlay.gd | 13 | story_docs(13) |
| LevelUpOverlay.gd | 11 | ui(9) |
| Briefing.gd | 10 | briefing_routes(2) · rival(6) · ui(힌트 2) |
| Ending.gd | 9 | endings(9항목) |
| 기타(Enemy 6 · DisposalChoiceOverlay 6 · CoreTunnel 6 · Death 4 · FalseVeil 4 등) | ~50 | 각 담당 파일 수록, FalseVeil은 유저 노출 문자열 없음 |
| 디버그·도구(PlaygroundOverlay 39 · PosterCanvas 26+18 · IgShotter 6 · DebugOverlay 1 · SfxPlayer 17) | 107 | 전량 제외(§4) |

총계: 스윕 1,274라인 중 디버그·도구 107 제외, 유저 노출 수집 약 864 문자열.

## 6. 남은 확인(다음 세션)

- `(분류 확인 필요)` 표시 항목: ArcturusDocumentOverlay 닫기 안내(story_docs, ui 후보) 등 ·
  grep `분류 확인 필요`로 일람.
- 환경 라벨·영문 디제시스 라벨의 번역 대상 여부는 번역 세션에서 결정.
- ui.md 패치 노트 2026-08-12 항목 "쓰러져도 진행한 단계부터 다시 시작해요"는 오늘(08-15)
  보스전 사망 P1 리셋 확정과 어긋남 · 코드(GameInfo.gd) 갱신과 함께 수정할 것.
