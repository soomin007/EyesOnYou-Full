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
- 어투 밴드 스윕(2026-08-21): 기본 = 중립 보고체, `· warm` 행 = warm 밴드 변형(`VeilDialogue.banded`).

| 모드 | KO | EN |
|---|---|---|
| lever | 게이트가 잠겨 있습니다. 근처 동력 레버를 찾으십시오. | |
| lever · warm | 게이트가 잠겨 있어요. 근처 동력 레버를 찾으세요. | |
| clear | 잠긴 게이트입니다. 바닥에 노란 선으로 칠한 구역, 그 안의 경비만 정리하면 열립니다. | |
| clear · warm | 잠긴 게이트예요. 바닥에 노란 선으로 칠해 둔 구역, 그 안의 경비만 정리하면 열려요. | |
| 정찰 발동(`Stage._ready`) | 정찰 데이터를 반영했습니다. 이 구간의 숨겨진 레버와 보급품, 청색 표식으로 짚어 두겠습니다. | |
| 정찰 발동 · warm | 정찰 데이터 반영했어요. 숨겨진 레버랑 보급품, 청색으로 짚어 둘게요. | |
| lab 위장 자폭 재기동(`_on_boss_self_destruct_disarmed`) | ...자폭은 위장입니다. 코어가 다시 점화됩니다. 침착하게, 마무리하십시오. | |
| lab 위장 자폭 재기동 · warm | ...자폭이 위장이에요. 코어가 다시 점화됩니다. 침착하게, 마무리하세요. | |
| lab 첫 과부하 배기(`_on_boss_vent_started`) | 김을 빼는 동안엔 총알이 안 박힙니다. 대신 쏠수록 배출이 빨라집니다. 그 사이 증원부터 정리하십시오. | |
| lab 첫 과부하 배기 · warm | 김을 빼는 동안엔 총알이 안 박힙니다. 대신 쏠수록 배출이 빨라져요. 그 사이 증원도 정리하고요. | |
| 14-1 P2 노드 재접속(`_on_p2_node_down`) | ...같은 자리에 회선이 다시 붙습니다. 한 번 더 끊어야 합니다. | |
| 14-1 P3 캠핑 감지(`_tick_p3_camp`, 1회) | 한자리에 오래 서 있으면 조준이 고정됩니다. 계속 움직이십시오. | |
| 14-1 P3 그림 격파(`_on_p3_fake_torn`, 1회 · 2026-08-22) | 저 가짜들은 저쪽이 직접 그리는 그림입니다. 다시 그리는 속도보다 빨리 찢으면, 저놈도 그림인 채로는 못 버팁니다. | Those fakes are its own renders. Tear them faster than it can redraw, and it can't stay a picture either. |
| beam | 게이트는 스캔 빔이 지날 때만 열립니다. 빔 뒤에 붙어 통과하십시오. | |
| beam · warm | 게이트는 스캔 빔이 지나갈 때만 열려요. 빔을 뒤따라 통과하세요. | |

### 대피 칸 숨기 티칭 (대피 칸 첫 진입, 맵당 1회 · 2026-08-23 능동 숨기)
- 화자: VEIL · 코드: `Stage.gd` `_tick_hide_zone`

| 밴드 | KO | EN |
|---|---|---|
| 공용 | 칠해진 칸 안쪽은 몸을 숨길 만큼 깊습니다. 칸 안에서 아래 키를 꾹 누르십시오. | That recess is deep enough to hide in. Hold Down inside the marked bay. |

### 감시등 경보 (감시탑 탐조등·순찰로 경계등 공용, 맵당 1회)
- 화자: VEIL · 맥락: 감시등 노출 0.45s 누적 → 경보 첫 발동 시. 진압 경비(추격 방패병) = 무보상 고지 포함 · 코드: `Stage.gd` `_on_searchlight_alert`

| 밴드 | KO | EN |
|---|---|---|
| 기본 | 감시등 노출. 진압 경비가 붙습니다. 잡아도 남는 게 없으니, 빛부터 피하십시오. | |
| warm | 감시등에 걸렸어요. 진압 경비가 붙어요. 잡아도 남는 건 없으니, 빛부터 피해요. | |

### 런 첫 드론 반응 (막1→막2 문턱, 런당 1회)
- 화자: VEIL · 맥락: 런에서 드론이 처음 배치된 맵 진입 5.2초 뒤 · 코드: `Stage.gd` `_drone_intro_line`

| 밴드 | KO | EN |
|---|---|---|
| cold | 머리 위에 드론입니다. 폭탄을 떨어뜨립니다. 위쪽을 경계하십시오. | Drone overhead. It drops bombs. Watch the sky. |
| thaw | 드론입니다. 폭탄을 머리 위에 떨어뜨립니다. 위쪽도 확인하십시오. | That's a drone. It drops bombs from overhead. Check above you as well. |
| warm | 드론이에요. 폭탄을 머리 위에 떨어뜨립니다. 위쪽도 챙기세요. | Drone overhead. It drops bombs, so keep an eye above you too. |

#### 격리 병동 봉인 복선
- 화자: VEIL
- 맥락: route_ward(격리 병동) 진입 직후 x=900 통과 시 1회. ??? 맵 복선.
- 코드: `Stage.gd` `_on_ward_foreshadow_zone`
- KO(기본):
  > 오래된 구역입니다. 누가 봉인했는지, 기록에 없습니다.
- KO(warm):
  > 이 구역은 오래됐어요. 누가 봉인했는지 저도 몰라요.
- EN:

---

## 2. 시야 역전 · 붕괴 (막3+)

### 시야 역전 자막
- 화자: VEIL · 코드: `Stage.gd` `_act3_vision_line`
- 맥락: 막3 시야 붕괴 아크. 점증 2단(마지막 스테이지 직전까지 / 마지막 스테이지). 스토리·일반 모드 공용 문자열.
- 어투 밴드 스윕(2026-08-21): 기본 = 중립 보고체, warm 변형 병기. 스토리 전용 2줄도 동일 구조.

| 단계 | KO | EN |
|---|---|---|
| 역전 시작 | 또 시작입니다. 심장부에 드니 시야가 다시 죽습니다. 전처럼, 안 보이는 쪽은 요원 몫입니다. | |
| 역전 시작 · warm | 또 시작이네요. 심장부에 드니 시야가 다시 죽습니다. 전처럼, 안 보이는 쪽은 요원이 봐 줘요. | |
| 클라이맥스(최종 스테이지) | 여기는... 저도 안 보입니다. 이제 요원이 보십시오. 저는 듣겠습니다. | |
| 클라이맥스 · warm | 여기는... 저도 안 보여요. 이제 요원이 봐요. 저는 들을게요. | |
| 스토리 · 역전 시작 | 여기서부터는 잘 안 보입니다. 이제 요원이 제 눈입니다. | |
| 스토리 · 역전 시작 · warm | 여기서부터는 잘 안 보여요. 이제 요원이 제 눈이 돼 줘요. | |

### 붕괴 상태 진입 맵의 위험 경고
- 화자: VEIL · 코드: `Stage.gd` `_arm_degraded_hazard_warning`
- 맥락: 이미 시야가 붕괴된 상태로 함정/둥지 저격 맵에 들어오면 진입 6초 뒤 1회.

| 조건 | KO | EN |
|---|---|---|
| 함정 있음 | 여기는 제 시야가 흐립니다. 함정이 있어도 못 짚어줄 수 있습니다. 직접 살피십시오. | |
| 함정 있음 · warm | 여기, 제가 잘 못 봐요. 함정이 있어도 못 짚어줄 수 있어요. 직접 살펴요. | |
| 둥지 저격만 있음 | 여기는 제 시야가 흐립니다. 매복이 있어도 못 짚어줄 수 있습니다. 직접 살피십시오. | |
| 둥지 저격만 · warm | 여기, 제가 잘 못 봐요. 매복이 있어도 못 짚어줄 수 있어요. 직접 살펴요. | |

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
| 붕괴 상태(warm) | {방향} 어딘가... 저도 잘 안 보여요. 직접 살펴요. | |
| 붕괴 상태(그 외) | {방향} 어딘가... 저도 잘 안 보입니다. 직접 살피십시오. | |
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
| 시야 붕괴 후 | 전방에 함정 신호. 확신이 없습니다. 발밑과 천장을 직접 살피십시오. | |
| 평시 | 저 포탑은 파괴할 수 없습니다. 발사 간격을 읽고 통과하십시오. | |

### 둥지 저격수(회피 전용) 접근
- 화자: VEIL · 코드: `Stage.gd` `_tick_avoid_warning`

| 조건 | KO | EN |
|---|---|---|
| 시야 붕괴 후 | 저 위 저격수, 제 쪽에선 흐릿합니다. 조준선을 피하거나, 글라이드로 위에서 덮치십시오. | |
| 평시 | 저 저격수는 정면으로 안 닿습니다. 조준선을 피해 가거나, 글라이드로 위에서 덮치십시오. | |

---

## 5. 잠긴 문 · 레버 · 해치

#### 잠긴 문 접근 (server_hall 숨은 문)
- 화자: VEIL
- 맥락: 잠긴 문에 처음 다가갈 때. 임무 밖 공간의 존재 암시.
- 코드: `Stage.gd` `_on_locked_door_approached`
- KO(기본):
  > 그쪽은 임무 범위 밖입니다.
  > 그 문, 도면에 없습니다.
- KO(warm):
  > 그쪽은 임무 범위 밖이에요.
  > 그 문, 도면에는 없어요.
- EN:

#### 잠긴 문 해제 (레버)
- 화자: VEIL
- 맥락: server_hall 숨은 레버를 당겨 문이 풀렸을 때.
- 코드: `Stage.gd` `_on_arcturus_lever_pulled`
- KO(기본):
  > 잠금 하나가 풀렸습니다. 잠긴 문 앞, 발판 위입니다.
- KO(warm):
  > 뭔가 풀렸어요. 잠긴 문 앞 발판 위로.
- EN:

#### 데이터센터 비밀 (가시 전원 차단)
- 화자: VEIL
- 맥락: datacenter 숨은 장치 작동 시. 바닥 가시가 무력화됨.
- 코드: `Stage.gd` `_build_datacenter_secret`
- KO(기본):
  > 전원 차단 확인. 발밑 가시 무력화.
- KO(warm):
  > 전기가 끊겼어요. 발 밑 가시 무력화.
- EN:

#### 뒷골목 비밀 해치 (첫 레버 튜토리얼)
- 화자: VEIL
- 맥락: back_alley 레버로 잠긴 칸이 열렸을 때. 무엇이 어디에 열렸는지 방향 안내.
- 코드: `Stage.gd` `_build_back_alley_secret`
- KO:
  > 잠긴 칸이 열렸습니다. 바로 앞, 위로 올라가 보십시오.
- EN:
- 비고: 막1 전용(첫 레버 튜토리얼)이라 warm 도달 불가 — 중립 단일.

#### 냉각 시설 비밀 칸
- 화자: VEIL
- 맥락: cooling 숨은 칸 개방 시.
- 코드: `Stage.gd` `_build_cooling_secret`
- KO(기본):
  > 여기도 잠긴 칸이었습니다. 발밑 보급품을 챙기십시오.
- KO(warm):
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
- KO(기본):
  > 황금 개체, 세 번째 확인입니다. 보관해 둔 색을 하나 드리겠습니다.
- KO(warm):
  > 황금을 세 번 알아봤네요. 숨겨둔 색을 드릴게요.
- EN:

#### 평화주의 클리어 인정 (런당 1회)
- 화자: VEIL
- 맥락: 적이 있는 통과형 맵을 한 발도 안 쏘고 클리어했을 때.
- 코드: `Stage.gd` `_begin_clear_sequence` (`_check_pacifist_clear`)
- KO(기본):
  > 한 발도 쏘지 않으셨군요. 그런 답도 있습니다.
- KO(warm):
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
- KO(기본):
  > 상대가 큽니다. 눈은 제가 맡습니다. 빨간 신호가 멎은 틈에 쏘십시오.
- KO(warm):
  > 상대가 커요. 그래도 눈은 제가 돼 드릴게요. 빨간 신호가 멎은 틈에 쏴요.
- EN:

#### 보스전 첫 안내 (경보 배너 채널)
- 화자: VEIL(보스 경보 배너로 표시)
- 맥락: SENTINEL 보스 스폰 시 조작 안내.
- 코드: `Stage.gd` `_spawn_boss`
- KO:
  > 빨간 불빛이 번뜩이면 그 자리를 비키십시오. 신호가 멎은 틈이 사격 타이밍입니다.
- EN:
- 비고: 전투 콜아웃 = 밴드 무관 보고체 단문(어투 규약 §6).

### 페이즈 전환 경보
- 화자: VEIL(보스 경보 배너) · 코드: `Stage.gd` `_on_boss_phase_changed`
- 리워크(2026-08-22): P2 = 시설 소환 고지로 교체 + 소환 직후 VEIL 학습 회수 자막 1회.

| 페이즈 | KO | EN |
|---|---|---|
| 2 | 격납 개방. 시설 설비가 전투에 개입합니다. | |
| 3 | 코어가 불안정합니다. 거리 두고, 빠르게. | |

#### P2 시설 소환 자막 (`_summon_facility_hazards`, 1회)
| 밴드 | KO | EN |
|---|---|---|
| 기본 | 증기와 방전, 지나온 설비들입니다. 리듬은 이미 배우셨습니다. 위쪽 발판의 방전을 조심하십시오. | |
| warm | 증기랑 방전, 지나온 설비들이죠. 리듬은 이미 몸에 익었을 겁니다. 위쪽 발판의 방전만 조심해요. | |

> 2026-08-25 리워크 §8: 방전 아크가 지면→정비 데크 1단 위로 이동("바닥 함정 무의미" 지적) —
> 마지막 문장을 배치와 일치하게 재작성.

#### 카운터플레이 티칭 자막 (`_summon_facility_hazards` +6.2s, 1회 · 2026-08-22)
| 밴드 | KO | EN |
|---|---|---|
| 기본 | 저 기계는 열에 약합니다. 증기 기둥 위로 몰아넣으면 잠깐 멈춥니다. | That machine runs hot. Herd it over a steam column and it will stop for a moment. |
| warm | 저 기계, 열에 약해요. 증기 기둥 위로 몰아넣으면 잠깐 멈춥니다. | |

#### 첫 과열 실속 자막 (`_on_boss_overheat_stalled`, 1회 · 2026-08-22)
| 밴드 | KO | EN |
|---|---|---|
| 기본 | 증기를 그대로 뒤집어썼습니다. 과열로 제어를 잃었습니다. 지금은 쏘는 만큼 전부 박힙니다. | It took the steam head-on. Overheated, control's gone. Right now every shot goes in clean. |
| warm | 증기를 제대로 먹였습니다. 과열로 제어를 잃었어요. 지금은 쏘는 만큼 전부 박힙니다. | |

#### 자폭 회피 안내 라벨 (분류 확인 필요: HUD 라벨이라 ui.md 이동 후보)
- 화자: 시스템(HUD 라벨) · 맥락: 보스 자폭 시퀀스 중 회피 반경 안내.
- 코드: `Stage.gd` `_on_boss_self_destruct_started`
- KO:
  > 노란 원 밖으로 멀어져요
- EN:

## 8. 도전방(블랙아웃 런) VEIL 자막

- 화자: VEIL · 코드: `Stage.gd` (앵커는 행별 표기) · 시스템 문구는 ui.md §10.
- 2026-08-21 어투 스윕에서 수록 누락 발견분 등재.

| 앵커 | KO | EN |
|---|---|---|
| 진입 안내(`_show_challenge_briefing`) | 이 안은 통신이 끊깁니다. 발판을 밟으면 시작입니다.⏎한 대만 맞아도 끝. | |
| 실패 위로 | 괜찮습니다. 다음 구역으로 갑니다. | |
| 실패 위로 · warm | 괜찮아요. 다음 구역으로 가요. | |
| 클리어 인정 | 도전 완수 확인. 교신도 없이 해내셨습니다. | |
| 클리어 인정 · warm | 혼자 해냈네요, 요원. | |

---

## 8.5 클리어 수행 보고 (무피격·전원 처치 보너스, 2026-08-23)

- 화자: VEIL · 코드: `Stage.gd` `_begin_clear_sequence`(토스트 뒤) · 3스테이지 간격 도배 방지.
- 상황: 스테이지 클리어 직후. 무피격(그 구역 피격 0) 또는 전원 처치(경비 전원 직접 처치 ·
  환경 처치 제외) 시 +150점 토스트와 함께 1줄.

| 조건 | KO | EN |
|---|---|---|
| 무피격 | 피격 0. 이 구간, 깨끗하게 지나셨습니다. | Zero hits taken. Clean pass on this section. |
| 무피격 · warm | 피격 0이에요. 이 구간, 깨끗하게 지나셨네요. | |
| 전원 처치 | 구역 경비, 전원 처치 확인했습니다. 이제 뒤는 조용합니다. | All area guards confirmed down. Nothing behind us now. |
| 전원 처치 · warm | 구역 경비까지 전부 정리하셨네요. 이제 뒤는 조용해요. | |

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
| `_ambience_demo_yard` | 파쇄 마당 · 중장비 작동 중 | |
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
| `_ambience_core_arena` | 코어 관제홀 · 최상위 권한 구역 | |
| `_ambience_core_arena` | OBSERVATION DECK | |
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
| `Stage.gd` (환경 라벨 부록) | 30 |
| `VeilSight.gd` | 16 |
| `Enemy.gd` | 4 |
| `DefenseCore.gd` | 1 |
| 합계 | 88 |
