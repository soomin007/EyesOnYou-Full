# 성장 시스템 설계 — 확정안 + 구현 계획

> 이전 `PROPOSAL_growth_system.md` (초안 제안) + `REPLY_growth_system_v2.md` (사용자 결정) 통합본.
> 본 문서가 단일 진실. 충돌 시 코드보다 본 문서 우선 (구현 진행 중에는 제외).

---

## 1. 결정 요약 (사용자 확정)

| 결정 | 값 |
|---|---|
| 시스템 형태 | **A안 — 티어형 스킬 트리** |
| 스테이지 수 | **5 → 7** |
| 맵 수 | **6 → 11** |
| `XP_PER_LEVEL` | **5 → 8** |
| trust/aggression 임계값 | **3 → 4** |
| 계열 분류 | **전투 / 이동 / 생존** 3계열 × 3티어 |
| trust/aggression 결합 강도 | **약 — VEIL 추천 표시만** (잠금 없음) |
| 튜토리얼 처리 | **튜토리얼 픽은 항상 T1**, 풀도 T1만 |
| `GameState.skills` 자료형 | `Array[String]` → `Dictionary[String, int]` (id → tier) |
| 도감(`seen_enemies`) | 별개 유지 |

**목표**: 7스테이지 × 평균 1.5레벨업 ≈ 10~11레벨업/런. T3 한 계열 특화는 가능, 전체 풀 소진은 불가.

---

## 2. 스킬 트리

### 전투 계열
```
T1 사격 강화         (+1 dmg)
T2 사격 강화+        (+2 dmg, 사격 시 잠깐 가속)
T3 관통              (1체 추가 관통)

T1 삼연사            (3발 부채꼴)
T2 오연사            (5발)
T3 오연사+추적        (5발 + 약한 추적)

T1 폭발물            (주위 적 광역 처치, 3.5s 쿨다운)
T2 폭발물+           (반경 +30%, 쿨다운 3.0s)
T3 이중 충전          (2회 충전)
```
> **폭발물 너프 (2026-06)**: `EXPLOSION_DAMAGE` 3→2, T1 쿨다운 3.0→3.5s, T2/T3 쿨다운 2.5→3.0s.
> 방패병(HP3)을 한 방에 못 죽이게 해 "모든 적 올킬 만능"을 깬다. 단 **방패 무시 광역은 유지** —
> 정면 못 뚫는 방패병에 여전히 유효(2뎀×2 타격), patrol/sniper/drone/bomber는 한 방 유지.
> → **방패병·군집 상성은 보존, 올킬 만능만 제거**. (코드: `Player.gd` `EXPLOSION_DAMAGE`/`SKILL_COOLDOWN`/`get_skill_cd_max`.)

### 이동 계열
```
T1 공중 활강          (낙하 시 자동으로 천천히 떨어짐 — 패시브)
T2 삼단 점프          (공중 점프 1회 추가 — 최대 3단; 2026-06-13 T1에서 분리)
T3 유도 사격          (활강 중 사격이 적을 강하게 유도 + 데미지 +1; 관통은 사격강화 T3 전담)

T1 대시 강화         (쿨다운 -20%)
T2 대시 거리+        (+30%)
T3 대시 후 0.3s 무적
```
> **글라이드 라인 재설계 (2026-06)**: 기존 T1 글라이드/T2 글라이드+/T3 공중사격 패널티 제거(no-op)는
> "T3까지 가야 빛나는 왕귀 구조"가 문제였다. T1부터 회피 기동(좌우 가속·제어)으로 즉시 쓸모 있게 하고,
> T2/T3는 활강 중 사격에 유도를 얹어 **공중 제압 라인(저격수·드론 상성)**으로 재정의.
> (2026-06-15) T3 '관통·추적' → '유도' 전담으로 정리: 관통 키워드가 사격강화 T3와 겹쳐 헷갈렸다.
> 활강 T3는 유도(homing), 사격강화 T3는 관통으로 분리 → 둘 다 보유 시 활강 중 관통+유도 시너지.
> 활강 발동 조건: 공중에서 낙하 중(`velocity.y > 0`) 점프 키 홀드. T2/T3 사격 효과도 이 조건 하에서만.

### 생존 계열
```
T1 HP +1
T2 HP +2 + 피격 후 1s 무적
T3 피격 시 짧은 슬로모

T1 비상 부활          (1회 부활)
T2 부활 회복+         (회복량 1→2)
T3 부활 재충전        (30s 후 재무장)
```

### 진행 규칙
- 같은 라인의 T2는 해당 T1 보유 시에만 후보 등장.
- 같은 라인의 T3는 해당 T2 보유 시에만 후보 등장.
- `roll_choices` 결과는 픽 가능한 후보 ≥ 픽 수면 후보 셔플 후 N개, 부족하면 가능한 만큼만 (기존 `min(count, available.size())` 패턴 유지).

---

## 3. 맵 — 11개 확정

| ID | 이름 | 위치 | ACT | risk | reward | 특징 |
|----|------|------|-----|------|--------|------|
| back_alley | 외곽 진입로 | 시설 외벽 접근 | 1 | 1 | 1 | 기본 루트. 경비 적음 |
| rooftops | 외벽 옥상 | 시설 외부 상단 | 1 | 2 | 2 | 저격 노출. 기동성 요구 |
| sewers | 지하 인입로 | 외부→내부 하수도 | 1 | 2 | 3 | 함정 많음. 보상 큼 |
| subway | 폐쇄 지하철 | 지하 연결로 | 1~2 | 2 | 2 | 좁고 어두움. 근접전 |
| cooling | 냉각 시설 | 내부 기계실 | 2 | 2 | 3 | 드론 첫 등장. 수직 구조 |
| watchtower | 감시탑 | 내부 중층 | 2 | 3 | 3 | 저격수 밀집. 원거리 유리 |
| **ward** | **격리 병동** | **내부 중층** | **2** | **2** | **3** | **좁은 복도. 은폐 유리. ??? 맵 복선¹** |
| datacenter | 데이터 센터 | 핵심부 인접 | 2~3 | 3 | 3 | 드론+저격 혼합. 고난도 |
| escape | 비상 탈출로 | 핵심부 우회 | 3 | 1 | 2 | ACT 3 유일 저위험 루트 |
| lab | 핵심부 | 서버실 직전 | 3 | 3 | 3 | 최고 난도 |
| hidden | ??? | 격리 서버실 | 3 | ? | ? | 특수. 전투 없음. unique |

> ¹ **격리 병동 노출 보장**: VEIL이 통과 중 짧게 멈추고 "...이 구역은 오래됐어요." → ??? 맵 복선. 이 흐름이 자연스러우려면 격리 병동은 Stage 3~4 선택지에 **반드시 포함**되어야 함 (강제 선택 아님, 후보로는 항상 등장).

### RouteData 신규 필드
```gdscript
{
  "min_stage": 0,    # 이 스테이지 이상에서만 등장
  "max_stage": 2,    # 이 스테이지 이하에서만 등장
  "unique": false,   # true면 1회 등장 후 풀 영구 제거 (??? 전용)
}
```

### 스테이지별 후보 풀

| 스테이지 | ACT | 픽 수 | 등장 가능 맵 |
|---------|-----|------|------------|
| Stage 0 | 1 | 2 | 외곽 진입로, 외벽 옥상 |
| Stage 1 | 1 | 2~3 | 외벽 옥상, 지하 인입로, 폐쇄 지하철 |
| Stage 2 | 1→2 | 3 | 지하 인입로, 폐쇄 지하철, 냉각 시설, 감시탑 |
| Stage 3 | 2 | 3 | 냉각 시설, 감시탑, **격리 병동** |
| Stage 4 | 2 | 3 | 감시탑, **격리 병동**, 데이터 센터 |
| Stage 5 | 2→3 | 3 | 데이터 센터, 비상 탈출로, 핵심부, ??? |
| Stage 6 | 3 | 2~3 | 비상 탈출로, 핵심부, ??? (Stage 5 미방문 시) |

**중복 방문 금지**: 한 번 선택한 맵은 `route_history`에 기록되어 이후 풀에서 제외 (전 맵 보편 규칙).
**Pick count 동적**: 후보 < 픽 수일 때 가능한 만큼만 (스킬 풀과 동일한 클램프 패턴).

---

## 4. 레벨업 추천 (※ 옛 trust/aggression 뱃지 설계는 폐기)

> 실제 구현은 trust/aggression이 아니라 **상성/태그 기반**(§4.1, `get_levelup_advice`)으로 ★ 추천을 정한다.
> 아래 옛 설계는 미사용. 2026-06-13부터 추천 앞에 **실력별 lead-in**만 붙는다
> (struggling="이건 꼭." / skilled="필요하면," — `VeilDialogue.levelup_leadin`). trust는 어투 색/밴드에만 관여.

- ~~trust 높음 → 이동/생존 뱃지 / aggression 높음 → 전투 뱃지~~ (폐기 — 상성/태그 추천으로 대체)
- 잠금 없음. 추천 무시 가능.
- aggression 임계값: 엔딩용 4 (엔딩 신뢰축은 2026-06-13부터 추천 수용률 ≥50%).

### 4.1 스킬-적 상성 (2026-06 신규)

trust/aggression 추천과 별개로, **현재 맵의 적 구성**을 보고 약점 스킬을 가르치는 상성 축을 추가.
"이 적엔 이 스킬"을 플레이 안에서 자연 학습시키는 것이 목적.

**상성 표** (`SkillTreeData.MATCHUP`, 위협 우선순위 순):

| 적 타입 | 약점 스킬(line id) | 이유 |
|---------|-------------------|------|
| `shield`(방패병) | `explosive` | 방향 무시 AoE로 정면 방패 관통 |
| `sniper`(저격) | `barrier` | 방어막으로 한 발 막고 사선 통과 (둥지=회피 대상) |
| `drone`(드론) | `glide` | 떠서 폭탄 피하고 활강 관통샷으로 처리 |
| `bomber`(폭격) | `fire_boost` | 붙기 전에 빠른 처치 |

**두 갈래로 작동** (같은 표 공유):
- **B — 레벨업 추천 ★**: 현재 맵에 등장하는 적 중 플레이어가 **아직 카운터 스킬을 안 가진** 최우선
  약점 스킬을 `skill_id` 단위로 강조 (line 단위 추천, 티어 무관).
- **C — 출현 가중**: `SkillSystem.roll_choices`가 그 약점 스킬이 후보 풀에 있으면 셔플 후
  **첫 슬롯으로 끌어와** 픽 등장을 보장 (강제 잠금 아님, 출현 확률만 ↑).

**공통 헬퍼**: `SkillTreeData.matchup_skill_for_route(route_id, player_skills) -> String`
- 현재 맵(`MapData.get_layout`)의 적 타입별 개체 수 = 고정 배치(`enemies`) + ARENA 웨이브(`waves`) 합산.
- `MATCHUP` 우선순위 순으로, 등장 수 > 0 이고 플레이어 미보유인 첫 스킬 id 반환. 없으면 빈 문자열.
- `route_id`가 비었거나 맵 데이터가 없으면 빈 문자열 → 추천/가중 모두 비활성.
- 호출처: 추천 표시(B), `SkillSystem.roll_choices`의 route 가중(C).

---

## 5. XP 곡선

- `XP_PER_LEVEL = 8`
- 적 처치 XP는 현행 유지
- 스테이지 클리어 보너스: reward 그대로 (1=+1, 2=+2, 3=+3)
- **신규**: high-risk(risk=3) 루트에서 적 처치 XP **+50%** 보너스
- 평균 1.5렙업/스테이지 → 7스테이지 합계 10~11렙업
- 레벨 캡 없음. 스테이지 수에 자연 수렴.

---

## 6. 튜토리얼

- 튜토리얼 스킬 풀 = 각 계열 T1 항목만 (전투/이동/생존 T1 1개씩 후보).
- 튜토리얼 픽은 항상 T1 등록.
- 본편 진입 시 T1 1개 보유 상태.
- `Tutorial._finish_tutorial`은 그대로 `GameState.start_main_game()` 사용 (스킬 보존, 레벨/XP 리셋).

---

## 7. 사전 메모 (잊지 말 것)

### 7.1 풀 크기 동적 클램프 — 이미 구현됨
- `SkillSystem.roll_choices`: `for i in min(count, available.size())` (line 31)
- `RouteData.get_route_pool_for_stage`: `var pick_count: int = min(available.size(), 3 if stage_index >= 1 else 2)` (line 90)

→ 새 시스템에서도 같은 패턴 유지. unique=true + 중복 방문 금지로 후반에 풀 부족 시 자동 축소.

### 7.2 격리 병동 노출 보장
- 표 그대로 Stage 3 후보(3개) 픽 3, Stage 4 후보(3개) 픽 3 → 항상 노출.
- 코드 보강 권장: `RouteData`에 `guaranteed_in_stages` 같은 필드를 두거나, Stage 3/4 풀 빌드 시 격리 병동을 셔플 전 fix-slot으로 박기. 미래에 후보 맵 추가될 때 보호.

### 7.3 변주 맵 옵션 (후속)
- 후보 부족 시 같은 맵의 시각/배치 변주 버전(예: `subway-1`, `subway-2`)을 두는 것도 가능.
- 현재 우선순위 아님. 11개로 일단 가고, 후반 풀 부족이 실제로 문제될 때 도입.

### 7.4 `Callable.bind` 파라미터 순서
- Godot 4 `Callable.bind`는 인자를 **뒤에** 추가. 신호가 emit하는 인자가 항상 앞.
- 새 Area2D 트리거 추가 시 핸들러 시그니처는 `(body, area)` 순.
- 이미 코드에서 한 번 버그 났음(2026-05-02 세션 3) — 같은 실수 반복 금지.

---

## 8. 구현 계획 (작업 순서)

### Phase B — 성장 시스템 (스토리/맵과 독립)

**B-1 데이터 정의** ✅ 완료 (commit 64dcbd1)
- [x] `scripts/SkillTreeData.gd` 신규 — 계열/티어 데이터 + lookup 헬퍼
- [x] `scripts/GameState.gd` — `skills: Array` → `skills: Dictionary` 마이그레이션
- [x] `scripts/SkillSystem.gd` — `roll_choices` 티어 prereq, `find_by_id` 위임

**B-2 효과 + UI** ✅ 완료 (commit ec368b2)
- [x] `scripts/Player.gd` — 각 라인 효과 티어 분기 (T1/T2/T3)
- [x] `scripts/LevelUpOverlay.gd` — 카드 [family · T#] 헤더 + VEIL 추천 표시
- [x] `scripts/GameState.gd` — high-risk 루트 적 처치 XP +50%, XP_PER_LEVEL 8

**B-3 밸런스 패스 (2026-06)** ✅ 완료
- [x] `scripts/SkillTreeData.gd` / `scripts/Player.gd` — 글라이드 라인 재설계 (활강 T1 / 관통 사격 T2 / 유도 사격 T3)
- [x] `scripts/Bullet.gd` — `tracking_blend`/`tracking_max_angle` 분리 (multishot 약한 추적 vs glide T3 강한 유도)
- [x] `scripts/Player.gd` / `scripts/SkillTreeData.gd` — 폭발물 너프 (EXPLOSION_DAMAGE 2, 쿨다운 3.5/3.0s, desc 동기화)
- [x] `scripts/SkillTreeData.gd` `MATCHUP` + `matchup_skill_for_route` / `scripts/SkillSystem.gd` — 스킬-적 상성 (추천 ★ + 출현 가중)

### Phase C — 맵 + 스테이지 확장

**C-1 데이터/규칙** ✅ 완료 (commit da74ea4)
- [x] `scripts/RouteData.gd` — min/max_stage/unique/guaranteed_in_stages, 11개 맵
- [x] `scripts/RouteMap.gd` — route_history 필터
- [x] `scripts/GameState.gd` — TOTAL_STAGES=7, SCORE_THRESHOLD=4
- [x] 신규 5개 맵 ambience 임시 매핑

**C-2 신규 맵 layout** ✅ 완료
- [x] `scripts/Stage.gd` — 5개 맵 platform layout
- [x] `scripts/Stage.gd` — 5개 맵 ambience (cooling/watchtower/ward/datacenter/escape)

**C-3 내러티브** ✅ 완료
- [x] `scripts/VeilDialogue.gd` — Stage 5/6 브리핑 풀 추가, ACT 매핑 재정렬
- [x] `scripts/Stage.gd` — 격리 병동 복선 트리거 (route_ward 진입 시)
- [x] `scripts/Stage.gd` — 잠긴 문 톤 보강 (크기 ↑, LED 펄스, ACCESS DENIED 라벨, 후광, 추가 대사)

### 인게임 검증 / 후속 polish 항목
- [ ] 새 빌드 평균 레벨업 횟수 측정 (XP_PER_LEVEL=8이 너무 빡빡한지)
- [ ] 7스테이지 완주 시간이 8~15분 안에 들어오는지
- [ ] 격리 병동 복선 → ??? 맵 발견 흐름이 "아, 그거였구나" 연결되는지
- [x] glide T3 — 폐기된 "사격 패널티 제거"(no-op) 대신 **유도 사격**으로 재구현 (`Player._spawn_bullet` 활강 분기 + `Bullet.tracking`)
- [x] explosive T3 (2회 충전) — `Player.skill_charges`/`_refresh_skill_charges`로 구현
- [x] hp T3 (피격 슬로모) — `Player._trigger_hit_slowmo` 구현 (실시간 타이머로 슬로모 내 정확 해제)
- [x] multishot T3 (약한 추적) — `Bullet.tracking` 기본값으로 구현
- [x] shield T3 (부활 재충전) — 구현(2026-06-09). T1/T2는 발동 시 `skills.erase`(1회용), **T3는 라인 유지 + `shield_spent`로 비무장 두었다가 `SHIELD_RECHARGE_TIME`(30s) 후 재무장**(`Player.take_hit`/`_tick_timers`, 재무장 시 `_show_shield_flash`로 알림). HUD "부활" 슬롯에 재충전 남은 초 표시. 맵 전환 시 Player 재생성으로 자연 재무장(T3 = "다시 돌아오는 부활" 판타지와 일치). 용어 통일: shield 라인은 "부활"(barrier "에너지 방어막"과 구분).
- [x] barrier 라인(에너지 방어막) — 트리 desc/효과 대조 완료(2026-06-08): T1 10초 충전→1회 무효(`BARRIER_CHARGE_T1`), T2 6초 단축(`BARRIER_CHARGE_T2`), T3 무효 직후 0.6초 무적(`BARRIER_INVULN_T3`). 셋 다 `Player._tick_barrier`/`take_hit`와 desc 일치. 불일치 없음.

---

## 9. 비목표

- 스킬 신규 추가 (기존 풀 재구성만)
- 무기/장비 슬롯 등 별도 축
- 런 간 영구 강화 (메타 진보)
