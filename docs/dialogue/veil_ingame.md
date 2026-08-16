# Eyes on You 대사집 · 인게임 VEIL 자막

> KO는 코드 문자열 원문 그대로(한 글자도 수정 금지 · i18n 원문 보존). 코드가 진실이며,
> 코드에서 대사를 바꾸면 이 파일도 같은 커밋에서 갱신한다. EN은 번역 세션에서 채운다.
> 앵커는 `파일.gd` 함수/상수명 기준(라인 번호 금지).

수록 범위: 스테이지 플레이 중 뜨는 VEIL 자막(진입·문턱·시야·경고·특별 개체·막3 보스전)과
그 주변 시스템 문구. 14-1 라이벌 보스전 → `rival.md` / 브리핑·루트 코멘트 → `briefing_routes.md` /
??? 방·회수 문서·서버 로그 → `story_docs.md` / 사망·튜토리얼·도전방·HUD 라벨 → `ui.md`.

---

## 1. 막 진입 · 문턱

### 막 진입 문턱 멘트 → briefing_routes.md §3 수록
- `VeilDialogue.gd` `ACT_ENTRY_BY_BAND`는 Briefing 화면에서 출력되므로(`Briefing.gd`가
  브리핑 앞에 1줄 끼움) 원문은 `briefing_routes.md` §3에만 둔다(중복 수록 금지).

### 막 이름 (막 진입 카드 "ACT N · 이름") → ui.md 수록
- `GameState.gd` `ACTS`의 막 이름 5종(침투/잠입/핵심부/추적/대면)은 시스템 라벨이라
  원문은 `ui.md`에만 둔다.

### 중간 관문 접근 힌트 (페이싱 확장, 맵당 1회)
- 화자: VEIL · 코드: `Stage.gd` `_tick_mid_gate`
- 맥락: mid_gate 있는 맵에서 관문 520px 이내 첫 접근 시 모드별 1회.

| 모드 | KO | EN |
|---|---|---|
| lever | 격벽이 잠겨 있어요. 근처 동력 레버를 찾으세요. | |
| clear | 잠긴 게이트입니다. 이 구역 경비를 정리해야 열려요. | |
| beam | 게이트가 스캔 빔에 동기돼 있어요. 빔이 지나갈 때 뒤따라 통과하세요. | |

### 런 첫 드론 반응 (막1→막2 문턱, 런당 1회)
- 화자: VEIL · 맥락: 런에서 드론이 처음 배치된 맵 진입 5.2초 뒤 · 코드: `Stage.gd` `_drone_intro_line`

| 밴드 | KO | EN |
|---|---|---|
| cold | 상공에 부유 유닛. 드론입니다. 머리 위가 사선입니다. 이제 위도 보십시오. | |
| thaw | 저거 봐요, 드론이에요. 머리 위를 봐요. ...이제 기계도 우릴 봐요. | |
| warm | 저거... 드론이에요. 머리 위에서 떨어뜨려요. 이제 위도 같이 봐요. | |

#### 격리 병동 봉인 복선
- 화자: VEIL
- 맥락: route_ward(격리 병동) 진입 직후 x=900 통과 시 1회. ??? 맵 복선.
- 코드: `Stage.gd` `_on_ward_foreshadow_zone`
- KO:
  > 이 구역은 오래됐어요. 누가 봉인했는지 저도 몰라요.
- EN:

---

## 2. 시야 역전 · 붕괴 (막3+)

### 시야 역전 자막
- 화자: VEIL · 코드: `Stage.gd` `_act3_vision_line`
- 맥락: 막3 시야 붕괴 아크. 점증 2단(마지막 스테이지 직전까지 / 마지막 스테이지). 스토리·일반 모드 공용 문자열.

| 단계 | KO | EN |
|---|---|---|
| 역전 시작 | 또 시작이네요. 심장부에 드니 시야가 다시 죽습니다. 전처럼, 안 보이는 쪽은 요원이 봐 줘요. | |
| 클라이맥스(최종 스테이지) | 여기는... 저도 안 보여요. 이제 요원이 봐요. 저는 들을게요. | |

### 붕괴 상태 진입 맵의 위험 경고
- 화자: VEIL · 코드: `Stage.gd` `_arm_degraded_hazard_warning`
- 맥락: 이미 시야가 붕괴된 상태로 함정/둥지 저격 맵에 들어오면 진입 6초 뒤 1회.

| 조건 | KO | EN |
|---|---|---|
| 함정 있음 | 여기, 제가 잘 못 봐요. 함정이 있어도 못 짚어줄 수 있어요. 직접 살펴요. | |
| 둥지 저격만 있음 | 여기, 제가 잘 못 봐요. 매복이 있어도 못 짚어줄 수 있어요. 직접 살펴요. | |

---

## 3. 위협 콜아웃 (VeilSight)

### 재밍 필드 첫 진입 반응 (맵당 1회)
- 화자: VEIL · 코드: `VeilSight.gd` `_scan_for_jam`

| 밴드 | KO | EN |
|---|---|---|
| warm | 여기... 제 시야가 안 닿아요. 뭔가가 가로막고 있어요. 조심해요. | |
| 그 외 | 이 구역, 시야가 차단됩니다. 무언가 개입하고 있습니다. 직접 확인하십시오. | |

### 화면 밖 위협 콜 (마킹 소개 = 런당 1회, 이후 방향 콜)
- 화자: VEIL · 코드: `VeilSight.gd` `_call_threat`
- 맥락: 화면 밖 새 위협 감지 시. `{방향}` 자리는 `_direction_word` 결과가 연결됨.

| 조건 | KO | EN |
|---|---|---|
| 소개(warm) | 위험한 건 제가 먼저 볼게요. 화면 끝에 띄워둘게요. 요원은 앞만 봐요. | |
| 소개(그 외) | 위험한 건 제가 먼저 확인하겠습니다. 화면 끝에 띄워둘 테니, 요원은 전방만 보십시오. | |
| 붕괴 상태 | {방향} 어딘가... 저도 잘 안 보여요. 직접 살펴요. | |
| cold | {방향}, 표시하겠습니다. | |
| 기본(thaw/warm) | {방향}, 표시해 둘게요. | |

### 방향어 (콜에 연결되는 8방위 + 근접)
- 화자: VEIL(문장 조각) · 코드: `VeilSight.gd` `_direction_word`

| 방위 | KO | EN |
|---|---|---|
| 근접 | 가까이 | |
| 우 | 오른쪽 | |
| 우하 | 오른쪽 아래 | |
| 하 | 아래쪽 | |
| 좌하 | 왼쪽 아래 | |
| 좌 | 왼쪽 | |
| 좌상 | 왼쪽 위 | |
| 상 | 위쪽 | |
| 우상 | 오른쪽 위 | |

---

## 4. 함정 · 포탑 · 저격 경고

### 발사 포탑 첫 접근 (런당 2회 제한)
- 화자: VEIL · 코드: `Stage.gd` `_tick_trap_warning`

| 조건 | KO | EN |
|---|---|---|
| 시야 붕괴 후 | 앞에 함정이 있는 것 같아요. 잘 안 보여요. 발밑·천장 조심해요. | |
| 평시 | 저 포탑은 파괴할 수 없습니다. 발사 간격을 읽고 통과하십시오. | |

### 둥지 저격수(회피 전용) 접근
- 화자: VEIL · 코드: `Stage.gd` `_tick_avoid_warning`

| 조건 | KO | EN |
|---|---|---|
| 시야 붕괴 후 | 저 위 저격수... 잘 안 보여요. 사선만 피하든지, 글라이드로 덮쳐요. | |
| 평시 | 저 저격수, 정면으론 안 닿아요. 사선 피해 가거나 글라이드로 위에서 덮쳐요. | |

---

## 5. 잠긴 문 · 레버 · 해치

#### 잠긴 문 접근 (server_hall 숨은 문)
- 화자: VEIL
- 맥락: 잠긴 문에 처음 다가갈 때. 임무 밖 공간의 존재 암시.
- 코드: `Stage.gd` `_on_locked_door_approached`
- KO:
  > 그쪽은 임무 범위 밖이에요.
  > 그 문, 도면에는 없어요.
- EN:

#### 잠긴 문 해제 (레버)
- 화자: VEIL
- 맥락: server_hall 숨은 레버를 당겨 문이 풀렸을 때.
- 코드: `Stage.gd` `_on_arcturus_lever_pulled`
- KO:
  > 뭔가 풀렸어요. 잠긴 문 앞 발판 위로.
- EN:

#### 데이터센터 비밀 (가시 전원 차단)
- 화자: VEIL
- 맥락: datacenter 숨은 장치 작동 시. 바닥 가시가 무력화됨.
- 코드: `Stage.gd` `_build_datacenter_secret`
- KO:
  > 전기가 끊겼어요. 발 밑 가시 무력화.
- EN:

#### 뒷골목 비밀 해치 (첫 레버 튜토리얼)
- 화자: VEIL
- 맥락: back_alley 레버로 잠긴 칸이 열렸을 때. 무엇이 어디에 열렸는지 방향 안내.
- 코드: `Stage.gd` `_build_back_alley_secret`
- KO:
  > 잠긴 칸이 열렸어요. 바로 앞, 위로 올라가 봐요.
- EN:

#### 냉각 시설 비밀 칸
- 화자: VEIL
- 맥락: cooling 숨은 칸 개방 시.
- 코드: `Stage.gd` `_build_cooling_secret`
- KO:
  > 여기도 잠긴 칸이었네요. 발밑 보급품을 챙겨요.
- EN:

---

## 6. 특별 개체 · 이스터에그

### 첫 조우 한마디 (각 런당 1회)
- 화자: VEIL · 코드: `Enemy.gd` `_check_first_encounter`

| 대상 | KO | EN |
|---|---|---|
| 황금(shiny) 개체 | 미확인 개체 포착. 데이터베이스에 없는 사양입니다. 회수 가치가 높습니다. | |
| 엘리트 | 저 계급장은 시설 편제에 없습니다. 외부 신호 수신 중. 교전에 주의하십시오. | |

#### 엘리트 방패병 폭발 무효 목격 (런당 1회)
- 화자: VEIL
- 맥락: 엘리트 방패병에게 폭발 피해가 무효 처리된 것을 처음 봤을 때.
- 코드: `Enemy.gd` `take_damage`
- KO:
  > 폭발 피해 무효 확인. 저 방패병은 측면과 후방 사격만 유효합니다.
- EN:

#### 폭발 무효 판정 라벨
- 화자: 시스템(전장 라벨) · 맥락: 무효 판정 시 몸 위로 떠오르는 짧은 라벨.
- 코드: `Enemy.gd` `_show_explosion_immune_flash`
- KO:
  > 무효
- EN:

#### 황금 개체 토스트
- 화자: 시스템(전장 라벨) · 맥락: 황금 개체 처치 지점 위 표시.
- 코드: `Stage.gd` `_show_shiny_toast`
- KO:
  > 황금 개체
- EN:

#### 코나미 스킨 해금 (황금 3처치)
- 화자: VEIL
- 맥락: 한 세이브에서 황금 개체를 3번 처치했을 때. 숨겨진 색(스킨) 해금 통보.
- 코드: `Stage.gd` `_reward_shiny_kill`
- KO:
  > 황금을 세 번 알아봤어요. 숨겨둔 색을 드릴게요.
- EN:

#### 평화주의 클리어 인정 (런당 1회)
- 화자: VEIL
- 맥락: 적이 있는 통과형 맵을 한 발도 안 쏘고 클리어했을 때.
- 코드: `Stage.gd` `_begin_clear_sequence` (`_check_pacifist_clear`)
- KO:
  > 한 발도 안 쏘고 지나왔네요. 그것도 하나의 답이겠죠.
- EN:

---

## 7. 막3 보스전 (SENTINEL) 자막

> SENTINEL 처치 직후의 라이벌 첫 발화·내 VEIL 동요(`_play_sentinel_reveal`)는 `rival.md` 수록.

### 보스 인트로 경보
- 화자: 시설 경보(시스템) · 코드: `Stage.gd` `_run_boss_intro_beats` (`_show_boss_alert`)

| 순서 | KO | EN |
|---|---|---|
| 1 | 침입자 식별. 회수 권한: 없음. | |
| 2 | 격리 프로토콜 SENTINEL, 기동. | |
| 3 (SENTINEL 발화) | 제거를 시작한다. | |

#### 보스 인트로 VEIL 한마디
- 화자: VEIL
- 맥락: 인트로 경보 사이. 상대의 체급과 대응법(빨간 신호 틈에 사격)을 짚음.
- 코드: `Stage.gd` `_run_boss_intro_beats`
- KO:
  > 상대가 커요. 그래도 눈은 제가 돼 드릴게요. 빨간 신호가 멎은 틈에 쏴요.
- EN:

#### 보스전 첫 안내 (경보 배너 채널)
- 화자: VEIL(보스 경보 배너로 표시)
- 맥락: SENTINEL 보스 스폰 시 조작 안내.
- 코드: `Stage.gd` `_spawn_boss`
- KO:
  > 빨간 불빛이 번뜩이면 그 자리를 비켜요. 신호가 멎은 틈에 쏘면 돼요.
- EN:

### 페이즈 전환 경보
- 화자: VEIL(보스 경보 배너) · 코드: `Stage.gd` `_on_boss_phase_changed`

| 페이즈 | KO | EN |
|---|---|---|
| 2 | 패턴이 바뀌었어요. 양쪽 조심해요. | |
| 3 | 불안정해졌어요. 거리 두고 빠르게. | |

#### 자폭 회피 안내 라벨 (분류 확인 필요: HUD 라벨이라 ui.md 이동 후보)
- 화자: 시스템(HUD 라벨) · 맥락: 보스 자폭 시퀀스 중 회피 반경 안내.
- 코드: `Stage.gd` `_on_boss_self_destruct_started`
- KO:
  > 노란 원 밖으로 멀어져요
- EN:

---

## 부록. 환경 라벨(배경 로어) (단일 수록처 = 이 표. 번역 대상 여부는 번역 세션에서 결정)

- 화자: 없음(배경 표지판·로어 라벨) · 코드: `Stage.gd` 각 `_ambience_*` 함수(`_add_lore_label`),
  `DefenseCore.gd` `_ready`(코어 태그). 맵 배경에 그려지는 안내판 문구.

| 앵커 | KO | EN |
|---|---|---|
| `_ambience_garage_props` | B2 · 주차 구역 | |
| `_ambience_pump_station` (기본값) | 배수 펌프 · B2 | |
| `_build_route_ambience` (pump 호출 변형) | 응축기 구역 · 냉각수 | |
| `_build_route_ambience` (electrical 호출) | 고압 위험 · 변전 구역 | |
| `_build_route_ambience` (electrical 호출) | 통신 중계 · 안테나 정렬 | |
| `_build_route_ambience` (warehouse 호출) | 물류 창고 · 구역 D | |
| `_build_route_ambience` (warehouse 호출) | 화물 구역 · 리프트 | |
| `_ambience_server_hall` | 서버 랙 · 코어 접근 | |
| `_ambience_control_room` | 통제실 · 감시망 | |
| `_ambience_checkpoint` | 보안 검문 · 신원 확인 | |
| `_ambience_demolition` | 철거 구역 · 접근 주의 | |
| `_ambience_testing` | 실험 구역 · 관측 | |
| `_ambience_gauntlet` | 함정 통로 · 경고 | |
| `_ambience_collapse` | 붕괴 진행 · 대피 | |
| `_ambience_collapse_shaft` | 격리 구획 승강로 · B7 | |
| `_ambience_collapse_shaft` | 지상 방면 ↑ | |
| `_ambience_collapse_mezz` | 중층 정비 통로 · B2 | |
| `_ambience_collapse_mezz` | 지상 출구 → | |
| `_ambience_scanner` | 보안 스캔 · 감시 활성 | |
| `_ambience_reactor` | 반응로 제어실 · 코어 방어 | |
| `_ambience_holdout` | 통제 구역 봉쇄 · 저지선 | |
| `_ambience_core_recovery` | 최심부 · 코어 격납 구역 | |
| `_ambience_back_alley` | PROJECT VEIL⏎시험 단계 | |
| `_ambience_subway_platform` | SILO-7  접근 통로⏎폐쇄: 2025.11 | |
| `_ambience_subway_platform` | 선로 방면 → | |
| `_ambience_subway_tracks` | 선로 진입 금지 · 무인 운행 중 | |
| `_ambience_subway_tracks` | MAINTENANCE ONLY⏎ARCTURUS 발주 | |
| `_ambience_subway_transfer` | 환승 → 지상 | |
| `_ambience_subway_transfer` | 개찰 구역 · 통행 기록 없음 | |
| `DefenseCore.gd` 코어 태그 | 코어 | |

(⏎ = 원문 개행. 표 안이라 기호로 표기 · 원문에는 실제 줄바꿈.)

---

## 수록 대조 (이 파일 몫)

| 소스 | 수록 문자열 수 |
|---|---|
| `VeilDialogue.gd` | 0 (막 문턱 멘트는 briefing_routes.md §3) |
| `GameState.gd` | 0 (막 이름은 ui.md) |
| `Stage.gd` (자막·라벨) | 29 |
| `Stage.gd` (환경 라벨 부록) | 29 |
| `VeilSight.gd` | 16 |
| `Enemy.gd` | 4 |
| `DefenseCore.gd` | 1 |
| 합계 | 88 |
