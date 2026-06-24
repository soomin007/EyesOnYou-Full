# 환경 퍼즐 — 현재 상태

레버·발판 시스템과 비밀칸/이스터에그 진입 메커니즘 정리. 코드의 단일 진실은
`scripts/LeverInteractable.gd` / `scripts/PressurePlate.gd` / `scripts/Stage.gd`.
이 문서는 어떤 맵에 무엇이 깔려 있는지 빠르게 훑기 위한 인덱스.

## 1. 공통 메커니즘

### LeverInteractable (`scripts/LeverInteractable.gd`)
- Area2D 기반. 플레이어 overlap 시 `Player.nearby_lever`에 자기 자신 세팅.
- `attack` 키 입력을 가로채 사격 대신 `try_pull()` 호출. 한 번 당기면 `locked=true`.
- `pulled(lever_id)` 시그널 emit → Stage가 받아 효과 trigger.
- 시각: 회색 받침 + 손잡이(idle 위, active 아래로 회전) + 점멸 hint glow(청색).

### PressurePlate (`scripts/PressurePlate.gd`)
- Area2D. 플레이어 body_entered 시 `stepped(plate_id)` emit.
- `require_armed=true`면 `arm()` 호출 전까지는 step 무시 — 레버를 먼저 당겨야
  활성되는 두 단계 흐름에 사용.
- `one_shot=true`(기본)면 한 번 step 후 잠김.
- 시각: 짙은 금속판 + hint 띠. armed 전엔 회색, armed 후엔 청색 점멸.

### 토글 가시 (`Stage._spawn_toggleable_spike` / `_set_spike_group_active`)
- 일반 `_build_spike`가 self에 add_child하는 시각/Area2D를 wrapper Node2D로 reparent.
- `_set_spike_group_active(group, false)`로 modulate dim + collision disabled 일괄 처리.

## 2. 맵별 배치 현황

### route_back_alley — 비밀칸 (튜토리얼)
- 레버: (1300, 588) — 지면 중반.
- 효과: 천장 해치 (2300, 290) fade out + 강하 발판 (2150, 380) 이동.
- 보상: XP orb 5개 (해치 안쪽).

### route_rooftops — 비밀칸 (튜토리얼 강화)
- 레버: (200, 3060) — 시작 좌측 외벽.
- 효과: 환기구 (200, 2820) fade + 사다리 발판 2개 강하.
- 보상: HP 회복 1 + XP 2.

### route_ward — ARCTURUS 아카이브 진입
- 레버: (2900, 388) — 맵 끝 상층 플랫폼.
- 발판: (2000, 596) `require_armed=true` — 잠긴 문 앞.
- 흐름: 잠긴 문 본 후 진행 → 끝까지 가서 레버 발견 → 당김 → 발판 청색 활성
  → 되돌아와서 발판 step → ARCTURUS 시퀀스 (`ArcturusDocumentOverlay`).
- VEIL: "그쪽은 임무 범위 밖이에요. / 그 문, 도면에는 없어요." (첫 접근 1회만).
- VEIL after 레버: "뭔가 풀렸어요. 잠긴 문 앞 발판 위로."

### route_datacenter — 가시 비활성화
- 레버: (1200, 320) — 상층 우측 플랫폼.
- 토글 가시: 지면 (550, 814) w=120, (1500, 814) w=120 — 두 구간.
- 효과: 양 구간 동시 dim + 콜리전 off.
- VEIL after: "전기가 끊겼어요. 발 밑 가시 무력화."

### route_blackout — 도전방 입구 연출 + 도전 본체
- 입구 발판: (170, 595) `one_shot=true`.
- 게이트: x=240 StaticBody (50×720). 폴리스 라인 + "출입 통제" 라벨.
- 차폐막: x=265~stage_end world-space 큰 dark 패널 (z=9, "DARK ZONE / 분류 미상" 라벨).
  발판 step 전에는 도전방 내부(플랫폼/적/가시)가 시각적으로 완전히 가려짐.
- 활성화 흐름 (`_start_challenge_run`):
  1. 게이트 visual fade + 차폐막 fade (0.5s + 0.9s).
  2. 사이렌 빨강 플래시 2회.
  3. challenge_dark_layer fade-in (CanvasLayer 안 Control wrapper로 트윈).
  4. 타이머 HUD + "BLACKOUT RUN / N초 안에 골 도달 / 한 대만 맞아도 실패" 배너.
- 도전 가시: y=594 (지면 윗면). x=480/950/1500/2050 발판 갭에 정렬.

## 3. 입력 모델

- 레버: `attack` 키 재사용. Area2D 안에서는 `Player._try_attack`이 사격을 흡수,
  대신 `nearby_lever.try_pull()` 호출. 따로 interact 키 추가 안 함.
- 발판: 입력 없음. body_entered 자동 step.

## 4. 시각 톤 — 색 규약

- 비밀칸 hint glow: ARCTURUS 청색 `Color(0.55, 0.85, 0.95)` (back_alley/rooftops/
  ward/datacenter 공통).
- 도전방 hint: 주황 경고 톤 `Color(0.95, 0.55, 0.30)` (blackout 입구 발판) — 안전한
  비밀칸과 시각적 차별화.

## 5. 미해결 / 다음 검토 후보

- 도전방 입구 발판 hint glow가 폴리스 라인·차폐막 색에 묻혀 안 보일 수 있음 →
  사용자 테스트 후 hint 강도 조정.
- ARCTURUS 진입 후 발판/레버 잠금 상태 — 현재 PressurePlate는 one_shot이라 한 번
  밟히면 잠김. 같은 stage 내 재진입은 의도적으로 막힘.
- back_alley/rooftops 비밀칸은 stage 0~1 한정 — 외곽 맵 풀에서 그 맵이 안 뜨면
  플레이어가 레버 시스템을 학습하지 못한 채 후반 맵에 도착. 풀 가중치 조정 검토 가능.
