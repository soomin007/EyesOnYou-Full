# Eyes on You — 문서 인덱스

외부 협업자/Claude 인계용 한 페이지 안내. **모든 문서의 단일 진입점이자, 무엇이 어디서 단일 진실인지의 지도.**
내용이 겹칠 땐 아래 "단일 소스 지도"의 담당 문서만 고치고, 나머지는 그 문서를 링크한다.

## 단일 소스 지도 (이 주제는 이 문서가 진실)

| 주제 | 단일 소스 |
|---|---|
| 게임 개요·조작·구조 요약(공개용) | [`../README.md`](../README.md) |
| 코드/씬 구조·게임플레이 사양·시스템 수치 | [`SPEC.md`](SPEC.md) |
| 스토리 캐논·인게임 텍스트 전량 | [`STORY.md`](STORY.md) |
| 스킬 트리·스킬-적 상성·글라이드/폭발물 밸런스·XP | [`design/growth_system.md`](design/growth_system.md) |
| 맵 좌표·4템플릿·보스/웨이브·이스터에그·도전방 | [`design/world_layout.md`](design/world_layout.md) |
| VEIL 어투(신뢰 COLD/THAW/WARM)·엔딩 점수 축·취약함 게이트 | [`design/veil_trust_arc.md`](design/veil_trust_arc.md) |
| └ VEIL 밴드×진행 대사 grid(설계 스냅샷) | [`design/veil_pool_remap.md`](design/veil_pool_remap.md) |
| └ 다회차 리플레이 대사 변형(제안·검토) | [`design/veil_replay_dialogue.md`](design/veil_replay_dialogue.md) |
| 톤 원칙 "글로 명시 < 체험으로 체득" | [`design/show_dont_tell.md`](design/show_dont_tell.md) |
| 레버·발판·비밀칸 배치 인덱스 | [`design/puzzle_ideas.md`](design/puzzle_ideas.md) |
| 난이도 정량 분석(누가 얼마나 어려운가) | [`design/difficulty_analysis.md`](design/difficulty_analysis.md) |
| 효과음 전수(id·트리거·prompt·상태) + 후처리 | [`design/sfx_list.md`](design/sfx_list.md) · [`design/sfx_trim_guide.md`](design/sfx_trim_guide.md) |
| 사람 vs AI 기여 분담(크레딧) | [`contributions.md`](contributions.md) |
| 포스터 비주얼 아이덴티티(색·모티프·카피) | [`poster_brief.md`](poster_brief.md) |
| 배포(GitHub Pages 자동) | [`../DEPLOY.md`](../DEPLOY.md) |
| **다음 작업·미착수 (진행상태 단일 소스)** | [`design/backlog.md`](design/backlog.md) |
| 본편 확장 전략(에셋 기반) | [`design/expansion_plan.md`](design/expansion_plan.md) |
| 반복 방지 함정·오류 이력 | [`design/known_issues.md`](design/known_issues.md) |
| 세션별 변경 흐름 | [`../session_logs/`](../session_logs/) (최근 + `SESSION_LOG_ARCHIVE.md`) |
| 운영 규칙(세션 루틴·커밋·로그) | [`../CLAUDE.md`](../CLAUDE.md) |

> **코드가 항상 최종 진실** — 문서의 구체 수치(HP·XP·좌표 등)가 코드와 어긋나면 코드를 따른다.

## 단일 진실의 원칙

- **진행/우선순위 = backlog**, 게임 개요 = README, 구현 디테일·사양 = SPEC. (제품 초기 정의 PRD는 완성 단계라 `archive/`로 보냄 — 비목표 등 의도 기록만 이력 보존.)
- **STORY**: 인게임 텍스트·스토리 캐논의 단일 진실. 코드 대사 풀(VeilDialogue 등)이 어긋나면 STORY를 따른다.
- **growth_system / world_layout**: 스킬·맵 메커닉의 단일 진실. 다른 문서는 요약을 복제하지 말고 이 문서를 링크한다.
- **show_dont_tell**: 텍스트/연출 의사결정의 상위 기준.

## 인계·정리 규칙

- 의뢰서·답변(BRIEF_*/DESIGN_*)·완료된 작업 계획·일회성 분석 스냅샷은 정리 후 [`archive/`](archive/)로 이동(이력 보존, 참조 금지).
- 새 디자인 문서는 `docs/design/<topic>.md`(snake_case). 큰 변경은 commit 단위로 끊고 `session_logs/`에 기록.
- **같은 내용이 두 문서에 생기면** "단일 소스 지도"의 담당 문서로 합치고, 다른 쪽은 한 줄+링크로 바꾼다.
