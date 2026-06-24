# Eyes on You

> **"AI 파트너 VEIL과 함께 7개 임무를 해치우는 횡스크롤 로그라이트. 마지막에 VEIL이 누구였는지가 드러난다."**

### ▶ [브라우저에서 바로 플레이](https://soomin007.github.io/EyesOnYou/)

> GitHub Pages 자동 배포 (main 푸시 시 갱신). 데스크톱 Chrome/Firefox 권장. 첫 로딩 ~10s.

근미래 민간 보안기업의 현장 요원이 되어, 상황실 AI 파트너 **VEIL**의 조언을 들으며(혹은 무시하며) 7개의 짧은 횡스크롤 스테이지를 클리어한다. 누적된 선택(VEIL 추천 수용률 × 전투/우회 비율)이 4종 결말 중 하나를 결정하고, 그 과정에서 VEIL의 말투가 차갑게→따뜻하게 변한다.

- **엔진**: Godot 4.6 (GL Compatibility, physics interpolation 활성)
- **장르**: 횡스크롤 액션 어드벤처 + 로그라이트
- **플레이 시간**: 8~15분 / 1회
- **플랫폼**: 브라우저(웹, 위 링크) · 데스크톱 · 키보드 / 게임패드
- **외부 의존성**: 없음 (API/서버/계정 없음, 모든 텍스트 하드코딩)

---

## 게임 루프

```
[타이틀] ── 게임 시작 ─→ [모드 선택] ─→ [튜토리얼? 예/아니오]
                          (일반/스토리)         ↓ 예    ↓ 아니오
                                          [튜토리얼]    [브리핑]
                                              ↓
                                          [브리핑] → [루트 선택] → [횡스크롤 스테이지]
                                                          ↑              ↓ 클리어     ↓ 사망
                                                          └─ 다음 루트 ──┘   레벨업    [데스 브리핑] → 재시작
                                                                     ↓ 5/7스테이지 클리어
                                                                [결말 (4종 분기)]
```

**일반 모드**: HP 3, 7 스테이지, 보스 3페이즈, 모든 적 등장.
**스토리 모드**: HP 무제한, 5 스테이지, 보스 단순화, 드론 없음. 키보드/패드가 익숙하지 않은 사람을 위한 짧은 코스.

## 결말 분기

두 점수 축으로 4종 결말이 결정된다.

| 추천 수용률 ≥ 50% | aggression ≥ 4 | 결말 | 한 줄 |
|---|---|---|---|
| ✅ | ✅ | **A — 완벽한 도구** | VEIL의 진짜 목적이 드러난다 |
| ❌ | ✅ | **B — 혼자였던 사람** | VEIL은 의존받지 않기를 바랐다 |
| ✅ | ❌ | **C — 공생** | 유일하게 VEIL에게 직접 묻는 선택지가 열린다 |
| ❌ | ❌ | **D — 유령 임무** | 10초 정적, 임무 기록 없음 |

- **신뢰 축** = VEIL 추천을 **절반 이상 따랐는가**(`followed_count*2 ≥ rec_count`). 루트 선택 시점에 집계.
- **공격성 축** = 전투·도전 태그 맵 선택 누적(`aggression ≥ 4`).
- 별도로 **어투 trust**(0에서 climbing)가 VEIL 말투를 차갑게→따뜻하게 바꾼다 — 엔딩과는 분리(아래 "VEIL 어투 아크").

---

## VEIL 어투 아크 (신뢰 + 사망 구동)

VEIL의 **말투가 관계에 따라 변한다.** 진행도가 아니라 *신뢰*가 구동한다:

- **COLD**(격식 작전통신, `~습니다`) → **THAW**(격식+`저도` 누수) → **WARM**(`~해요`, 사적·고백).
- 신뢰는 **0에서 벌어 올린다** — 추천 따라 클리어 +2, **같이 고비 돌파**(죽고 회복·고위험·도전·히든) +2, 독립적 성공 +0.
- **취약함 게이트**: 신뢰가 높아도 *같이 고비를 넘긴 적*이 없으면 WARM에 못 든다 → **한 번도 안 죽고 VEIL을 무시한 고수는 엔딩까지 COLD**로 남는다.
- 사망/실력에 따라 안내 강도도 변한다 — 고전하면 강조·위로↑, 무사망 고수에겐 "내가 필요 없겠네" 물러섬.
- 같은 stage여도 신뢰가 낮으면 차가운 채. 튜토리얼이 "믿을수록 더 도와드릴 수 있다"로 미리 암시한다.

설계: [`docs/design/veil_trust_arc.md`](docs/design/veil_trust_arc.md) · 대사 grid: [`docs/design/veil_pool_remap.md`](docs/design/veil_pool_remap.md)

---

## 조작

| 동작 | 키보드/마우스 | Xbox 컨트롤러 |
|---|---|---|
| 좌우 이동 | A / D, ←/→ | 좌스틱 / D-Pad |
| 점프 (이중 점프) | W / Space | A |
| 아래 내려가기 | S / ↓ | ↓ (좌스틱/D-Pad) |
| 사격 | J *(마우스 좌는 설정에서 바인드)* | X 또는 RT |
| 대시 | Shift / K | B 또는 RB |
| 액티브 스킬 | Q *(마우스 우는 설정에서 바인드)* | Y |
| 일시정지 | ESC | START |
| UI 확정 | Enter / Space | A |
| UI 취소 / 뒤로 | ESC | B |
| Settings 탭 전환 | Q / E | LB / RB |

키바인드는 설정 메뉴에서 변경 가능 (키보드 + 마우스 슬롯 2개씩, 게임패드 매핑은 별도로 항상 활성화).
입력 모드(키보드/패드)는 자동 감지되어 화면 안내 텍스트가 실시간 swap.

---

## 12개 맵 + 진행 흐름 (Dead Cells 스타일)

각 맵마다 등장 가능 스테이지가 다름. Dead Cells 스타일로 매 스테이지마다 풀에서 2~3개를 추첨해 보여준다.

| 루트 | id | min~max stage | risk | reward | 태그 |
|---|---|---|---|---|---|
| 외곽 진입로 | route_back_alley | 0~1 | 1 | 1 | 우회, 어두운 |
| 외벽 옥상 | route_rooftops | 0~1 | 2 | 2 | 원거리, 노출, 이동 (vertical-up) |
| 지하 인입로 | route_sewers | 2~3 | 2 | 3 | 근접전, 함정, 전투 |
| 폐쇄 지하철 | route_subway | 1~3 | 2 | 2 | 근접전, 함정, 전투 |
| 냉각 시설 | route_cooling | 3~4 | 2 | 3 | 전투, 드론, 수직 |
| 감시탑 | route_watchtower | 1~4 | 3 | 3 | 원거리, 전투, 노출 |
| 격리 병동 | route_ward | 3~4 | 2 | 3 | 우회, 어두운, 은폐 (이스터에그 트리거) |
| 데이터 센터 | route_datacenter | 4~5 | 3 | 3 | 전투, 드론, 원거리 (ARENA, 웨이브) |
| 비상 탈출로 | route_escape | 5~6 | 1 | 2 | 우회, 은폐 |
| 핵심부 | route_lab | 5~6 | 3 | 3 | 전투, 드론, 밝은 (보스 SENTINEL) |
| 블랙아웃 런 | route_blackout | 4 | 2 | 3 | 도전, 어두운 (challenge=true, 한 대 맞으면 끝) |
| ??? | route_hidden | 5~6 | 2 | 3 | 우회, 정보 (hidden=true, ARCTURUS 아카이브) |

스토리 모드는 5개 스테이지로 압축된 고정 코스 (back_alley/rooftops → subway/watchtower → ward/sewers → lab(보스) → 최종 탈출).

- **Risk**: 1=적 수 ×0.8 / 2=×1.1 / 3=×1.5 + 적 행동 강화
- **Reward**: 클리어 시 보너스 XP (1=+1, 2=+2, 3=+3)
- 함정 태그(지하 배수로/지하철 연결로)에는 가시 자동 배치
- 각 맵마다 다른 플랫폼 layout + 환경 효과
- ??? 루트는 Stage 5~6 풀에 무작위 등장, hidden=true (VEIL 추천에서 제외) — 메타 서사. 비추천 카드라 고르면 추천 수용률이 내려가고(엔딩 B/D 쪽), 클리어 시 어투 trust(따뜻함)는 오른다

---

## 적 (5종) — 도감 자동 트리거

첫 조우 시 도감 카드가 떠서 행동/공략을 알려줌.

| 적 | 핵심 행동 | 공략 |
|---|---|---|
| 정찰병 (Patrol) | 좌우 순찰, 근접 시 텔레그래프 후 돌진 | 깜빡일 때 옆으로 회피 → 회복 중 사격 |
| 저격수 (Sniper) | 정지, 조준선 노출 후 발사 | 플랫폼/벽으로 시야 차단 시 발사 취소 |
| 공습 드론 (Strike Drone) | 머리 위 호버링 후 폭탄 투하 | 그림자 들어오면 옆 회피, 호버 중 사격 |
| 자폭병 (Bomber) | 순찰 → 감지 시 추격 → 90px 안에서 점멸 → 광역 폭발 | 멀리서 정리 / 점멸 시작하면 즉시 거리 벌리기 (HP 1) |
| 방패병 (Shield) | 정면 32px 무효, 같은 높이대 안에서 플레이어 방향 고정 | 정면 사격 막힘 → dash/점프로 측면 잡고 사격 (HP 3) |

---

## 스킬 (8 라인 × 3 티어, 3 계열)

레벨업마다 3중 1 카드. 계열은 색으로 구분(전투=주황 / 이동=하늘 / 생존=초록). 같은 라인의 다음 티어는 이전 티어 보유 시에만 후보로 등장. 일시정지·레벨업 화면에서 트리 오버레이로 전체 라인을 미리 본다.

| 계열 | 라인 | T1 → T2 → T3 |
|---|---|---|
| 전투 | 사격 강화 (fire_boost) | 데미지 +1 → 속사(연사 +40%)·사격 후 이동 가속 → 1체 관통 |
| 전투 | 다중사격 (multishot) | 삼연사(부채꼴 3) → 오연사(5) → 5발 + 약한 추적 |
| 전투 | 폭발물 (explosive, 액티브) | 광역 처치(3s) → 반경 +30%·쿨 2.5s → 2회 충전 |
| 이동 | 공중 활강 (glide) | 자동 활강(천천히 낙하) → 삼단 점프(공중 점프 +1) → 유도 사격(활강 중 사격이 적을 강하게 유도·데미지 +1) |
| 이동 | 대시 강화 (dash_boost) | 쿨 −20% → 거리 +30% → 대시 후 0.3s 무적 |
| 생존 | 체력 (hp) | 최대 HP +1 → +2·피격 후 1s 무적 → 피격 슬로모 |
| 생존 | 비상 부활 (shield) | 쓰러질 때 1회 부활(HP1) → 부활 HP2 → 30s 후 재충전(반복) |
| 생존 | 에너지 방어막 (barrier) | 10s 충전 후 1회 피격 무효 → 충전 6s 단축 → 무효 직후 0.6s 무적 |

- 베이스라인(시작 시 보유): **대시**(짧은 무적 이동), **이중점프**.
- **"비상 부활"과 "에너지 방어막"은 다른 라인** — 부활은 *쓰러질 때 되살아남*, 방어막은 *충전식 피격 1회 무효*. 화면 하단 게이지에 각각 남은 초(부활 재충전 / 방어막 충전)가 표시된다.
- **스킬↔적 상성**: 방패병→폭발물 / 저격수→방어막 / 드론→글라이드 / 자폭병→사격강화. 맵에 그 적이 있고 카운터를 아직 안 가졌으면 VEIL이 레벨업에서 콕 집어 추천(★)하고 출현 가중을 준다.

## 위협 요소 & 맵 기믹

| 기믹 | 설명 |
|---|---|
| **발사 함정** (BulletTrap) | 표면 장착 포탑, **파괴 불가**. 텔레그래프 후 주기/버스트 발사 — 타이밍·대시로 회피. subway·cooling·ward·datacenter(가로 교차)·watchtower(등반). |
| **레이저 탐지선** (LaserTripwire) | 가로지르면 떨어진 곳의 triggered 포탑이 일제 버스트. 포탑과 분리 배치라 "밟으면 다른 데서 불을 뿜는다". |
| **둥지 저격수** | rooftops·watchtower·cooling의 저격수는 메인 경로 밖 **측면 단독 둥지**(회피 전용). VEIL이 "정면으론 못 잡으니 사선 피하거나 글라이드로 덮쳐라" 안내 → 글라이드 가치와 시너지. |
| **VEIL 시야** (VeilSight) | VEIL이 화면 안팎 위협을 마킹·말로 짚어줌. ACT3에선 마킹이 흐려지고 일부는 영영 안 보임(시야 역전) + 진입 시 함정/매복 미리 경고. |
| **글라이드 게이트 보상** | 발판 위 ~220px 단독 알코브 — 더블점프(190)론 못 닿고 **삼단점프(글라이드 T2)로만**. 흡인 반경을 줄여 직접 도달해야 획득. cooling·ward. |
| **정적 가시 / 토글 가시** | "함정" 태그 맵(배수로·블랙아웃)에 자동 배치. |

---

## 프로젝트 구조

```
EoY/
├── README.md                   이 문서 (게임 소개·구조 요약)
├── CLAUDE.md                   에이전트(Claude Code) 작업 규칙
├── DEPLOY.md                   GitHub Pages 자동 배포 가이드
├── project.godot               Godot 4.6 프로젝트 설정 (AutoLoad: GameState)
├── icon.svg
├── docs/
│   ├── SPEC.md                 구현 사양 (씬 구조·시스템 도식·인게임 텍스트 인벤토리)
│   ├── STORY.md                스토리 캐논 + 게임 텍스트 (단일 진실)
│   └── design/
│       ├── backlog.md          미착수 작업 단일 소스 (다음 작업 후보 + ★추천)
│       ├── known_issues.md     반복 방지 — 버그/설계 함정 "증상→원인→방지책"
│       ├── map_audit.md        12맵 감사 (흐름·난이도·적 배치·스킬-맵 정합)
│       ├── growth_system.md    스킬 트리 3계열×3티어 + 7스테이지 확장 설계
│       ├── world_layout.md     맵 4 템플릿 + 12맵 좌표 + 보스/이스터에그 명세
│       └── show_dont_tell.md   "글로 명시 < 체험으로 체득" 톤 원칙 + 적용 후보
├── assets/
│   └── fonts/Pretendard-Regular.otf   (한글 default font, OFL)
├── scenes/                     절차적 빌드 — .tscn은 최소 트리만, Stage.gd 등이 코드로 채움
│   ├── main / title / tutorial / briefing / route_map
│   ├── stage / death / ending
│   └── settings                키바인드 + 디버그(연습장) 탭
├── scripts/
│   ├── GameState.gd            AutoLoad — 진행도/점수/스킬/루트/도감 영속
│   ├── SceneRouter.gd
│   ├── RouteData.gd            루트 풀 (id/risk/reward/tags/available_stages)
│   ├── MapData.gd              12맵 좌표 + 함정/트립와이어 + 보스/웨이브/이스터에그 메타
│   ├── SkillSystem.gd          레벨업 3중 1 카드 풀 빌더
│   ├── VeilDialogue.gd         신뢰밴드별 브리핑/사망 풀(*_BY_BAND) + 레벨업 조언
│   ├── EndingResolver.gd       추천 수용률 × aggression → 결말 결정
│   ├── Player.gd               이동/점프/대시/사격/활강/부활/방어막 등
│   ├── Enemy.gd                5종 + 가장자리 raycast + spawn snap
│   ├── BossSentinel.gd         핵심부 보스 (3페이즈 + 자폭)
│   ├── BossMissile.gd          보스 측면 미사일 (약한 유도)
│   ├── Bullet.gd / EnemyBullet.gd / Bomb.gd / ExpOrb.gd / HpOrb.gd
│   ├── BulletTrap.gd           발사 포탑 (periodic/triggered, 파괴 불가)
│   ├── LaserTripwire.gd        레이저 탐지선 — 가로지르면 떨어진 포탑 트리거
│   ├── VeilSight.gd            VEIL 위협 마킹 + 시야 비네트 + ACT3 붕괴
│   ├── SkillTreeData.gd        스킬 트리 8라인×3티어 + 스킬↔적 상성(MATCHUP)
│   ├── SkillTreeOverlay.gd     스킬 트리 미리보기 오버레이
│   ├── SkillIcon.gd / EnemyIcon.gd   절차적 아이콘 (스킬·적)
│   ├── CharacterArt.gd         벡터 캐릭터 빌더 (코드 생성)
│   ├── BriefingVisual.gd / MissionObjective.gd   오프닝 VEIL 눈·목표물 비주얼
│   ├── BestiaryData.gd / BestiaryOverlay.gd   적 도감 (메모 + 첫 조우 카드)
│   ├── ArchiveOverlay.gd / ArcturusDocumentOverlay.gd   ??? 단말기·이스터에그 문서
│   ├── LevelUpOverlay.gd       스킬 3중 1 카드
│   ├── PlaygroundOverlay.gd    디버그 연습장 패널 (맵/스킬/시야붕괴 즉시 조정)
│   ├── LeverInteractable.gd / PressurePlate.gd   레버·발판 상호작용
│   ├── SfxPlayer.gd / BgmPlayer.gd / Accessibility.gd
│   ├── PauseHelper.gd / Tutorial.gd / TutorialDummy.gd / Settings.gd / Credits.gd
│   └── Main.gd / Title.gd / Briefing.gd / RouteMap.gd / Stage.gd / Death.gd / Ending.gd
└── session_logs/               일자별 작업 로그
```

### 주요 설계 결정

- **씬 절차적 빌드**: `.tscn`은 노드 트리 최소만 담고, 플랫폼·적·플레이어·HUD는 `Stage.gd._ready()`에서 코드로 생성. 루트 id별 layout, 태그별 가시, route 별 환경 효과가 동적으로 적용된다.
- **레벨업은 별도 씬이 아닌 오버레이**: `CanvasLayer`로 표시해 스테이지 상태를 보존. 스테이지 클리어 시 보너스 XP로 레벨업해도 다음 scene 전환 전에 띄움.
- **Physics interpolation**: 60Hz 물리 + 고주사율 모니터에서 떨림 없도록 활성화.
- **VEIL은 가끔 틀린다**: 조언을 늘 따르는 게 정답이 되지 않도록 의도적으로 빗나간 조언을 풀에 넣음. `trust`와 `aggression`이 직교하도록 설계됨.
- **도감 트리거**: 적 첫 조우 시 자동으로 카드 표시. seen_enemies는 settings.cfg에 영속화돼서 다음 런에선 안 뜸.
- **디버그 연습장**: 설정 → "연습장으로 진입". HUD에 토글 패널이 떠서 stage/route/risk/reward·스킬 티어(3계열 8라인 0~3)·기본(대시·이중점프)·시야붕괴를 그 자리에서 바꾸고 즉시 reload. **맵을 누르면 그 맵의 기본 risk/reward/stage가 자동 설정**되고, 시야붕괴 토글로 ACT3 경고·붕괴 톤 대사를 연습장에서도 테스트할 수 있다.
- **자동저장/이어하기**: 스테이지 사이마다 `user://run.cfg`에 자동저장. 타이틀 "이어하기"로 닫았다 와도 직전 체크포인트로 복귀(웹은 브라우저 IndexedDB에 영속, 도메인별). 도감·본 엔딩·완주 횟수도 누적 영속이며, 완주 1회 이상이면 오프닝 VEIL 대사가 다회차 변형으로 바뀐다.

---

## 실행

1. [Godot 4.6](https://godotengine.org/download)을 설치한다.
2. 본 레포를 클론한 뒤 Godot 에디터에서 `project.godot`을 import.
3. F5로 실행 (메인 씬은 `scenes/main.tscn`).

### Web Export

`Project → Export → Add → Web` 프리셋(이름 "Web")으로 빌드, Threads Support 끄기. 자세한 절차는 [`DEPLOY.md`](DEPLOY.md). 한글 폰트는 `assets/fonts/Pretendard-Regular.otf`로 번들 — `gui/theme/custom_font` 등록.

---

## 개발 현황

핵심 시스템은 완성 단계 — 플레이→4종 결말, 12개 맵 분기, 3계열×3티어 스킬 트리, 5종 적·보스 SENTINEL,
VEIL 어투 아크(신뢰 구동), UI 시각화(텍스트→그래픽), 음악·효과음(전부 AI 생성), 자동저장/이어하기·다회차 오프닝 변형, Xbox 컨트롤러, 웹 자동 배포.

**다음 작업·미착수는 [`docs/design/backlog.md`](docs/design/backlog.md)** (단일 소스), 변경 이력은 [`session_logs/`](session_logs/),
구현 디테일은 [`docs/SPEC.md`](docs/SPEC.md), 스토리 캐논은 [`docs/STORY.md`](docs/STORY.md) 참조.

---

## 라이선스

- **코드** (`scripts/`·`scenes/`·셰이더·프로젝트 설정): [MIT](LICENSE) © 2026 Soomin Kim
- **자산**: 폰트 Pretendard는 [SIL OFL 1.1](assets/fonts/OFL.txt), 음악은 Suno·효과음은 ElevenLabs 생성물로 각 툴 약관을 따른다. 엔진 Godot는 별도 MIT. 자세한 건 [`LICENSE`](LICENSE) 하단 "BUNDLED THIRD-PARTY ASSETS" 참조.

개인 프로젝트(웹 배포 데모)라 코드만 MIT로 열고, 번들된 폰트·오디오는 원 출처 라이선스를 유지한다.
