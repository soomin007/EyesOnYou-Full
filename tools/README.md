# QA 도구 모음

코드를 고치면 해당하는 탐지기를 돌린다. 전부 프로젝트 루트 기준.

## 자동 탐지기 (헤드리스 · 종료 코드 연동)

| 도구 | 실행 | 잡는 것 |
|---|---|---|
| InvariantSweep | `godot --headless --path . tools/invariant_sweep.tscn` | 런 상태 불변식 11항목: 전 스테이지 사망 불변식(막 시작·기록 절단·풀 보존·hp 복원) · 14-1 제자리 예외 · 처리 4종 그리디 완주 풀 하한 · 실효 최대 HP ≥ 2 · 런 직렬화 왕복 · 오버레이 pause/time_scale 복원 |
| TrapSweep | `godot --headless --path . tools/trap_sweep.tscn` | 전 라우트·전 방 포탑 사선 vs 플랫폼 기하(탄이 발판에 먹혀 죽는 배치) |
| BootSweep | `godot --headless --path . tools/boot_sweep.tscn` | 전 라우트 × 전 방(61맵) 실제 Stage 인스턴스화 · 맵 구성 붕괴/스폰 크래시/플레이어 미생성 감시 |
| RuleSmoke | `godot --headless --path . --audio-driver Dummy tools/rule_smoke.tscn` | 실플레이 규칙 3종 실인스턴스 단언: 저격 조준 고정(비키면 빗나감·제자리 명중·사거리 600·거치대 하향 사각) · 도전방(피격 -5s·비상등·시간 초과 = 조명 복구+방 계속+프리미엄 없음) · 방류구(판정 = 플랜지 입구부터·하우징 z) |
| text_lint | `python tools/text_lint.py` | em dash(U+2014) 재유입(ERROR) · en dash(WARN) · .gd 문자열 내 노출 금지 조어(격벽·실체화·사선·벽감·차폐) |
| spawn_lint | `python tools/spawn_lint.py` | add_child 후 global_position 대입에 reset_physics_interpolation 누락(원점 잔상 함정) |

## 촬영·계측 하니스

| 도구 | 실행 | 용도 |
|---|---|---|
| VerifyShots | `VERIFY_ONLY=id1,id2` 환경 변수 + `godot --path . --audio-driver Dummy tools/verify_shots.tscn` | 갤러리용 스크린샷·프레임 연사(창모드 · 오디오 무음) |
| BotRunner | `scenes/bot_runner.tscn` (헤드리스 가능) | 빌드×맵 자동 주파 계측([BOT] 지표) |
| BossTimeBench | `godot --headless --path . tools/boss_time_bench.tscn` | SENTINEL 격파 시간 하한(전 시간 명중 지속 화력 모델 · 빌드 4변형) |
| ChainShotter | `scenes/chain_shotter.tscn` | 방 체인 배경 촬영 |

## 편집 시점 감지 (자동)

- `tools/hooks/dialogue_watch.py` (PostToolUse 훅): .gd 한국어 문자열 → 무맥락 대사 검수 상기 ·
  모든 편집의 em dash 재유입 경고 · .gd 문자열 금지 조어 경고.

## 규칙

- 새 하니스/스모크 씬은 `_ready` 첫 줄에서 `GameState.persist_blocked = true` 의무
  (실사용자 세이브 오염 방지 · known_issues 2026-08-24).
- 헤드리스에서 시간 대기는 `create_timer`(게임 시간)로, 프레임 수 루프는 초기화 대기에만
  (known_issues 2026-08-25).
- 새 상태 규칙(불변식)이 생기면 InvariantSweep에 단언을 추가한다.
