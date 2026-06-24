# Session Log Archive

이전 세션 로그 요약. 시간이 지나 안정화된 결정만 남기고 디버깅 노트와 일과성 변경은 제거.

---

## 2026-04-28 — 프로젝트 초기 설정

`EYES_ON_YOU_v2_spec.md` 기반으로 PRD 작성 + Godot 4.6 프로젝트 뼈대 구축.

### 굳어진 결정
- **PRD vs Spec 분리**: 제품 의사결정은 PRD 우선, 구현 디테일은 spec 우선
- **씬 절차적 빌드**: `.tscn`은 노드 트리 + 스크립트만, 게임 객체는 `_ready()`에서 코드로 생성. 루트 태그에 따라 적 구성/배경색이 동적으로 바뀌는 구조에 유리
- **레벨업은 별도 씬이 아닌 오버레이**: `CanvasLayer`로 표시해 스테이지 상태(적 위치, 카메라, 진행도) 보존
- **자식 노드 부착 순서**: `add_child(parent)` → `parent.add_child(visual)` 시 `@onready`가 visual을 못 찾음. 자식 모두 부착 후 트리에 추가하는 패턴으로 통일
- **`Array[T]` 회피**: Dictionary 안의 배열 리터럴은 항상 untyped. 일관되게 `Array`로 선언

### 만들어진 것
- `PRD.md`, `EYES_ON_YOU_v2_spec.md`, `project.godot`
- Title→Briefing→RouteMap→Stage→Death/Ending 풀 흐름
- 14개 스크립트 (GameState, RouteData, VeilDialogue, SkillSystem, EndingResolver, SceneRouter, Player, Enemy, ExpOrb, Main, Title, Briefing, RouteMap, Stage, Death, Ending)

---

## 2026-04-30 — GitHub push + 스프라이트/튜토리얼/설정 1차

### 굳어진 결정
- **Tutorial은 별도 씬, 일회성**: `GameState.tutorial_done`은 `reset()`에서 보존되며 `user://settings.cfg`에 영속화
- **Tutorial에서 dash/double_jump 스킬 임시 부여**: 표지판이 약속한 동작이 실제로 작동하도록. 완료 시 `reset()`으로 정리
- **PauseHelper는 RefCounted 정적 헬퍼**: Stage/Tutorial 두 곳에서 동일 오버레이 사용. 콜백은 `Callable`로 받아 결합도 낮춤
- **Settings는 단일 씬 재사용**: Title/Pause 양쪽에서 `instantiate()`로 자식 추가
- **`pause` 액션을 키바인딩 변경 대상에 포함**: 사용자가 ESC 외 다른 키로 바꿀 수 있음. 단 캡처 중 ESC는 캡처 취소
- **세션 도중 발견된 Web Export 영속화**: `user://` 경로는 브라우저 localStorage에 매핑됨

### 폐기된 접근 (다음 세션에서 갈아엎음)
- ❌ PNG 스프라이트 + `assets/shaders/remove_white.gdshader` (흰배경 알파 마스킹)
- ❌ `Sprite2D + ShaderMaterial` 동적 생성, `PlaceholderTexture2D` fallback
- ❌ scale 0.42 (PNG가 작아서 키워야 했음)

이유: 콜리전 박스(28×56 / 28×40)와 시각이 어긋나 히트박스 vs 시각 혼란. 셰이더로 흰배경 잘라도 외곽선 거침. 정적 그래픽으로는 단순 벡터가 깨끗함. → 다음 세션에 `CharacterArt.gd` 폴리곤 합성 방식으로 교체.

### 만들어진 것
- `README.md`, `.gitignore` (Godot 4 표준)
- GitHub `soomin007/EyesOnYou` 레포 초기 push
- `Tutorial.gd` + `tutorial.tscn` + `TutorialDummy.gd`
- `Settings.gd` + `settings.tscn` (TabContainer 2탭, ConfigFile 영속화)
- `PauseHelper.gd` (CanvasLayer 오버레이 빌더)
- `GameState`에 `tutorial_done`, `master_volume`, `sfx_volume`, `load_settings()`, `save_settings()`
- `pause` 액션(ESC) 추가

---

## 2026-05-01 — 벡터 캐릭터 + 5단 튜토리얼

### 굳어진 결정
- **벡터 합성 vs PNG**: PNG는 콜리전 박스와 시각이 어긋나고 셰이더로 흰배경 잘라도 외곽선이 거침. `CharacterArt.gd` (Polygon2D 합성, RefCounted + static) 채택 — 콜리전 안쪽에서만 그림. 외곽선 없는 단순 톤이 PRD §9 "코드 생성 미니멀 벡터" 방침과 일치.
- **레벨업 오버레이 추출**: 인라인 → `LevelUpOverlay.show()`. Stage/Tutorial 둘 다 같은 UI 보장.
- **레벨업 더미 lazy 스폰**: _ready에서 미리 만들면 사거리 안에서 보이지 않게 처치되는 사고 → `_advance_to(LEVELUP)` 시점에 spawn.
- **Stage 플랫폼은 단일점프 도달 가능**: 이중점프 없이도 모든 레이아웃 클리어 가능. 이중점프는 더 빠른 루트로 보상.
- **PRESET_FULL_RECT + CenterContainer**: PRESET_CENTER 단독은 좌상단 잘림 버그 → CenterContainer로 통일.

---

## 2026-05-02 — 6맵 SILO-7 + Phase B 시스템 + 적 2종 추가

### 굳어진 결정
- **6개 맵 ↔ SILO-7 매핑**: 도시 다양한 장소가 아니라 SILO-7 안의 진입 경로로 재정의 (외곽→옥상→지하→지하철→핵심부→격리 서버실). FULL_STORY 단일 임무 컨셉(OPERATION PALIMPSEST)과 정합.
- **잠긴 문 vs ??? 루트 분리**: 잠긴 문은 시각적 복선만(콜리전 없음). ??? 진입은 루트 선택에서 별개로.
- **VEIL-1/2 표시**: 화면 하단 자막 + 색 구분 (VEIL-1 빨강, VEIL-2 노랑, VEIL 청록).
- **HP 5→3**: 5는 사실상 무한이라 위협 없음. 3으로 줄여 위기감.
- **shield = 죽기 직전 부활**: "2뎀 이상을 1로" 룰은 적이 대부분 1뎀이라 사실상 무의미 → 라이프라인 형태가 직관적.
- **wall_slide → 공중 글라이드**: 게임에 가운데 벽이 없어 "벽타기" 의미 없음. 효과만 변경하고 id 유지.
- **regen on_stage_clear heal 제거**: 매 stage 풀 회복이 의도된 동작이라 중복.
- **자폭병/방패병 추가** (적 5종): take_damage 시그니처에 from_x 정보 전달, shield는 정면 32px 안에서 막힘 + `_show_block_spark` 노란 라인.

---

## 2026-05-03 — 세계 템플릿 4종 + 보스 SENTINEL + 도전방 + 이스터에그

### 굳어진 결정
- **세계 템플릿 4종**: HORIZONTAL / VERTICAL_UP / VERTICAL_DOWN / ARENA. 각 맵이 컨셉에 맞는 템플릿 선택.
- **STAGE_LENGTH/GROUND_Y/PLAYER_START를 var로**: const → var. MapData에서 덮어쓸 수 있게.
- **FIXED 카메라 zoom**: ARENA에서 player follow 대신 고정 + zoom = min(1280/world.x, 720/world.y)로 월드가 viewport에 맞게 자동.
- **ENEMY_CLEAR goal_type**: ARENA에서 spawn 후 group 카운트, 0 도달 시 클리어.
- **vertical 발판 gap 100~170**: 이중점프 한계 ~190px이라 180+는 도달 불가.
- **저격수 발판 mid step**: 지면→step→mid 단계화. step 없으면 폭발물로만 잡을 수 있음.
- **GitHub Pages는 Actions 방식**: 별도 브랜치 안 만들고 Actions API로 직접 배포.
- **보스 별도 스크립트**: `BossSentinel.gd` 분리 — group "enemy" 등록으로 ARENA enemy_clear에 자연 통합.
- **lab 일반 적 제거**: DESIGN §2.10 "보스 챔버" 정체성 강조.
- **이스터에그 in-place 시퀀스**: 별도 방 append 대신 페이드 오버레이 + ArchiveOverlay 재생.
- **블랙아웃 시야**: 정확한 원형 cutout 대신 풀스크린 dim 0.55 + 비네트.

---

## 2026-05-04 — 적 가장자리 감지 + 보스 페이즈 무적 + Pretendard + 이스터에그 풀스크린 문서

### 굳어진 결정
- **적 가장자리 감지는 raycast**: spawn 시 발판 메타 부여 대신 동적 raycast — 모든 맵 적용 가능 + 발판 변화에도 robust.
- **수직 맵 gap 80 표준**: 1단 점프 한계 104px이라 80은 여유, 분기 도약 140은 1단으로 절대 안 감.
- **patrol 발판 폭 240+**: 너무 좁으면 ping-pong하다 텔레그래프 거리 안 나옴.
- **보스 페이즈 무적 1.2s**: 사격 spam 시 freeze 종료 즉시 데미지 들어가 못 인지 → 1.2s + take_damage 무시로 강제 인지.
- **Pretendard 선택**: NotoSansKR ~16MB 너무 큼. Pretendard subset 1.5MB가 부스 환경 로딩에 적합. OFL 라이선스.
- **show-don't-tell 원칙 채택**: 모든 텍스트/연출 의사결정의 상위 기준. `docs/design/show_dont_tell.md` 작성.
- **보스 페이즈 알림 = VEIL**: 큰 영문 배너 대신 VEIL 한 줄 — 캐릭터·메카닉 통합.
- **도감은 "관찰 메모"**: blurb 한 줄 + 키워드 색 강조. 공략 글 제거.
- **자폭 dual-zone**: 단일 반경 2200은 회피 불가 → inner(풀뎀)/outer(1뎀) 거리 보상.
- **미사일 약한 유도**: 1.4s 유도 후 직진. TURN_RATE 80도/s로 직각 회피 가능, 수직 정지엔 위협.
- **barrier vs shield 분리**: 능동(타이밍) / 보험. 별 라인 추가, shield 라인은 유지.
- **풀스크린 문서 vs 패널**: 단말기는 패널, 이스터에그(회의록)는 풀스크린 문서로 분리.

---

## 2026-05-05 — 캐릭터/맵 비주얼 톤업 + VEIL 신뢰도 게이지 + 튜토리얼·맵 폴리시

### 굳어진 결정
- **AI 컨셉 = 코드 도형 유지**: 외부 픽셀/벡터 자산 거부, `_filled`/외곽선/디테일 헬퍼로만 톤업. "AI가 만들었다"는 정체성을 비주얼로도 밀기 위함.
- **5두신 비례**: 4두신(chibi)·8두신(사실적) 사이에서 게임 캐릭터다움 균형. 머리14/상체22/다리16/신발4.
- **신뢰도 = trust − aggression**: 둘 다 높으면 neutral, 한쪽 우세할 때만 단계가 명확해짐. 두 점수는 결말에 독립적으로 작용.
- **VEIL 멘트가 추천의 단일 source**: trust/aggression 휴리스틱 대신 `advice.family`로 ★ 마킹 → 멘트와 카드 ★가 항상 같은 카드를 가리킴.
- **튜토리얼 ↔ 본편 완전 분리**: `start_main_game()`이 skills를 STARTING_SKILLS로 초기화 — 튜토리얼 강제 부여 스킬/XP/레벨이 본편에 안 넘어감.
- **비밀 통로 = 더블점프 + 시야 외곽 발판**: 메인 spine 단축으로 줄어든 진행감을 "찾는 재미"로 보상.

---

## 2026-05-06 — 결말/이스터에그 자막 버그 진짜 원인 + 탈출로 cross-fade + 레버 시스템

### 굳어진 결정
- **버그는 로그로 원인부터**: 결말 C followup 미표시는 choice 라인에서도 `silent_timer`가 누적돼 line_idx가 자동 진행된 게 진짜 원인. watchdog/lockout 우회 시도가 다 실패한 이유 — 디버그 print 없이는 못 잡았음.
- **CanvasLayer는 부모 modulate를 안 받음**: cross-fade·암전 연출은 CanvasLayer가 아닌 그 안의 Control(`*_root`)에 modulate 적용해야 함.
- **자막 큐는 paused 전환 직전 purge**: paused 전환 시 SceneTreeTimer가 멈췄다 풀린 뒤 한꺼번에 흘러 outro와 겹침 → 진입 시점에 큐 clear.
- **interact = attack 키 재사용**: 레버 영역 안에서는 attack 입력을 완전 흡수(별도 interact 키 없음). 영역 밖이면 기존 사격.
- **드롭 발판 collision은 초기 비활성**: invisible 상태에서도 StaticBody collision은 살아있어 떠있는 발판 버그 → `col.disabled=true`로 시작, descend 시 해제.
- **비밀칸은 MapData 스키마 대신 Stage 인라인**: 맵별 1~2개라 스키마 확장 비용이 큼. per-route 빌더에 좌표 하드코딩.

---

## 2026-05-08 — BGM 매핑 + 크레딧 화면 + 도전방 차폐막 + 디버그 잠금

### 굳어진 결정
- **BGM은 stage_index가 아닌 route_id로 매핑**: 같은 stage라도 외곽 통로와 시설 내부는 톤이 달라야 함. 시설 진입이 자연스러운 BPM step-up 지점. BgmPlayer=두 AudioStreamPlayer crossfade autoload.
- **크레딧은 scene/overlay 두 진입점 공통 화면**: 엔딩→크레딧→타이틀(scene) / 설정 탭(overlay, `closed` signal). ESC 한 번으로 닫힘.
- **ward 레버는 잠긴 문에서 먼 상층 끝**: 의도적 backtracking — "발판→레버 발견→되돌아와 밟기" 두 단계 능동 행동. 5초 hold 방식 폐기.
- **도전방 진입은 발판으로**: 레버("당긴다")보다 발판("들어선다")이 무거운 결정을 가벼운 스텝으로 표현하는 톤에 맞음. 안은 world-space 차폐막(z=9)으로 통째 가림 + 게이트 후 점진 노출.
- **디버그 모드는 영속화 X**: 타이틀 "snu" 키 시퀀스로 매 실행 해제 — 부스에서 우연히 켠 채 쓰는 일 차단.
- **사망 화면은 BGM 트랙 유지 + ducking(-12dB)**: 트랙 전환은 분위기가 끊김 — dB만 죽인 먹먹한 톤이 무력감과 맞음.

---

## 2026-05-09 — SfxPlayer 시스템 + 미구현 스킬 2종 + 탈출로 터널 재설계

### 굳어진 결정
- **SfxPlayer autoload**: `assets/sfx/<id>(N).{mp3|ogg|wav}` 자동 스캔, variant 무작위, POOL_SIZE=8 round-robin, id별 dB 보정. MP3는 `loop=false` 강제(Godot 기본 true 함정).
- **time_scale 스킬은 `_exit_tree`에서 안전 복원**: 슬로모 활성 중 씬 전환으로 player가 free되면 다음 씬도 배속이 박힘. 해제 타이머는 `ignore_time_scale=true`.
- **터널은 cross-fade가 아니라 물리적으로 끝남**: walls를 일정 X까지만 깔아 city group을 가림 → 카메라가 지나면 자연 노출. alpha fade는 "빠져나가는" 신체 감각과 안 맞음.
- **Parallax 좌표는 `get_screen_center_position()`**: Camera2D.global_position은 parent(player) 좌표라 limit 무시 → 맵 끝에서 배경이 계속 흐름. screen center는 limit/smoothing 반영.

---

## 2026-05-15 — combat/enemy SFX wire-up 원칙

### 굳어진 결정
- **발사 1회 = SFX 1회**: `bullet_fire`는 Player._try_attack에서만(Bullet._ready에 넣으면 multishot 5발이 5번 겹침).
- **명중/디플렉트 판정은 Enemy.take_damage 안에서**: Bullet은 SFX 책임 안 짐(Bullet 쪽이면 방패 막힘 시 impact+deflect 둘 다 재생).
- **loop 미지원 SFX는 상태 전이 edge에서만**: drone_hover 등은 flag로 entry edge만 캡처(매 프레임 재생 방지).
- **bomber_explode와 enemy_death 중복 방지**: `_die`에서 BOMBER면 enemy_death 생략(폭발음이 사실상 death 사운드).

---

## 2026-05-16 — Patrol 사격+돌진 이중 모드 + positional 호버

### 굳어진 결정
- **Patrol = 압박형 이중 모드**: 중거리 사격 + 근접 돌진. 사격 전용은 sniper와 겹침 → 정찰병 정체성을 "사격"이 아닌 "압박"으로. `CHARGE_RANGE=240`으로 거의 항상 돌진, 사격은 보조.
- **EnemyBullet은 별도 클래스**: Bullet에 enemy flag 추가하면 pierce/tracking/multishot이 죽은 멤버로 남음. 속도 240px/s(Player 900의 27%)로 회피 가능.
- **Veil 대사는 적 타입 명시 대신 정도·방향 표현**: route 선택에 따라 특정 적 등장이 거짓이 될 수 있음 → "저격수 자리가 많아져요" 식 일반화.
- **호버만 positional(AudioStreamPlayer2D)**: 전체 positional화는 큰 리팩토링 — "거리 감쇠가 정체성"인 SFX만 개별. AudioListener2D는 Player에 명시 부착(FIXED ARENA 카메라 고정 호환).

---

## 2026-06-06 — paused carry 4중 방어 + 스토리 재설계 외부화

### 굳어진 결정
- **paused carry 4중 방어망**: `get_tree().paused`는 SceneTree 전역이라 씬 전환에도 carry → freeze. SceneRouter 전환 직전 해제 + 각 씬 `_ready` 첫 줄 + 오버레이 안전판(`tree_exited`) + 실패 경로 명시 해제로 한 층 누락돼도 회복.
- **스토리 재설계는 핸드오프 문서로 외부화**: 코드를 보는 Claude Code가 "게임이 강제하는 제약"을 정확히 정리, 창작 이터레이션은 웹이 편함. 갈아엎지 않고 `docs/STORY_HANDOFF.md`로.
- **em dash 정책**: 캐릭터 대사에서만 제거(톤 가이드), UI 타이포 구분자(`VEIL — ` prefix·라벨·서명)는 디자인이라 유지.
- **Bash 커밋 메시지는 heredoc(`<<'MSG'`)으로**: PowerShell here-string 오용으로 제목 깨진 적 있음.

---

## 2026-06-07 — 위치 효과음 + VeilSight 파일럿(서사 HUD)

### 굳어진 결정
- **몰입 부족의 뿌리 = 구조 문제**: VEIL의 "봄"이 전부 플레이 *사이* 텍스트(루트★·스킬★·브리핑·자막)뿐, 플레이 *중* 실연이 0 → v3 역전("이제 요원이 본다")의 baseline 자체가 화면에 없었음.
- **VeilSight 신설 = "VEIL이 본다"를 플레이로 실연**: 전 전투맵 위협 마킹(화면 안 reticle / 밖 화살표). 초중반 baseline → ACT3 degradation이 곧 시야 역전. blackout(교신 차단)은 제외.
- **VeilSight는 레이더가 아니라 작가성**: 등장 페이드인·8방위 말걸기(쿨다운+진입보호로 절제)·영구 소등 35%로 "누가 보여주는가"를 입힘. 기능만 늘리면 레이더성만 강해지는 함정.
- **ACT3 degradation 동기화가 정수**: 진입부터가 아니라 62% 트리거(POSITION)/지연 자막(ARENA)에서 동적 전환 → 자막과 마커 붕괴가 한 사건.
- **자폭 보스는 끝까지 보이게(카운트다운 중 무적)**: 잔탄 즉사로 자폭 시퀀스 안 보이던 문제 → "도망쳐야 하는 클라이맥스 연출" 우선.
- **자막은 하단 중앙 + pill 배경**: 조작 중 상단 대사 인지 안 됨 → 시선 가까이 + 내용 폭만 감싸는 pill.

---

## 2026-06-08 — 스킬-적 상성 시스템 + 운영 루틴 도입

### 굳어진 결정
- **폭발물 너프는 데미지+쿨다운 둘 다**: 방패 무시 AoE(상성)는 보존, "올킬 만능"만 제거. 글라이드 정체성 = 공중 제압(저격·드론 상성).
- **글라이드 라인 재설계**: T3까지 가야 빛나던 것 → T1 활강·T2 관통·T3 유도로 매 티어 유효. 스킬만으론 안 쓰임 → "글라이드 유리한 맵"이 필요(백로그).
- **상성 매핑은 `SkillTreeData` 공통 헬퍼**: MATCHUP(shield→explosive 등) + 맵 enemies·waves 분석을 추천·출현 가중이 공유. ★는 skill_id 단위, family는 폴백.
- **세션 운영 루틴 도입**: 세션 시작 루틴(backlog→최신 로그→known_issues→git) + 오류 기록 루틴(known_issues에 증상→원인→방지책). 표류·반복 실수 차단.
- **outdated docs는 하드 삭제 대신 archive 이동**: 설계 흐름 이력 보존, 가역적.

---

## 2026-06-09 — 못 잡는 적/함정 VEIL 안내 + 트랩 확산 / shield T3 / 글라이드 게이트

### 굳어진 결정
- **회피 전용 식별 = 맵 레벨 플래그(`nest_snipers`)**: 위치 리스트 복제(좌표 매칭 깨지기 쉬움) 대신 "이 맵 저격수는 전부 둥지"를 boolean으로.
- **안내 문구는 "못 잡는다"가 아니라 "글라이드로 덮쳐라"**: 둥지 저격수는 글라이드로 도달·처치 가능 → 글라이드-저격 상성을 가르치는 멘트.
- **shield T3 = "구현" 선택**(desc≠효과 해소): 30s 재충전 구현. 맵 전환 시 Player 재생성으로 자연 재무장. 부활 vs 방어막 용어 분리(shield="부활", barrier="에너지 방어막").
- **글라이드 게이트는 VERTICAL_UP 맵에만, 220px 순수 수직 hop**: 더블(190) 못 닿고 삼단(381)으로만. 흡인 반경 축소(60→44)로 게이팅.
- **가로 포탑은 발판 top 금지**: 같은 높이면 탄이 표면을 스쳐 무해 → 갭(점프 경로)/body 높이로.
- **크래시 가드는 단일 길목에**: player 조회를 `_find_player` 하나로 모아 null 가드 → 모든 호출처 동시 보호.

---

## 2026-06-11 — 감시탑 저격수 완화 + 게이트 오브 차별화

### 굳어진 결정
- **저격수는 엄폐가 아니라 수치로 조정**: 발판 위 적의 하향 사격은 탄 출발점이 벽 밑이라 발판 위 벽으로 못 막음(기하학적 무효) → 둥지 전용(`avoid_only`) 사거리/간격/텔레그래프 완화. 전투 맵 저격수는 보존.
- **무효 트랩은 고치지 말고 제거**: 동선과 어긋나 한 번도 안 터진 트랩은 재배치보다 제거가 깔끔(노이즈 감소).
- **게이트 보상 흡인은 LoS로 게이팅**: 반경 축소만으론 옆 발판이 직선거리 안 → 레이캐스트로 사이 지형이 막혔으면 흡인 보류(위치/반경 튜닝 없이 견고).
- **VEIL 대사는 어색한 것만 손댐**: 엔딩·진입·경고·보스 대사는 캐논이라 보존, 번역 투 3~5줄만 교정해 드리프트 방지.

---

## 2026-06-12 — 둥지 저격수 스폰 버그 + 공격 강화 재설계

### 굳어진 결정
- **위치가 고정 의미인 적은 개수 스케일에서 제외**: risk 배율(×1.5)이 추가 저격수를 `base±120`에 스폰해 64px 둥지 발판을 벗어나 낙하 → 둥지 저격수는 배율 복제 제외.
- **공격 강화는 데미지 스택 폐기, 항상-유효 효과로**: 적 HP 대부분 1~2라 데미지 3은 방패병 1샷에만 의미 → 새 라인 추가(카드 풀 희석) 대신 fire_boost T2를 "속사"로 교체(데미지↑→연사↑→관통 일관성).
- **비밀 보상은 난이도에 비례**: 글라이드 없는 stage0 맵의 게이트는 부적합 → 제거하고 보상은 레버→해치 개방으로 이전.
