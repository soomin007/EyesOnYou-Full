extends Node

# 입력 모드 — 마지막으로 들어온 이벤트가 키보드/마우스인지 패드인지 추적.
# UI hint 라벨/키캡 표지가 이 값에 따라 실시간 swap된다.
# 변경 시 input_kind_changed 시그널 → 각 UI가 _refresh_hints 갱신.
signal input_kind_changed(kind: String)
# 스킬 티어가 바뀔 때 — Player가 캐릭터 부착물(파우치·윙 등) 외형을 갱신하는 데 사용.
signal skills_changed
const PAD_AXIS_DEADZONE: float = 0.4
var last_input_kind: String = "kb"  # "kb" | "pad"

const TOTAL_STAGES: int = 7
const SCORE_THRESHOLD: int = 4
const SETTINGS_PATH: String = "user://settings.cfg"
# 런 진행 저장(이어하기) — 설정과 분리한 별도 파일. 웹에선 user://가 브라우저 IndexedDB에 영속.
const RUN_PATH: String = "user://run.cfg"
const RUN_VERSION: int = 1
# 플레이 피드백 설문(구글 폼). 타이틀·크레딧 끝 메뉴의 "피드백 보내기"가 연다.
const FEEDBACK_URL: String = "https://forms.gle/byS8EABJitB9r6z88"
const KEYBIND_ACTIONS: Array[String] = ["move_left", "move_right", "jump", "attack", "dash", "skill", "pause"]
# 모든 플레이어가 기본 보유하는 베이스라인 스킬 (트리 외)
# 자료형: Dictionary[String, int] — line_id → 보유 티어 (베이스라인은 항상 1).
const STARTING_SKILLS: Dictionary = {"dash": 1, "double_jump": 1}

var current_stage: int = 0
var death_count: int = 0
var score: int = 0

# --- 실력 추적 (VEIL 적응형 맵 추천) ---
# 피격·죽음을 스테이지 단위로 모아 "고전했나/잘했나"를 읽고 추천 톤을 정한다.
# baseline은 record_route_choice(스테이지 진입 직전)에서, 마감은 on_stage_clear에서.
# 죽음 재시도는 같은 baseline..clear 창에 누적돼 자연히 "고전" 신호가 된다.
var hits_taken: int = 0              # 누적 피격 수 (take_hit이 invuln 통과 시 +1)
var _stage_hits_base: int = 0        # 현재 스테이지 진입 시점 hits_taken 스냅샷
var _stage_deaths_base: int = 0      # 현재 스테이지 진입 시점 death_count 스냅샷
var _stage_start_msec: int = 0       # 현재 스테이지 진입 시각
var recent_stage_hits: Array = []    # 최근 스테이지별 피격 수 (최대 2)
var recent_stage_deaths: Array = []  # 최근 스테이지별 죽음 수 (최대 2)
var last_stage_secs: float = 0.0     # 직전 스테이지 소요 시간 (참고용)

# 어투 trust 재설계(2026-06-13, veil_trust_arc.md §3) — 따뜻함=관계, 0에서 climbing.
# 추천 따라 클리어 +2 / 함께 고비 +2 / 독립 성공 +0. 클리어 시점(on_stage_clear)에 적립.
var trust_score: int = 0
var aggression_score: int = 0
var shared_hardship: int = 0      # 함께 고비를 넘긴 횟수 — WARM 취약함 게이트(§3.5)
var rec_count: int = 0            # VEIL이 추천을 제시한 스테이지 수 — 엔딩 수용률 분모(§3.3)
var followed_count: int = 0       # 그중 추천을 따른 수 — 엔딩 수용률 분자
var route_history: Array = []
var last_veil_recommended_route: String = ""
var followed_veil_last_choice: bool = false

# VEIL 시야 붕괴(ACT3 degradation)가 한 번 시작되면 이후 맵에서도 계속 어두운 상태 유지.
# VeilSight.begin_degradation()에서 켜고, VeilSight._ready가 이 값을 보고 시작부터 degraded.
var veil_degraded: bool = false
# 시야 역전 onset 맵에서 "진입부터 붕괴" 처리를 위한 1회용 신호 — record_route_choice가 켜고
# Stage._ready가 진입 역전 멘트 1회 소비 후 끈다(중간 글리치·자막 겹침 제거, 사용자 보고).
var veil_reversal_pending: bool = false

var skills: Dictionary = {}
var current_route_id: String = ""
var current_route_tags: Array = []
var current_route_risk: int = 1   # 1~3, 적 수 배율 + 행동 강화에 사용
var current_route_reward: int = 1  # 1~3, 클리어 시 보너스 XP에 사용
var current_route_challenge: bool = false  # 도전 맵 여부 — 고비 판정용
var current_route_hidden: bool = false     # 히든 맵 여부 — 고비 판정용

var player_max_hp: int = 3
var player_hp: int = 3
var player_xp: int = 0
var player_level: int = 1
const XP_PER_LEVEL: int = 8

var tutorial_done: bool = false
var bgm_volume: float = 1.0
var sfx_volume: float = 1.0

# 접근성 — settings.cfg에 영속. reset()에서 안 지움(볼륨처럼 사용자 환경 설정).
var screen_brightness: float = 1.0   # 0.5~1.5 (1.0=기본). Accessibility 오버레이가 반영.
var sfx_captions: bool = false       # 효과음 자막 (무음 플레이 대응)

# 디스플레이 — settings.cfg에 영속. 환경 설정이라 reset()에서 안 지움.
# 웹에선 창 크기는 브라우저 캔버스가 정하므로 무의미 → 전체화면 토글만 적용.
var fullscreen: bool = false
var window_size_index: int = 0       # WINDOW_SIZES 인덱스 (창모드일 때만)
const WINDOW_SIZES: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]

# 스토리 모드 — 키보드/패드 조작이 어려운 사람을 위한 간략화 모드.
# 체력 무제한 / 드론 배제 / 보스 P1만 / 스테이지·맵 수 축소.
# Title의 "스토리 모드" 버튼으로만 켜지고, ending에서 reset() 시 꺼진다.
var story_mode: bool = false
const STORY_TOTAL_STAGES: int = 5

# 디버그 연습장 모드 — Settings에서 진입. 영속화하지 않음.
var playground_active: bool = false

# 엔딩 후 "다시 플레이하기"로 들어온 회차인가 — 물음표 방 첫 단말기 변형(VEIL-1 → 추가 풀)을 가른다.
# reset()/start_main_game()에서 일부러 안 지운다(크레딧 버튼이 set한 값이 새 런까지 살아남아야 함).
# 부스(기기≠사람)에서 새 사람이 VEIL-1 도입을 놓치는 걸 막으려 기기 영속 카운트 대신 명시적 신호로.
var replaying: bool = false

# 디버그 메뉴 잠금. 타이틀에서 비밀 키 시퀀스("snu")를 입력해야 활성. 영속화하지 않음.
# 부스/공유 환경에서 일반 플레이어가 디버그 기능에 접근하지 못하도록.
var debug_unlocked: bool = false

# ??? 맵 진행 중 Player 입력 제한 (이동/점프만 허용, 공격/대시/스킬 비활성)
var restrict_combat_input: bool = false

# 도감 — 첫 조우 시 카드 한 번만 띄우기 위한 영속 플래그.
# 게임 reset()에서는 비우지 않음 (한 번 본 적은 다음 런에서도 본 거).
var seen_enemies: Array = []

# ??? 맵 누적 방문 횟수 — settings.cfg에 영속.
# 첫 방문(0): 기존 VEIL-1/VEIL-2/VEIL 고백 고정.
# 이후 방문(>=1): 추가 풀에서 1개 랜덤 교체 (VEIL-1 단말기 자리).
var hidden_visit_count: int = 0
# 이스터에그 방(ARCTURUS 아카이브) 방문 여부 — 1회만 트리거되도록 영속.
var visited_arcturus: bool = false

# 본 엔딩 목록(A/B/C/D) — settings.cfg에 영속. 다회차 "엔딩 모으기" + 리플레이 대사 차별화의 토대.
var endings_seen: Array = []
# 엔딩까지 도달한 완주 횟수 — settings.cfg에 영속.
var playthrough_count: int = 0

func _input(event: InputEvent) -> void:
	# 입력 모드 자동 감지. autoload Node여서 모든 InputEvent를 받는다.
	# 패드 motion은 데드존 이상만 인정 (스틱 미세 떨림 무시).
	var kind: String = ""
	if event is InputEventKey or event is InputEventMouseButton or event is InputEventMouseMotion:
		kind = "kb"
	elif event is InputEventJoypadButton:
		kind = "pad"
	elif event is InputEventJoypadMotion:
		if absf((event as InputEventJoypadMotion).axis_value) < PAD_AXIS_DEADZONE:
			return
		kind = "pad"
	if kind == "" or kind == last_input_kind:
		return
	last_input_kind = kind
	emit_signal("input_kind_changed", kind)

func is_pad_mode() -> bool:
	return last_input_kind == "pad"

# 입력 락아웃 — 메뉴/오버레이 등장 직후 일정 시간 동안 첫 버튼 포커스를 보류.
# 사용자 피드백: 점프 연타로 메뉴를 본의 아니게 활성화시키는 사고 방지.
# release 대기보다 시간 기반(기본 1.0s)이 더 단순·예측 가능.
const INPUT_LOCKOUT_DURATION: float = 1.0

func arm_focus_with_delay(host: Node, first_btn: Button, delay: float = INPUT_LOCKOUT_DURATION, wire_sfx: bool = true) -> void:
	if first_btn == null:
		return
	# 메뉴 root 아래 모든 Button에 ui_focus / ui_confirm 자동 hook.
	# 게임 내 선택(LevelUpOverlay 카드)처럼 별도 SFX가 있는 곳은 wire_sfx=false.
	if wire_sfx and host != null:
		SfxPlayer.wire_ui_buttons(host)
	var btn_ref: WeakRef = weakref(first_btn)
	get_tree().create_timer(delay).timeout.connect(func() -> void:
		var b := btn_ref.get_ref() as Button
		if b != null and is_instance_valid(b):
			b.grab_focus()
	)

# 짧은 헬퍼 — 입력 모드에 따라 둘 중 하나를 반환. UI 라벨에서 사용.
func hint(kb_text: String, pad_text: String) -> String:
	return pad_text if last_input_kind == "pad" else kb_text

# 액션의 대표 입력 라벨 — InputMap에서 첫 키(없으면 마우스)를 읽어 표시용 문자열로 만든다.
# 키 안내의 단일 소스: 기본 키를 바꾸거나 사용자가 설정에서 리매핑해도 안내가 자동으로 따라온다.
# (하드코딩 "J"/"Q" 등을 곳곳에 박지 말 것 — 키 변경 시 안내가 거짓말이 된다.)
func action_label(action: String, fallback: String = "?") -> String:
	if not InputMap.has_action(action):
		return fallback
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var kc: int = k.physical_keycode
			if kc == 0:
				kc = k.keycode
			var s: String = OS.get_keycode_string(kc)
			if s != "":
				return s
		elif ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT: return "마우스 좌클릭"
				MOUSE_BUTTON_RIGHT: return "마우스 우클릭"
				MOUSE_BUTTON_MIDDLE: return "마우스 가운데"
	return fallback

# 하단 조작 안내 한 줄 — 키 라벨을 action_label로 동적 조립(단일 소스).
# Tutorial·Stage 일시정지 등이 공유한다. 키 변경/리매핑 시 자동 반영.
func controls_hint_line() -> String:
	if is_pad_mode():
		return "좌스틱/D-Pad 이동   A 점프   ↓ 내려가기   X/RT 사격   B/RB 대시   Y 스킬   START 일시정지"
	return "%s/%s 이동   %s 점프   %s 내려가기   %s 사격   %s 대시   %s 스킬   %s 일시정지" % [
		action_label("move_left", "A"), action_label("move_right", "D"),
		action_label("jump", "W"), action_label("move_down", "S"),
		action_label("attack", "J"), action_label("dash", "K"),
		action_label("skill", "L"), action_label("pause", "ESC")]

func reset() -> void:
	current_stage = 0
	death_count = 0
	score = 0
	trust_score = 0
	aggression_score = 0
	shared_hardship = 0
	rec_count = 0
	followed_count = 0
	route_history = []
	last_veil_recommended_route = ""
	followed_veil_last_choice = false
	skills = STARTING_SKILLS.duplicate()
	current_route_id = ""
	current_route_tags = []
	current_route_risk = 1
	current_route_reward = 1
	current_route_challenge = false
	current_route_hidden = false
	player_max_hp = 3
	player_hp = 3
	player_xp = 0
	player_level = 1
	story_mode = false
	veil_degraded = false
	veil_reversal_pending = false
	# 디버그 연습장 플래그 누수 차단 — 연습장을 종료 버튼 아닌 경로(ESC→타이틀 등)로 빠져나오면
	# playground_active가 true로 남아, 다음 일반 모드 클리어가 _trigger_stage_clear에서 연습장 분기로
	# 빠져 패널만 뜨고 다음 맵으로 안 넘어가던 치명 버그. reset()은 타이틀 복귀/새 런마다 호출되므로 여기서 해제.
	playground_active = false
	_reset_perf_metrics()

# 튜토리얼 종료 후 본편 시작 시 호출. 진행/스킬/XP 모두 초기화 — 튜토리얼은
# 연습용이라 본편에 영향 없음. VEIL이 "잠깐 빌려드려요" 멘트로 명시.
# (이전엔 튜토리얼에서 고른 스킬을 본편에 들고갔지만, 사용자 피드백으로 분리)
func start_main_game() -> void:
	current_stage = 0
	death_count = 0
	score = 0
	trust_score = 0
	aggression_score = 0
	shared_hardship = 0
	rec_count = 0
	followed_count = 0
	route_history = []
	last_veil_recommended_route = ""
	followed_veil_last_choice = false
	current_route_id = ""
	current_route_tags = []
	current_route_risk = 1
	current_route_reward = 1
	current_route_challenge = false
	current_route_hidden = false
	player_max_hp = 3
	player_hp = player_max_hp
	player_xp = 0
	player_level = 1
	skills = STARTING_SKILLS.duplicate()
	veil_degraded = false
	veil_reversal_pending = false
	playground_active = false  # 연습장 플래그 누수 차단(디버그→일반 모드) — reset()과 동일 방어.
	_reset_perf_metrics()

func _reset_perf_metrics() -> void:
	hits_taken = 0
	_stage_hits_base = 0
	_stage_deaths_base = 0
	_stage_start_msec = 0
	recent_stage_hits = []
	recent_stage_deaths = []
	last_stage_secs = 0.0

func record_route_choice(route: Dictionary, recommended_id: String) -> void:
	var rid: String = route.get("id", "")
	route_history.append(rid)
	current_route_id = rid
	current_route_tags = route.get("tags", [])
	current_route_risk = int(route.get("risk", 1))
	current_route_reward = int(route.get("reward", 1))
	current_route_challenge = bool(route.get("challenge", false))
	current_route_hidden = bool(route.get("hidden", false))
	# 비상 탈출로: 시야 붕괴 해제(끌려온 degradation 끔). 탈출=종착이라 이후 맵·엔딩 영향 없음.
	# 그 외, 보스/탈출 직전 첫 전투 맵(일반 stage>=4 / 스토리 stage2~3, 아직 안 붕괴)은 "진입부터 붕괴"
	# onset으로: VeilSight가 시작부터 어둡고 진입 시 역전 멘트 1회(Stage가 pending으로 처리). 중간 글리치·
	# 자막 겹침을 없애 "갑자기 와다닥" 느낌 제거(사용자 보고).
	if rid == "route_escape":
		veil_degraded = false
		veil_reversal_pending = false
	elif not veil_degraded:
		var reversal_onset: bool = (current_stage == 2 or current_stage == 3) if story_mode else (current_stage >= 4)
		if reversal_onset:
			veil_degraded = true
			veil_reversal_pending = true
	followed_veil_last_choice = (rid == recommended_id and recommended_id != "")
	# 엔딩 도덕 축 = 추천 수용률(§3.3). 선택 시점에 1회만 집계 — 죽음 재시도엔 record가
	# 재호출되지 않으므로 한 맵당 한 번. (어투 trust는 클리어 시점에 적립 — on_stage_clear.)
	if recommended_id != "":
		rec_count += 1
		if followed_veil_last_choice:
			followed_count += 1
	# 공격성 — 전투 태그/도전 맵 선택. 엔딩 축이며 어투 trust와는 무관(§2 두 축 분리).
	if "전투" in current_route_tags or "근접전" in current_route_tags:
		aggression_score += 1
	if current_route_challenge:
		aggression_score += 1
	# 실력 추적 baseline — 이 스테이지에 들어가기 직전 스냅샷. 죽음 재시도엔 재호출되지
	# 않으므로 baseline..on_stage_clear 한 창에 재시도의 피격·죽음이 모두 누적된다.
	_stage_hits_base = hits_taken
	_stage_deaths_base = death_count
	_stage_start_msec = Time.get_ticks_msec()

# 피격 1회 등록 — Player.take_hit이 invuln을 통과한 실제 타격마다 호출.
# (스토리 모드 체력 무제한이어도 타격 자체는 카운트 → 모드 무관 실력 신호.)
func register_hit() -> void:
	hits_taken += 1

# 방금 깬 스테이지의 실력 지표를 최근 기록에 적재 (on_stage_clear에서 호출).
func _finalize_stage_metrics() -> void:
	var hits: int = max(0, hits_taken - _stage_hits_base)
	var deaths: int = max(0, death_count - _stage_deaths_base)
	last_stage_secs = float(Time.get_ticks_msec() - _stage_start_msec) / 1000.0
	recent_stage_hits.append(hits)
	recent_stage_deaths.append(deaths)
	if recent_stage_hits.size() > 2:
		recent_stage_hits.pop_front()
	if recent_stage_deaths.size() > 2:
		recent_stage_deaths.pop_front()

# 최근 스테이지 수행으로 능숙도 판정. 데이터 없으면(첫 선택) "steady".
# 죽음이 있었거나 평균 피격이 잦으면 "struggling", 거의 안 맞았으면 "skilled".
const PERF_SKILLED_HITS_MAX: float = 1.0   # 평균 이 이하 피격 = 능숙
const PERF_STRUGGLE_HITS_MIN: float = 4.0  # 평균 이 이상 피격 = 고전
func competence_tier() -> String:
	if recent_stage_hits.is_empty():
		return "steady"
	var hit_sum: int = 0
	for h in recent_stage_hits:
		hit_sum += int(h)
	var avg_hits: float = float(hit_sum) / float(recent_stage_hits.size())
	var death_sum: int = 0
	for d in recent_stage_deaths:
		death_sum += int(d)
	if death_sum >= 1 or avg_hits >= PERF_STRUGGLE_HITS_MIN:
		return "struggling"
	if death_sum == 0 and avg_hits <= PERF_SKILLED_HITS_MAX:
		return "skilled"
	return "steady"

# 신뢰 단계 — UI 톤색 + ??? 방 분기용. 어투 trust(0에서 climbing) 원값 기준(§3.4).
# 재설계(2026-06-13): trust는 음수가 안 되므로 "거리감"은 낮은 값(broken/cool)으로 표현.
# 대사 풀 밴드 선택은 veil_register_band() — 취약함 게이트 포함이라 별도.
func veil_trust_tier() -> String:
	var t: int = trust_score
	if t >= 12:
		return "high"
	if t >= 8:
		return "warm"
	if t >= 4:
		return "neutral"
	if t >= 2:
		return "cool"
	return "broken"

# 대사 풀 어투 밴드(COLD/THAW/WARM) — veil_pool_remap.md. WARM은 취약함 게이트(§3.5):
# trust가 충분해도 "같이 고비를 넘긴 적"이 없으면 THAW에 머문다(무사망 고수=COLD 가능).
func veil_register_band() -> String:
	if trust_score >= 8 and shared_hardship >= 1:
		return "warm"
	if trust_score >= 4:
		return "thaw"
	return "cold"

# 차가움(직업적)→따뜻함(유대) 그라데이션. 시작(trust 0)은 스틸블루(거리감) — 적대 빨강 아님.
func veil_tone_color() -> Color:
	match veil_trust_tier():
		"high":
			return Color(0.55, 0.97, 0.85)   # 따뜻한 청록 — 깊은 유대
		"warm":
			return Color(0.55, 0.90, 0.92)   # 청록 기운
		"neutral":
			return Color(0.72, 0.86, 0.92)   # 해빙 — 옅은 청
		"cool":
			return Color(0.64, 0.76, 0.86)   # 직업적 — 스틸블루
		"broken":
			return Color(0.60, 0.70, 0.80)   # 가장 차가움 — 거리감(적대 아님)
	return Color(0.64, 0.76, 0.86)

# (구 TONE_PREFIXES / veil_tone_prefix 제거 — 2026-06-13. 어투는 신뢰밴드 대사 풀로 운반,
#  레벨업 추천 앞 lead-in은 VeilDialogue.levelup_leadin. 미사용 dead code였음.)

# 신뢰 게이지 — UI 표시용 (0.0 ~ +1.0 정규화). 0에서 차오름(§3.1 리베이스).
func veil_trust_normalized() -> float:
	return clampf(float(trust_score) / 15.0, 0.0, 1.0)

# 신뢰 게이지 5점 문자열 — HUD/루트맵/레벨업 공용(드리프트 방지). 0에서 차오름.
const TRUST_GAUGE_THRESHOLDS: Array[int] = [2, 4, 8, 12, 16]
func veil_trust_gauge_dots() -> String:
	var dots: String = ""
	for th in TRUST_GAUGE_THRESHOLDS:
		dots += "●" if trust_score >= int(th) else "○"
	return dots

func is_high_risk() -> bool:
	return current_route_risk >= 3

func is_high_reward() -> bool:
	return current_route_reward >= 3

func enemy_count_multiplier() -> float:
	# 부스 환경에서 너무 빡세지 않게 살짝만 ↑.
	# 1=0.8 (기존 0.7), 2=1.1 (기존 1.0), 3=1.5 (기존 1.4)
	match current_route_risk:
		1: return 0.8
		3: return 1.5
	return 1.1

func add_xp(amount: int, apply_risk_bonus: bool = true) -> bool:
	# high-risk 루트(risk=3)에서 적 처치 XP +50% (스테이지 클리어 보상은 apply_risk_bonus=false로 호출).
	var gain: int = amount
	if apply_risk_bonus and current_route_risk >= 3:
		gain = int(round(float(amount) * 1.5))
	player_xp += gain
	if player_xp >= XP_PER_LEVEL:
		player_xp -= XP_PER_LEVEL
		player_level += 1
		return true
	return false

func has_skill(id: String) -> bool:
	return int(skills.get(id, 0)) >= 1

# 해당 라인의 보유 티어 반환 (0=미보유, 1~3=보유).
func get_skill_tier(id: String) -> int:
	return int(skills.get(id, 0))

# 라인을 한 단계 업그레이드. 이미 T3면 무시.
# 즉시 효과(예: hp 라인의 max_hp 증가)는 여기서 처리.
func add_skill(id: String) -> void:
	var current: int = int(skills.get(id, 0))
	if current >= 3:
		return
	var new_tier: int = current + 1
	skills[id] = new_tier
	# 라인별 즉시 효과 — 티어 업 시점에 적용.
	# B-1 단계: hp 라인만 처리(기존 regen 동작 보존). 나머지 효과는 B-2에서 Player.gd가 티어를 읽어 분기.
	match id:
		"hp":
			# T1: max_hp +1, T2: 추가 +1 (총 +2), T3: max_hp 변화 없음 (슬로모만)
			if new_tier == 1 or new_tier == 2:
				player_max_hp += 1
				player_hp = min(player_hp + 1, player_max_hp)
	emit_signal("skills_changed")

func damage_player(amount: int) -> void:
	# 스토리 모드는 체력 무제한 — 피격 자체를 무시. (Player.take_hit의 invuln 등은 그대로 동작)
	if story_mode:
		return
	player_hp = max(0, player_hp - amount)

func heal_player(amount: int) -> void:
	player_hp = min(player_max_hp, player_hp + amount)

func is_dead() -> bool:
	return player_hp <= 0

func register_death() -> void:
	death_count += 1

func on_stage_clear() -> bool:
	# 반환: 보너스 XP로 인한 레벨업이 발생했는지. 호출자가 LevelUpOverlay를
	# 띄울지 판단할 수 있게 해 보너스 레벨업이 누락되지 않도록.
	# 방금 깬 스테이지의 실력 지표를 먼저 마감 (current_stage 증가 전).
	_finalize_stage_metrics()
	# 어투 trust 적립(§3.2) — 클리어 시점에만. 추천 따라 깼으면 +2.
	# 함께 고비 돌파(죽고 회복 / 고위험·도전·히든 클리어) +2 = 따뜻함의 주 소스.
	# 독립적 성공(추천 무시하고 무난히 클리어)은 +0 — 따뜻함은 관계로만 번다(§3.5).
	var deaths_this_stage: int = max(0, death_count - _stage_deaths_base)
	if followed_veil_last_choice:
		trust_score += 2
	var hardship: bool = deaths_this_stage > 0 or current_route_risk >= 3 or current_route_challenge or current_route_hidden
	if hardship:
		trust_score += 2
		shared_hardship += 1
	current_stage += 1
	score += 100 * current_stage
	var leveled: bool = false
	if current_route_reward > 0:
		if add_xp(current_route_reward, false):
			leveled = true
	# regen은 획득 시점에 max_hp +1 효과만 — 매 stage HP 풀 회복이라 heal_player 불필요
	return leveled

func effective_total_stages() -> int:
	return STORY_TOTAL_STAGES if story_mode else TOTAL_STAGES

func is_final_stage_done() -> bool:
	return current_stage >= effective_total_stages()

func mark_enemy_seen(id: String) -> bool:
	if id == "" or id in seen_enemies:
		return false
	seen_enemies.append(id)
	save_settings()
	return true

# 엔딩 도달 1회 처리 — 본 엔딩 기록(중복 제외) + 완주 카운트 + 진행 저장 삭제. Ending._ready에서 호출(런당 1회).
func record_ending(id: String) -> void:
	if id != "" and not (id in endings_seen):
		endings_seen.append(id)
	playthrough_count += 1
	save_settings()
	clear_run()

# 다회차 — 완주 1회 이상(영속) 또는 즉시 리플레이(replaying). 오프닝/인게임 대사 변형의 단일 신호.
func is_replay_run() -> bool:
	return playthrough_count >= 1 or replaying

# --- 런 진행 저장(이어하기) — user://run.cfg. RouteMap 진입(스테이지 사이)마다 자동저장. ---
func save_run() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", RUN_VERSION)
	cf.set_value("run", "current_stage", current_stage)
	cf.set_value("run", "death_count", death_count)
	cf.set_value("run", "score", score)
	cf.set_value("run", "trust_score", trust_score)
	cf.set_value("run", "aggression_score", aggression_score)
	cf.set_value("run", "shared_hardship", shared_hardship)
	cf.set_value("run", "rec_count", rec_count)
	cf.set_value("run", "followed_count", followed_count)
	cf.set_value("run", "route_history", route_history)
	cf.set_value("run", "last_veil_recommended_route", last_veil_recommended_route)
	cf.set_value("run", "followed_veil_last_choice", followed_veil_last_choice)
	cf.set_value("run", "skills", skills)
	cf.set_value("run", "current_route_id", current_route_id)
	cf.set_value("run", "current_route_tags", current_route_tags)
	cf.set_value("run", "current_route_risk", current_route_risk)
	cf.set_value("run", "current_route_reward", current_route_reward)
	cf.set_value("run", "current_route_challenge", current_route_challenge)
	cf.set_value("run", "current_route_hidden", current_route_hidden)
	cf.set_value("run", "player_max_hp", player_max_hp)
	cf.set_value("run", "player_hp", player_hp)
	cf.set_value("run", "player_xp", player_xp)
	cf.set_value("run", "player_level", player_level)
	cf.set_value("run", "story_mode", story_mode)
	cf.set_value("run", "veil_degraded", veil_degraded)
	cf.set_value("run", "veil_reversal_pending", veil_reversal_pending)
	cf.set_value("run", "replaying", replaying)
	cf.set_value("run", "hits_taken", hits_taken)
	cf.set_value("run", "recent_stage_hits", recent_stage_hits)
	cf.set_value("run", "recent_stage_deaths", recent_stage_deaths)
	cf.set_value("run", "last_stage_secs", last_stage_secs)
	cf.save(RUN_PATH)

func has_run() -> bool:
	return FileAccess.file_exists(RUN_PATH)

func clear_run() -> void:
	var d := DirAccess.open("user://")
	if d != null and d.file_exists("run.cfg"):
		d.remove("run.cfg")

# run.cfg를 GameState에 복원. 성공 시 true(이어하기 → ROUTE_MAP 복귀). 실패 시 false(상태 불변).
func load_run() -> bool:
	var cf := ConfigFile.new()
	if cf.load(RUN_PATH) != OK:
		return false
	current_stage = int(cf.get_value("run", "current_stage", 0))
	death_count = int(cf.get_value("run", "death_count", 0))
	score = int(cf.get_value("run", "score", 0))
	trust_score = int(cf.get_value("run", "trust_score", 0))
	aggression_score = int(cf.get_value("run", "aggression_score", 0))
	shared_hardship = int(cf.get_value("run", "shared_hardship", 0))
	rec_count = int(cf.get_value("run", "rec_count", 0))
	followed_count = int(cf.get_value("run", "followed_count", 0))
	route_history = []
	for v in cf.get_value("run", "route_history", []):
		route_history.append(str(v))
	last_veil_recommended_route = str(cf.get_value("run", "last_veil_recommended_route", ""))
	followed_veil_last_choice = bool(cf.get_value("run", "followed_veil_last_choice", false))
	var saved_skills: Dictionary = cf.get_value("run", "skills", {})
	skills = {}
	for k in saved_skills:
		skills[str(k)] = int(saved_skills[k])
	current_route_id = str(cf.get_value("run", "current_route_id", ""))
	current_route_tags = []
	for t in cf.get_value("run", "current_route_tags", []):
		current_route_tags.append(str(t))
	current_route_risk = int(cf.get_value("run", "current_route_risk", 1))
	current_route_reward = int(cf.get_value("run", "current_route_reward", 1))
	current_route_challenge = bool(cf.get_value("run", "current_route_challenge", false))
	current_route_hidden = bool(cf.get_value("run", "current_route_hidden", false))
	player_max_hp = int(cf.get_value("run", "player_max_hp", 3))
	player_hp = int(cf.get_value("run", "player_hp", player_max_hp))
	player_xp = int(cf.get_value("run", "player_xp", 0))
	player_level = int(cf.get_value("run", "player_level", 1))
	story_mode = bool(cf.get_value("run", "story_mode", false))
	veil_degraded = bool(cf.get_value("run", "veil_degraded", false))
	veil_reversal_pending = bool(cf.get_value("run", "veil_reversal_pending", false))
	replaying = bool(cf.get_value("run", "replaying", false))
	hits_taken = int(cf.get_value("run", "hits_taken", 0))
	recent_stage_hits = []
	for h in cf.get_value("run", "recent_stage_hits", []):
		recent_stage_hits.append(int(h))
	recent_stage_deaths = []
	for dd in cf.get_value("run", "recent_stage_deaths", []):
		recent_stage_deaths.append(int(dd))
	last_stage_secs = float(cf.get_value("run", "last_stage_secs", 0.0))
	return true

# --- 설정 영속화 ---
# v1: input.<action> = [physical_keycode, ...]  — 키보드 전용
# v2: input.<action> = [{type, code/button}, ...]  — 키보드+마우스
# v3 (현): v2 + joy_button/joy_motion 타입 — 게임패드 매핑 보존
# 구 버전 cfg 로드 시 input 섹션은 무시 (project.godot 기본값 유지), 다음 저장에서 v3로 전환

const SETTINGS_VERSION: int = 4  # 4: 키 기본배열 개편(JKL+ZXC+화살표). 구 cfg 키바인드 무효화→새 기본 적용.

func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	var version: int = int(cf.get_value("meta", "version", 1))
	tutorial_done = bool(cf.get_value("flags", "tutorial_done", false))
	# audio.bgm로 마이그레이션. 구 audio.master 키는 fallback으로 한 번 더 읽음.
	bgm_volume = float(cf.get_value("audio", "bgm", cf.get_value("audio", "master", 1.0)))
	sfx_volume = float(cf.get_value("audio", "sfx", 1.0))
	seen_enemies = []
	for v in cf.get_value("flags", "seen_enemies", []):
		seen_enemies.append(str(v))
	hidden_visit_count = int(cf.get_value("flags", "hidden_visit_count", 0))
	visited_arcturus = bool(cf.get_value("flags", "visited_arcturus", false))
	endings_seen = []
	for ev in cf.get_value("flags", "endings_seen", []):
		endings_seen.append(str(ev))
	playthrough_count = int(cf.get_value("flags", "playthrough_count", 0))
	screen_brightness = clampf(float(cf.get_value("access", "brightness", 1.0)), 0.5, 1.5)
	sfx_captions = bool(cf.get_value("access", "sfx_captions", false))
	fullscreen = bool(cf.get_value("display", "fullscreen", false))
	window_size_index = clampi(int(cf.get_value("display", "window_size_index", 0)), 0, WINDOW_SIZES.size() - 1)
	if version < SETTINGS_VERSION:
		# 구 스키마 — 키바인드 폐기, project.godot + Main.gd 기본값 유지
		return
	for action in KEYBIND_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var stored: Array = cf.get_value("input", action, [])
		if stored.size() == 0:
			continue
		InputMap.action_erase_events(action)
		for entry in stored:
			if not (entry is Dictionary):
				continue
			var d: Dictionary = entry
			var t: String = str(d.get("type", ""))
			if t == "key":
				var ev := InputEventKey.new()
				ev.physical_keycode = int(d.get("code", 0))
				InputMap.action_add_event(action, ev)
			elif t == "mouse":
				var ev2 := InputEventMouseButton.new()
				ev2.button_index = int(d.get("button", 0))
				InputMap.action_add_event(action, ev2)
			elif t == "joy_button":
				var ev3 := InputEventJoypadButton.new()
				ev3.button_index = int(d.get("button", 0))
				InputMap.action_add_event(action, ev3)
			elif t == "joy_motion":
				var ev4 := InputEventJoypadMotion.new()
				ev4.axis = int(d.get("axis", 0))
				ev4.axis_value = float(d.get("value", 1.0))
				InputMap.action_add_event(action, ev4)

func save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("meta", "version", SETTINGS_VERSION)
	cf.set_value("flags", "tutorial_done", tutorial_done)
	cf.set_value("flags", "seen_enemies", seen_enemies)
	cf.set_value("flags", "hidden_visit_count", hidden_visit_count)
	cf.set_value("flags", "visited_arcturus", visited_arcturus)
	cf.set_value("flags", "endings_seen", endings_seen)
	cf.set_value("flags", "playthrough_count", playthrough_count)
	cf.set_value("access", "brightness", screen_brightness)
	cf.set_value("access", "sfx_captions", sfx_captions)
	cf.set_value("display", "fullscreen", fullscreen)
	cf.set_value("display", "window_size_index", window_size_index)
	cf.set_value("audio", "bgm", bgm_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	for action in KEYBIND_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var entries: Array = []
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var k := ev as InputEventKey
				entries.append({"type": "key", "code": int(k.physical_keycode)})
			elif ev is InputEventMouseButton:
				var m := ev as InputEventMouseButton
				entries.append({"type": "mouse", "button": int(m.button_index)})
			elif ev is InputEventJoypadButton:
				var jb := ev as InputEventJoypadButton
				entries.append({"type": "joy_button", "button": int(jb.button_index)})
			elif ev is InputEventJoypadMotion:
				var jm := ev as InputEventJoypadMotion
				entries.append({"type": "joy_motion", "axis": int(jm.axis), "value": float(jm.axis_value)})
		cf.set_value("input", action, entries)
	cf.save(SETTINGS_PATH)

# 디스플레이 설정(전체화면/창 크기)을 DisplayServer에 즉시 반영.
# Main.gd가 load_settings 직후 호출, Settings에서 값 바꿀 때도 호출.
# 웹: 창 크기는 브라우저 캔버스가 정하므로 무시 — 전체화면만 적용(버튼 입력=사용자 제스처라 허용됨).
func apply_display_settings() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	if OS.has_feature("web"):
		return
	var idx: int = clampi(window_size_index, 0, WINDOW_SIZES.size() - 1)
	var sz: Vector2i = WINDOW_SIZES[idx]
	DisplayServer.window_set_size(sz)
	# 창 크기 변경 후 현재 모니터 중앙으로 재배치 (안 하면 좌상단으로 튐).
	var screen_idx: int = DisplayServer.window_get_current_screen()
	var screen_pos: Vector2i = DisplayServer.screen_get_position(screen_idx)
	var screen_size: Vector2i = DisplayServer.screen_get_size(screen_idx)
	DisplayServer.window_set_position(screen_pos + (screen_size - sz) / 2)

# 피드백 설문을 외부 브라우저(데스크톱) / 새 탭(웹)으로 연다.
# 버튼 pressed에서 호출 — 웹의 window.open이 팝업 차단되지 않도록 사용자 제스처 컨텍스트 유지.
func open_feedback() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.open('%s', '_blank')" % FEEDBACK_URL, true)
	else:
		OS.shell_open(FEEDBACK_URL)
