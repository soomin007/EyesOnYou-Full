# 문서 최신화·정리 작업 지시서 (별도 세션용)

> 이 문서는 **더 싼 모델(Sonnet 권장)로 도는 별도 세션**을 위한 작업 지시서다(사용자 2026-08-13).
> 판단 기준을 여기 고정해 두었으니, 실행 세션은 기준대로 기계적으로 수행하고
> 애매한 것은 **고치지 말고 "판단 보류 목록"으로 보고**한다.

## 절대 규칙

1. **삭제 금지.** 역할이 끝난 문서는 `docs/archive/`로 `git mv`만 한다(이력 보존).
2. **코드가 진실.** 문서와 코드가 다르면 문서를 코드에 맞춘다. 코드는 절대 만지지 않는다.
3. 내용 판단이 필요한 수정(설계 서술 고쳐쓰기)은 하지 않는다 · 상태 표기(✅/레거시 라벨),
   깨진 링크, 스테일 수치·경로만 고친다.
4. em dash(U+2014) 새로 쓰지 않는다. 기존 것은 건드리지 않는다(일괄 치환 금지 · diff 오염).
5. 커밋은 문서 단위로 작게, 한국어 `docs(cleanup): ...` 형식. **push 하지 않는다.**
6. 이동 시 그 문서를 가리키는 링크를 전부 grep해서 경로를 갱신한다(`docs/design/`, `docs/`, README).

## 살아있는 단일 소스 · 이동 금지, 스테일 표기만 갱신

`backlog.md`(다음 작업) · `known_issues.md`(함정) · `dialogue_review.md`(대사 검토) ·
`replay_support_plan.md` · `lore_expansion.md` · `rival_veil_concept.md` · `act_identity.md` ·
`STORY.md`(정사) · `SPEC.md` · README/INDEX류 · `doc_cleanup_workorder.md`(이 문서)

## 아카이브 후보 · 아래 조건이 확인되면 이동, 아니면 보류 목록으로

각 문서 머리의 상태 표기와 `backlog.md` 완료 이력을 대조해 "반영 완료/역할 종료"가 명시적으로
확인되는 경우에만 이동한다:
- `demo_feedback_2026-06-26.md` (Tier1·2 완료 표기 확인)
- `playtest_round2.md` / `veil_pool_remap.md` / `veil_trust_arc.md` (코드 이식 완료 여부)
- `growth_system.md` / `difficulty_analysis.md` / `mobile_feasibility.md` (현행 시스템과 대조)
- `puzzle_ideas.md` / `sfx_trim_guide.md` / `show_dont_tell.md` (참조하는 곳이 남았는지 grep)
- `veil_replay_dialogue.md` (다회차 대사가 replay_support_plan·코드로 이식됐는지)
- `act4_bgm_plan.md` / `elite_enemies_plan.md` / `expansion_plan.md` (구현 완료분 · 완료면 이동,
  미완 항목이 남았으면 그 항목을 backlog에 있는지 확인 후 이동, 없으면 보류)

## 스테일 동기화 대상 (수치·표만)

- `STORY.md` Part II(게임 텍스트 인벤토리)와 §2 표: "코드가 진실" 원칙대로 레거시 라벨이
  붙어 있는지 확인만 하고, 없으면 라벨 추가(내용 재작성 금지).
- README/INDEX: 최근 시스템(기록 재진입·처리별 탈출 4종·관측 프레임·14장 보스전) 한 줄씩 반영,
  스킬 표·기믹 표가 `SkillTreeData.gd`·`MapData.gd`와 어긋난 항목만 수정.
- `SPEC.md`: run.cfg/settings.cfg 필드 요약이 `GameState.gd` `_store_run_state`/`save_settings`와
  일치하는지 대조(rival/ 섹션·palimpsest.cfg 추가분 반영).

## 산출물

1. 커밋들(문서 단위).
2. `docs/design/doc_cleanup_report.md`: 이동한 것 / 고친 것 / **판단 보류 목록**(이유 포함).
   보류 목록은 다음 본 세션에서 상위 모델이 처리한다.
