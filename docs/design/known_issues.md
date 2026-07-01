# 알려진 오류 / 재발 방지

> 세션 중 발견한 버그·설계 함정·작업 실수와 그 방지책. 같은 걸 두 번 겪지 않기 위해 남긴다.
> 매 세션 시작 시 이 파일을 먼저 본다(CLAUDE.md 세션 시작 루틴). 발견 즉시 "증상 → 원인 → 방지책"으로 추가.
> 런타임 freeze 패턴의 상세는 자동 메모리 `project-runtime-safety`에도 있음.

---

## 작업 프로세스

- **project.godot이 `M`으로 떠도 대개 줄바꿈(CRLF/LF) 차이뿐.**
  → `git diff project.godot`로 내용 변경 없음을 확인되면 커밋에서 제외. 습관적으로 add 하지 말 것.

- **새 `.gd` 커밋 시 `.gd.uid`도 함께 add.**
  Godot 4.x은 스크립트마다 `.uid`를 자동 생성한다. 함께 `git add` 안 하면 추적 누락.
  (2026-06-07 `VeilSight.gd.uid`가 직전 커밋에서 빠져 별도 정리 커밋 필요했음.)

- **AskUserQuestion 호출 시 `questions` 배열을 반드시 채울 것.**
  누락하면 `InputValidationError: The required parameter questions is missing`로 반복 실패.
  (2026-06-08 여러 번 빈 호출로 실패함.)

- **GDScript: untyped Array/Dictionary 인덱싱 시 명시 타입 선언.** `var x := arr[i]` 대신 `var x: Dictionary = arr[i]`.
  `Array[T]`에 untyped Array(사전 리터럴 값, `Dictionary.get` 결과) 직접 대입 금지(런타임 에러).

- **`int(배열)`/`int(딕셔너리)` 호출 금지 — "Nonexistent 'int' constructor" 크래시.**
  값이 *개수*가 아니라 *컬렉션*일 때 `int()`로 변환하면 크래시. 적 종류 집계에서 wave의 enemies 값이
  위치 **배열**인데 `int(wen[k]) > 0`으로 개수처럼 다뤄 크래시(RouteMap.gd:240, 2026-06-09).
  → 컬렉션 크기는 `arr.size()`. 같은 데이터를 여러 경로에서 셀 땐(enemies/waves) 동일 패턴 유지.

- **PowerShell 백그라운드로 godot 실행 시 출력을 `| Out-String`으로 받지 말 것 — 프로세스 종료까지 버퍼링.**
  `... | Out-String`은 파이프 전체를 모은 뒤 한 번에 반환하므로, godot이 도는 동안 output 파일이 계속 비어
  진행 로그를 볼 수 없고, godot이 hang하면 PowerShell도 무한 대기한다(포스터 창모드 렌더가 20분 안 끝남, 2026-06-14).
  → 출력은 `*> "log.txt"`로 직접 리다이렉트(또는 Tee-Object). 진행이 실시간 기록돼 hang 진단이 가능.

- **Godot.exe(Windows 에디터/GUI 빌드)의 스크립트 `print`(stdout)는 콘솔에 안 잡힌다 — 검증 값은 `FileAccess`로 파일에 직접 써라.**
  엔진 로그(import·WARNING 등 stderr)는 `... 2>&1 | Select-String`으로 보이지만, `print` 출력은 GUI 빌드라
  `*>`/`2>&1`로도 빈 파일이었다(2026-07-01 터치 검증, 0바이트 반복). → 검증 스크립트가
  `FileAccess.open("C:/abs/path.txt", FileAccess.WRITE)`로 결과를 *직접 기록*하고 PowerShell이 그 파일을 읽는다.
  단계마다 flush(매번 열고 닫기)하면 어디서 멈췄는지도 보인다.

- **헤드리스에선 `Input.parse_input_event`의 ScreenTouch/ScreenDrag가 `_input`에 안 오고 뷰포트가 정사각(비정상)이다 — 터치 검증은 창모드로.**
  헤드리스 DisplayServer가 dummy라 주입한 터치가 액션을 안 만들었고(action_press 전부 0/0.0),
  `get_viewport().get_visible_rect().size`가 1280×1280으로 나왔다. → 터치·뷰포트·입력 좌표 의존 검증은
  **`--windowed --resolution 1280x720`** 창모드로. FileAccess 기록은 창모드에서도 되니 결과는 회수된다.
  (2026-07-01: 헤드리스 전부 실패 → 창모드에서 멀티터치·좌우 드래그 전환·release 전부 통과.)

- **포스터/캐릭터 렌더 검증은 헤드리스 import로 파싱부터 확인 후 창모드.**
  창모드 `--gen`은 hang 위험(원인 불명: 창 포커스/렌더 루프 추정)이고 결과를 Claude가 직접 못 본다. 먼저
  `--headless --import`로 스크립트 파싱·컴파일 에러를 잡고(EXIT 코드 확인), 그 다음 창모드로 실제 PNG를 뽑는다.

- **`godot --import`는 스크립트 *함수 본문* 파싱 에러를 캐시로 놓칠 수 있다 — fresh import/부팅으로 검증.**
  `_handle_input(_delta)` 파라미터를 `delta`로 참조한 미선언 에러를, 이미 import 캐시가 있는 repo의
  `--import`는 통과시켰고(RC=0, 출력 없음), 캐시 없는 다른 repo의 *fresh* import만 잡아냈다(2026-06-24
  데모 백포트). 원인: `--import`는 에셋 재import 중심이라 변경 없다고 본 스크립트의 함수 본문 재컴파일을
  건너뛸 수 있고, `update_scripts_classes`는 class_name *선언*만 본다. 게다가 GitHub Actions의 export조차
  이 에러를 통과시켰다(빌드 OK). → **스크립트 변경 검증은 `--import` RC=0만으로 "클린" 단정 금지.**
  ⓐ `.godot` 없는 fresh 체크아웃에서 import, 또는 ⓑ 게임을 실제 부팅(`--quit-after`)해 해당 코드 경로를
  타게 하거나, ⓒ 변경 스크립트를 인스턴스화하는 래퍼 씬으로 확인할 것. 미사용 prefix(`_delta`)를 쓰는
  파라미터를 나중에 참조하게 되면 prefix를 떼는 것도 잊지 말 것.

- **`const` 배열/사전은 오토로드 멤버(`GameState.X`)를 못 담는다 — 컴파일 에러.**
  `const CHOICES = [{"id": GameState.DISPOSAL_EXTRACT}]`처럼 const 초기값에 오토로드의 const/멤버를
  참조하면 "non-constant value in constant expression"으로 컴파일 실패(2026-06-25 DisposalChoiceOverlay).
  오토로드는 런타임 싱글톤이라 컴파일 타임 상수가 아니다. → 런타임 지역변수(`var`)나 static 함수로 빼서
  반환. 단일 소스 유지하려면 id 문자열을 오토로드 const로 두되 *참조는 런타임에*.

- **새 `class_name` 스크립트는 `--import` 후에야 헤드리스 씬 검증에서 보인다.**
  방금 만든 `class_name Foo`를 래퍼 씬에서 쓰면 "Identifier 'Foo' not declared"로 파스 실패(2026-06-25).
  전역 클래스 캐시(`update_scripts_classes`)가 아직 비어서. → 새 class_name 추가 후 검증 전 한 번
  `godot --headless --import`로 캐시 갱신(로그에 `update_scripts_classes | Foo` 확인) → 그다음 씬 실행.
  (래퍼 검증 패턴: import → `--headless res://_check.tscn --quit-after N`.)

- **헤드리스 검증 끝의 `ObjectDB instances leaked` / `1 resources still in use at exit`는 대개 무해.**
  타이핑/트윈이 진행 중인 씬(Ending 등)을 `get_tree().quit()`/`--quit-after`로 끊으면 미정리 노드·리소스가
  남아 이 경고가 뜬다. SCRIPT ERROR/Parse Error가 없으면 로직엔 영향 없음(2026-06-25 B2/B3 검증).

- **Edit 도구 들여쓰기 불일치 — Read 표시는 줄번호 뒤 탭이 하나 더 붙어 보인다(2026-06-15).**
  Read 출력의 들여쓰기를 그대로 세어 old_string을 만들면 탭 수가 1 어긋나 "String not found"가 반복된다.
  → 들여쓰기가 안 맞으면 `sed -n 'N,Mp' file | cat -A`로 실제 탭(^I) 수를 확인하고 맞춘다(GDScript는 탭 들여쓰기).

- **`export_filter="all_resources"`는 `.gitignore`를 무시하고 프로젝트 폴더 안 임포트 리소스를 전부 패킹.**
  `poster_out/`을 git에선 빼놔도 export는 파일시스템을 보므로 로컬 빌드(web/win pck)에 포스터·스크린샷·QR이
  들어가 용량이 부풀었다(codex 리뷰, 2026-06-18 — pck ~58MB). → 빌드 무관 산출물은 두 preset 모두
  `exclude_filter="poster_out/*"`로 제외. export 후 `--verbose` 또는 pck 크기로 실제 제외를 검증.

- **스킬/맵 재설계 시 README·MapData 주석의 티어 표기가 코드와 어긋난 채 남는다.**
  글라이드 T3을 '관통·추적'→'유도'로 재설계(2026-06-15)했으나 README는 옛 문구를, 삼단점프 티어는
  T1/T2가 파일마다 뒤섞여 있었다(codex 리뷰, 2026-06-18). 게이트 맵 목록도 강등/제거된 rooftops·watchtower가
  남아 있었다. → 스킬 정의의 단일 소스는 `SkillTreeData.gd`. 티어/효과를 바꾸면 README 스킬표·기믹표와
  MapData 주석을 같은 커밋에서 동기화하고, "실제 게이트=gate_orbs 채워진 맵"만 문서에 적는다.

---

## 게임 설계 함정

- **연출 시스템 ↔ 맵 형태 정합.**
  마커/위협 표시 기반 연출은 잡몹이 있는 맵에서만 의미가 있다. ARENA/보스 맵(단일 보스)에선 마킹할
  대상이 없어 무의미 → 시야 역전 같은 비트는 잡몹 맵에서 실연해야 한다.
  (2026-06-08: 스토리 ACT3 시야 역전이 보스전(lab, ARENA)에서 발동해 마커 degradation이 안 보였음.
  → stage2(ward/sewers)부터 시작하도록 변경.)

- **서사 HUD엔 "작가성"이 필요.**
  "VEIL이 본다" 같은 서사 시스템을 순수 기능 표시(기하학 마커)로만 만들면 플레이어에겐 "레이더"로 읽힌다.
  누가/왜 보여주는지 — 말걸기·고유색·등장 연출·화면효과 — 가 있어야 서사로 읽힌다.
  (2026-06-08: VeilSight 마커가 레이더로 읽힘 → 페이드인·말걸기·테두리 시안/시야 축소 화면효과 추가.)

- **스킬 가치는 맵이 받쳐줘야 한다.**
  회피/기동 스킬(글라이드)은 그것을 강제하는 지형(고지대·갭·긴 낙하) 없이는 안 쓰인다. 저격병이 평지
  한가운데 서 있으면 회피 스킬은 영영 무의미 → 스킬 효과 변경만으론 부족하고 맵 디자인이 함께 가야 한다.
  (2026-06-08: 글라이드를 T1부터 매력적으로 재설계해도 맵이 안 받쳐 안 쓰임. "글라이드 유리한 맵" 백로그.)

- **AoE 몰살 주의.**
  폭발물 등 광역기가 반경 내 전체를 치면 뭉친 적이 한 방에 몰살된다 → 최대 타격 수 또는 거리 감쇠를 고려.
  (2026-06-08: 감시탑 발판에서 폭발 한 번에 전멸 → 거리순 최대 3체로 제한.)

- **엄폐물(모래주머니/ㄴ자 발판)로는 "아래를 향한 사격"을 못 막는다.**
  발판 *위*에 선 적의 하향 사격은 발판 *아래 가장자리*로 빠져나가므로, 그 적 위에 세운 벽/모래주머니로는
  아래(등반 경로)로 가는 탄을 차단할 수 없다(탄 출발점이 벽 밑이라 벽 위쪽이 무의미). 수직 등반을 내려다보는
  저격수의 압박은 *지오메트리 엄폐*가 아니라 **사거리·발사 간격·텔레그래프 같은 수치**로 조정해야 한다.
  (2026-06-11: 감시탑 둥지 저격수 셋이 HP 3 등반자를 십자포화 → "ㄴ자 모래주머니" 제안은 기하학적으로 무효라
   판단, avoid_only 둥지 저격수만 사거리 700·조준 1.1s·간격 1.5배로 완화. Enemy._eff_sniper_*.)

- **트랩/기믹은 "주 동선과 교차"해야 효과가 있다 — 동선 밖이면 없는 것과 같다.**
  수직 등반 맵에서 합류 직전에 깐 가로 트립와이어 + 하향 버스트 포탑이 실제 오르는 경로와 어긋나 한 번도
  발동되지 않았다(사용자: "별 효과가 없어"). 트랩을 추가할 땐 플레이어가 *반드시 지나는* 발판/갭에
  겹치는지 좌표로 확인하고, 안 겹치면 추가 대신 제거가 맞다(노이즈 제거). (2026-06-11: 감시탑 wt1 쌍 제거.)

- **"라벨 ≠ 실제 공식" 함정 — 점수식과 표시 문구를 같이 검증.**
  추천 점수식이 표시 라벨과 다른 의미면 플레이어가 혼란. VEIL "위험 대비 보상 균형"이 실제론
  `reward*2 - risk`라 보상에 2배 가중 → 위험2보상2(점수2) < 위험3보상3(점수3)로 고위험을 밀었음.
  → 진짜 균형은 순가치 `reward - risk` 최대 + 동점 시 저위험. 점수식 만들 때 양 끝 케이스를 손으로
  넣어 라벨과 일치하는지 확인할 것. (2026-06-08 사용자 지적으로 발견 → 실력 기반으로 재설계.)

- **적응형 지표 추적 경계는 "재시도에도 안 깨지는 지점"에 둘 것.**
  스테이지 실력 추적의 baseline을 Stage._ready에 두면 죽음 재시도마다 리셋돼 고전 신호가 사라진다.
  → `record_route_choice`(스테이지 진입 직전, 재시도엔 재호출 안 됨)를 baseline, `on_stage_clear`를
  마감으로 잡으면 재시도의 피격·죽음이 한 창에 누적돼 자연히 "고전"으로 읽힌다. (2026-06-08 VEIL 적응형.)

- **AskUserQuestion `questions` 누락이 또 재발(2026-06-08 세션 4).** 빈 호출로 1회 실패 — 위 작업
  프로세스 항목 재확인. 호출 직전 `questions` 배열 채웠는지 항상 점검.

- **흡인형 보상(ExpOrb)은 벽/바닥을 무시한다 — 높이 게이트 보상이 메인 경로로 빨려옴.**
  `PICKUP_RANGE`(220) 안이면 직선거리로 끌려오므로, 글라이드 게이트 알코브(발판 위 220px) 보상이
  바로 아래 메인 경로에서 바닥을 뚫고 흡인돼 게이트가 무의미해졌다(2026-06-09). 게이트 높이와 흡인
  반경이 같았던 게 직접 원인. → "직접 도달해야 하는" 보상은 작은 흡인 반경(`gate_orbs`)으로 분리.
  단 반경만 줄여도 직선거리상 옆 발판이 범위에 들 수 있어, 게이트 오브는 **LoS 레이캐스트로 확실히
  차단**한다(`ExpOrb._has_clear_path`, mask 1). 사이에 막힌 발판/바닥이 있으면 흡인 자체를 보류 →
  실제 알코브에 올라서야만 획득. 흡인 반경은 "줍는 손맛"이 아니라 "도달 의도"에 맞춰 설정할 것.
  (2026-06-11: 60→44px + LoS 게이팅으로 보강. 동시에 게이트 오브 = 황금 마름모·가치 3으로 차별화.)

- **"표시된 사거리 ≠ 실제 사거리" — 위협 표시 길이는 진짜 도달거리에 맞춰야 한다.**
  발사 트랩이 그리는 조준선(`LINE_LEN`)을 460으로 박아뒀는데, 트랩 총알은 EnemyBullet을 속도만
  460으로 올려 쓰고 수명(1.6s)은 그대로라 실제론 460×1.6 = 736px 날아갔다 → 선 끝 너머 ~276px
  에서도 맞아 "표시가 거짓말"이 됐다(사용자 지적). 원인: 표시 길이를 상수로 따로 두고 실제 사거리
  (속도×수명)와 연동하지 않음. → 표시 길이를 `BULLET_SPEED * EnemyBullet.BASE_LIFETIME`로 유도해
  자동 일치. 텔레그래프/사거리 시각화는 항상 실제 충돌 도달거리에서 역산할 것. (2026-06-13.)

- **가로 발사 포탑이 발판 top과 같은 높이면 위협이 안 된다.**
  탄이 발판 표면/발 밑을 스쳐 지나가 서 있는 플레이어 몸통을 안 맞힌다(감시탑 포탑, 2026-06-09).
  발판 top 좌표를 그대로 포탑 y로 쓴 게 원인. → 가로 포탑은 **갭(점프 경로) 높이**(발판 사이)나
  **발판 위 body 높이(~top-28)**에 둬 통과/체류 시 실제로 맞게. 같은 높이=무해.

- **기본 입력 보강은 `load_settings()` *뒤에* 둘 것.**
  project.godot 기본 attack에 마우스 좌클릭이 없어 Main이 런타임에 `_ensure_mouse_event`로 추가한다.
  이 보강을 load_settings보다 *먼저* 호출하면, load_settings가 `action_erase_events`+재로드로 attack을
  cfg값(마우스 빠진 상태)으로 덮어써 좌클릭 사격이 사라진다. 게다가 한 번 마우스 빠진 cfg가 저장되면
  계속 전파됨(자기 영속). → 순서: load_settings → _bind_default_mouse_inputs/_bind_wasd_to_ui.
  좌=사격/우=스킬은 핵심 조작이라 cfg가 잃어도 항상 보강되게. (2026-06-08 사용자 보고 → fix 27852ae.)

- **키 기본배열을 바꾸면 `SETTINGS_VERSION`을 같이 올릴 것 — 안 그러면 기존 cfg가 새 기본을 덮어쓴다.**
  `load_settings`는 저장된 `meta.version >= SETTINGS_VERSION`이면 cfg의 `[input]` 키바인드로 InputMap을
  `action_erase_events` 후 덮어쓴다. 키 기본값(project.godot)만 바꾸고 버전을 안 올리면, 이전에 플레이해
  cfg가 있는 사용자는 *옛 키*가 복원돼 새 기본(예: ZXC, 화살표↑)이 안 먹힌다(2026-06-24 사용자 보고:
  "데모에서 ZXC 안 됨"). → 키 배열 개편 시 `SETTINGS_VERSION`을 +1. `version < SETTINGS_VERSION`이면
  키바인드만 폐기되고 도감·볼륨 등 다른 cfg 값은 보존되므로 안전(키만 새 기본으로 리셋). (3→4: e8fc845.)

- **고정 거치 적(둥지 저격수)을 개체 수 배율로 복제하면 발판 밖 허공에 떨어진다.**
  `_spawn_from_enemies_dict`는 risk 배율(risk3=1.5)로 적 수를 늘릴 때 추가분을 `base_p ± 120px`
  랜덤 오프셋으로 스폰한다. patrol(넓은 지면)엔 맞지만, 둥지 저격수는 64px 단독 발판에 거치돼
  ±120 오프셋이 발판을 벗어나 → 중력으로 낙하(감시탑 risk3에서 "시작하자마자 우측에서 저격수가
  뚝 떨어짐"). 원인: 위치가 *고정 의미*인 적을 *개수 스케일* 대상으로 같이 처리. → 둥지 저격수
  (`nest_snipers`)는 정의된 위치에 정확히 1명씩만, 배율 복제 제외. 외벽 옥상은 risk2(×1.1→추가 0)라
  같은 버그가 잠복했어도 안 드러났음. (2026-06-12 fix.)

- **글라이드 게이트는 ① 바로 아래에 stepping-stone 발판이 없어야 하고 ② 글라이드를 가질 수 있는 stage에 둬야 한다.**
  외벽 옥상(stage0) 게이트 알코브(1180,2060) 바로 아래 안테나 발판(2160, 100px)이 있어 더블점프로
  닿아 글라이드가 무의미했고, 애초에 stage0엔 글라이드(스킬) 미보유라 게이트 자체가 부적합했다.
  → 게이트 배치 시 ⓐ 알코브 아래 *가장 가까운 발판까지 거리 > 더블점프(190px)* 인지 좌표로 검증,
  ⓑ 해당 맵이 등장하는 최소 stage에서 글라이드 획득이 가능한지 확인. stage0~1 맵엔 게이트를 두지 말 것.
  (2026-06-12: 외벽 옥상 게이트 제거, 비밀 보상은 일반 XP/HP로 유지. cooling/ward/watchtower 게이트는 유효.)

- **레버/해치 등 비밀 보상은 맵 난이도와 비례해야 한다 — 쉬운 맵이 더 주면 역전.**
  외곽 진입로(risk1, 짧은 가로) 해치는 XP5, 외벽 옥상(risk2, 수직 등반+저격) 해치는 XP2+HP1로
  더 어려운 맵이 더 적게 줬다(사용자 지적). 보상 배치 시 맵 risk/길이와 같은 방향인지 한 번 훑을 것.
  (2026-06-12: 외벽 옥상 해치 XP2→4로 상향.)

- **데미지 +N 스택은 적 HP 분포에 막혀 효용이 빠르게 사라진다 — 항상-유효 효과(공속/관통)를 우선.**
  적 HP가 대부분 1~2(patrol 2, 그 외 1, 방패병만 3)라, 데미지 2면 방패병 빼고 전부 1샷. 그 위로
  올리는 +데미지는 방패병 1샷에만 의미가 있는데 방패병은 폭발물이 상성 카운터라 사실상 무효였다.
  → 스킬 상위 티어는 데미지 스택 대신 연사 속도·관통처럼 적 HP와 무관하게 항상 DPS/도달을 늘리는
  효과로. (2026-06-12: fire_boost T2 "데미지+2"→"속사(연사 +40%)", 데미지는 T1에서 2 고정.)

- **비밀 레버는 해저드 옆 지면이 아니라 안전한 발판 위에 두고, "레버로 솟는 발판" 연출이 꼭 필요한지 따질 것.**
  냉각 시설(cooling) 레버가 증기 분출구(steam_vent x1380) 바로 옆 지면(1450,548)에 있어 당기러
  가는 것 자체가 해저드 노출이었고, 당기면 솟는 발판(drop_platform)으로 위 해치 XP를 먹는 구조가
  과했다(사용자: "레버가 가시 위에 있어 불합리, 솟는 발판 굳이 필요 없어 보임", 2026-06-19).
  → 레버를 증기 사이 안전 발판(1560,380) 위로 옮기고 발판/해치 연출을 빼 XP를 그 발판 위에 직접
  spawn. 비밀 보상의 "도달 난이도"는 해저드 근접이 아니라 발견성(glow)·위치로 줄 것. back_alley·
  rooftops의 drop_platform 퍼즐은 동선·인과가 맞아 유지.

- **적/보스의 시각(Visual)과 피격 판정(CollisionShape2D)은 분리돼 있다 — 크기를 바꿀 땐 반드시 둘 다.**
  Enemy/보스는 CharacterBody2D + 자식 CollisionShape2D가 피격 판정이고, 시각은 별도 Node2D("Visual",
  `CharacterArt.build_*`)다. `visual.scale`만 키우면 *보이는 크기만* 커지고 탄은 그대로라 "큰데 안 맞는"
  착시가 생긴다. → 크기 조정 시 ⓐ `visual.scale`(Enemy.gd 적 분기 / BossSentinel `_ready`)과 ⓑ 콜리전
  `shape.size`(Stage `_spawn_enemy` / BossSentinel `_ready`·`_spawn_minion`)를 같은 비율로 함께 바꾼다.
  드론은 스폰 콜리전이 Stage(`_spawn_enemy`)·BossSentinel(`_spawn_minion`) 두 곳에 중복 정의돼 있어 둘 다
  맞춰야 일관됨. patrol/shield가 이미 이 패턴. (2026-06-23 드론·보스 피격 범위 확대 — 피드백 반영.)

- **플랫포머 점프에 coyote time이 없으면 "분명 점프했는데 안 올라가짐"으로 읽힌다.**
  `Player.gd._try_jump`는 `is_on_floor()`만 보고 지상 풀점프(`JUMP_VELOCITY -540`) vs 공중 2단(`×0.92`)을
  가른다. 가장자리에서 *걸어서 떨어지면* `is_on_floor()`가 즉시 false인데 `jumps_used`는 0이라, 첫 점프가
  지상 풀점프가 아니라 약한 2단(-497)으로 나가고 더블점프 1회를 소모한다 → 높이 부족으로 플랫폼에 못 닿고,
  바닥에 멈췄다 뛰면(is_on_floor true) 성공해서 "멈췄다 하면 됨"이 된다(2차 피드백 다수, [[playtest_round2]]).
  → **coyote time(~0.08~0.1s) + jump buffer를 짝으로 추가.** 가장자리 이탈 직후 윈도우의 첫 점프는 지상
  점프로 처리. 더불어 제자리 더블점프(수평속도 0)의 정점이 플랫폼 간격에 닿는지 레벨 좌표로 검증할 것
  (수평 입력 없이 한 칸은 오르게). 점프 "느낌" 버그는 대개 입력 타이밍 관용(coyote/buffer) 부재가 원인.

- **지속 상태 플래그(`veil_degraded`)는 서사가 바뀌는 맵 경계에서 명시 해제해야 한다.**
  VEIL 시야 붕괴는 한 번 켜지면 *이후 맵에 계속 유지*되는데, 비상 탈출로(최종 비전투 탈출)까지 끌려와
  "조용히 빠져요" 톤의 맵이 어둡게(축소 비네트 + "안 보임") 나왔다(사용자 보고, 2026-06-23). 게다가 일반
  모드는 탈출로가 stage6이라 `_arm_act3_vision_subtitle`의 `stage>=5`에 걸려 *재발동*까지 했다. → 탈출
  선택 시 `record_route_choice`에서 해제 + `_arm_act3_vision_subtitle`에 route 가드. `playground_active`
  누수와 동형 — **지속/세션 플래그는 켜는 곳뿐 아니라 "의미가 끝나는 경계"에서 끄는 코드를 짝으로 둘 것.**
  (지속 플래그를 새로 만들면: 어디서 켜고 / 어디서 꺼지는지를 같이 설계. 단일 해제처는 누수원.)

---

## 모바일 / 터치 (2026-07-01)

- **`DisplayServer.is_touchscreen_available()`은 모바일 *웹*에서 false를 흔히 반환한다 — 터치 UI 게이팅이 안 켜진다.**
  안드로이드 크롬에서 false라 터치 패드가 생성 안 돼 "데스크톱 화면 그대로"가 나왔다(사용자 보고).
  → 웹이면 `JavaScriptBridge.eval("(navigator.maxTouchPoints||0)>0 || 'ontouchstart' in window")`로 직접
  판정(`OrientationGuard.is_touch_device()`). 데스크톱 네이티브는 is_touchscreen_available()로 충분.

- **터치 조작을 인게임(Stage)에만 붙이면 그 앞 진입 경로에서 막혀 게임 시작 자체가 불가하다.**
  패드를 Stage에만 넣었더니 튜토리얼(=실제 플레이)·오프닝 멘트(브리핑)를 폰에서 못 넘겨 "플레이를 못한다"
  (사용자). → 씬 흐름 전체를 터치로 커버: Tutorial엔 패드(player가 Player.gd라 폴링 입력 그대로 먹음),
  진행성 화면(Briefing/Death/Ending)은 화면 탭을 진행 입력으로. 새 조작 넣을 땐 Title→Tutorial→Briefing→
  RouteMap→Stage 전 경로가 폰으로 통과되는지 확인.

- **화면을 덮는 Control이 있는 씬에서 `_unhandled_input`은 터치 탭을 못 받는다(키보드는 받음).**
  Briefing 등은 루트가 full-rect Control이라 탭(emulate 마우스)이 gui_input에서 소비돼 `_unhandled_input`에
  ScreenTouch가 안 온다. 키(jump)는 UI가 안 먹어 데스크톱에선 정상이라 놓치기 쉽다(사용자: "튜토는 되는데
  오프닝 멘트가 안 넘어감"). → 터치 진행이 필요한 화면은 `_input`으로(UI 소비 전에 받음). 자체 클릭 버튼이
  있으면 그 상태에서 return해 버튼 gui_input으로 넘긴다.

- **모바일 웹은 데스크톱 비율(1280×720) UI를 그대로 렌더해 버튼·글씨가 작아 누르기 어렵다.**
  stretch/expand는 해상도만 맞출 뿐 UI 물리 크기를 안 키운다. 폰 작은 화면에선 메뉴/설정 버튼이 너무
  작았다(사용자 보고). → 터치 기기에서 `get_window().content_scale_factor`를 올려 확대(메뉴 1.4 / 인게임
  1.1, 씬 그룹으로 분기). 인게임은 월드도 같이 커지니 밸런스 고려해 낮게.

- **모바일 웹 가로 강제는 project 설정으론 안 되고 런타임 처리가 필요하다.**
  `window/handheld/orientation`은 네이티브 빌드에만 먹고 브라우저는 무시(기기 방향 추종). → 웹은 첫 제스처에
  `screen.orientation.lock('landscape')`(fullscreen 필요, 안드로이드만; iOS Safari 미지원) 시도 + 세로면
  "가로로 돌려주세요" 안내로 폴백. fullscreen 대상은 `canvas`보다 `document.documentElement`가 안정적.

- **`emulate_mouse_from_touch`(기본 true)로 화면 탭은 좌클릭도 합성한다 — is_tap과 좌클릭을 둘 다 처리하면 2회 발동.**
  탭 한 번에 ScreenTouch + 합성 InputEventMouseButton(LEFT)이 각각 `_input`에 와, `is_tap`(ScreenTouch)과
  `MOUSE_BUTTON_LEFT`을 모두 인정하는 화면(ArcturusDocumentOverlay: 줄 진행/닫기)은 한 탭에 2줄이 넘어간다.
  `set_input_as_handled()`는 *다른* 합성 이벤트를 막지 못한다(별개 이벤트). Briefing류는 좌클릭을 안 다루고
  jump/is_tap만 봐서 무사했음. → 좌클릭 분기에 `not OrientationGuard.is_touch_device()` 가드를 달아
  터치 기기에선 is_tap 경로만 쓴다. emulate 자체는 메뉴 버튼 탭에 필요하니 끄지 말 것(2026-07-02).

- **process_mode=ALWAYS 오버레이를 `show_doc()` 없이 add_child만 하면 _process가 미생성 노드에서 null 크래시.**
  검증 하니스가 `ArcturusDocumentOverlay.new()`+`add_child`만 하고 `show_doc(lines)`를 안 부르면, `paper`가
  아직 null인데 _process(line166 `paper.position`)가 돌아 "property 'position' on Nil"이 뜬다. 실게임은
  add_child 직후 같은 프레임에 show_doc를 부르므로 정상. → 지연 초기화 오버레이는 **하니스에서도 정식 진입
  함수까지 호출**해 검증할 것(안 그러면 하니스 인공물을 실버그로 오판). (2026-07-02 터치 검증에서 관측.)

---

## 렌더링 / 레이아웃

- **오버레이/끝 메뉴를 띄울 때 그 아래 스크롤·스택 컨텐츠를 숨기지 않으면 멈춘 위치에서 겹친다.**
  크레딧 끝 메뉴(`Credits._show_end_menu`)가 ESC로 스크롤 도중 호출되면 `_process`가 `_menu_shown`
  에서 멈춰 크레딧 본문(`_scroll`)이 그 자리에 정지 → 메뉴 버튼과 겹쳤다(끝까지 자동 스크롤된
  경우엔 본문이 화면 위로 올라가 우연히 안 겹쳐, 특정 진행도에서만 재현, 2026-06-19). → 메뉴 진입
  시 `_scroll.visible = false`로 배경 컨텐츠를 명시적으로 분리. "보일 때만 겹치는" 류는 스크롤 위치에
  의존하므로 한 번 안 겹친다고 안전하다고 보지 말 것.

- **`--headless`로 Stage 진입 시 `_build_camera`(Stage.gd) backtrace는 무해한 헤드리스 quirk.**
  헤드리스엔 실제 윈도우/뷰포트가 없어 카메라 셋업 일부가 에러를 찍지만 *창모드 게임 로직엔* 영향 없음.
  창 모드(`--windowed`) 실행에선 안 남. 검증 하니스가 Stage를 헤드리스로 띄울 땐 이 backtrace 무시.

- **그러나 그 카메라 에러는 헤드리스에서 `Stage._ready`를 그 지점(`_build_camera`)에서 *중단*시킨다 — 이후
  코드가 안 돈다.** `_ready` 순서상 `_build_camera`(line 67) *뒤*의 `_build_hud`/`_spawn_enemies`/`_build_goal`/
  `_setup_veil_mistakes`(72) 등은 헤드리스에서 실행되지 않는다. `_map_data`는 그 *앞*(`_build_world`, 65)에서
  채워져 멀쩡해 보이므로 "빌드는 됐는데 진입 자막/스폰 로직이 안 탄다"로 오인하기 쉽다(2026-06-26 B-4 첫
  드론 반응이 헤드리스에서 `false`로 나와 버그로 오판할 뻔). → **`_build_camera` 이후의 Stage 진입 로직 검증은
  반드시 `--windowed`로.** 헤드리스로는 그 메서드를 *직접 호출*(`s.call("_arm_drone_intro")`)해 로직만 분리
  검증하거나, 자동 경로(_ready 통과)는 창모드로 확인. (헤드리스 RC=0 + 카메라 backtrace만 있어도 _ready
  완주를 단정하지 말 것.)

- **CanvasLayer의 Control 자식은 anchor로 화면 크기를 못 받는다.**
  CanvasLayer는 Control이 아니라 자식에게 rect를 전파하지 않는다. 그 아래 Control에 `PRESET_FULL_RECT`를
  걸어도 self.size=0이 된다. full-rect로 깐 손자 노드(예: 비네트 TextureRect, STRETCH_SCALE)는 늘어날
  대상이 없어 **텍스처 native 크기로 좌상단(0,0)에만** 그려진다.
  → CanvasLayer 자식 Control은 `size = get_viewport_rect().size`로 직접 맞추고 `get_viewport().size_changed`에
  연결해 해상도 변경에도 갱신. (2026-06-08: VeilSight 시안 테두리 비네트가 좌상단 320×200 blob으로만
  떴던 버그 — 이 패턴이 원인. `VeilSight._fit_to_viewport`로 해결.)

- **"해상도 흐릿함"은 엔진 stretch가 아니라 에디터 임베드/OS 스케일링.**
  `window/stretch/mode="canvas_items"`는 Godot 4에서 **창의 네이티브 해상도로 2D를 렌더**한다(폰트도
  그 해상도로 래스터 → 선명). standalone `--windowed --resolution 1920x1080` 렌더의 뷰포트 텍스처가
  1886×1061(=창 크기)로 나오고 한글 텍스트가 또렷함을 확인. 따라서 "작은 화면을 디지털 줌한 듯 흐릿"은
  ① 에디터가 게임을 **임베드/플로팅 창**으로 띄워 스케일하거나 ② **Windows HiDPI(125/150%) OS 업스케일**
  때문. → 진짜 환경은 **내보낸 빌드**로 확인. `allow_hidpi`는 4.x 기본 true라 명시 불필요.
  체감 선명도는 **텍스트 검정 아웃라인**(outline_size)으로 더 끌어올림(faux-bold보다 가볍고 또렷).
  (2026-06-08 플레이테스트.)

- **런타임에 창 크기를 바꾸면 canvas_items content_scale이 카메라 프레이밍에 안 먹는다.**
  스크린샷 하니스(IgShotter)에서 `_ready`에 창을 1920x1080으로 키웠더니, UI(Control/CanvasLayer)는
  정상 스케일됐는데 **Camera2D(월드)만 설계(1280폭)보다 넓게(≈1920폭) 잡혀** 캐릭터가 작게 나왔다.
  원인: 런타임 리사이즈가 `content_scale_size`를 자동 갱신하지 않아 2D 카메라 변환 기준이 어긋남.
  → 창 리사이즈와 함께 `get_window().content_scale_size = Vector2i(1280,720)`(+mode/aspect)을 **명시
  설정**하면 월드+HUD가 1.5배 균일 확대되며 설계 프레이밍이 유지된다(IgShotter._set_high_res).
  추가로 임팩트가 필요한 클로즈업은 `camera.zoom`/`camera.offset`로 따로 당긴다. FIXED(ARENA) 카메라는
  `get_visible_rect()` 기준 zoom_fit이 자기일관적이라 영향 없음. (2026-06-22 IG 스크린샷 작업.)

## 런타임 (상세: 메모리 project-runtime-safety)

- **paused / Engine.time_scale carry로 인한 freeze.**
  `get_tree().paused`는 SceneTree 전역이라 scene 전환에 carry된다. overlay/도전방 등에서 paused 해제
  누락 시 다음 scene이 freeze. 새 overlay/scene 추가 시 paused 해제 안전판을 같은 패턴으로 둘 것.

- **검증 하니스가 Stage를 *단독* 부팅하면 `get_tree().paused=true`로 시작 → `_physics_process` 안 돈다.**
  실제 게임은 Briefing._ready가 `paused=false`로 풀고 Stage로 오지만, 래퍼에서 Stage.tscn을 직접
  인스턴스화하면 그 해제를 건너뛰어 트리가 paused로 남는다. 그러면 이동 발판(MovingPlatform) 등
  `_physics_process` 구동 요소가 첫 프레임만 돌고 멈춰 "안 움직인다"로 오판된다(2026-06-26 MovingPlatform
  검증에서 dx=0으로 나와 메커닉 버그로 오해할 뻔). → **Stage 단독 부팅 검증은 `add_child` 직후
  `get_tree().paused = false`를 명시**해 실게임 조건(unpause)을 만들 것. (메커닉이 unpause에서 정상이면
  실게임에서도 정상.)

- **트리에서 빠진 노드의 콜백/틱이 `get_tree()`를 쓰면 null 크래시.**
  플레이어 사망 → 씬 전환 중, 아직 free 안 된 적의 tween/timer 콜백이나 한 프레임 늦은 틱이
  `get_tree().get_nodes_in_group(...)`를 호출 → "Cannot call method ... on a null value"(Enemy.gd, 2026-06-09).
  → 트리 접근(`get_tree()`/`get_world_2d()`/`get_parent()`) 전에 null 가드. player 조회처럼 자주 쓰는
  접근은 **단일 헬퍼**(`_find_player`)에 가드를 모아 모든 호출처를 한 번에 보호. `_physics_process`엔
  `is_inside_tree()` 가드를 더해도 저렴.

- **`get_tree().paused=true` 중엔 PAUSABLE 노드가 입력 콜백(`_input`/`_unhandled_input`)을 못 받는다.**
  pause는 `_process`뿐 아니라 입력 처리도 막는다. 그래서 "ESC로 자기 일시정지 메뉴를 *열고 닫기*"를
  PAUSABLE 호스트(RouteMap/Stage)의 `_unhandled_input`에 두면, 연 뒤(paused=true)엔 닫는 ESC가
  호스트에 도달하지 않아 안 닫힌다(헤드리스 재현 확인, 2026-06-15). → 메뉴 *씬*(게임 로직 없는 RouteMap)은
  `process_mode = PROCESS_MODE_ALWAYS`로 둬 paused 중에도 ESC를 받게. Stage처럼 ALWAYS로 못 두는
  게임플레이 호스트는 ESC는 열기만, 닫기는 "계속하기" 버튼(ALWAYS)에 맡기는 게 현재 동작.
  ALWAYS로 둘 땐 `_input`이 paused 중 SPACE를 소비하지 않게 가드(일시정지 메뉴 버튼 ui_accept 보호).

- **헤드리스 `-s` SceneTree 스크립트에선 오토로드가 컴파일 타임에 안 보일 수 있다.**
  `godot --headless -s test.gd`로 `GameState` 등 오토로드를 직접 식별자로 쓰면 "Identifier not found"
  컴파일 에러(2026-06-15). 오토로드가 필요한 런타임 검증은 **래퍼 .tscn(Control)을 창모드로 실행**하면
  오토로드가 정상 초기화된다. `Input.parse_input_event`로 ESC 등 액션을 주입해 동작을 관찰할 수 있다.

- **부트스트랩 노드의 `_ready()`에서 `change_scene_to_file()` 직접 호출 → "Parent node is busy adding/removing children".**
  main 씬(Main.gd)이 트리에 붙는 중에 같은 프레임에 씬을 교체하려 해 SceneTree가 충돌 경고를 낸다(codex 리뷰,
  2026-06-18 헤드리스 재현). 게임은 동작하나 콘솔에 에러. → `change_scene_to_file.call_deferred(path)`로
  한 프레임 미뤄 전환. `--quit-after 30` 헤드리스 부팅으로 경고 소멸 확인 가능.

- **세션 플래그(`playground_active`)는 *해제처가 하나뿐*이면 누수된다 — 해제는 보편 초기화(`reset()`)에 둘 것.**
  디버그 연습장 진입(`Settings._on_playground_pressed`)이 `playground_active=true`만 켜고, 해제는
  연습장 오버레이 *종료 버튼*(`PlaygroundOverlay._on_exit`) 한 곳에만 있었다. ESC→타이틀 등 다른 경로로
  연습장을 빠져나오면 플래그가 true로 남아, **다음 일반 모드에서 스테이지를 클리어해도** `_trigger_stage_clear`
  가 연습장 분기(`_show_playground_clear_msg`)로 빠져 패널만 뜨고 다음 맵으로 안 넘어갔다(2026-06-23 치명
  버그). → `paused` carry와 동형 함정: **모드/세션 플래그는 켜는 곳이 여럿이어도 해제는 "타이틀 복귀/새 런마다
  반드시 지나는" `GameState.reset()`(+`start_main_game()`)에 둬 단일 누수 차단.** 일반 모드는 항상 Title을
  거치고 `Title._ready`가 `reset()`을 부르므로, reset()에 해제를 넣으면 모든 경로가 막힌다. ([[project-runtime-safety]])
