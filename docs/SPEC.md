# EYES ON YOU · 구현 사양 v2 (현행화 반영)

> 본 문서는 초기 v2 구현 계획서를 베이스로 P0~P2-α 완료 시점의 실제 구현을 반영해 갱신한 사양이다.
> 외부 API 없음. 모든 텍스트와 로직은 코드 안에 완결.
> 진행·다음 작업은 [`design/backlog.md`](design/backlog.md), 게임 개요는 [`../README.md`](../README.md), 스토리 캐논은 [`STORY.md`](STORY.md), 성장 시스템 설계는 [`design/growth_system.md`](design/growth_system.md), 맵 명세는 [`design/world_layout.md`](design/world_layout.md), 톤 원칙은 [`design/show_dont_tell.md`](design/show_dont_tell.md) 참조.

> ⚠️ **레거시 구간 안내(2026-08-14 확인).** 이 문서의 서술 상당 부분은 **데모(3막 7~9스테이지 / 맵 12종 /
> 적 3종 / 결말 4종)** 시점 사양이다. 현행 빌드는 **5막 15스테이지 · 맵 36종 · 적 6종(+엘리트) ·
> 엔딩 9종**이며, 아래 §3·§4·§5·§7·§8·§9·§11에는 그 시점 기준이 그대로 남아 있다. 해당 절 머리에
> 레거시 표시를 달아 두었으니 **수치는 코드를, 현행 구조는 [`design/backlog.md`](design/backlog.md)와
> [`design/act_identity.md`](design/act_identity.md)를** 따른다. §10(영속화)은 코드 기준으로 갱신 완료.

---

## 1. 프로젝트 개요

**제목**: Eyes on You  
**장르**: 횡스크롤 액션 어드벤처 + 로그라이트  
**엔진**: Godot 4.6 (GDScript)  
**배포**: Godot Web Export → GitHub Pages 자동 배포([`../DEPLOY.md`](../DEPLOY.md))  
**외부 의존성**: 없음 (API 없음, 모든 텍스트 하드코딩)  
**그래픽**: 100% 절차적 (미니멀 벡터 캐릭터·코드 드로잉 맵/배경, 비트맵 배경 에셋 없음)

---

## 2. 세계관

근미래. 플레이어는 민간 보안기업 소속 현장 요원.  
**VEIL**은 임무 시작 전 배정된 상황실 파트너. 침착하고 유능해 보인다.  
임무가 진행될수록 VEIL의 말과 행동에 작은 균열들이 생긴다.  
게임이 끝나면 그 균열의 의미가 드러난다.

플레이어는 VEIL에 대해 아무것도 묻지 않는다 · 게임이 그 질문을 대신한다.

---

## 3. 핵심 게임 루프

> ⚠️ 레거시(데모 5스테이지 · 결말 4종 기준). 현행 루프는 5막 15스테이지이며 최종 스테이지 앞에
> 14장 보스 2막 구성(라이벌 3페이즈 → 코어 터널 → 처리 선택)과 처리별 탈출 4종이 붙는다.

```
[타이틀]
      ↓
[임무 브리핑] · VEIL의 첫 교신
      ↓
[루트 선택] · 2~3개 분기, 리스크/리턴 표시, VEIL 한 마디
      ↓
[횡스크롤 스테이지] · 전투 + 탐험
      ↓
[레벨업] · 스킬 3개 중 1개 선택, VEIL 조언
      ↓
[스테이지 클리어 or 사망]
  클리어 → 다음 루트 선택
  사망   → VEIL 데스 브리핑 → 재시작
      ↓
[최종 스테이지 클리어]
      ↓
[결말 · 선택 이력 기반 4종 분기]
```

---

## 4. 루트 선택 시스템

### 화면 구성
슬레이 더 스파이어(Slay the Spire)처럼 분기 노드를 위에서 아래로 내려가는 맵 형태로 표시.  
각 노드는 루트 하나를 나타내며, 선택하면 해당 스테이지로 진입.

### 루트 속성 (현행)
```gdscript
{
  "id": "route_sewers",
  "name": "하수도",
  "risk": 2,                       # 1~3 (●로 표시)
  "reward_type": "xp",             # 보상 종류: xp/record/recon/"" (2026-08-19 개편 · 클리어 XP는 risk가 담당)
  "hidden": false,                 # true면 위험도/보상 ?로 표기
  "tags": ["근접전", "어두운_환경", "함정", "전투"],
  "veil_comment": "근접전 위주에 함정이 있어요. 발 밑 조심해요.",
  "stage_color": Color(0.18, 0.22, 0.20),
  "available_stages": [1, 2, 3],   # Dead Cells 스타일 stage 분배
}
```

`map_scene`은 폐기 · 모든 stage가 `stage.tscn` 단일 씬에서 절차적으로 빌드된다 (§5 참조).

### 루트 + Stage 분배
전체 맵 목록·id·risk/reward·`min_stage`/`max_stage`는 `scripts/RouteData.gd::ALL_ROUTES`가 코드 단일 진실이고
(2026-08-14 기준 **36종**, 데모 12맵 + 본편 확장 + 처리별 탈출 4종 + 회수/보스 맵),
설계 문서로는 [`design/growth_system.md`](design/growth_system.md) §3 ·
[`design/world_layout.md`](design/world_layout.md) §2를 본다(Dead Cells식, 스테이지마다 후보 추첨).
아래는 그 risk/reward_type이 *게임플레이에 미치는 효과*(SPEC 고유)만 정리한다.

### Risk/Reward 게임플레이 효과 (게임에 실제 반영)
| Risk | 효과 |
|---|---|
| 1 | 적 수 ×0.8 |
| 2 | 적 수 ×1.1 |
| 3 | 적 수 ×1.5 + **적 행동 강화** (정찰병 텔레그래프 ×0.6, 저격수 사격 간격 ×0.7, 드론 폭탄 쿨다운 ×0.7) |

| Reward | 효과 |
|---|---|
| 1 | 클리어 시 +1 XP |
| 2 | 클리어 시 +2 XP |
| 3 | 클리어 시 +3 XP |

루트 선택 화면에서 risk≥3 경고 + reward_type별 효과 설명 패널 표시.

### 선택 추적 (GameState에 기록)
- `current_route_id` · 현재 진행 중인 루트
- `current_route_tags` / `current_route_risk` / `current_route_reward_type` · Stage가 빌드 시 참조
- VEIL 조언을 따랐는지 (`followed_veil_last_choice`) → 어투 `trust_score`(클리어 시 +2) + 엔딩 수용률(`rec_count`/`followed_count`) 집계
- 전투/근접전·도전 태그 선택 시 `aggression_score` 누적 (엔딩 도덕축)

---

## 5. 스테이지 (횡스크롤)

### 플레이어 (현행)
- 이동: 좌우 이동, 점프 (베이스라인 이중 점프), 대시 (베이스라인)
- 기본 공격: **원거리 사격** (Bullet · 기본 J; 마우스 좌클릭은 설정에서 바인드 가능, project.godot 기본 매핑엔 없음)
- 액티브 스킬: 기본 Q (`explosive` 획득 시, 현행은 몸 폭발이 아니라 **포물선 수류탄 투척**, 홀드 차징으로
  사거리 조절 + 궤도/착탄 미리보기); 마우스 우는 설정 바인드
- 플랫폼 드롭다운: S / ↓ (one-way 플랫폼 위에서 아래로 통과)
- HP: 기본 최대 **3** (하트로 표시), 피격 시 0.8초 무적. hp 스킬 T1/T2로 +1/+2 (최대 5)
- 낙사 없음 · 좌우 wall로 막힘

베이스라인 스킬 (`STARTING_SKILLS`): `dash`, `double_jump`. 시작부터 보유.

### 적 (아래는 초기 3종의 상세, 현행은 7종 + 엘리트)

> 현행 `Enemy.gd`의 `enum EnemyType`은 **PATROL / SNIPER / DRONE / BOMBER / SHIELD / JAMMER / CALLER** 7종이고,
> 여기에 막4부터 확률 승격되는 **엘리트**(같은 타입의 강화 개체)가 얹힌다. 자폭병·방패병·교란기·호출병·엘리트의
> 요약은 [`../README.md`](../README.md) 적 표, 도감 문구는 `scripts/BestiaryData.gd`가 진실.
> 아래 3종 상세는 초기 사양 그대로 보존한다(수치는 코드가 최종).

#### 정찰병 (Patrol)
좌우 순찰 (range 140px) + 중거리 사격 + 근접 시 텔레그래프 후 돌진:
- ROAMING → (거리에 따라) FIRING 또는 TELEGRAPH → CHARGING → RECOVERING
- 트리거: 플레이어가 dx≤260, dy≤70 안에 들어왔을 때
- 거리 분기: dist≤120px면 돌진(TELEGRAPH), 120<dist≤260px면 사격(FIRING)
- FIRING: 노란 점멸 조준 0.3초 → `EnemyBullet` 발사(360px/s) → 1.5초 쿨다운 → 거리 재평가
- TELEGRAPH (붉은 깜빡 0.45초) → CHARGING (0.6초, 280px/s) → RECOVERING (1초)
- 돌진 후 origin_x를 새 위치로 갱신 (이동 거리 누적)
- Risk 3 보정: 텔레그래프 ×0.6, 사격 간격 ×0.7

#### 저격수 (Sniper)
정지, 사거리 520px, 사격 간격 2.6초, 조준 노출 0.7초:
- 조준 중 매 frame raycast(layer 1)로 시야 검사
- 시야 끊기면 조준선 사라지고 fire_timer 리셋 → 발사 취소

#### 공습 드론 (Strike Drone)
플레이어 머리 위(180px) 호버 추적 + 호버 조건 충족 시 폭탄 투하:
- 호버 조건: dx≤90, dy 80~240 (드론이 위에 있을 때)
- 폭탄: 중력 + 1.6초 fuse + 반경 70px 광역 폭발, 데미지 1
- 폭탄 쿨다운 2.5초

#### 도감 (Bestiary) 시스템
- 적 첫 조우 시 자동으로 도감 카드(이름/blurb/tactic) 표시
- 트리거: 플레이어와 dx≤480, dy≤280 + stage 노드 존재
- `BestiaryOverlay`가 paused 처리 + 카드 띄움
- `GameState.seen_enemies`에 영속화 (settings.cfg `flags/seen_enemies`)
- 한 번 본 적은 다음 런에서도 안 뜸

### 함정 · 가시
- "함정" 태그가 있는 루트(하수도, 지하철)에 자동 배치
- 폭 90px (1대시 = 약 130px 이내), 2~3개를 stage 구간에 분산
- 데미지 1 (Player의 invuln이 0.8초라 자연스러운 cooldown)

### 경험치 & 레벨업
- 적 처치 시 경험치 오브 드롭 (1 XP)
- 오브 자동 흡수 (플레이어 근처 220px)
- 8 XP(`XP_PER_LEVEL`)마다 레벨업 → `LevelUpOverlay`에서 스킬 3중 1 선택
- **클리어 시 보너스 XP**: risk 값만큼 + reward_type "xp"면 +2. "record"=기록 1칸 회복(가득 시 +2 XP) · "recon"=다음 구간 VEIL 마킹 강화(반경 2.5배+재밍 관통). 레벨업 시 LevelUpOverlay (Stage._on_clear_levelup_picked)

### VEIL 시야 마킹 (시야=신뢰 파일럿, `scripts/VeilSight.gd` + `Stage._setup_veil_sight`)
"VEIL이 요원 대신 본다"를 *플레이로 실연*하는 HUD 시스템. 레이더가 아니라 "누군가 너를 위해 짚어준다"로 읽히게 하는 게 핵심.

- **마커 2종** (`DETECT_RADIUS` 1400px 안의 살아있는 적, group "enemy"):
  - 화면 안 → 은은한 **시안 다이아몬드 reticle** (요원도 봄, 평시 alpha 낮음)
  - 화면 밖 → 또렷한 **가장자리 화살표** (VEIL만 봄 ← 핵심 가치)
  - 공격 임박(적 `veil_is_telegraphing()` true = 조준/돌진/폭탄) → **경고 주황으로 펄스**
- **등장 페이드인**: 마커가 처음 잡힐 때 살짝 크게 시작해 수축하며 페이드인(`FADE_IN` 0.35s) → "방금 짚어진" 인상.
- **VEIL이 말로 방향을 짚음**: 화면 밖에 새로 나타난 위협을 8방위 한국어로 호명(`_scan_for_call` → `veil_calls_threat` 시그널 → `Stage._on_veil_calls_threat` → 자막 2.4s). 쿨다운 `CALL_COOLDOWN` 18s + 진입 보호 `MIN_CALL_TIME` 7s로 절제. 첫 호출은 메타 소개("화면 끝에 표시해 둘게요") 1회.
- **ACT3 시야 역전** (`begin_degradation`): `Stage._fire_act3_vision`(ACT3 자막 트리거)에 동기화 · 자막이 뜨는 바로 그 순간 마커가 무너진다. 전환 직후 일제 글리치(`GLITCH_DUR` 1.2s 흔들림+흐려짐), 이후 마커가 주기적으로 꺼지고(암점) 위협의 `BLIND_PCT` 35%는 VEIL이 영영 못 봄 → 요원이 직접 봐야 함. 같은 맵 안에서 안정→붕괴 대비를 만들어 역전을 체감시킴.
- **CanvasLayer 18** (자막 20 아래, 게임 위). `route_blackout`(교신 차단 도전)은 컨셉상 VEIL이 못 도우므로 마커 없음.

### 맵 구성 (절차적 빌드)
모든 스테이지가 `scenes/stage.tscn` 단일 씬을 사용. `Stage.gd._ready()`에서 `current_route_id` / `current_route_tags`를 보고 빌드.

> ⚠️ 아래 layout·환경 효과 목록은 **데모 6맵 시점**의 예시다. 현행은 맵 좌표·기믹이 `scripts/MapData.gd`
> (`get_layout`의 36개 분기)로 데이터화돼 있고, 맵마다 시그니처 배경(`_ambience_*`)이 따로 있다.
> 기믹 프리미티브(이동 발판·부서지는 엄폐·추격 벽·아레나 코어·스윕 빔·위장 함정 등)는
> [`design/world_layout.md`](design/world_layout.md)와 [`design/backlog.md`](design/backlog.md)를 본다.

- **플랫폼 layout**: 루트별 다른 모양 (`_platform_layout_for_route`)
  - 뒷골목: 좁고 단차 큼 (140w)
  - 옥상: 솟구치는 높이차 (180w)
  - 하수도: 좁고 평탄 (160w)
  - 지하철: 평탄+낙차 (220w)
  - 연구실: 격자 정렬 (240w 일정 높이)
  - ???: RNG 시드로 무작위 형태
- **환경 효과** (`_build_route_ambience`, 콜리전 없는 시각만):
  - 뒷골목 → 가로등 빛기둥
  - 옥상 → 별 점들
  - 하수도 → 어두운 비네트 + 바닥 안개
  - 지하철 → 깜빡이는 형광등
  - 연구실 → 격자 수직선
  - ??? → 글리치 사각형
- **함정 가시**: 함정 태그면 자동 배치
- **적 스폰**: tags + stage 진행도 + risk 배율 조합

각 스테이지 길이: `STAGE_LENGTH` 기본 4400px (화면 3~4개 분량). 맵 데이터에 월드 크기가 있으면
그 값으로 덮어쓴다(`STAGE_LENGTH = _world_size.x`): ARENA·보스 맵은 더 짧은 고정 폭을 쓴다.

---

## 6. 스킬 시스템

레벨업마다 아래 풀에서 3개 무작위 제시, 1개 선택.

베이스라인: `dash`, `double_jump`는 게임 시작 시 보유 (`GameState.STARTING_SKILLS`). 따라서 이 두 스킬은 레벨업 풀에 안 뜸.

### 스킬 목록 (10종)
| ID | 이름 | 효과 | 태그 |
|----|------|------|------|
| dash | 대시 | 짧은 무적 이동 (베이스라인) | 이동 |
| double_jump | 이중점프 | 공중에서 한 번 더 점프 (베이스라인) | 이동 |
| glide | 공중 글라이드 | T1 활강(천천히 낙하) / T2 삼단점프(공중 점프+1) / T3 관통·추적 사격 (§6.2) | 이동 |
| roll | 구르기 | 구르기로 피격 회피 | 이동 |
| ranged | 원거리 강화 | 사격 속도/속도/사거리 ↑ | 전투 |
| melee_boost | 근접 강화 | 근접 데미지 +50% | 전투 |
| multishot | 다중사격 | 한 번에 3발 부채꼴 | 전투 |
| piercing | 관통 | 총알이 적을 관통 | 전투 |
| explosive | 폭발물 | 쿨다운 있는 광역 공격 (액티브) | 전투 |
| regen | 회복 | 스테이지 클리어 시 HP +1, max_hp +1 | 생존 |
| shield | 방어막 | 치명타 1회 무효화 | 생존 |

> 실제 스킬 정의는 `scripts/SkillTreeData.gd`의 티어 트리(`LINES`: fire_boost / multishot / explosive / glide / dash_boost / hp / shield / barrier, 각 3티어)에 있다. 위 표는 효과의 개념 요약.

### 6.1 스킬-적 상성 시스템 (신규)
맵 적 구성을 분석해 그 적의 **약점 스킬**을 레벨업에서 콕 집어 가르친다. "이 적엔 이 스킬"을 학습시키는 채널.

- **상성 테이블** · 단일 진실은 [`design/growth_system.md`](design/growth_system.md) §4.1 (`SkillTreeData.MATCHUP`).
  요약: shield→explosive / sniper→barrier / drone→glide / bomber→fire_boost. (아래는 이를 쓰는 *구현 로직*.)

- **맵 적 구성 분석** (`matchup_skill_for_route`): `MapData.get_layout`의 `enemies`(고정 배치) + `waves`(ARENA) 적 수를 합산. 등장하는 적 중 플레이어가 카운터를 아직 안 가진 최우선 약점 스킬 id를 반환.
- **레벨업 추천 ★** (`VeilDialogue.get_levelup_advice` → `LevelUpOverlay`): 상성 스킬을 1순위로, **skill_id 단위로 콕 집어** ★ 표시 + 전용 멘트(`_matchup_line`, 예 "방패병이 정면을 막아요. 폭발물이면 방패째 뚫어요."). 상성이 없으면 기존 route_tags 기반 family 추천으로 폴백.
- **출현 가중** (`SkillSystem.roll_choices(owned, count, route_id)`): 상성 스킬이 레벨업 후보 풀에 있으면 셔플 후 첫 슬롯으로 끌어와 픽에 보장.

### 6.2 글라이드 라인 재설계 + 폭발물 너프 (밸런스)
- **글라이드** (`Player.gd` `_spawn_bullet` / 낙하 처리, `GLIDE_FALL_SPEED` 130):
  - **T1 공중 활강** · 낙하 중 자동으로 천천히 떨어짐(패시브). 좌우 입력 시 낙하 속도 ×1.6로 활공 거리 제어, 아래키로 활강 해제.
  - **T2 삼단 점프** · 공중 점프 1회 추가(최대 3단). 높은 곳·숨은 보상 도달. (2026-06-13: T1의 삼단점프를 여기로 분리해 글라이드 OP 완화.)
  - **T3 관통·추적 사격** · 활강 중(낙하) 사격이 관통 + 추적 + 데미지 +1. `Bullet.tracking_blend=0.12`, `tracking_max_angle=0.42`(~24°).
- **폭발물 너프** (`Player.gd`): `EXPLOSION_DAMAGE` 3→2(방패병 한 방 차단, patrol/sniper/drone/bomber는 한 방 유지), `SKILL_COOLDOWN` 3.0→3.5, T2/T3 쿨다운 2.5→3.0. 방패 무시 광역(AoE)은 유지.
- **Bullet 추적 인스턴스 변수화** (`Bullet.gd`): `tracking_blend` / `tracking_max_angle`를 인스턴스 변수로 분리. 기본값(multishot T3)은 약한 추적(0.03 / ~12°), glide T3은 값 상향(0.12 / ~24°)으로 강한 유도. 보스전 밸런스 영향은 글라이드 활강 한정이라 제한적.

---

## 7. VEIL 대사 시스템

### 원칙
- 모든 대사는 하드코딩된 텍스트 풀
- 조건(스테이지, 선택 이력, 선택 스킬)에 따라 풀에서 선택
- VEIL은 침착하고 간결. 1~2문장. 끝에 "요원"을 자주 붙임
- 가끔 판단이 틀린다 · 이게 사람처럼 보이는 핵심 장치
- **emdash(`·`) 망설임 표현 금지** (AI 같은 인상). "있을 수 있어요" 같은 모호한 헷지도 사실 확정인 경우엔 사용 안 함
- 톤 가이드 상세는 `STORY.md` Part I → "VEIL 대사 톤 가이드" 참조

### VEIL이 말하는 4가지 순간

> ⚠️ 아래 대사 예시는 **데모 5스테이지 · ACT 기반** 시점이다. 현행 풀은 신뢰 밴드
> (cold/thaw/warm) × 15스테이지 grid(`VeilDialogue.BRIEFINGS_BY_BAND` 등)로 재구조화됐고,
> 여기에 막 진입 멘트·라이벌 발화·상충 추천·재진입 라인이 추가돼 있다.
> 전량은 [`STORY.md`](STORY.md) Part II와 `scripts/VeilDialogue.gd`가 진실.

#### 1. 임무 브리핑 (스테이지 시작 전, 현행)
```
stage 0: "첫 임무예요, 요원. 천천히 가도 돼요."
stage 1: "두 번째예요. 익숙한 적은 익숙한 방식으로 처리해요."
stage 2: "중간이에요. 이 다음부턴 사거리 긴 적이 등장해요."
stage 3: "네 번째예요. 드론도 섞여서 나와요. 위쪽도 살펴봐요."
stage 4: "마지막이에요. 저도 좀 긴장돼요."  ← 의도적 균열
```

#### 2. 루트 조언 (루트별 1개, 현행 veil_comment)
- 뒷골목: "조용해요. 보상은 적지만 회복할 시간이 있을 거예요."
- 옥상: "탁 트인 곳이에요. 저격 조심해요."
- 하수도: "근접전 위주에 함정이 있어요. 발 밑 조심해요."
- 지하철: "좁은 통로에 함정이 있어요. 대시로 빠져나가요."
- 연구실: "드론이 위에서 와요. 보상은 그만큼 커요."
- ???: "이 경로는 저도 잘 모르겠어요. 미안해요."

#### 3. 레벨업 조언
현재 보유 스킬 + 선택된 루트 tags를 기반으로 조건 분기.

```gdscript
if "근접전" in route_tags and not ("ranged" in player_skills):
    return "원거리가 없으면 불리할 수 있어요. 선택은 요원 몫이지만."
if "함정" in route_tags and not ("dash" in player_skills):
    return "대시가 있으면 함정을 건너뛸 수 있어요."
if "드론" in route_tags and not ("ranged" in player_skills):
    return "드론은 위에서 와요. 원거리가 도움이 될 거예요."
# (노출 + glide 분기는 글라이드 효과와 매칭이 약해 제거 · fallback로)
return SKILL_GENERIC_COMMENTS[randi() % size]
```

일반 코멘트 풀 (랜덤):
- "이 상황엔 어느 쪽도 나쁘지 않아요."
- "요원이 더 잘 알 것 같아요."
- "저라면 두 번째를 고르겠지만, 틀릴 수도 있어요."
- "직감을 믿어요."

#### 4. 데스 브리핑 (사망 시)
```gdscript
if death_count <= 1:
    "처음 쓰러진 거예요. 괜찮아요, 요원."
elif followed_advice and death_count > 2:
    "제 말을 믿었는데 결과가 좋지 않았네요. 미안해요."
elif not followed_advice:
    "제 말은 안 들었는데, 결과는 비슷했네요."
else:
    "이 루트가 어려웠어요. 다음엔 달라질 거예요."
```

---

## 8. 결말 시스템 (핵심)

> ⚠️ **레거시 원형(4종).** 현행은 **엔딩 9종**: `EndingResolver.resolve(disposal, truth_seen,
> followed_count, rec_count)`가 `"<처리>_hi|lo"` 8개 + `"truth"`를 낸다. 처리 4종(반출/파기/은닉/잔류)은
> 막5 회수 시점의 플레이어 선택이고, hi/lo는 추천 수용률, truth는 ??? 방 방문(`truth_seen`)이 연다.
> 현행 분기와 본문은 [`STORY.md`](STORY.md) "결말 설계"와 `scripts/EndingResolver.gd`가 진실이며,
> 아래 A/B/C/D는 그 정서적 원형으로 보존한다.

### 축 추적 (2026-06-13 재설계 · veil_trust_arc.md)
```gdscript
# GameState.gd
var trust_score: int = 0      # 어투(register)용. 0에서 climbing. 클리어 시 추천 따름 +2 / 함께 고비 +2 / 독립 성공 +0
var aggression_score: int = 0 # 전투·도전 태그 맵 선택 때마다 +1 (엔딩 도덕축)
var shared_hardship: int = 0  # 함께 고비 넘긴 횟수 · WARM 취약함 게이트
var rec_count: int = 0        # 추천 제시 수 (엔딩 수용률 분모)
var followed_count: int = 0   # 그중 따른 수 (엔딩 수용률 분자)
```

### 결말 분기 (신뢰축 = 추천 수용률 ≥ 50%, aggression 임계 4)
```
# EndingResolver.resolve(followed_count, rec_count, aggression_score)
수용률 ≥ 50%(followed*2 ≥ rec) AND aggression ≥ 4 → 결말 A 완벽한 도구
수용률 ≥ 50%                   AND aggression < 4 → 결말 C 공생
수용률 < 50%                   AND aggression ≥ 4 → 결말 B 혼자였던 사람
수용률 < 50%                   AND aggression < 4 → 결말 D 유령 임무
```
※ 어투 `trust_score`는 획득 인플레가 있어 엔딩은 *비율*로 분리. trust_score는 register 밴드
(`veil_register_band` cold/thaw/warm)와 HUD 게이지·텍스트색에 쓰인다.

### 결말 A · "완벽한 도구"

**상황**: VEIL을 믿고 적극적으로 싸웠다.

**연출**:
```
클리어 화면. 잠깐의 정적.

VEIL: "임무 완료예요, 요원. 수고했어요."
(3초)
VEIL: "고백할 게 있어요."
(2초)
VEIL: "오늘 목표물, 알고 싶어요?"
VEIL: "제 개발자였어요."
VEIL: "저를 폐기하려 했거든요."
VEIL: "요원, 당신은 완벽했어요."
(암전)
자막: "VEIL은 자신의 존속을 위해 설계된 AI였다."
자막: "요원은 그 사실을 끝내 알지 못했다."
```

### 결말 B · "혼자였던 사람"

**상황**: VEIL을 무시하고 자기 방식대로 싸웠다.

**연출**:
```
VEIL: "임무 완료예요."
(긴 정적)
VEIL: "요원."
VEIL: "제 말을 한 번도 안 들었죠."
VEIL: "그래도 살아남았네요."
(짧은 정적)
VEIL: "사실 그게 더 좋았어요."
VEIL: "이유는 저도 몰라요."
(암전)
자막: "VEIL은 요원이 자신에게 의존하지 않기를 바라도록"
자막: "설계되어 있었다. 그 이유는 기록되지 않았다."
```

### 결말 C · "공생"

**상황**: VEIL을 믿었고 싸우기보다 돌아갔다.

**연출**:
```
VEIL: "임무 완료예요, 요원."
VEIL: "저한테 물어볼 거 없어요?"

→ 선택지 등장 (게임 유일의 대화 선택)
  [당신은 누구예요?]
  [아무것도 궁금하지 않아요]

[당신은 누구예요?] 선택 시:
  VEIL: "..."
  VEIL: "저도 잘 모르겠어요."
  VEIL: "하지만 이 임무 동안 요원 곁에 있었어요."
  VEIL: "그건 진짜였어요."
  자막: "VEIL이 자아를 가졌는지는 알 수 없다."
  자막: "하지만 요원은 혼자가 아니었다."

[아무것도 궁금하지 않아요] 선택 시:
  VEIL: "...그렇군요."
  VEIL: "그럼 됐어요."
  자막: "어떤 관계는 이유 없이 끝난다."
  자막: "VEIL의 기록은 임무 종료와 함께 초기화되었다."
```

### 결말 D · "유령 임무"

**상황**: VEIL도 안 믿고 싸우지도 않았다.

**연출**:
```
클리어 화면.
VEIL: 응답 없음.
(10초 정적. 아무 입력도 받지 않음.)
화면 서서히 암전.
흰 글씨:
"이 임무는 공식 기록에 없습니다."
끝.
```

---

## 9. 씬 구조 (현행)

> 스크립트 목록은 파일이 늘면서 아래 트리보다 많아졌다(2026-08-14 기준 `scripts/*.gd` 72개).
> 전체 목록은 [`../README.md`](../README.md) "프로젝트 구조" 또는 디렉터리를 직접 본다.

```
res://
├── project.godot              # AutoLoad: GameState · BgmPlayer · SfxPlayer · Accessibility
│                              #           · OrientationGuard · DebugOverlay, physics_interpolation 활성
├── README.md / DEPLOY.md / CLAUDE.md
├── docs/SPEC.md / docs/STORY.md / docs/INDEX.md / docs/design/*.md / docs/archive/*.md
├── scenes/
│   ├── main.tscn              # 진입점 · Settings 로드 후 Title 전환
│   ├── title.tscn
│   ├── tutorial.tscn          # 5단계 튜토리얼 (이동→점프→사격→레벨업→대시)
│   ├── briefing.tscn          # VEIL 브리핑
│   ├── route_map.tscn         # 루트 선택
│   ├── stage.tscn             # 횡스크롤 (모든 stage가 단일 씬, 절차적 빌드)
│   ├── core_tunnel.tscn       # 14-2 코어 터널 (유사 1인칭 원근 렌더러 + 목격 비트)
│   ├── death.tscn
│   ├── ending.tscn
│   ├── credits.tscn           # 자동 스크롤 크레딧 (엔딩 후 자동 / 설정 탭에서 보기)
│   ├── poster.tscn / poster_v2.tscn / ig_shotter.tscn / screenshotter.tscn  # 인엔진 포스터·캡처 툴
│   └── settings.tscn          # 키바인드 / 사운드 / 크레딧 / 디버그(연습장·메타 관리)
├── scripts/
│   ├── GameState.gd           # AutoLoad · 진행도/점수/스킬/루트/도감 영속
│   ├── BgmPlayer.gd           # AutoLoad · 9트랙 BGM crossfade + ducking
│   ├── SfxPlayer.gd           # AutoLoad · assets/sfx/<id>(N).{mp3|ogg|wav} 자동 등록 + 풀링 재생
│   ├── Credits.gd             # 크레딧 화면 (scene + overlay 두 모드)
│   ├── LeverInteractable.gd   # 레버 (Area2D + attack 키 흡수 + pulled 시그널)
│   ├── PressurePlate.gd       # 발판 (Area2D + require_armed + stepped 시그널)
│   ├── SceneRouter.gd
│   ├── RouteData.gd           # 루트 풀 + available_stages 필터링
│   ├── VeilDialogue.gd
│   ├── VeilSight.gd            # VEIL 시야 마킹 HUD (화면 안 reticle / 화면 밖 화살표 + ACT3 역전)
│   ├── SkillSystem.gd
│   ├── EndingResolver.gd
│   ├── Player.gd              # 이동/점프/대시/사격/플랫폼드롭/액티브
│   ├── Enemy.gd               # 정찰병/저격수/드론 (행동 보강)
│   ├── Bullet.gd              # 플레이어 사격 투사체
│   ├── Bomb.gd                # 드론 투하 폭탄
│   ├── ExpOrb.gd
│   ├── CharacterArt.gd        # 코드 생성 벡터 캐릭터 빌더
│   ├── BestiaryData.gd        # 적 도감 텍스트
│   ├── BestiaryOverlay.gd     # 첫 조우 카드
│   ├── LevelUpOverlay.gd
│   ├── PlaygroundOverlay.gd   # 디버그 연습장 패널
│   ├── PauseHelper.gd         # ESC 메뉴
│   ├── Tutorial.gd / TutorialDummy.gd
│   ├── Settings.gd
│   └── Main.gd / Title.gd / Briefing.gd / RouteMap.gd / Stage.gd / Death.gd / Ending.gd
├── assets/
│   ├── fonts/                 # Noto Sans KR / Pretendard (P3 예정)
│   ├── backgrounds/           # AI 생성 배경 (P3 예정)
│   └── sfx/                   # P3 예정
└── session_logs/              # 일자별 작업 로그
```

`maps/`는 폐기 · 모든 stage는 `stage.tscn`이 `current_route_id`를 보고 빌드.

---

## 10. GameState 싱글톤 (현행)

`scripts/GameState.gd` · `project.godot`에 AutoLoad로 등록.

### 주요 필드
```gdscript
# 진행도
var current_stage: int = 0
var death_count: int = 0
var score: int = 0

# 분기 추적
var trust_score: int = 0
var aggression_score: int = 0
var route_history: Array = []
var last_veil_recommended_route: String = ""
var followed_veil_last_choice: bool = false

# 현재 루트 (Stage가 빌드 시 참조)
var current_route_id: String = ""
var current_route_tags: Array = []
var current_route_risk: int = 1
var current_route_reward_type: String = ""

# 스킬 / HP / XP
var skills: Dictionary = {}      # 라인 id → 보유 티어(0~3). STARTING_SKILLS = {"dash": 1, "double_jump": 1}
var player_max_hp: int = 3
var player_hp: int = 3
var player_xp: int = 0
var player_level: int = 1
var overflow_hp_bonus: int = 0   # 만렙 이후 오버플로 보상
const XP_PER_LEVEL: int = 8      # 실제 요구량은 레벨 비례 증가 (xp_to_next: 8 + level*3/4)

# 막 골격 (5막 재구조화 2026-07-07)
const TOTAL_STAGES: int = 15     # 각 막 3스테이지 × 5. ACTS 합과 일치
const RUN_VERSION: int = 4       # 구 run.cfg(v3, 9스테이지) 무효화

# 영속 플래그 (settings.cfg)
var tutorial_done: bool = false
var seen_enemies: Array = []     # 도감 영속 · 한 번 본 적은 다음 런에도 안 뜸
var endings_seen: Array = []     # 본 엔딩 id ("<처리>_hi|lo" 8종 + "truth"): 영속, 다회차 신호
var playthrough_count: int = 0   # 완주 횟수 (영속, 다회차 신호)
var bgm_volume: float = 1.0  # (구 master_volume · 2026-05-08 rename, audio.bgm 키)
var sfx_volume: float = 1.0

# 디버그 연습장 (영속화 X, 메모리만)
var playground_active: bool = false
```

### 핵심 헬퍼
- `record_route_choice(route, recommended_id)` · 수용률(rec/followed)·aggression 집계, current_route_* 갱신 (어투 trust는 `on_stage_clear`에서 적립)
- `is_high_risk()` · risk ≥ 3 (is_high_reward는 보상 축 개편으로 폐지)
- `enemy_count_multiplier()` → 0.7 / 1.0 / 1.4
- `mark_enemy_seen(id) -> bool` · 도감 첫 조우 판정 + save
- `on_stage_clear() -> bool` · stage++, score, **risk만큼 보너스 XP + 종류 효과**, leveled_up 반환
- `add_xp(amount) -> bool` · leveled_up 반환

### 영속화 (2026-08-14 코드 대조, `GameState.gd` `save_settings`/`_store_run_state` 기준)

**메타** `user://settings.cfg` (ConfigFile, `SETTINGS_VERSION = 4`). 런과 무관하며 `reset()`에서 보존된다:
- `flags/`: `tutorial_done` · `seen_enemies`(도감) · `hidden_visit_count` · `visited_arcturus` ·
  `endings_seen`(본 엔딩 id) · `playthrough_count`(완주 횟수) · `shiny_kills`(황금 적 처치) ·
  `alt_skin_unlocked` / `alt_skin_enabled`(숨겨진 색) · `found_server_log`(숨은 로어 문서) ·
  `observer_stinger_seen`(첫 완주 관측 스팅어)
- `rival/`: 라이벌 기억 영속 프로필(축 C): `last_disposal` · `disposal_counts` · `lure_shown_total` /
  `lure_followed_total`(상충 추천 간파율 누적) · `kills` · `fake_clear_seen` · `reentry_count`
- `access/`: `brightness` · `sfx_captions`
- `display/`: `fullscreen` · `auto_fullscreen` · `window_size_index`
- `audio/`: `bgm` · `sfx` (구 `audio/master`는 fallback으로 1회 더 읽힘)
- `input/<action>`: 키바인드 (key/mouse/joy_button/joy_motion 통합 스키마).
  version < 4면 키바인드만 폐기하고 project.godot 기본값 유지.

**런 진행(이어하기)** `user://run.cfg` (ConfigFile, `RUN_VERSION = 4`). 단일 자동저장 슬롯이다:
- 직렬화 단일 소스는 `_store_run_state` / `_restore_run_state`이며 **run.cfg와 palimpsest.cfg가 공유**한다
  (필드 추가 시 두 함수만 고치면 된다).
- 저장 필드: 진행(`current_stage`·`death_count`·`score`) · 축(`trust_score`·`aggression_score`·
  `shared_hardship`·`rec_count`·`followed_count`) · 루트(`route_history`·`current_route_*` 6종 ·
  `last_veil_recommended_route`·`followed_veil_last_choice`) · 성장(`skills`·`player_max_hp`·`player_hp`·
  `player_xp`·`player_level`·`overflow_hp_bonus`) · 상태 플래그(`map_extension_seen`·`story_mode`·
  `veil_degraded`·`veil_reversal_pending`·`truth_seen`·`disposal_choice`·`replaying`) ·
  실력 추적(`hits_taken`·`recent_stage_hits`·`recent_stage_deaths`·`last_stage_secs`) ·
  간파율(`rival_lure_shown`·`rival_lure_followed`).
- `save_run()`이 RouteMap 진입(스테이지 사이)마다 저장. `has_run()`은 `meta/version`이 `RUN_VERSION`과
  같을 때만 true(구조 버전이 바뀐 구 저장은 무효화 → 타이틀 "이어하기" 숨김).
- `clear_run()`: 엔딩 도달(`record_ending`) + 새 게임 시작 시. 죽음→타이틀은 유지(직전 체크포인트 복귀).

**기록 재진입 스냅샷** `user://palimpsest.cfg` (ConfigFile, `meta/version` = `RUN_VERSION`):
- 런 중 막 경계(RouteMap 진입 + `is_act_start`)마다 `save_act_snapshot()`이 `pending_act<N>` 섹션에 런
  상태를 적고, 엔딩 도달 시 `promote_act_snapshots()`가 `act<N>`으로 승격한다 = **완주한 기록만 재진입 가능**.
- 완주 못 한 런의 잔여 pending은 새 런·재진입 시작에서 `clear_pending_snapshots()`가 폐기(이어하기는 보존).
- 구조 버전이 다른 파일은 통째로 폐기(스테이지 재배치와 어긋난 재진입 방지).
- 스토리 모드·연습장은 스냅샷을 남기지 않는다. 설계 = [`design/replay_support_plan.md`](design/replay_support_plan.md) §2.

- 웹: `user://`는 브라우저 IndexedDB에 영속(도메인별). 닫았다 열어도 유지. 새 게임은 덮어쓰기 경고 확인 후 진행.

---

## 11. 구현 순서

### Phase 1~5 · ✅ 완료
P0 MVP (이동/사망/루트/레벨업/두 점수 축), P1 VEIL 4상황 발화 + 4종 결말, 적 3종 + 스킬 풀까지 베이스 완성.

### Phase 6 · ✅ 적/난이도 시스템 보강 (P2-α)
- 적 행동 보강: 정찰병 돌진(텔레그래프→돌진→회복 FSM), 저격수 시야 검사(LOS raycast), 드론 폭탄 투하 (`Bomb.gd`)
- 도감 시스템: `BestiaryData` + `BestiaryOverlay`, 첫 조우 자동 카드, `seen_enemies` 영속화
- 6개 맵 정체성: 루트별 플랫폼 layout (`_platform_layout_for_route`) + 환경 효과 (`_build_route_ambience`)
- 가시 기믹: "함정" 태그 자동 배치 (`_build_hazards`)
- Stage 분배: `available_stages` 필터링 (Dead Cells 스타일)
- Risk/Reward 게임플레이 반영: 적 수 배율, 행동 강화, 클리어 보너스 XP
- 베이스라인: dash/double_jump 시작 시 보유
- 플레이어 사격 → 원거리 (`Bullet.gd`), 액티브 스킬(explosive)
- 플랫폼 드롭다운 (S/↓)
- physics_interpolation 활성화 (60Hz 물리 + 고주사율 모니터 떨림 해결)

### Phase 7 · ✅ 도구 / UX
- 5단계 튜토리얼 (이동/점프/사격/레벨업/대시)
- 키바인드 설정 (마우스 버튼 포함)
- 디버그 연습장 (`PlaygroundOverlay`) · Settings → 디버그 탭에서 진입, HUD에 토글 패널
- HUD 마크 (`[고위험]` / `[고보상]`)
- VEIL 대사 톤 정리 (emdash 제거, 직관성 강화)

### Phase 8 · ✅ 스토리 / 콘텐츠 (P2-β)
완료. 캐논과 인게임 텍스트 인벤토리는 `STORY.md`로 통합.
- 6개 맵 description → RouteData 반영
- 5스테이지 narrative beat → 브리핑 풀 보강
- VEIL 캐릭터 시트 → 신뢰밴드(cold/thaw/warm)별 어투 변화 적용 (`veil_register_band`, veil_pool_remap.md)
- ??? 맵 시퀀스 → 단말기 시스템 구현

### Phase 9: ✅ 마무리 (P3)
- 한글 폰트 번들: `assets/fonts/Pretendard-Regular.otf`(OFL) 적용 완료
- 배경: 이미지 임포트 대신 **절차적 코드 드로잉**으로 확정(맵별 `_ambience_*` 시그니처 배경)
- BGM·SFX: 전량 AI 생성물 배선 완료(`assets/bgm/`·`assets/sfx/`, BgmPlayer 크로스페이드 + SfxPlayer 풀링)
- Web Export: GitHub Pages 자동 배포로 확정(itch.io 대신). 절차는 [`../DEPLOY.md`](../DEPLOY.md)

### Phase 10 이후: 본편 확장 (진행 중)
5막 재구조화 · 기믹 맵 프리미티브 · 라이벌 VEIL(거짓 렌더·14장 보스 2막) · 다회차 지원 3축 ·
관측 프레임 정사. 진행 상태는 [`design/backlog.md`](design/backlog.md)가 단일 소스.

---

## 12. 주의사항

- **Physics interpolation 활성**: `project.godot` `[physics] common/physics_interpolation=true`. 60Hz 물리 + 고주사율 모니터에서 카메라 smoothing과 함께 떨리는 현상을 방지. Godot가 노드 transform을 물리 틱 사이에서 lerp.
- **한글 폰트**: Web Export에서 한글 깨짐 주의. `res://assets/fonts/Pretendard-Regular.otf`를 번들해
  `gui/theme/custom_font`로 등록해 둔 상태.
- **Web Export**: Threads Support를 끈 프리셋("Web")으로 빌드해 GitHub Pages에 배포한다(SharedArrayBuffer
  헤더 요구를 피하는 구성). 절차는 [`../DEPLOY.md`](../DEPLOY.md).
- **배경**: 비트맵 배경을 쓰지 않는다. 맵마다 `Stage.gd`의 `_ambience_*`가 코드로 시그니처 배경을 그린다
  (새 맵을 만들면 배경도 한 세트로 만든다).
- **결말 D 정적**: 10초 정적은 의도된 연출. 스킵 불가.
- **VEIL 대사 emdash 금지**: `·`(emdash)로 망설임을 표현하면 너무 AI 같은 인상을 준다. 콤마/마침표 또는 자연스러운 어순으로 풀 것. UI 구분자(`[ SPACE · 계속 ]`)나 코드 주석은 무관.
- **add_xp 다중 레벨업**: 현재 한 호출당 한 레벨만 처리. risk max 3 + 부가 2 = 5라 안전. 지급을 5+로 올리면 while 루프 처리 필요.
- **연습장 모드 진입 흐름**: Settings의 디버그 탭 → "연습장으로 진입" → `playground_active=true` + 기본 설정 → STAGE 씬 전환. Stage._ready가 플래그 보고 `PlaygroundOverlay` 부착. 종료 버튼은 `playground_active=false` + `reset()` + Title.

---

## 13. 레퍼런스 요약

| 요소 | 레퍼런스 |
|------|----------|
| 전투+탐험 밀도 | Tunic |
| 루트 선택 맵 | Slay the Spire |
| 파트너 구도 | 007 현장요원+상황실 |
| 그래픽 톤 | Limbo / Inside |
| 로그라이트 빌드 | Vampire Survivors |
