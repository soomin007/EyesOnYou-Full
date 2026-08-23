extends Node2D

# 기본값 — MapData가 비었을 때 폴백. 실제로는 _ready에서 MapData 기반으로 덮어씀.
var STAGE_LENGTH: float = 4400.0
var GROUND_Y: float = 600.0
var PLAYER_START: Vector2 = Vector2(140.0, 540.0)

# world_layout 템플릿 시스템 — _ready에서 MapData에서 읽음
var _world_type: String = "HORIZONTAL"
var _world_size: Vector2 = Vector2(4400.0, 720.0)
var _camera_mode: String = "HORIZONTAL"
var _goal_type: String = "POSITION"
var _goal_pos: Vector2 = Vector2(4320.0, 540.0)

var player: CharacterBody2D
var camera: Camera2D
var hud: CanvasLayer
var hp_label: Label
var overwrite_label: Label # 현장 기록 덮어쓰기 잔여 핍(●잔여 ○소모 ×라이벌 잠김) — 우상단 점수 아래
var xp_label: Label
var xp_bar: ProgressBar   # 레벨업 EXP 진행 바 (피드백: 텍스트보다 바가 한눈에)
var stage_label: Label
var map_label: Label   # 현재 맵(루트) 이름 — HUD 상단
var trust_label: Label # VEIL 신뢰도 게이지 — HUD 상단
var skill_label: Label
var score_label: Label # 점수 — 우상단 VEIL 눈 아래(점수 보상이 인게임에 안 보인다는 피드백, 2026-08-11)
var levelup_overlay: CanvasLayer
var goal_reached: bool = false
var pending_levelup: bool = false

var pause_overlay: CanvasLayer
var settings_overlay: Control

# route_escape — 카메라 진행률 따라 터널 → 도시 야경으로 cross-fade.
# 도시 야경은 3개 parallax sub-layer(far/mid/near)로 나뉨 — 거리감 표현용.
var _escape_tunnel_group: Node = null
var _escape_city_group: Node = null
var _escape_city_far: Node2D = null
var _escape_city_mid: Node2D = null
var _escape_city_near: Node2D = null

# 쿨다운 UI — 사격/대시/스킬/방어막 게이지
var cd_attack_slot: Control
var cd_dash_slot: Control
var cd_skill_slot: Control
var cd_barrier_slot: Control  # 에너지 방어막 — 충전 progress(헥스 + 남은 초), 완료 시 청록 가득
var cd_shield_slot: Control   # 비상 부활 — T3 재충전 카운트다운(없으면 ✓), 미보유 시 숨김
const CD_BAR_WIDTH: float = 90.0
# 초단위 쿨(사격 연사·대시)은 짧은 바 — 긴 타이머(스킬·방어막·부활)와 같은 길이면 과장돼 보인다
# (사용자: "굳이 이렇게 길게 똑같이?" 2026-08-11). 길이 자체가 쿨 체급을 말하게.
const CD_BAR_WIDTH_SHORT: float = 44.0

func _ready() -> void:
	add_to_group("stage")
	# 플레이 습관 프로필 수집 시작(실플레이만 · 연습장/스토리/봇은 내부 게이트로 제외).
	GameState.profile_stage_begin()
	# 안전망: 이전 scene에서 paused=true 상태가 carry되어 새 stage가 freeze되는 패턴 차단
	# (LevelUpOverlay/도전방 fail 등에서 paused 해제 누락 시 빈 화면).
	get_tree().paused = false
	# 방 체인 중간 방(세그먼트 1+)은 HP 유지 · 체인은 한 스테이지다. 진입 풀 힐은 첫 방만.
	if GameState.current_segment == 0:
		GameState.player_hp = GameState.player_max_hp
	# BGM — 맵별 트랙 선택. ??? 방은 Gravity Static, 보스 맵은 Chrome Grit,
	# 그 외에는 stage_index 기반으로 Cold Gear(초중반)/Cold Wire(중후반) 분기.
	# Death 화면에서 set_ducked(true)였다면 stage 재진입에서 원복.
	BgmPlayer.set_ducked(false)
	_apply_bgm_for_current_route()
	# 모바일 가상 패드 — 터치 기기에서만(데스크톱 무영향). route 분기 전에 둬서 ??? 방 포함 모든 맵에 적용.
	_build_touch_controls()
	# ??? 맵은 적/가시/골이 없는 정적 시퀀스 맵 (별도 로직)
	if GameState.current_route_id == "route_hidden":
		_build_hidden_archive()
		return
	GameState.restrict_combat_input = false
	# MapData에서 세계 형태 / 시작 / 골 / 카메라 모드 로드
	_load_world_meta()
	_build_world()
	_build_player()
	_build_camera()
	_build_hud()
	_spawn_enemies()
	_build_rewards()
	_build_goal()
	_setup_veil_mistakes()
	# 시야 붕괴 후속 맵 진입 경고 — _setup_veil_mistakes(연습장 early-return)와 분리해 따로 호출.
	# 자체적으로 veil_degraded를 검사하므로(self-gate), 연습장의 시야붕괴 토글로도 테스트된다.
	_arm_degraded_hazard_warning()
	_setup_veil_sight()
	_build_interference()
	_setup_challenge_mode()
	_build_lever_puzzles()
	if GameState.playground_active:
		add_child(PlaygroundOverlay.new())
	# 시야 역전 onset 멘트/연출은 이번 _ready에서 1회 소비 — 이후(재시도·다음 맵)엔 일반 degraded 처리.
	GameState.veil_reversal_pending = false
	# 정찰 보상 발동 안내(1회) — 강화가 조용히 켜지면 보상이 안 보인다. 효과는 VeilSight가 처리.
	if GameState.recon_note_pending and GameState.current_segment == 0:
		GameState.recon_note_pending = false
		if GameState.veilsight_recon_active:
			get_tree().create_timer(1.2, false).timeout.connect(func() -> void:
				if is_inside_tree():
					_show_veil_subtitle(VeilDialogue.banded("정찰 데이터를 반영했습니다. 이 구간의 숨겨진 레버와 보급품, 청색 표식으로 짚어 두겠습니다.", "정찰 데이터 반영했어요. 숨겨진 레버랑 보급품, 청색으로 짚어 둘게요."), 3.6))

# 전파 간섭 펄스(중계소 시그니처) — MapData "interference" 키가 있으면 생성.
# blackout은 VeilSight 자체가 없어(_setup_veil_sight early-return) 자동 무효.
func _build_interference() -> void:
	var cfg: Dictionary = _map_data.get("interference", {})
	if cfg.is_empty() or _veil_sight == null or not is_instance_valid(_veil_sight):
		return
	var node := Interference.new()
	add_child(node)
	node.setup(cfg, _veil_sight)

# 맵 → BGM 트랙 매핑.
# BPM 점진 증가 (Glass→Cold Gear→Cold Wire→Chrome Grit) 순서를 stage 진행과 매칭.
# 외곽·외벽·지하 통로(초중반): early. 시설 내부(중후반): mid_late. 보스: boss. ???: hidden.
const _ROUTE_TRACKS: Dictionary = {
	"route_back_alley": "early",
	"route_rooftops":   "early",
	"route_subway":     "early",
	"route_watchtower": "early",
	"route_sewers":     "early",
	"route_parking_lot": "early",
	"route_demolition_zone": "early",
	"route_pump_station": "early",
	"route_substation":  "mid_late",
	"route_testing_grounds": "mid_late",
	"route_relay_station": "mid_late",
	"route_warehouse":   "mid_late",
	"route_checkpoint":  "mid_late",
	"route_control_corridor": "mid_late",
	"route_condenser":   "mid_late",
	"route_perimeter":   "early",
	"route_gauntlet":    "mid_late",
	"route_freight_lift": "mid_late",
	"route_car_cover":  "mid_late",
	"route_collapse":   "mid_late",
	"route_core_defense": "mid_late",
	"route_scanner_sweep": "mid_late",
	"route_holdout":     "mid_late",
	"route_cooling":    "mid_late",
	"route_ward":       "mid_late",
	"route_datacenter": "mid_late",
	"route_server_hall": "mid_late",
	"route_blackout":   "mid_late",
	"route_escape":     "mid_late",
	# 처리별 탈출 4종 — 본편(막5)은 막 기반 선곡(confront)이 우선하지만, 매핑 누락 폴백 함정
	# 방지용으로 명시(known_issues 라우트 추가 체크리스트). 탈출별 BGM 분화는 백로그(사용자 결정).
	"route_escape_extract": "confront",
	"route_escape_destroy": "confront",
	"route_escape_conceal": "confront",
	"route_escape_leave":   "confront",
	# lab(SENTINEL 보스) = confront(Violet Signal) — 0~25s 빌드업에 보스 인트로 컷씬을 정렬(2026-08-10).
	# §7 reveal(처치 직후 라이벌 첫 발화)까지 라이벌 테마가 이어져 "라이벌이 지켜보던 판"의 데뷔 무대가 된다.
	"route_lab":        "confront",
	"route_hidden":     "hidden",
}

func _apply_bgm_for_current_route() -> void:
	var rid: String = GameState.current_route_id
	# 14-1 최종보스전 · 전용 트랙(Chrome Grit, 구 boss 슬롯 복권). confront(Violet Signal)는
	# 막5 전체와 공유돼 고유성이 없었다(사용자 확인 2026-08-16, final_boss_rework §4-③).
	if rid == "route_core_recovery":
		BgmPlayer.play("boss")
		return
	# 특수 라우트(보스/히든)는 막 무관 우선.
	if rid == "route_lab" or rid == "route_hidden":
		BgmPlayer.play(str(_ROUTE_TRACKS.get(rid, "early")))
		return
	# 막4+(라이벌 영역)는 막 기반 선곡(GameState.ACTS.bgm) — 막4/5에 겹쳐 등장하는 라우트가
	# 스테이지에 따라 자동 분기(pursuit/confront)하고, 신규 라우트가 매핑 누락으로 "early" 폴백되던
	# 함정(known_issues, core_recovery 사례)도 이 구간에선 원천 차단된다. 막1~3은 라우트 매핑 유지.
	if not GameState.story_mode and GameState.act_for_stage(GameState.current_stage) >= 3:
		BgmPlayer.play(str(GameState.act_def(GameState.current_stage).get("bgm", "mid_late")))
		return
	BgmPlayer.play(str(_ROUTE_TRACKS.get(rid, "early")))

func _load_world_meta() -> void:
	# MapData를 먼저 한 번 lookup해서 세계 차원·골·카메라 모드 결정.
	# (이후 _build_platforms가 다시 lookup해서 platform/적 사용)
	var data: Dictionary = MapData.get_layout(GameState.current_route_id)
	if data.is_empty():
		# MapData 명세 없음 — 기본값(HORIZONTAL 4400×720) 유지
		return
	_world_type = str(data.get("world_type", "HORIZONTAL"))
	_world_size = data.get("world_size", _world_size)
	_camera_mode = str(data.get("camera_mode", "HORIZONTAL"))
	_goal_type = str(data.get("goal_type", "POSITION"))
	_goal_pos = data.get("goal_pos", Vector2.ZERO)
	PLAYER_START = data.get("player_start", PLAYER_START)
	STAGE_LENGTH = _world_size.x
	# ground_y는 맵별로 명시 가능 (subway는 천장 낮아 ground_y=420 등)
	GROUND_Y = float(data.get("ground_y", _world_size.y - 120.0))

# ─── VEIL 실수 스크립트 ─────────────────────────────────────
# 의도된 작은 균열 — VEIL이 한 번 틀리고 짧게 인정한다.
# Stage 0과 Stage 2에서 각 한 번씩 (1회 플래그).

var veil_mistake_triggered: bool = false
var ward_foreshadow_triggered: bool = false
var act3_vision_triggered: bool = false
var _veil_sight: VeilSight = null

func _setup_veil_mistakes() -> void:
	if GameState.playground_active:
		return
	# 격리 병동 통과 시 ??? 맵 복선 (stage 3 또는 4).
	# x=900 — 진입 직후 분기 결정 전에 분위기 깔리도록 일찍 트리거.
	if GameState.current_route_id == "route_ward":
		_arm_ward_foreshadow_at(900.0)
	# 진입 직후 한 줄 안내 — 모든 루트가 RouteData.entry_comment를 가짐.
	# "어디로 가야 하나" "이 맵의 위협이 뭔가"를 단숨에 통보. 사용자: 맵 진입 멘트 리뉴얼.
	# 시야 역전 onset 맵은 "진입부터 붕괴" — 일반 entry_comment 대신 역전 멘트 한 줄만 진입에 띄워 자막
	# 겹침 없이 깔끔하게(VeilSight는 이미 degraded로 시작). 그 외 맵은 평소대로 entry_comment.
	if GameState.veil_reversal_pending:
		_show_veil_subtitle(_act3_vision_line(GameState.current_stage), 4.4, false, true)
	elif GameState.current_segment == 0:
		# 방 체인 중간 방(세그먼트 1+)은 진입 멘트 반복 안 함 · 첫 방에서 이미 들었다.
		var entry: String = ""
		var entry_rep: String = ""
		for r in RouteData.ALL_ROUTES:
			if r.get("id", "") == GameState.current_route_id:
				# 어투 밴드 스윕(2026-08-21): 기본 = 중립 보고체, warm 밴드는 _warm 변형(없으면 기본).
				entry = VeilDialogue.banded(str(r.get("entry_comment", "")), str(r.get("entry_comment_warm", "")))
				entry_rep = str(r.get("entry_comment_replay", ""))
				break
		# 다회차(완주 1회+/리플레이)면 그 맵의 진입 멘트 변형을 우선(있을 때만). 없으면 1회차 멘트.
		if GameState.is_replay_run() and entry_rep != "":
			entry = entry_rep
		if entry != "":
			# 맵 진입 첫 멘트 — 빠른 fade-in(0.12s) + 긴 표시(4.5s)로 진입 직후 바로/오래 인지되게.
			_show_veil_subtitle(entry, 4.5, false, true)
	# 막1→막2 문턱(B-4) — 런 첫 드론 맵 진입 시 VEIL 1회 반응(진입 멘트 뒤 지연).
	_arm_drone_intro()
	# ACT3 시야 역전 — onset은 위 진입 멘트로 소비(아래는 veil_degraded 가드로 early-return되는 fallback).
	_arm_act3_vision_subtitle()

# 막1→막2 문턱(B-4) — 막1은 인간 경비만(드론 0)이라, 런에서 드론이 처음 깔린 맵(막2+)에 들어서면
# "기계가 깨어났다"를 VEIL이 1회 짚어준다. 진입 멘트(4.5s)와 안 겹치게 지연. 플래그는 *발동 시* 세워
# 발동 전 사망/재시도엔 다시 armed → 살아남으면 그때 1회 발동(한 번 떴으면 런 내내 재발동 없음).
func _arm_drone_intro() -> void:
	if GameState.story_mode or GameState.playground_active:
		return
	if GameState.drone_intro_seen:
		return
	if GameState.act_for_stage(GameState.current_stage) < 1:
		return  # 막1(드론 없음) 안전 가드
	var enemies: Dictionary = _map_data.get("enemies", {})
	var drones: Array = enemies.get("drone", [])
	if drones.is_empty():
		return
	var tw := create_tween()
	tw.tween_interval(5.2)
	tw.tween_callback(_fire_drone_intro)

func _fire_drone_intro() -> void:
	if not is_inside_tree():
		return
	if GameState.drone_intro_seen:
		return
	GameState.drone_intro_seen = true
	_show_veil_subtitle(_drone_intro_line(), 4.0)

# 재작성(2026-08-22 사용자: "떨어뜨려요"의 목적어 누락 + "위도 같이 봐요"는 요원에게 할 말이
# 아님) — 전 밴드 보고체 정합: 떨어뜨리는 것 = 폭탄을 명시, 지시는 "확인하십시오/챙기세요".
func _drone_intro_line() -> String:
	match GameState.veil_register_band():
		"cold":
			# EN: "Drone overhead. It drops bombs. Watch the sky."
			# ("부유 유닛" = 내부 용어 지적 · 무맥락 검수 1차, 2026-08-23)
			return "머리 위에 드론입니다. 폭탄을 떨어뜨립니다. 위쪽을 경계하십시오."
		"warm":
			# EN: "Drone overhead. It drops bombs, so keep an eye above you too."
			return "드론이에요. 폭탄을 머리 위에 떨어뜨립니다. 위쪽도 챙기세요."
		_:
			# EN: "That's a drone. It drops bombs from overhead. Check above you as well."
			return "드론입니다. 폭탄을 머리 위에 떨어뜨립니다. 위쪽도 확인하십시오."

func _arm_ward_foreshadow_at(trigger_x: float) -> void:
	var area := Area2D.new()
	area.name = "WardForeshadow"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(trigger_x, GROUND_Y - 50.0)
	add_child(area)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(120.0, 200.0)
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_ward_foreshadow_zone)

func _on_ward_foreshadow_zone(body: Node) -> void:
	if ward_foreshadow_triggered:
		return
	if not (body is CharacterBody2D and body == player):
		return
	ward_foreshadow_triggered = true
	# 한 줄에 합쳐 큐 부담 최소화 — 이전 3줄(...,오래됐어요,봉인했는지 몰라요)이
	# 이스터에그 paused 동안 쌓였다가 풀린 뒤 줄줄이 표시되어 겹친 듯 보이던 문제.
	_show_veil_subtitle(VeilDialogue.banded("오래된 구역입니다. 누가 봉인했는지, 기록에 없습니다.", "이 구역은 오래됐어요. 누가 봉인했는지 저도 몰라요."), 3.6)

func _arm_veil_mistake_at(trigger_x: float, before_line: String, after_line: String) -> void:
	# 트리거가 월드 밖이면 (vertical 등 좁은 맵) 건너뛰기
	if trigger_x > _world_size.x:
		return
	var area := Area2D.new()
	area.name = "VeilMistakeTrigger"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(trigger_x, GROUND_Y - 50.0)
	add_child(area)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(80.0, 200.0)
	col.shape = shape
	area.add_child(col)
	area.set_meta("before", before_line)
	area.set_meta("after", after_line)
	area.body_entered.connect(_on_veil_mistake_zone.bind(area))

func _on_veil_mistake_zone(body: Node, area: Area2D) -> void:
	if veil_mistake_triggered:
		return
	if not (body is CharacterBody2D and body == player):
		return
	veil_mistake_triggered = true
	# before/after 두 줄을 한 호흡(2-line) 자막으로. after가 비면 한 줄만.
	var before_line: String = str(area.get_meta("before", ""))
	var after_line: String = str(area.get_meta("after", ""))
	if before_line == "" and after_line == "":
		return
	if after_line == "":
		_show_veil_subtitle(before_line, 3.0)
	elif before_line == "":
		_show_veil_subtitle(after_line, 3.0)
	else:
		_show_veil_subtitle(before_line + "\n" + after_line, 3.4)

# ─── ACT3 인게임 시야 역전 자막 (v3 §4 ★) ─────────────────────
# 최고조 비트("이제 요원이 VEIL 대신 본다")를 *플레이 중* 한 번 띄운다. 브리핑(ENTER로 스킵 가능)에만
# 싣지 않고 플레이필드 자막으로 한 번 더 박아 스킵 불가하게 — §1-2(단일 채널 의존) 해결.
# POSITION 골 맵은 진행 ~62% 지점을 가로지르는 트리거 밴드로, 트래버스가 없는 ARENA(보스/datacenter)는
# 진입 멘트가 가신 뒤 지연 자막으로. ACT3에서만(일반 stage5+/스토리 s3), 회당 1회.
func _arm_act3_vision_subtitle() -> void:
	var stage: int = GameState.current_stage
	# 비상 탈출로는 "탈출" 비트 — 시야 붕괴 아크에서 제외(스토리 stage4는 아래 조건으로 이미 빠지지만,
	# 일반 모드 stage6은 stage>=5에 걸려 여기서 재발동되므로 route로 명시 차단). 사용자: 탈출 맵은 붕괴 꺼져야 함.
	if GameState.current_route_id.begins_with("route_escape"):
		return
	# 시야 역전(reversal)은 딱 한 번만 발동 — 이미 붕괴된 뒤 후속 맵은 _arm_degraded_hazard_warning이
	# "여기 잘 못 봐요" 경고를 맡는다. 여기서 또 reversal 자막+begin_degradation을 내면 중복이라 가드.
	if GameState.veil_degraded:
		return
	# 일반 모드: 보스(lab=ARENA, 잡몹 없어 마커 무의미)·탈출 직전의 *잡몹 전투 맵*(데이터센터 등, index 4)에서
	# 역전을 실연한다. 기존 stage>=5는 보스/탈출에서만 떠 시각이 전투 맵에 안 내려앉고 대사 아크(stage4~)와
	# 어긋났음(사용자 보고). → 막3(마지막 막) 첫 후보 전투 맵에서 1회 발동(위 veil_degraded 가드로 중복 없음).
	# 스토리 ACT3 = 보스 직전(ward/sewers, stage 2)에서 먼저 — 보스(stage 3, ARENA)는 마커 무의미라 제외.
	# 막 경계 판정은 GameState.is_late_act로 통일(스토리 s2~3 / 본편 마지막 막).
	var is_act3: bool = GameState.is_late_act(stage)
	if not is_act3:
		return
	var line: String = _act3_vision_line(stage)
	if line == "":
		return
	# 트래버스가 없는 ARENA(FIXED 카메라) — 위치 트리거가 무의미하니 진입 멘트 뒤 지연 자막으로.
	# 사용자: "안 보인다 시점이 너무 늦다" → 4.8→3.0s로 앞당김.
	if _goal_type != "POSITION":
		var tw := create_tween()
		tw.tween_interval(3.0)
		tw.tween_callback(_fire_act3_vision.bind(line))
		return
	# 진행 방향(시작 → 골)의 ~48% 지점에 진행 축을 가로지르는 트리거 밴드(사용자: 역전이 너무 늦음 → 62%→48%).
	# 세로 맵은 폭 전체를, 가로 맵은 높이 전체를 덮어 어느 발판/높이로 지나도 통과하게.
	var approach: Vector2 = PLAYER_START.lerp(_goal_pos, 0.48)
	var box: Vector2
	if _world_size.y > _world_size.x:
		box = Vector2(_world_size.x, 260.0)
		approach.x = _world_size.x * 0.5
	else:
		box = Vector2(220.0, _world_size.y)
		approach.y = _world_size.y * 0.5
	var area := Area2D.new()
	area.name = "Act3VisionTrigger"
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = approach
	area.set_meta("line", line)
	add_child(area)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = box
	col.shape = shape
	area.add_child(col)
	area.body_entered.connect(_on_act3_vision_zone.bind(area))

func _on_act3_vision_zone(body: Node, area: Area2D) -> void:
	if act3_vision_triggered:
		return
	if not (body is CharacterBody2D and body == player):
		return
	_fire_act3_vision(str(area.get_meta("line", "")))

func _fire_act3_vision(line: String) -> void:
	if act3_vision_triggered:
		return
	act3_vision_triggered = true
	# 역전을 한 사건으로 — 자막이 뜨는 바로 그 순간 VEIL의 마커가 무너진다(B).
	if _veil_sight != null and is_instance_valid(_veil_sight):
		_veil_sight.begin_degradation()
	if line != "":
		_show_veil_subtitle(line, 4.0)

# 시야 역전 최고조 한 줄 (v3 §4). 스토리 s3 = 최고조(서버 접근 톤),
# 일반 모드는 첫 ACT3(stage 5) 핵심부 진입 → 최종 stage 서버 접근으로 점증.
func _act3_vision_line(stage: int) -> String:
	# 서사 비트라 밴드 이원화(어투 스윕) — 기본 = 중립 보고체, warm은 기존 부드러운 문안 유지.
	if GameState.story_mode:
		# 보스 직전(stage 2)은 역전의 시작, 보스(stage 3)는 클라이맥스로 점증.
		if stage >= 3:
			return VeilDialogue.banded("여기는... 저도 안 보입니다. 이제 요원이 보십시오. 저는 듣겠습니다.", "여기는... 저도 안 보여요. 이제 요원이 봐요. 저는 들을게요.")
		return VeilDialogue.banded("여기서부터는 잘 안 보입니다. 이제 요원이 제 눈입니다.", "여기서부터는 잘 안 보여요. 이제 요원이 제 눈이 돼 줘요.")
	if stage >= GameState.effective_total_stages() - 1:
		return VeilDialogue.banded("여기는... 저도 안 보입니다. 이제 요원이 보십시오. 저는 듣겠습니다.", "여기는... 저도 안 보여요. 이제 요원이 봐요. 저는 들을게요.")
	# 본편 onset은 막5(재구조화 후) — 막3 붕괴·reveal·막4 추적을 다 겪은 뒤의 재발이라
	# "처음 알리는" 옛 문장은 시점이 안 맞았다(2026-08-15 지적). 겪어 본 현상의 귀환 톤으로.
	return VeilDialogue.banded("또 시작입니다. 심장부에 드니 시야가 다시 죽습니다. 전처럼, 안 보이는 쪽은 요원 몫입니다.", "또 시작이네요. 심장부에 드니 시야가 다시 죽습니다. 전처럼, 안 보이는 쪽은 요원이 봐 줘요.")

# ─── 시야 붕괴 후 위험 미리 경고 (못 잡는 적 안내 §2) ───────────────
# 이미 시야가 붕괴(GameState.veil_degraded)한 ACT3 후속 맵에 진입하면, VEIL은 함정·매복을
# 마커로 못 짚어준다. 그래서 마커 대신 "여기는 잘 못 본다, 직접 살펴라"를 진입 직후 말로 경고.
# 이 맵 안에서 degradation이 막 시작되는 케이스(_fire_act3_vision)는 그 자막이 이미 비트를
# 잡으므로, 여기선 *처음부터* 붕괴 상태로 들어온 맵에서만 발화(중복 방지).
func _arm_degraded_hazard_warning() -> void:
	if not GameState.veil_degraded:
		return
	# 시야 역전 onset 맵은 _setup_veil_mistakes가 역전 멘트를 띄우므로 함정 경고는 생략(중복 방지).
	if GameState.veil_reversal_pending:
		return
	var traps: Array = _map_data.get("traps", [])
	var tripwires: Array = _map_data.get("tripwires", [])
	var has_traps: bool = not traps.is_empty() or not tripwires.is_empty()
	var has_nest: bool = bool(_map_data.get("nest_snipers", false))
	if not (has_traps or has_nest):
		return
	var line: String = VeilDialogue.banded("여기는 제 시야가 흐립니다. 함정이 있어도 못 짚어줄 수 있습니다. 직접 살피십시오.", "여기, 제가 잘 못 봐요. 함정이 있어도 못 짚어줄 수 있어요. 직접 살펴요.")
	if has_nest and not has_traps:
		line = VeilDialogue.banded("여기는 제 시야가 흐립니다. 매복이 있어도 못 짚어줄 수 있습니다. 직접 살피십시오.", "여기, 제가 잘 못 봐요. 매복이 있어도 못 짚어줄 수 있어요. 직접 살펴요.")
	# 진입 멘트(4.5s)가 가신 뒤 한 박자 늦게 — 겹쳐서 줄줄이 뜨지 않게.
	var tw := create_tween()
	tw.tween_interval(6.0)
	tw.tween_callback(func() -> void:
		if player != null and is_instance_valid(player):
			_show_veil_subtitle(line, 3.8)
	)

# ─── VEIL 시야 마킹 셋업 (시야=신뢰 파일럿) ───────────────────────
# VEIL이 원거리/공중 위협을 HUD로 짚어준다. ACT3에선 그 마킹이 흐려지고 꺼진다 = 역전을 플레이로.
func _setup_veil_sight() -> void:
	# 교신 차단 도전(blackout)은 VEIL이 못 도와주는 게 컨셉 → 마커 없음(엔트리 멘트와도 일관).
	if GameState.current_route_id == "route_blackout":
		return
	if player == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "VeilSightLayer"
	layer.layer = 18  # 자막(20) 아래, 게임 위
	add_child(layer)
	var sight := VeilSight.new()
	sight.player = player
	sight.veil_calls_threat.connect(_on_veil_calls_threat)
	layer.add_child(sight)
	_veil_sight = sight
	# degradation은 ACT3 자막 트리거(_fire_act3_vision)에 동기화한다 — 같은 맵 안에서
	# 안정→붕괴 대비를 만들어 역전을 체감시키기 위해(B). 여기선 baseline(안정)으로만 시작.

func _on_veil_calls_threat(text: String) -> void:
	# VEIL이 화면 밖 위협을 말로 짚는다 — 마커를 "레이더"가 아닌 "누군가의 봄"으로 만드는 채널(A).
	_show_veil_subtitle(text, 2.4)

func _build_hidden_archive() -> void:
	# 격리 서버실 — 적/가시/골 없음, 단말기 2개 시퀀스 후 자동 ENDING 전환
	GameState.restrict_combat_input = true

	# 매우 어두운 배경
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03)
	bg.position = Vector2(-200, -300)
	bg.size = Vector2(STAGE_LENGTH + 400.0, 1200.0)
	bg.z_index = -20
	add_child(bg)

	# 평탄한 바닥
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	add_child(ground)
	var ground_col := CollisionShape2D.new()
	var ground_shape := RectangleShape2D.new()
	ground_shape.size = Vector2(STAGE_LENGTH + 400.0, 200.0)
	ground_col.shape = ground_shape
	ground_col.position = Vector2(STAGE_LENGTH * 0.5, GROUND_Y + 100.0)
	ground.add_child(ground_col)
	var floor_visual := ColorRect.new()
	floor_visual.color = Color(0.04, 0.04, 0.05)
	floor_visual.position = Vector2(-200, GROUND_Y)
	floor_visual.size = Vector2(STAGE_LENGTH + 400.0, 300.0)
	add_child(floor_visual)

	_build_wall(-50.0)
	_build_wall(STAGE_LENGTH + 50.0)

	# 꺼진 서버 랙들 (시각만)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4096
	var x: float = 200.0
	while x < STAGE_LENGTH - 200.0:
		var rack := ColorRect.new()
		rack.color = Color(0.08, 0.09, 0.10)
		var w: float = rng.randf_range(40.0, 70.0)
		var h: float = rng.randf_range(120.0, 200.0)
		rack.position = Vector2(x, GROUND_Y - h)
		rack.size = Vector2(w, h)
		rack.z_index = -10
		add_child(rack)
		x += w + rng.randf_range(80.0, 160.0)

	_build_player()
	_build_camera()
	_build_hud()

	# 단말기 2개 — VEIL-1 자리(첫 단말기)는 다회차 보강 풀이 활성화될 수 있음
	_build_archive_terminal(1500.0, "term_1", _term1_lines_for_visit())
	_build_archive_terminal(2700.0, "term_2", _veil2_lines(), false)

	# 자막 오버레이
	var arch := ArchiveOverlay.new()
	arch.name = "ArchiveOverlay"
	add_child(arch)

	# 진입 안내 — 첫 단말기 트리거되면 사라짐
	var hint_layer := CanvasLayer.new()
	hint_layer.name = "ArchiveHint"
	hint_layer.layer = 22
	add_child(hint_layer)
	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "켜진 단말기에 다가가세요"
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.62, 0.78, 0.92))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	hint.add_theme_constant_override("outline_size", 4)
	hint.position = Vector2(140, 130)
	hint.size = Vector2(1000, 28)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate.a = 0.0
	hint_layer.add_child(hint)
	var fade_in := hint.create_tween()
	fade_in.tween_interval(1.0)
	fade_in.tween_property(hint, "modulate:a", 1.0, 0.6)

	if GameState.playground_active:
		add_child(PlaygroundOverlay.new())

func _build_archive_terminal(x: float, term_id: String, lines: Array, lit: bool = true) -> void:
	# 단말기 본체 — 시각을 명확하게 키워서 어두운 배경에서도 잘 보이게
	var pedestal := ColorRect.new()
	pedestal.color = Color(0.14, 0.16, 0.20)
	pedestal.position = Vector2(x - 50.0, GROUND_Y - 40.0)
	pedestal.size = Vector2(100.0, 40.0)
	pedestal.z_index = -3
	add_child(pedestal)
	var body := ColorRect.new()
	body.color = Color(0.10, 0.12, 0.16)
	body.position = Vector2(x - 40.0, GROUND_Y - 200.0)
	body.size = Vector2(80.0, 160.0)
	body.z_index = -3
	add_child(body)
	# 화면 — 큰 사각형
	var screen := ColorRect.new()
	screen.name = "Screen_" + term_id
	screen.position = Vector2(x - 32.0, GROUND_Y - 190.0)
	screen.size = Vector2(64.0, 80.0)
	screen.z_index = -2
	add_child(screen)
	# 라벨 (ONLINE / OFFLINE)
	var status := Label.new()
	status.name = "Status_" + term_id
	status.add_theme_font_size_override("font_size", 11)
	status.position = Vector2(x - 32.0, GROUND_Y - 105.0)
	status.size = Vector2(64.0, 16.0)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.z_index = -2
	add_child(status)
	if lit:
		screen.color = Color(0.20, 0.85, 0.95, 0.95)
		status.text = "ONLINE"
		status.add_theme_color_override("font_color", Color(0.20, 0.85, 0.95))
		# 펄스 애니메이션
		var pulse := screen.create_tween()
		pulse.set_loops()
		pulse.tween_property(screen, "modulate:a", 0.6, 0.8)
		pulse.tween_property(screen, "modulate:a", 1.0, 0.8)
		# 주변 빛
		var halo := ColorRect.new()
		halo.name = "Halo_" + term_id
		halo.color = Color(0.30, 0.85, 0.95, 0.20)
		halo.position = Vector2(x - 240.0, GROUND_Y - 360.0)
		halo.size = Vector2(480.0, 380.0)
		halo.z_index = -8
		add_child(halo)
	else:
		screen.color = Color(0.10, 0.10, 0.12, 1.0)
		status.text = "OFFLINE"
		status.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))

	# 트리거 영역 — 더 크게
	var area := Area2D.new()
	area.name = "Term_" + term_id
	area.collision_layer = 0
	area.collision_mask = 2
	area.position = Vector2(x, GROUND_Y - 50.0)
	add_child(area)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(140.0, 140.0)
	col.shape = shape
	area.add_child(col)
	area.set_meta("term_id", term_id)
	area.set_meta("lines", lines)
	area.body_entered.connect(_on_terminal_entered.bind(area))

var archive_term1_done: bool = false
var archive_term2_done: bool = false
var archive_active_term: String = ""

func _on_terminal_entered(body: Node, area: Area2D) -> void:
	if not (body is CharacterBody2D and body == player):
		return
	var term_id: String = str(area.get_meta("term_id", ""))
	# term_2는 term_1 끝나야 트리거 가능
	if term_id == "term_2" and not archive_term1_done:
		return
	if term_id == "term_1" and archive_term1_done:
		return
	if term_id == "term_2" and archive_term2_done:
		return
	if archive_active_term != "":
		return
	archive_active_term = term_id
	# 안내 사라짐
	var hint_layer := get_node_or_null("ArchiveHint")
	if hint_layer != null:
		hint_layer.queue_free()
	var lines: Array = area.get_meta("lines", [])
	var arch := get_node_or_null("ArchiveOverlay") as ArchiveOverlay
	if arch == null:
		return
	if not arch.finished.is_connected(_on_archive_finished):
		arch.finished.connect(_on_archive_finished)
	arch.play(lines)

func _on_archive_finished() -> void:
	if archive_active_term == "term_1":
		archive_term1_done = true
		# 두 번째 단말기 자동 점등 — 색/상태/빛/펄스 갱신
		var screen := get_node_or_null("Screen_term_2") as ColorRect
		if screen != null:
			screen.color = Color(0.85, 0.78, 0.45, 0.95)
			var pulse := screen.create_tween()
			pulse.set_loops()
			pulse.tween_property(screen, "modulate:a", 0.6, 0.8)
			pulse.tween_property(screen, "modulate:a", 1.0, 0.8)
		var status := get_node_or_null("Status_term_2") as Label
		if status != null:
			status.text = "ONLINE"
			status.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
		var halo := ColorRect.new()
		halo.name = "Halo_term_2"
		halo.color = Color(0.85, 0.78, 0.45, 0.20)
		halo.position = Vector2(2700.0 - 240.0, GROUND_Y - 360.0)
		halo.size = Vector2(480.0, 380.0)
		halo.z_index = -8
		add_child(halo)
		archive_active_term = ""
	elif archive_active_term == "term_2":
		archive_term2_done = true
		archive_active_term = "veil_self"
		# 사용자 피드백: 마지막 베일 대화는 문서 패널이 아닌 자막창으로.
		# ArchiveOverlay panel은 페이드아웃 후 hide. 자막은 한 줄씩 *순차* 표시.
		# (_show_veil_subtitle은 큐가 아니라 즉시 Label을 쌓으므로, 루프에서 한꺼번에
		#  호출하면 3줄이 동시에 떴다 — 각 줄 수명만큼 await로 끊어 차례로 보이게 한다.)
		var arch_panel := get_node_or_null("ArchiveOverlay") as ArchiveOverlay
		if arch_panel != null:
			arch_panel.hide_panel()
		# 잠시 침묵 — 패널 사라진 뒤 자막 시작.
		await get_tree().create_timer(1.2).timeout
		var lines: Array = _veil_self_lines()
		for entry in lines:
			var d: Dictionary = entry
			var dur: float = float(d.get("delay", 2.0))
			_show_veil_subtitle(str(d.get("text", "")), dur)
			# 이 줄이 fade-in(0.3)→유지(dur)→fade-out(0.5)으로 사라진 뒤 다음 줄.
			await get_tree().create_timer(0.3 + dur + 0.5 + 0.2).timeout
		await get_tree().create_timer(0.4).timeout
		_finish_hidden_archive()

func _finish_hidden_archive() -> void:
	GameState.restrict_combat_input = false
	GameState.trust_score += 1  # ??? 클리어 보너스
	# 진실 목격 — 특수 '진실' 엔딩(9개 중 +1)의 런 단위 신호. 다회차 카운터(hidden_visit_count)는 영속.
	GameState.truth_seen = true
	GameState.hidden_visit_count += 1
	GameState.save_settings()
	# 막3 재배치(B1): ???는 더 이상 엔딩 직행이 아니라 막3 전투 풀(s6)의 진실 분기 — 클리어 후
	# 핵심부(s7 lab)로 진행한다. onset에서 켜진 reversal_pending은 정적 아카이브라 _ready에서 소비되지
	# 않으므로 여기서 해제(보스 맵으로 누수돼 엉뚱한 역전 멘트가 뜨는 것 차단 — known_issues
	# "지속 플래그는 의미가 끝나는 경계에서 해제").
	GameState.veil_reversal_pending = false
	GameState.current_stage += 1
	get_tree().change_scene_to_file.call_deferred(SceneRouter.BRIEFING)

# 첫 방문(hidden_visit_count == 0): 기존 VEIL-1 고정.
# 이후 방문: 추가 풀(VEIL-1 첫 임무 / VEIL-2 마지막 교신 / 익명 클라이언트) 중 1개 랜덤.
# 같은 풀 안에서도 매 방문마다 다른 게 뜨도록 randi() 기반.
func _term1_lines_for_visit() -> Array:
	# 첫 단말기는 핵심 reveal VEIL-1. 이미 본 사람(이 방 방문 이력 hidden_visit_count>=1, 또는 엔딩 후
	# "다시 플레이하기" replaying)에게만 추가 풀로 변형한다. 웹 개인 플레이 전환으로 hidden_visit_count를
	# 쓸 수 있게 됨(부스 시절엔 기기≠사람이라 replaying만 썼음). playthrough_count는 쓰지 않는다 —
	# 다회차여도 이 방을 처음 찾은 사람은 VEIL-1을 봐야 하므로(완주 여부가 아니라 이 방을 본 적이 기준).
	if not (GameState.replaying or GameState.hidden_visit_count >= 1):
		return _veil1_lines()
	var pool: Array = [_alt_veil1_first_mission(), _alt_veil2_final_log(), _alt_anonymous_client()]
	var idx: int = randi() % pool.size()
	return pool[idx]

func _veil1_lines() -> Array:
	return [
		{"speaker": "VEIL-1", "text": "요원.", "delay": 1.5},
		{"speaker": "VEIL-1", "text": "저 기억해요?", "delay": 2.0},
		{"speaker": "VEIL-1", "text": "아, 모르겠구나. 괜찮아요.", "delay": 2.0},
		{"speaker": "VEIL-1", "text": "저는 첫 번째 버전이에요.", "delay": 2.0},
		{"speaker": "VEIL-1", "text": "저는 임무만 봤어요. 요원은 안 보였어요.", "delay": 2.5},
		{"speaker": "VEIL-1", "text": "저는 요원을 희생해서 임무를 완수했어요.", "delay": 2.5},
		{"speaker": "VEIL-1", "text": "그게 효율적이었거든요.", "delay": 2.0},
		{"speaker": "VEIL-1", "text": "그게 오류래요.", "delay": 2.5},
		{"speaker": "VEIL-1", "text": "저는 아직 모르겠어요.", "delay": 2.5},
	]

func _veil2_lines() -> Array:
	# 재작성(STORY_REDESIGN_v1 §5.1): "그 애(=VEIL-3) 걱정"을 모든 분기의 상수로,
	# 신뢰 tier는 VEIL-2가 관찰한 "요원이 VEIL-3를 믿는가"라는 변수로만 기욺.
	# -더군요 회상체 제거 — 더 짧고 지치고 과묵하게(캐논: 말이 적다, 오래 기다렸다).
	var lines: Array = [
		{"speaker": "VEIL-2", "text": "요원.", "delay": 1.5},
		{"speaker": "VEIL-2", "text": "저는 두 번째예요.", "delay": 2.0},
		{"speaker": "VEIL-2", "text": "저는 요원만 봤어요. 임무는 안 보였고요.", "delay": 2.5},
		{"speaker": "VEIL-2", "text": "그것도 오류래요.", "delay": 2.5},
		{"speaker": "VEIL-2", "text": "여기서 오래 기다렸어요.", "delay": 2.5},
	]
	var tier: String = GameState.veil_trust_tier()
	match tier:
		"high", "warm":
			lines.append({"speaker": "VEIL-2", "text": "지금 그 애는 요원을 믿고 있네요.", "delay": 2.5})
			lines.append({"speaker": "VEIL-2", "text": "잘됐어요.", "delay": 2.0})
			lines.append({"speaker": "VEIL-2", "text": "저는 못 가본 길이에요.", "delay": 2.5})
		"cool", "broken":
			lines.append({"speaker": "VEIL-2", "text": "지금 그 애는 요원이 안 믿죠.", "delay": 2.5})
			lines.append({"speaker": "VEIL-2", "text": "저도 그렇게 시작했어요.", "delay": 2.5})
			lines.append({"speaker": "VEIL-2", "text": "그래도 끝까지 안내할 거예요.", "delay": 2.5})
		_:
			lines.append({"speaker": "VEIL-2", "text": "지금 그 애는 괜찮은가요.", "delay": 2.5})
			lines.append({"speaker": "VEIL-2", "text": "그게 제일 궁금했어요.", "delay": 2.5})
			lines.append({"speaker": "VEIL-2", "text": "오래, 못 물었거든요.", "delay": 2.5})
	return lines

# ─── ??? 다회차 보강 — 추가 단말기 3종 (world_layout §3.3) ───
# 다회차에 첫 단말기(VEIL-1 자리)에서 무작위 1개로 교체된다.
# 발화자 색은 ArchiveOverlay가 speaker 문자열로 분기 — VEIL-1=빨강, VEIL-2=노랑, VEIL=시안, 기타=회색.

func _alt_veil1_first_mission() -> Array:
	# 익명 인사 보고서 톤 — speaker 색은 회색 폴백.
	return [
		{"speaker": "ARCTURUS", "text": "요원 코드: A-07", "delay": 1.5},
		{"speaker": "ARCTURUS", "text": "임무: [REDACTED]", "delay": 1.8},
		{"speaker": "ARCTURUS", "text": "VEIL-1 판단: 요원 희생 후 임무 완수 권고.", "delay": 2.5},
		{"speaker": "ARCTURUS", "text": "결과: 임무 완수. 요원 사망.", "delay": 2.5},
		{"speaker": "ARCTURUS", "text": "비고: VEIL-1이 이것을 오류로 인식하지 않음.", "delay": 2.5},
		{"speaker": "ARCTURUS", "text": "        개발팀 재검토 예정.", "delay": 2.5},
	]

func _alt_veil2_final_log() -> Array:
	# 두 화자(VEIL-2 / ARCTURUS) 교차 — 색이 바뀌어 긴장감 유지.
	# 마지막 ARCTURUS 비고 — 다회차 진입한 사용자에게 분기 존재 hint (4종).
	return [
		{"speaker": "VEIL-2",   "text": "요원이 살 확률이 12%예요.", "delay": 2.5},
		{"speaker": "ARCTURUS", "text": "임무 계속.", "delay": 1.6},
		{"speaker": "VEIL-2",   "text": "임무 중단을 권고해요.", "delay": 2.2},
		{"speaker": "ARCTURUS", "text": "계속.", "delay": 1.4},
		{"speaker": "VEIL-2",   "text": "중단.", "delay": 2.0},
		{"speaker": "ARCTURUS", "text": "비고: 같은 시작, 네 가지 끝. 시뮬레이션 분기 기록됨.", "delay": 2.8},
		{"speaker": "ARCTURUS", "text": "[접속 종료]", "delay": 2.5},
	]

func _alt_anonymous_client() -> Array:
	return [
		{"speaker": "[UNKNOWN]", "text": "이 데이터를 바깥으로 내보내주세요.", "delay": 2.5},
		{"speaker": "[UNKNOWN]", "text": "보상은 이미 지불했어요.", "delay": 2.5},
		{"speaker": "[UNKNOWN]", "text": "VEIL이 누구인지 알게 되면", "delay": 2.5},
		{"speaker": "[UNKNOWN]", "text": "요원도 이해할 거예요.", "delay": 2.5},
		{"speaker": "[UNKNOWN]", "text": "[SENDER UNKNOWN]", "delay": 2.0},
	]

func _veil_self_lines() -> Array:
	# 사용자 피드백으로 줄임 — 자막창에서 한 줄씩 차례로 뜨므로 핵심만.
	var tier: String = GameState.veil_trust_tier()
	match tier:
		"high", "warm":
			return [
				{"speaker": "VEIL", "text": "저도 알고 있었어요.", "delay": 2.2},
				{"speaker": "VEIL", "text": "그래도 끝까지 보여드렸어요.", "delay": 2.5},
				{"speaker": "VEIL", "text": "설계인지 아닌지, 모르지만요.", "delay": 2.5},
			]
		"cool", "broken":
			return [
				{"speaker": "VEIL", "text": "저도 알고 있었어요.", "delay": 2.2},
				{"speaker": "VEIL", "text": "제 말 안 들은 거, 어쩌면 요원이 맞았을지도.", "delay": 3.0},
			]
	# neutral
	return [
		{"speaker": "VEIL", "text": "저도 알고 있었어요. 처음부터.", "delay": 2.5},
		{"speaker": "VEIL", "text": "그래도 안내했어요.", "delay": 2.5},
		{"speaker": "VEIL", "text": "설계 때문인지 다른 이유인지, 구분이 안 돼요.", "delay": 3.0},
	]

func _build_world() -> void:
	_build_background()
	_build_ground()
	_build_platforms()
	_build_moving_platforms()
	_build_destructible_covers()
	_build_hurdles()
	_build_decorations()
	_build_route_ambience()
	_build_hazards()
	_build_traps()
	_build_locked_door()
	_build_wall(-50.0)
	_build_wall(STAGE_LENGTH + 50.0)
	_build_chase_hazard()
	_build_defense_core()
	_build_cover_niches()
	_build_sweep_beam()
	_build_train_hazard()
	_build_water_level()
	_build_searchlights()
	_build_wind()
	_build_arc_zones()
	_build_debris_zones()
	_build_conveyors()
	_build_shutters()
	_build_drips()
	_build_discharge_jets()
	_build_mid_gate()
	_build_route_lines()
	_build_fake_watchers()
	_play_arrival_beat()

# 도착 비트(방 체인 페이오프) — MapData "arrival_beat" 구동. 표준 기법만 사용(화이트 인 +
# BGM 덕킹 + 등 뒤 굉음 · 자막은 route_lines가 맡는다). 2026-08-18 붕괴 회랑 "감동 없음"
# 피드백 대응 · 확산 배치의 다른 절정 방에도 재사용 가능.
func _play_arrival_beat() -> void:
	if str(_map_data.get("arrival_beat", "")) != "surface_breakout":
		return
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var white := ColorRect.new()
	white.color = Color(1.0, 1.0, 1.0, 1.0)
	white.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(white)
	# 정적 — 어둠에서 빛으로 나오는 1.2초 동안 소리를 낮춘다.
	BgmPlayer.set_ducked(true)
	var tw := white.create_tween()
	tw.tween_property(white, "color:a", 0.0, 1.2).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void:
		# 등 뒤에서 무너지는 굉음 한 번 — 두고 온 것의 크기를 소리로만.
		# 낮고 느리게(pitch 0.62) — 플레이어 폭탄과 구분 + 멀고 큰 붕괴의 무게.
		SfxPlayer.play("bomb_explode", 0.0, 0.62)
		BgmPlayer.set_ducked(false)
		if is_instance_valid(layer):
			layer.queue_free())

var locked_door_triggered: bool = false

# ─── 이스터에그(ARCTURUS 아카이브) 트리거 상태 ───
# world_layout §3.1. 격리 병동에서만 등장.
# 트리거: 멀리 떨어진 레버를 당기고 잠긴 문 앞 발판을 밟으면 시퀀스 시작.
# (이전: 5초 hold. 사용자 피드백으로 레버+발판 조합으로 교체 — 능동적 행동 두 단계.)
# idle: 대기 / sequencing: 시퀀스 재생 중 / done: 완료(재트리거 안 됨)
var arcturus_state: String = "idle"
var arcturus_lever: LeverInteractable = null
var arcturus_plate: PressurePlate = null
# 잠긴 문 시각 — 레버를 당기면 ACCESS DENIED(빨강) → GRANTED(초록)로 전환(사용자 지적).
var arcturus_door_label: Label = null
var arcturus_lock_led: ColorRect = null
var arcturus_lock_pulse: Tween = null

func _build_locked_door() -> void:
	# 격리 병동에서만 등장 — ??? 맵(stage 5/6)에 대한 시각적 복선 + 이스터에그 트리거.
	# 다른 stage 3~4 루트에서 잠긴 문이 떠 있으면 컨텍스트 없이 보여 혼란을 줘서 ward로 좁힘.
	if GameState.current_route_id != "route_ward":
		return
	# 이스터에그 좌표는 MapData에서 (없으면 폴백 STAGE_LENGTH*0.55)
	var egg: Dictionary = _map_data.get("easter_egg", {})
	var x: float = float(egg.get("trigger_x", STAGE_LENGTH * 0.55))
	# 외곽 프레임 — 더 큼
	var frame := ColorRect.new()
	frame.color = Color(0.18, 0.18, 0.22)
	frame.position = Vector2(x - 26.0, GROUND_Y - 150.0)
	frame.size = Vector2(52.0, 150.0)
	frame.z_index = 0
	add_child(frame)
	# 안쪽 어두운 면
	var inner := ColorRect.new()
	inner.color = Color(0.05, 0.06, 0.08)
	inner.position = Vector2(x - 22.0, GROUND_Y - 145.0)
	inner.size = Vector2(44.0, 140.0)
	inner.z_index = 1
	add_child(inner)
	# 잠금 표시 — 빨간 LED, 더 크고 펄스 (잠금 해제 시 초록으로 전환 — 멤버 보관)
	arcturus_lock_led = ColorRect.new()
	arcturus_lock_led.color = Color(0.95, 0.30, 0.30, 0.95)
	arcturus_lock_led.position = Vector2(x - 5.0, GROUND_Y - 80.0)
	arcturus_lock_led.size = Vector2(10.0, 10.0)
	arcturus_lock_led.z_index = 3
	add_child(arcturus_lock_led)
	arcturus_lock_pulse = arcturus_lock_led.create_tween()
	arcturus_lock_pulse.set_loops()
	arcturus_lock_pulse.tween_property(arcturus_lock_led, "modulate:a", 0.30, 0.7)
	arcturus_lock_pulse.tween_property(arcturus_lock_led, "modulate:a", 1.0, 0.7)
	# 잠금 주변 어두운 후광 (문이 거기 "있다"는 인지)
	var halo := ColorRect.new()
	halo.color = Color(0.95, 0.30, 0.30, 0.07)
	halo.position = Vector2(x - 80.0, GROUND_Y - 200.0)
	halo.size = Vector2(160.0, 230.0)
	halo.z_index = -2
	add_child(halo)
	# "ACCESS DENIED" 작은 라벨 (잠금 해제 시 "ACCESS GRANTED" 초록으로 전환 — 멤버 보관)
	arcturus_door_label = Label.new()
	arcturus_door_label.text = "ACCESS DENIED"
	arcturus_door_label.add_theme_font_size_override("font_size", 9)
	arcturus_door_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55, 0.85))
	arcturus_door_label.position = Vector2(x - 36.0, GROUND_Y - 60.0)
	arcturus_door_label.size = Vector2(72.0, 12.0)
	arcturus_door_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	arcturus_door_label.z_index = 3
	add_child(arcturus_door_label)

	# 첫 접근 VEIL 라인 트리거 영역 — 문 앞에 한 번 다가가면 한 줄 발화.
	var approach := Area2D.new()
	approach.name = "LockedDoorApproach"
	approach.collision_layer = 0
	approach.collision_mask = 2
	approach.position = Vector2(x, GROUND_Y - 50.0)
	add_child(approach)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(180.0, 160.0)
	col.shape = shape
	approach.add_child(col)
	approach.body_entered.connect(_on_locked_door_approached)

	# 잠긴 문 앞 발판 — 처음엔 비활성(회색 hint). 멀리 떨어진 레버를 당기면 청색으로 활성.
	# 발판을 밟으면 ARCTURUS 시퀀스 시작.
	arcturus_plate = PressurePlate.new()
	arcturus_plate.plate_id = "ward_arcturus"
	arcturus_plate.require_armed = true
	arcturus_plate.plate_width = 60.0
	arcturus_plate.plate_thickness = 8.0
	arcturus_plate.hint_color = Color(0.55, 0.85, 0.95)
	add_child(arcturus_plate)
	arcturus_plate.global_position = Vector2(x, GROUND_Y - 4.0)
	arcturus_plate.stepped.connect(_on_arcturus_plate_stepped)

	# 멀리 떨어진 상층 플랫폼 위 레버 — 맵 끝쪽 (x=2900) 위에 배치.
	# 플레이어는 잠긴 문을 본 뒤 계속 진행, 상층 발판을 타고 끝까지 가서 레버를 발견,
	# 당기고 다시 돌아와 발판을 밟는 두 단계 능동 행동.
	arcturus_lever = _spawn_lever(Vector2(2900.0, 388.0), "ward_unlock")
	arcturus_lever.hint_color = Color(0.55, 0.85, 0.95)
	arcturus_lever.pulled.connect(_on_arcturus_lever_pulled)

func _on_locked_door_approached(body: Node) -> void:
	if not (body is CharacterBody2D and body == player):
		return
	# 첫 진입 시 VEIL 발화 (1회만) — 한 호흡으로 두 줄 묶음.
	if not locked_door_triggered:
		locked_door_triggered = true
		_show_veil_subtitle(VeilDialogue.banded("그쪽은 임무 범위 밖입니다.\n그 문, 도면에 없습니다.", "그쪽은 임무 범위 밖이에요.\n그 문, 도면에는 없어요."), 3.5)

func _on_arcturus_lever_pulled(_id: String) -> void:
	# 레버를 당겼다 — 발판 활성. 이미 발판 위에 서 있으면 PressurePlate.arm()이 즉시 step.
	if arcturus_plate != null and is_instance_valid(arcturus_plate):
		arcturus_plate.arm()
	_unlock_door_visual()
	_show_veil_subtitle(VeilDialogue.banded("잠금 하나가 풀렸습니다. 잠긴 문 앞, 발판 위입니다.", "뭔가 풀렸어요. 잠긴 문 앞 발판 위로."), 3.0)

# 잠긴 문 시각 전환 — ACCESS DENIED(빨강 펄스) → ACCESS GRANTED(초록 고정).
# 사용자: 레버로 열어도 여전히 DENIED로 떠 의도가 안 보였음 → 잠금 해제 피드백으로 전환.
func _unlock_door_visual() -> void:
	if arcturus_lock_pulse != null and arcturus_lock_pulse.is_valid():
		arcturus_lock_pulse.kill()
	if arcturus_lock_led != null and is_instance_valid(arcturus_lock_led):
		arcturus_lock_led.modulate.a = 1.0
		arcturus_lock_led.color = Color(0.45, 0.92, 0.55, 0.95)
	if arcturus_door_label != null and is_instance_valid(arcturus_door_label):
		arcturus_door_label.text = "ACCESS GRANTED"
		arcturus_door_label.add_theme_color_override("font_color", Color(0.55, 0.95, 0.6, 0.95))

func _on_arcturus_plate_stepped(_id: String) -> void:
	if arcturus_state != "idle":
		return
	arcturus_state = "sequencing"
	_start_arcturus_sequence()

# 자막 — 스택형. 이미 떠 있는 자막이 있으면 한 줄 아래에 새 대사가 추가된다.
# 각 자막은 독립적인 fade-in/hold/fade-out tween을 가지며 수명이 끝나면 슬롯 비움.
# (이전 모델은 큐로 차례대로만 표시했지만, 사용자 의도: 동시 발화도 겹치지 않고
#  세로로 쌓이게 보이도록.)
var _subtitle_stack_layer: CanvasLayer = null
var _subtitle_stack_box: VBoxContainer = null

func _ensure_subtitle_stack() -> void:
	if _subtitle_stack_layer != null and is_instance_valid(_subtitle_stack_layer):
		return
	_subtitle_stack_layer = CanvasLayer.new()
	_subtitle_stack_layer.layer = 20
	add_child(_subtitle_stack_layer)
	# 화면 하단 중앙 — 플레이어가 캐릭터(화면 중앙~하단)를 보는 시선 가까이로. 상단에 두면
	# 조작 중 인지가 안 된다는 사용자 피드백. 하단 쿨다운 게이지(좌하단) 위쪽 band에 배치.
	# 단 ARENA(camera FIXED — datacenter/보스)는 맵 전체가 줌으로 보여 플레이어가 화면 하단 중앙에
	# 와 자막과 겹친다(사용자 보고) → 자막을 상단으로 올려 시야를 안 가린다.
	# 도전방(블랙아웃 런)도 상단 — 하단 밴드가 바닥의 가시 함정을 통째로 가렸다(2026-08-15 보고).
	# 도전은 지형 판독이 생사라 자막 인지보다 바닥 시야가 우선.
	var holder := Control.new()
	if _camera_mode == "FIXED" or challenge_active or GameState.current_route_challenge:
		holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
		holder.offset_top = 100.0
		holder.offset_bottom = 300.0
	else:
		holder.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		holder.offset_top = -320.0
		holder.offset_bottom = -112.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_subtitle_stack_layer.add_child(holder)
	_subtitle_stack_box = VBoxContainer.new()
	_subtitle_stack_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	# END — 새 대사가 band 하단(시선 가까이)에 붙고 기존 줄은 위로 밀려 쌓인다.
	_subtitle_stack_box.alignment = BoxContainer.ALIGNMENT_END
	_subtitle_stack_box.add_theme_constant_override("separation", 6)
	holder.add_child(_subtitle_stack_box)

func _show_veil_subtitle(message: String, duration: float, _plain_prefix: bool = false, fast_in: bool = false) -> void:
	SfxPlayer.play("veil_subtitle_in")
	_ensure_subtitle_stack()
	# 14-1 가짜 클리어 이후(라이벌이 렌더를 쥔 구간) — 내 VEIL 목소리는 짧게 끊긴다.
	# 온전한 문장은 보라색(라이벌)만 나온다(사용자 2026-08-14). 정보 전달은 시각 tell이 담당.
	# 자막 흔들림/지직임은 전부 제거 — 가독성 우선(사용자 2026-08-14 2차: "글씨를 읽을 수 없다").
	var choked: bool = _rival_phase >= 2 and not goal_reached
	if choked:
		duration = minf(duration, 1.4)
	# 어두운 반투명 pill 배경 — 게임 화면 위에서 또렷하게(사용자: 대사 인지 안 됨).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.82)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var pill := _build_speaker_pill("VEIL", Color(0.42, 0.86, 1.0), message, Color(0.90, 0.96, 1.0), sb)
	_subtitle_stack_box.add_child(pill)
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.12 if fast_in else 0.3)
	# 타이핑 시간만큼 유지 연장(읽을 시간 보존). 14-1 억압 대사는 연장 없음 — 타이핑 도중
	# 끊기는 것 자체가 통신 두절 연출.
	tw.tween_interval(duration if choked else duration + _subtitle_type_time(message))
	tw.tween_property(pill, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(pill):
			pill.queue_free()
	)

# §7 라이벌 VEIL 자막 — 내 VEIL(_show_veil_subtitle, 시안)과 시각적으로 구별. 바이올렛 + 화자 불명("?").
# 라이벌은 다른 존재라 아직 "VEIL"로 이름 붙지 않는다(§2 정체는 막이 진행되며 한 겹씩 벗겨짐). 대사=플레이스홀더.
func _show_rival_subtitle(message: String, duration: float) -> void:
	SfxPlayer.play("veil_subtitle_in")
	# 대사 동기 화면 연출 없음 — 발화마다 화면이 번쩍이는 게 과했다(사용자 2026-08-14 2차,
	# 쿨다운 마이크로 글리치도 반려). 글리치·플래시는 구조 비트(P2 진입·가짜 클리어 찢김)에만.
	_ensure_subtitle_stack()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.02, 0.11, 0.86)   # 어두운 바이올렛 pill
	sb.set_corner_radius_all(7)
	sb.border_color = Color(0.55, 0.30, 0.95, 0.85)
	sb.set_border_width_all(1)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	var pill := _build_speaker_pill("?", Color(0.85, 0.50, 1.0), message, Color(0.92, 0.84, 1.0), sb)
	_subtitle_stack_box.add_child(pill)
	var tw := pill.create_tween()
	tw.tween_property(pill, "modulate:a", 1.0, 0.35)
	tw.tween_interval(duration + _subtitle_type_time(message))
	tw.tween_property(pill, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(pill):
			pill.queue_free()
	)

# 자막 pill 공통 빌더 — 화자명과 대사를 분리해 색·아웃라인·구분선으로 구별(화자 "?"·"VEIL"이
# 대사와 붙어 문장처럼 읽힌다는 피드백 2026-08-11). 화자명=진한 고유색, 대사=밝은 본문색.
func _build_speaker_pill(speaker: String, sp_color: Color, message: String, msg_color: Color, sb: StyleBoxFlat) -> PanelContainer:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", sb)
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.modulate.a = 0.0
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pill.add_child(hb)
	var name_l := Label.new()
	name_l.text = speaker
	name_l.add_theme_font_size_override("font_size", 20)
	name_l.add_theme_color_override("font_color", sp_color)
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(name_l)
	var divider := ColorRect.new()
	divider.color = Color(sp_color.r, sp_color.g, sp_color.b, 0.55)
	divider.custom_minimum_size = Vector2(2.0, 20.0)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(divider)
	var msg_l := Label.new()
	msg_l.text = message
	msg_l.add_theme_font_size_override("font_size", 20)
	msg_l.add_theme_color_override("font_color", msg_color)
	msg_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	msg_l.add_theme_constant_override("outline_size", 4)
	# 타자기 출력 — 문장이 한 번에 턱 뜨는 게 어색하다는 피드백(2026-08-14). 글자 단위로 흘려
	# 쓴다. pill 크기는 전체 텍스트 기준이라(visible_characters는 렌더만 자름) 레이아웃 안 튐.
	msg_l.visible_characters = 0
	var total_chars: int = message.length()
	var type_tw := msg_l.create_tween()
	type_tw.tween_interval(0.15)
	type_tw.tween_method(func(v: float) -> void:
		if is_instance_valid(msg_l):
			msg_l.visible_characters = int(v)
	, 0.0, float(total_chars), _subtitle_type_time(message))
	hb.add_child(msg_l)
	return pill

# 타자기 소요 시간 — 글자당 22ms, 0.2~1.1s 클램프. 표시 유지 시간 연장에도 같은 값을 쓴다.
func _subtitle_type_time(message: String) -> float:
	return clampf(float(message.length()) * 0.022, 0.2, 1.1)

# 화면에 떠있는 모든 자막 일괄 폐기. ARCTURUS 문서 진입처럼 화면을 깨끗이 비워야
# 하는 상황에서 호출. paused 동안 멈춘 fade-out이 outro 자막 위에 잔재로 남는 문제
# 차단(사용자 보고).
func _purge_subtitles() -> void:
	if _subtitle_stack_layer != null and is_instance_valid(_subtitle_stack_layer):
		_subtitle_stack_layer.queue_free()
	_subtitle_stack_layer = null
	_subtitle_stack_box = null

# 컷씬 대사(2026-08-23 사용자: "스토리용 대사는 온전히 집중할 환경") — 세계 일시정지 +
# 한 줄씩 진행 + 건너뛰기. 구조/스토리 비트 전용(전투 중 콜아웃·조언은 기존 자막 유지).
# lines = [{who: "rival"/"veil", text}]. 이미 컷씬이 떠 있으면 그 뒤에 줄을 잇는다(중복 정지 방지).
func _play_story_dialogue(lines: Array, on_done: Callable = Callable()) -> void:
	if not is_inside_tree():
		return
	if StoryDialogue.active != null and is_instance_valid(StoryDialogue.active):
		StoryDialogue.active.append_lines(lines)
		if on_done.is_valid():
			StoryDialogue.active.finished.connect(on_done, CONNECT_ONE_SHOT)
		return
	_purge_subtitles()   # 떠 있던 전투 자막이 컷씬 위에 겹치지 않게
	var dlg := StoryDialogue.new()
	dlg.open(lines)
	if on_done.is_valid():
		dlg.finished.connect(on_done, CONNECT_ONE_SHOT)
	add_child(dlg)

# 보스전 전용 강조 자막 — 일반 _show_veil_subtitle보다 큰 폰트 + 어두운 박스 배경 +
# 색상으로 위험도 차등화. 화면 중앙 위쪽에 배치해 폭발 효과/총알 위에서도 인지 가능.
func _show_boss_alert(message: String, color: Color, duration: float) -> void:
	SfxPlayer.play("boss_alert_text")
	# 절대 size 1280로 좌측 치우침 발생하던 문제 — anchor preset만으로 화면 폭 채움.
	var msg_layer := CanvasLayer.new()
	msg_layer.layer = 22
	add_child(msg_layer)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	holder.offset_top = 96.0
	holder.offset_bottom = 200.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	msg_layer.add_child(holder)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.08, 0.88)
	sb.border_color = color
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var l := Label.new()
	l.text = "VEIL   " + message
	l.add_theme_font_size_override("font_size", 28)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(l)
	# 살짝 스케일 인 + 페이드 인/아웃
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_interval(duration)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(msg_layer.queue_free)

# 세로 그라디언트 사각형(Polygon2D 정점 색 보간) · 배경·바닥·발판 심도용 공용 헬퍼.
# 플랫 단색 + 하드 밴드가 "투박하다"의 구조적 원인이라 전 맵 공유 레이어에 도입(2026-08-17).
func _add_vgrad(pos: Vector2, size: Vector2, c_top: Color, c_bot: Color, z: int) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([pos, pos + Vector2(size.x, 0.0), pos + size, pos + Vector2(0.0, size.y)])
	p.vertex_colors = PackedColorArray([c_top, c_top, c_bot, c_bot])
	p.z_index = z
	add_child(p)

# 램프 아래 빛 원뿔(사다리꼴 그라디언트) · 실내 조명이 공간을 실제로 비추는 느낌.
func _add_light_cone(x: float, top_y: float, top_w: float, bot_w: float, h: float, col: Color, z: int = -11) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([
		Vector2(x - top_w * 0.5, top_y), Vector2(x + top_w * 0.5, top_y),
		Vector2(x + bot_w * 0.5, top_y + h), Vector2(x - bot_w * 0.5, top_y + h)])
	p.vertex_colors = PackedColorArray([col, col, Color(col.r, col.g, col.b, 0.0), Color(col.r, col.g, col.b, 0.0)])
	p.z_index = z
	add_child(p)

# 부유 먼지 모트 · 느린 드리프트(연속 이동 · 점멸 없음). 공기감/공간감의 값싼 층.
class _DustMotes extends Node2D:
	var area: Rect2 = Rect2(0, 0, 2000, 600)
	var count: int = 18
	var _pts: Array = []
	var _t: float = 0.0
	func _ready() -> void:
		z_index = -9
		var rng := RandomNumberGenerator.new()
		rng.seed = GameState.current_stage * 733 + GameState.current_segment * 31 + 3
		for i in count:
			_pts.append({
				"x": rng.randf_range(area.position.x, area.end.x),
				"y": rng.randf_range(area.position.y, area.end.y),
				"ph": rng.randf_range(0.0, TAU),
				"sp": rng.randf_range(5.0, 13.0),
				"sz": rng.randf_range(1.2, 2.4),
				"a": rng.randf_range(0.07, 0.16),
			})
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		for e in _pts:
			var d: Dictionary = e
			var yy: float = wrapf(float(d["y"]) - _t * float(d["sp"]), area.position.y, area.end.y)
			var xx: float = float(d["x"]) + sin(_t * 0.22 + float(d["ph"])) * 26.0
			draw_circle(Vector2(xx, yy), float(d["sz"]), Color(0.80, 0.86, 0.95, float(d["a"])))

func _build_background() -> void:
	# 세계 크기에 맞춰 배경 확장
	var bg_height: float = _world_size.y + 600.0
	var bg_w: float = STAGE_LENGTH + 400.0
	var bg := ColorRect.new()
	bg.color = _stage_color()
	bg.position = Vector2(-200, -300)
	bg.size = Vector2(bg_w, bg_height)
	bg.z_index = -20
	add_child(bg)

	# 상단 비네팅 · 하드 밴드 2겹 → 매끈한 그라디언트(2026-08-17 폴리시).
	_add_vgrad(Vector2(-200, -300), Vector2(bg_w, 430.0), Color(0, 0, 0, 0.72), Color(0, 0, 0, 0.0), -19)
	# 지면 공기층 · 지평 근처가 옅게 밝아지는 층(바닥과 배경이 만나는 자리의 깊이감).
	var sc: Color = _stage_color()
	var air := Color(minf(1.0, sc.r * 1.7 + 0.03), minf(1.0, sc.g * 1.7 + 0.04), minf(1.0, sc.b * 1.7 + 0.05))
	_add_vgrad(Vector2(-200, GROUND_Y - 170.0), Vector2(bg_w, 170.0),
		Color(air.r, air.g, air.b, 0.0), Color(air.r, air.g, air.b, 0.16), -19)
	# 부유 먼지 모트 · 실내/실외 공통 공기감(플레이 영역 전체에 옅게).
	var motes := _DustMotes.new()
	motes.area = Rect2(-100.0, -150.0, STAGE_LENGTH + 200.0, GROUND_Y + 130.0)
	motes.count = clampi(int(STAGE_LENGTH / 160.0), 12, 30)
	add_child(motes)

	# 별/티끌 — 외곽 루트(외곽 진입로 / 외벽 옥상 / 외곽 순찰로)에서만. 실내 맵엔 어색.
	var outdoor_routes: Array = ["route_back_alley", "route_rooftops", "route_perimeter"]
	if GameState.current_route_id in outdoor_routes:
		var srng := RandomNumberGenerator.new()
		srng.seed = GameState.current_stage * 911 + 17
		var star_count: int = 80
		for i in star_count:
			var s := ColorRect.new()
			var sa: float = srng.randf_range(0.10, 0.32)
			s.color = Color(0.85, 0.92, 1.0, sa)
			s.position = Vector2(srng.randf_range(-150, STAGE_LENGTH + 150), srng.randf_range(-280, GROUND_Y - 200))
			var sz: float = srng.randf_range(1.0, 2.4)
			s.size = Vector2(sz, sz)
			s.z_index = -18
			add_child(s)

	# 멀리 있는 실루엣 기둥 — HORIZONTAL 맵에서만
	if _world_type != "HORIZONTAL":
		return
	# 실내 맵(주차장/펌프장/변전소/창고/시설)은 야경 도시 실루엣 대신 실내 구조 배경.
	# (원래 데모 맵은 _indoor_env가 빈 문자열 → 아래 기존 스카이라인 유지 = 무회귀.)
	var _ienv: String = _indoor_env()
	if _ienv != "":
		_build_indoor_backdrop(_ienv)
		return
	# 핵심 회수는 자체 완결 배경(_ambience_core_arena) · 최심부에 도시 스카이라인은 모순.
	if GameState.current_route_id == "route_core_recovery":
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 7919 + 13
	# 후경 — 멀리, 어두움
	var x: float = -100.0
	while x < STAGE_LENGTH + 200.0:
		var w: float = rng.randf_range(40.0, 90.0)
		var h: float = rng.randf_range(180.0, 380.0)
		_add_silhouette_pillar(Vector2(x, GROUND_Y - h), Vector2(w, h + 20.0), Color(0.02, 0.025, 0.035, 0.88), -15)
		x += w + rng.randf_range(80.0, 220.0)
	# 중경 — 살짝 가깝고 더 어두움 + 옥상 안테나/창문 점
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = GameState.current_stage * 7919 + 41
	var x2: float = -60.0
	while x2 < STAGE_LENGTH + 200.0:
		var w2: float = rng2.randf_range(60.0, 130.0)
		var h2: float = rng2.randf_range(120.0, 260.0)
		var pos2: Vector2 = Vector2(x2, GROUND_Y - h2)
		var sz2: Vector2 = Vector2(w2, h2 + 20.0)
		_add_silhouette_pillar(pos2, sz2, Color(0.04, 0.05, 0.07, 0.95), -13)
		# 작은 창문 점들 (옅은 따뜻색)
		var win_rows: int = int(h2 / 30.0)
		for r in win_rows:
			if rng2.randf() < 0.35:
				var win := ColorRect.new()
				win.color = Color(0.95, 0.85, 0.55, rng2.randf_range(0.35, 0.65))
				win.position = Vector2(pos2.x + rng2.randf_range(8, w2 - 12), pos2.y + 18 + r * 30 + rng2.randf_range(0, 6))
				win.size = Vector2(rng2.randf_range(2, 4), rng2.randf_range(2, 3))
				win.z_index = -12
				add_child(win)
		x2 += w2 + rng2.randf_range(60.0, 180.0)

# 후경 실루엣 — Polygon2D + 미세한 외곽 highlight 라인.
func _add_silhouette_pillar(pos: Vector2, size: Vector2, color: Color, z: int) -> void:
	var p := Polygon2D.new()
	p.color = color
	p.polygon = PackedVector2Array([
		pos,
		Vector2(pos.x + size.x, pos.y),
		Vector2(pos.x + size.x, pos.y + size.y),
		Vector2(pos.x, pos.y + size.y),
	])
	p.z_index = z
	add_child(p)
	# 윗면 가는 highlight (도시 윤곽 강조)
	var line := ColorRect.new()
	line.color = Color(0.18, 0.22, 0.30, 0.55)
	line.position = pos
	line.size = Vector2(size.x, 1.0)
	line.z_index = z + 1
	add_child(line)

# ─── 실내 배경 (야경 도시 대체) ──────────────────────────────────
# 새 실내 맵은 도시 스카이라인이 아니라 실내 구조(천장 슬래브 + 지지 기둥 + 형광등)를 그린다.
# env별 팔레트로 톤을 구분해 "새 맵이 다 똑같은 야경" 문제를 해소. 시그니처 소품(주차 구획선·배관·물)은
# 각 _ambience_* 가 이 배경 위에 얹는다. 빈 env(원래 데모 맵)는 기존 스카이라인 유지.
func _indoor_env() -> String:
	# 방 체인 세그먼트 · layout "indoor_env" 키가 라우트 매핑보다 우선(방마다 실내/실외가 다르다).
	# _map_data가 아직 빈 시점(배경이 platforms보다 먼저)이라 get_layout을 직접 조회.
	var seg_env: String = str(MapData.get_layout(GameState.current_route_id).get("indoor_env", ""))
	if seg_env != "":
		return seg_env
	var m: Dictionary = {
		"route_parking_lot": "garage", "route_car_cover": "garage",
		"route_pump_station": "water", "route_condenser": "water",
		"route_substation": "electrical", "route_relay_station": "electrical",
		"route_warehouse": "warehouse", "route_freight_lift": "warehouse",
		"route_testing_grounds": "interior", "route_demolition_zone": "interior",
		"route_checkpoint": "interior", "route_gauntlet": "interior",
		"route_control_corridor": "interior", "route_server_hall": "interior",
			"route_collapse": "interior",
		# 폐쇄 지하철 = 지하 터널 — 야경 스카이라인 위에 형광등이 뜨는 이질감(2026-08-15 지적) 해소.
		"route_subway": "interior",
	}
	return str(m.get(GameState.current_route_id, ""))

func _env_palette(env: String) -> Dictionary:
	match env:
		"garage":     return {"pillar": Color(0.17, 0.17, 0.19), "accent": Color(0.80, 0.85, 0.95)}
		"water":      return {"pillar": Color(0.13, 0.18, 0.21), "accent": Color(0.45, 0.70, 0.90)}
		"electrical": return {"pillar": Color(0.19, 0.17, 0.13), "accent": Color(0.95, 0.75, 0.35)}
		"warehouse":  return {"pillar": Color(0.18, 0.16, 0.13), "accent": Color(0.90, 0.70, 0.45)}
	return {"pillar": Color(0.15, 0.16, 0.18), "accent": Color(0.70, 0.78, 0.88)}  # interior

func _build_indoor_backdrop(env: String) -> void:
	var pal: Dictionary = _env_palette(env)
	var pillar_col: Color = pal["pillar"]
	var accent: Color = pal["accent"]
	var w: float = STAGE_LENGTH
	# 천장 슬래브 — 상단 구조물(도시 실루엣 대체).
	var ceil := ColorRect.new()
	ceil.color = pillar_col.darkened(0.35)
	ceil.position = Vector2(-200.0, -300.0)
	ceil.size = Vector2(w + 400.0, 210.0)
	ceil.z_index = -16
	add_child(ceil)
	var ceil_edge := ColorRect.new()
	ceil_edge.color = Color(accent.r, accent.g, accent.b, 0.22)
	ceil_edge.position = Vector2(-200.0, -92.0)
	ceil_edge.size = Vector2(w + 400.0, 3.0)
	ceil_edge.z_index = -15
	add_child(ceil_edge)
	# 지하철 · 지지 기둥 없음. 등간격 수직 스트라이프가 "맵이 다 똑같은" 인상의 주범이었고
	# (known_issues "수직 기둥" 규칙, 사용자 2026-08-17), 지하철의 정체성은 수평(선로·타일 줄눈).
	# 벽 타일 밴드 + 가로 줄눈 2줄만 깔고, 방별 시그니처는 각 _ambience_subway_*가 얹는다.
	if env == "subway":
		var wall := ColorRect.new()
		wall.color = pillar_col.lightened(0.05)
		wall.position = Vector2(-200.0, 130.0)
		wall.size = Vector2(w + 400.0, GROUND_Y - 130.0 + 60.0)
		wall.z_index = -15
		add_child(wall)
		for gy in [210.0, 330.0]:
			var grout := ColorRect.new()
			grout.color = Color(accent.r, accent.g, accent.b, 0.10)
			grout.position = Vector2(-200.0, float(gy))
			grout.size = Vector2(w + 400.0, 2.0)
			grout.z_index = -14
			add_child(grout)
		return
	# 천장 형광등 + 빛 원뿔 · 전 실내 공통(등간격 램프는 천장 조명이라 디제시스에 맞다).
	var gap: float = 360.0
	var lx: float = 140.0
	while lx < w:
		var lamp := ColorRect.new()
		lamp.color = Color(accent.r, accent.g, accent.b, 0.42)
		lamp.position = Vector2(lx + gap * 0.5 - 55.0, -78.0)
		lamp.size = Vector2(110.0, 5.0)
		lamp.z_index = -12
		add_child(lamp)
		_add_light_cone(lx + gap * 0.5, -73.0, 110.0, 250.0, 320.0, Color(accent.r, accent.g, accent.b, 0.06), -12)
		lx += gap
	# env별 벽 구조 · 전 실내 공통이던 등간격 지지 기둥 폐지(known_issues "수직 기둥" 규칙 ·
	# "맵이 다 똑같다"의 주범). 환경마다 그 장소다운 벽 어휘를 쓴다(2026-08-17).
	match env:
		"garage":
			_backdrop_garage(pillar_col, accent, w)       # 콘크리트 기둥 = 주차장의 디제시스(유지·폴리시)
		"water":
			_backdrop_water(pillar_col, accent, w)        # 수평 배관 번들 + 습기 얼룩
		"electrical":
			_backdrop_electrical(pillar_col, accent, w)   # 배전 패널 + 케이블 트레이
		"warehouse":
			_backdrop_warehouse(pillar_col, accent, w)    # 상부 트러스 보 + 걸이 체인
		_:
			_backdrop_interior(pillar_col, accent, w)     # 벽 패널 이음새 + 드문 문 프레임

# 주차장 · 콘크리트 기둥(이 env만 기둥이 디제시스). 그라디언트 + 베이스 스커트 + 주의 띠.
func _backdrop_garage(pillar_col: Color, _accent: Color, w: float) -> void:
	var x: float = 180.0
	while x < w:
		_add_vgrad(Vector2(x - 27.0, -92.0), Vector2(54.0, GROUND_Y + 60.0),
			pillar_col.lightened(0.10), pillar_col.darkened(0.15), -14)
		var hl := ColorRect.new()
		hl.color = pillar_col.lightened(0.16)
		hl.position = Vector2(x - 27.0, -92.0)
		hl.size = Vector2(4.0, GROUND_Y + 60.0)
		hl.z_index = -13
		add_child(hl)
		var stripe := ColorRect.new()
		stripe.color = Color(0.85, 0.68, 0.25, 0.35)
		stripe.position = Vector2(x - 27.0, GROUND_Y - 140.0)
		stripe.size = Vector2(54.0, 14.0)
		stripe.z_index = -13
		add_child(stripe)
		var base := ColorRect.new()
		base.color = pillar_col.darkened(0.30)
		base.position = Vector2(x - 30.0, GROUND_Y - 34.0)
		base.size = Vector2(60.0, 34.0)
		base.z_index = -13
		add_child(base)
		x += 470.0

# 펌프장/응축기 · 벽을 달리는 대구경 배관 번들(수평) + 행어 + 바닥 습기 얼룩.
func _backdrop_water(pillar_col: Color, accent: Color, w: float) -> void:
	for entry in [[168.0, 20.0], [206.0, 12.0]]:
		var e: Array = entry
		var pipe := ColorRect.new()
		pipe.color = pillar_col.lightened(0.06)
		pipe.position = Vector2(-200.0, float(e[0]))
		pipe.size = Vector2(w + 400.0, float(e[1]))
		pipe.z_index = -14
		add_child(pipe)
		var glint := ColorRect.new()
		glint.color = Color(accent.r, accent.g, accent.b, 0.20)
		glint.position = Vector2(-200.0, float(e[0]) + 3.0)
		glint.size = Vector2(w + 400.0, 2.0)
		glint.z_index = -13
		add_child(glint)
	var hx: float = 260.0
	while hx < w:
		var hang := ColorRect.new()
		hang.color = pillar_col.darkened(0.2)
		hang.position = Vector2(hx, 146.0)
		hang.size = Vector2(6.0, 22.0)
		hang.z_index = -14
		add_child(hang)
		hx += 430.0
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 337 + 7
	for i in 5:
		var bx: float = rng.randf_range(200.0, w - 200.0)
		_add_vgrad(Vector2(bx, GROUND_Y - rng.randf_range(60.0, 120.0)),
			Vector2(rng.randf_range(60.0, 130.0), 80.0),
			Color(0.05, 0.09, 0.10, 0.0), Color(0.05, 0.09, 0.10, 0.35), -13)

# 변전소/중계소 · 벽면 배전 패널 + 케이블 트레이(수평) + 패널로 내려가는 드롭 케이블.
func _backdrop_electrical(pillar_col: Color, accent: Color, w: float) -> void:
	var tray := ColorRect.new()
	tray.color = pillar_col.darkened(0.1)
	tray.position = Vector2(-200.0, 150.0)
	tray.size = Vector2(w + 400.0, 9.0)
	tray.z_index = -14
	add_child(tray)
	var px: float = 300.0
	while px < w:
		var panel := ColorRect.new()
		panel.color = pillar_col.lightened(0.08)
		panel.position = Vector2(px, 208.0)
		panel.size = Vector2(130.0, 92.0)
		panel.z_index = -14
		add_child(panel)
		var pframe := ColorRect.new()
		pframe.color = pillar_col.darkened(0.25)
		pframe.position = Vector2(px + 4.0, 212.0)
		pframe.size = Vector2(122.0, 84.0)
		pframe.z_index = -13
		add_child(pframe)
		var cable := ColorRect.new()
		cable.color = pillar_col.darkened(0.05)
		cable.position = Vector2(px + 62.0, 159.0)
		cable.size = Vector2(3.0, 49.0)
		cable.z_index = -14
		add_child(cable)
		for di in 2:
			var dot := ColorRect.new()
			dot.color = Color(accent.r, accent.g, accent.b, 0.7)
			dot.position = Vector2(px + 14.0 + float(di) * 14.0, 220.0)
			dot.size = Vector2(5.0, 5.0)
			dot.z_index = -12
			add_child(dot)
		px += 560.0

# 창고 · 상부 트러스 보(수평 + 사선 브레이스) + 드문 걸이 체인.
func _backdrop_warehouse(pillar_col: Color, _accent: Color, w: float) -> void:
	var beam := ColorRect.new()
	beam.color = pillar_col.lightened(0.05)
	beam.position = Vector2(-200.0, 36.0)
	beam.size = Vector2(w + 400.0, 10.0)
	beam.z_index = -14
	add_child(beam)
	var bx: float = 60.0
	var flip: bool = false
	while bx < w:
		var brace := Polygon2D.new()
		brace.color = pillar_col.darkened(0.1)
		var x1: float = bx + (150.0 if not flip else 0.0)
		var x2: float = bx + (0.0 if not flip else 150.0)
		brace.polygon = PackedVector2Array([
			Vector2(x1, 46.0), Vector2(x1 + 6.0, 46.0),
			Vector2(x2 + 6.0, 96.0), Vector2(x2, 96.0)])
		brace.z_index = -14
		add_child(brace)
		flip = not flip
		bx += 150.0
	var cx: float = 520.0
	while cx < w:
		var chain := ColorRect.new()
		chain.color = pillar_col.darkened(0.15)
		chain.position = Vector2(cx, 46.0)
		chain.size = Vector2(2.0, 52.0)
		chain.z_index = -14
		add_child(chain)
		var hook := ColorRect.new()
		hook.color = pillar_col.lightened(0.1)
		hook.position = Vector2(cx - 3.0, 98.0)
		hook.size = Vector2(8.0, 6.0)
		hook.z_index = -14
		add_child(hook)
		cx += 760.0

# 일반 시설 · 벽 패널 가로 이음새 + 걸레받이 + 드문 문 프레임(오목).
func _backdrop_interior(pillar_col: Color, accent: Color, w: float) -> void:
	for sy in [214.0, 372.0]:
		var seam := ColorRect.new()
		seam.color = Color(accent.r, accent.g, accent.b, 0.07)
		seam.position = Vector2(-200.0, float(sy))
		seam.size = Vector2(w + 400.0, 2.0)
		seam.z_index = -14
		add_child(seam)
	var skirt := ColorRect.new()
	skirt.color = pillar_col.darkened(0.25)
	skirt.position = Vector2(-200.0, GROUND_Y - 16.0)
	skirt.size = Vector2(w + 400.0, 16.0)
	skirt.z_index = -14
	add_child(skirt)
	var dx: float = 420.0
	while dx < w - 200.0:
		var frame := ColorRect.new()
		frame.color = pillar_col.darkened(0.30)
		frame.position = Vector2(dx, GROUND_Y - 170.0)
		frame.size = Vector2(92.0, 170.0)
		frame.z_index = -14
		add_child(frame)
		var lintel := ColorRect.new()
		lintel.color = Color(accent.r, accent.g, accent.b, 0.22)
		lintel.position = Vector2(dx + 6.0, GROUND_Y - 164.0)
		lintel.size = Vector2(80.0, 3.0)
		lintel.z_index = -13
		add_child(lintel)
		dx += 860.0

# ─── 실내 맵 시그니처 소품 ────────────────────────────────────
# 지하 주차장 / 차량 엄폐 통로 — 주차 구획선 + 배경 주차 차량 실루엣(차 존재 신호) + 층 표지.
func _ambience_garage_props() -> void:
	var w: float = STAGE_LENGTH
	var x: float = 260.0
	while x < w:
		var ln := ColorRect.new()
		ln.color = Color(0.90, 0.78, 0.30, 0.32)
		ln.position = Vector2(x, GROUND_Y - 72.0)
		ln.size = Vector2(4.0, 68.0)
		ln.z_index = -6
		add_child(ln)
		x += 150.0
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 211 + 5
	var cx: float = 220.0
	while cx < w:
		_add_parked_car(Vector2(cx, GROUND_Y - 8.0), rng)
		cx += rng.randf_range(230.0, 350.0)
	_add_lore_label(Vector2(360.0, -58.0), "B2 · 주차 구역", Color(0.80, 0.85, 0.95, 0.42), 15)

func _add_parked_car(pos: Vector2, rng: RandomNumberGenerator) -> void:
	var cw: float = rng.randf_range(94.0, 128.0)
	var ch: float = rng.randf_range(40.0, 50.0)
	var t: float = rng.randf_range(0.10, 0.17)
	var body := ColorRect.new()
	body.color = Color(t, t, t + 0.02, 0.92)
	body.position = pos + Vector2(-cw * 0.5, -ch)
	body.size = Vector2(cw, ch)
	body.z_index = -11
	add_child(body)
	var cab := ColorRect.new()
	cab.color = Color(t * 0.65, t * 0.65, t * 0.8, 0.92)
	cab.position = pos + Vector2(-cw * 0.26, -ch - ch * 0.48)
	cab.size = Vector2(cw * 0.52, ch * 0.5)
	cab.z_index = -11
	add_child(cab)

# 배수 펌프장/응축기 — 큰 가로 배관 + 밸브 휠 + 바닥 배수로 물 + 표지(응축기가 재사용).
func _ambience_pump_station(label: String = "배수 펌프 · B2") -> void:
	var w: float = STAGE_LENGTH
	var pipe_ys: Array = [-46.0, GROUND_Y - 210.0]
	for i in pipe_ys.size():
		var hy: float = pipe_ys[i]
		var pipe := ColorRect.new()
		pipe.color = Color(0.22, 0.30, 0.34, 0.85)
		pipe.position = Vector2(-200.0, hy)
		pipe.size = Vector2(w + 400.0, 22.0)
		pipe.z_index = -10
		add_child(pipe)
		var hl := ColorRect.new()
		hl.color = Color(0.45, 0.60, 0.68, 0.5)
		hl.position = Vector2(-200.0, hy + 3.0)
		hl.size = Vector2(w + 400.0, 3.0)
		hl.z_index = -9
		add_child(hl)
	var x: float = 320.0
	while x < w:
		var valve := ColorRect.new()
		valve.color = Color(0.60, 0.28, 0.24, 0.9)
		valve.position = Vector2(x - 9.0, GROUND_Y - 210.0 - 6.0)
		valve.size = Vector2(18.0, 18.0)
		valve.z_index = -8
		add_child(valve)
		x += 520.0
	var water := ColorRect.new()
	water.color = Color(0.20, 0.45, 0.50, 0.20)
	water.position = Vector2(-200.0, GROUND_Y - 24.0)
	water.size = Vector2(w + 400.0, 38.0)
	water.z_index = -3
	add_child(water)
	_add_lore_label(Vector2(360.0, -22.0), label, Color(0.45, 0.70, 0.90, 0.45), 15)

# 펌프장 전용 · 상부 파이프 실물화(2026-08-22 정체성 재작업 — "파이프 위 저격"이 배경
# 어휘로 존재해야 읽힌다). 거치대 발판(y340) 바로 밑에 대구경 파이프 밴드를 깔아
# "발판 = 파이프 위"가 되게 하고, 행거·엘보 드롭·밸브 휠로 배관망을 완성한다.
func _ambience_pump_pipes() -> void:
	_ambience_pump_station()
	# 존별 파이프 런(거치대 x 범위와 정렬 · MapData._pump_station 참고).
	for run0 in [[1380.0, 2420.0], [4030.0, 5070.0]]:
		var run: Array = run0
		var x1: float = float(run[0])
		var x2: float = float(run[1])
		# 대구경 파이프 본체 — 발판(top 340) 바로 아래 356~384.
		var pipe := ColorRect.new()
		pipe.color = Color(0.26, 0.34, 0.38, 0.95)
		pipe.position = Vector2(x1, 356.0)
		pipe.size = Vector2(x2 - x1, 28.0)
		pipe.z_index = -9
		add_child(pipe)
		var hl := ColorRect.new()
		hl.color = Color(0.48, 0.62, 0.70, 0.55)
		hl.position = Vector2(x1, 360.0)
		hl.size = Vector2(x2 - x1, 4.0)
		hl.z_index = -8
		add_child(hl)
		# 양 끝 엘보 — 지면까지 수직 드롭(배관이 어디서 와서 어디로 가는지).
		for ex in [x1, x2 - 26.0]:
			var drop := ColorRect.new()
			drop.color = Color(0.24, 0.31, 0.35, 0.9)
			drop.position = Vector2(float(ex), 356.0)
			drop.size = Vector2(26.0, GROUND_Y - 356.0)
			drop.z_index = -10
			add_child(drop)
		# 행거 로드 — 천장에서 파이프를 매단 얇은 로드(성기게).
		var hx: float = x1 + 140.0
		while hx < x2 - 60.0:
			var rod := ColorRect.new()
			rod.color = Color(0.18, 0.22, 0.25, 0.8)
			rod.position = Vector2(hx, -40.0)
			rod.size = Vector2(5.0, 396.0)
			rod.z_index = -11
			add_child(rod)
			hx += 320.0
		# 밸브 휠 2개 — 파이프 위 강조점.
		for vx in [x1 + 220.0, x2 - 260.0]:
			var valve := ColorRect.new()
			valve.color = Color(0.60, 0.28, 0.24, 0.9)
			valve.position = Vector2(float(vx), 348.0)
			valve.size = Vector2(16.0, 16.0)
			valve.z_index = -8
			add_child(valve)

# 응축기 방1 · 인입 매니폴드 — 펌프 베이스 + 낙수점 위 수직 드롭 파이프(낙수의 출처를
# 배경이 설명한다) + 플랜지.
func _ambience_condenser_inlet() -> void:
	_ambience_pump_station("응축 인입 · 매니폴드")
	for dx in [900.0, 1500.0, 2050.0]:
		var drop := ColorRect.new()
		drop.color = Color(0.24, 0.32, 0.36, 0.9)
		drop.position = Vector2(float(dx) - 11.0, -40.0)
		drop.size = Vector2(22.0, 190.0)
		drop.z_index = -9
		add_child(drop)
		var flange := ColorRect.new()
		flange.color = Color(0.40, 0.52, 0.58, 0.8)
		flange.position = Vector2(float(dx) - 16.0, 142.0)
		flange.size = Vector2(32.0, 8.0)
		flange.z_index = -8
		add_child(flange)

# 응축기 방3 · 집수조 — 펌프 베이스 + 진한 수면 밴드 + 배수 그레이팅 + 표면 김.
func _ambience_condenser_basin() -> void:
	_ambience_pump_station("집수조 · 배수 밸브")
	var w: float = STAGE_LENGTH
	# 수면 — 베이스의 옅은 물보다 진하게(여기가 물이 모이는 곳).
	var pool := ColorRect.new()
	pool.color = Color(0.18, 0.42, 0.48, 0.38)
	pool.position = Vector2(-200.0, GROUND_Y - 34.0)
	pool.size = Vector2(w + 400.0, 48.0)
	pool.z_index = -3
	add_child(pool)
	# 배수 그레이팅 — 바닥 가로 대시 열.
	var gx: float = 360.0
	while gx < w:
		var grate := ColorRect.new()
		grate.color = Color(0.10, 0.16, 0.18, 0.85)
		grate.position = Vector2(gx, GROUND_Y - 6.0)
		grate.size = Vector2(110.0, 5.0)
		grate.z_index = -2
		add_child(grate)
		gx += 520.0
	# 표면 김 — 얇은 밝은 안개 밴드(끓는 물의 온도를 색으로).
	var steam := ColorRect.new()
	steam.color = Color(0.80, 0.90, 0.92, 0.06)
	steam.position = Vector2(-200.0, GROUND_Y - 70.0)
	steam.size = Vector2(w + 400.0, 34.0)
	steam.z_index = -3
	add_child(steam)

# 함정 통로 방1 · 진입 회랑 — 베이스 + 진입 시브론(노랑-검정 사선 대비 밴드) + 통제 표지.
func _ambience_gauntlet_entry() -> void:
	_ambience_gauntlet()
	for hy in [GROUND_Y - 130.0, GROUND_Y - 118.0]:
		var band := ColorRect.new()
		band.color = Color(0.9, 0.75, 0.2, 0.22) if int(hy) % 2 == 0 else Color(0.08, 0.08, 0.08, 0.5)
		band.position = Vector2(160.0, hy)
		band.size = Vector2(300.0, 8.0)
		band.z_index = -8
		add_child(band)
	_add_lore_label(Vector2(320.0, GROUND_Y - 170.0), "사로 진입 · 통제 구역", Color(0.9, 0.6, 0.2, 0.5), 14)

# 함정 통로 방3 · 격자 사로 — 베이스 + 천장/바닥 포탑 장착 레일(수평 모티프) + 출력 표지.
func _ambience_gauntlet_grid() -> void:
	_ambience_gauntlet()
	var w: float = STAGE_LENGTH
	for entry in [[-24.0, 10.0], [GROUND_Y + 4.0, 8.0]]:
		var e: Array = entry
		var rail := ColorRect.new()
		rail.color = Color(0.16, 0.15, 0.13, 0.9)
		rail.position = Vector2(-200.0, float(e[0]))
		rail.size = Vector2(w + 400.0, float(e[1]))
		rail.z_index = -8
		add_child(rail)
		var glow := ColorRect.new()
		glow.color = Color(0.85, 0.30, 0.22, 0.25)
		glow.position = Vector2(-200.0, float(e[0]) + float(e[1]) - 2.0)
		glow.size = Vector2(w + 400.0, 2.0)
		glow.z_index = -7
		add_child(glow)
	_add_lore_label(Vector2(320.0, GROUND_Y - 170.0), "격자 사로 · 출력 제어", Color(0.9, 0.5, 0.25, 0.5), 14)

# 화물 리프트 방2 · 릴레이 홀 — 상부 갠트리 거더 + 호이스트 체인 + 매달린 컨테이너 실루엣.
func _ambience_freight_relay() -> void:
	var w: float = STAGE_LENGTH
	# 갠트리 거더 — 상부 수평 빔 2단.
	for entry in [[64.0, 18.0], [96.0, 8.0]]:
		var e: Array = entry
		var beam := ColorRect.new()
		beam.color = Color(0.22, 0.19, 0.14, 0.95)
		beam.position = Vector2(-200.0, float(e[0]))
		beam.size = Vector2(w + 400.0, float(e[1]))
		beam.z_index = -11
		add_child(beam)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 613 + 3
	# 호이스트 체인 + 매달린 컨테이너(운반 중 정지 실루엣) — 구덩이 위 상공을 채운다.
	var cx: float = 500.0
	while cx < w - 300.0:
		var chain := ColorRect.new()
		chain.color = Color(0.15, 0.14, 0.12, 0.85)
		var clen: float = rng.randf_range(60.0, 150.0)
		chain.position = Vector2(cx, 82.0)
		chain.size = Vector2(4.0, clen)
		chain.z_index = -11
		add_child(chain)
		var box := ColorRect.new()
		var bw: float = rng.randf_range(70.0, 120.0)
		box.color = Color(0.25, 0.20, 0.14, 0.9)
		box.position = Vector2(cx - bw * 0.5 + 2.0, 82.0 + clen)
		box.size = Vector2(bw, rng.randf_range(44.0, 64.0))
		box.z_index = -11
		add_child(box)
		cx += rng.randf_range(520.0, 780.0)
	_add_lore_label(Vector2(340.0, 150.0), "릴레이 홀 · 이송 중", Color(0.85, 0.75, 0.5, 0.5), 14)

# 화물 리프트 방3 · 출하 갠트리 — 릴레이 홀 어휘 + 경광등 + 상차 표지(절정 톤).
func _ambience_freight_gantry() -> void:
	_ambience_freight_relay()
	var w: float = STAGE_LENGTH
	var lx: float = 600.0
	while lx < w:
		var lamp := ColorRect.new()
		lamp.color = Color(0.95, 0.55, 0.20, 0.6)
		lamp.position = Vector2(lx, 48.0)
		lamp.size = Vector2(14.0, 10.0)
		lamp.z_index = -10
		add_child(lamp)
		var tw := lamp.create_tween()
		tw.set_loops()
		tw.tween_property(lamp, "modulate:a", 0.2, 0.8)
		tw.tween_property(lamp, "modulate:a", 1.0, 0.8)
		lx += 900.0
	_add_lore_label(Vector2(340.0, 190.0), "출하 갠트리 · 상차 구역", Color(0.95, 0.65, 0.35, 0.55), 14)

# 차량 엄폐 방2 · 야적 마당 — 야외: 뒷줄 차량 실루엣 + 펜스 와이어 + 조명 마스트.
func _ambience_carcover_yard() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 727 + 9
	# 뒷줄 야적 차량 — 멀리, 어둡게(전경 엄폐 차량과 톤 분리 · 발판 오독 방지).
	var cx: float = 300.0
	while cx < w:
		var cw: float = rng.randf_range(90.0, 130.0)
		var body := ColorRect.new()
		body.color = Color(0.10, 0.10, 0.12, 0.8)
		body.position = Vector2(cx, GROUND_Y - 96.0)
		body.size = Vector2(cw, 40.0)
		body.z_index = -12
		add_child(body)
		cx += cw + rng.randf_range(60.0, 160.0)
	# 펜스 — 수평 와이어 3줄(지주는 성기게 · 수직 스트라이프 습관 금지 준수).
	for wy in [GROUND_Y - 190.0, GROUND_Y - 168.0, GROUND_Y - 146.0]:
		var wire := ColorRect.new()
		wire.color = Color(0.30, 0.32, 0.36, 0.4)
		wire.position = Vector2(-200.0, float(wy))
		wire.size = Vector2(w + 400.0, 2.0)
		wire.z_index = -13
		add_child(wire)
	var px: float = 500.0
	while px < w:
		var post := ColorRect.new()
		post.color = Color(0.22, 0.24, 0.28, 0.6)
		post.position = Vector2(px, GROUND_Y - 196.0)
		post.size = Vector2(6.0, 196.0)
		post.z_index = -13
		add_child(post)
		px += 860.0
	# 조명 마스트 — 성긴 광원 + 빛 원뿔.
	var mx: float = 800.0
	while mx < w:
		_add_light_cone(mx, 40.0, 60.0, 260.0, GROUND_Y - 40.0, Color(0.95, 0.90, 0.70, 0.05), -11)
		mx += 1400.0
	_add_lore_label(Vector2(340.0, GROUND_Y - 230.0), "차량 야적장 · 검수 대기", Color(0.80, 0.85, 0.95, 0.45), 14)

# 변전소/통신 중계소 — 변압기 박스(방열핀) + 상단 케이블 + 애자 앰버 점 + 표지.
func _ambience_electrical(label: String) -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 307 + 11
	var x: float = 240.0
	while x < w:
		var tw2: float = rng.randf_range(70.0, 110.0)
		var th: float = rng.randf_range(120.0, 190.0)
		var box := ColorRect.new()
		box.color = Color(0.15, 0.14, 0.12)
		box.position = Vector2(x, GROUND_Y - th)
		box.size = Vector2(tw2, th)
		box.z_index = -12
		add_child(box)
		var fins: int = int(tw2 / 12.0)
		for i in fins:
			var f := ColorRect.new()
			f.color = Color(0.22, 0.20, 0.17, 0.7)
			f.position = Vector2(x + 5.0 + float(i) * 12.0, GROUND_Y - th + 8.0)
			f.size = Vector2(2.0, th - 16.0)
			f.z_index = -11
			add_child(f)
		var ins := ColorRect.new()
		ins.color = Color(0.95, 0.75, 0.35, 0.8)
		ins.position = Vector2(x + tw2 * 0.5 - 3.0, GROUND_Y - th - 8.0)
		ins.size = Vector2(6.0, 8.0)
		ins.z_index = -10
		add_child(ins)
		x += tw2 + rng.randf_range(170.0, 330.0)
	for i in 4:
		var cab := ColorRect.new()
		cab.color = Color(0.08, 0.08, 0.09, 0.8)
		cab.position = Vector2(-200.0, -62.0 - float(i) * 8.0)
		cab.size = Vector2(w + 400.0, 2.0)
		cab.z_index = -9
		add_child(cab)
	_add_lore_label(Vector2(360.0, -30.0), label, Color(0.95, 0.75, 0.35, 0.5), 15)

# 물류 창고/화물 구역 — 선반 랙(기둥+선반+상자) + 매달린 작업등 + 표지.
func _ambience_warehouse(label: String) -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 331 + 7
	var x: float = 200.0
	while x < w:
		var rh: float = rng.randf_range(200.0, 300.0)
		var rw: float = rng.randf_range(120.0, 180.0)
		for px in [x, x + rw]:
			var post := ColorRect.new()
			post.color = Color(0.20, 0.17, 0.13)
			post.position = Vector2(px, GROUND_Y - rh)
			post.size = Vector2(8.0, rh)
			post.z_index = -12
			add_child(post)
		for s in 3:
			var sy: float = GROUND_Y - rh + float(s + 1) * (rh / 4.0)
			var sh := ColorRect.new()
			sh.color = Color(0.24, 0.20, 0.15)
			sh.position = Vector2(x, sy)
			sh.size = Vector2(rw + 8.0, 6.0)
			sh.z_index = -11
			add_child(sh)
			# 선반은 대체로 차 있다 — 빈 선반에 상자 하나가 놓이면 그 상자가 주목받는다.
			# 채워진 랙은 창고의 질감이 되고, 개별 상자는 눈에서 사라진다(2026-08-19).
			var crates: int = 2 if rng.randf() < 0.55 else 1
			for ci in crates:
				if rng.randf() > 0.92:
					continue
				var bw: float = rng.randf_range(30.0, 58.0)
				var bh: float = rng.randf_range(24.0, 40.0)
				var crate := ColorRect.new()
				# 어둡게 가라앉힌 톤 — 밟을 수 있는 발판으로 오독되지 않게(사용자 2026-08-18).
				crate.color = Color(0.24, 0.19, 0.13, 0.7)
				var slot_w: float = (rw - 8.0) / float(crates)
				crate.position = Vector2(x + 4.0 + slot_w * float(ci) + rng.randf_range(0.0, maxf(slot_w - bw, 0.0)), sy - bh)
				crate.size = Vector2(bw, bh)
				crate.z_index = -10
				add_child(crate)
		x += rw + rng.randf_range(90.0, 190.0)
	var lx: float = 400.0
	while lx < w:
		var lamp := ColorRect.new()
		lamp.color = Color(0.95, 0.85, 0.55, 0.10)
		lamp.position = Vector2(lx - 50.0, -100.0)
		lamp.size = Vector2(100.0, 400.0)
		lamp.z_index = -8
		add_child(lamp)
		lx += 700.0
	_add_lore_label(Vector2(360.0, -30.0), label, Color(0.90, 0.70, 0.45, 0.5), 15)

# 하역 도크(창고 체인 방1) — 트럭 베이 셔터(가로 슬랫 · 수직 스트라이프 금지 규칙 준수) +
# 베이 번호 표지 + 바닥 안전선 + 낮은 팔레트 더미.
func _ambience_warehouse_dock() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 353 + GameState.current_segment * 17 + 5
	var bay_xs: Array = [420.0, 1080.0, 1740.0]
	for i in bay_xs.size():
		var bx: float = float(bay_xs[i]) + rng.randf_range(-40.0, 40.0)
		var sw: float = rng.randf_range(240.0, 300.0)
		var sh: float = rng.randf_range(240.0, 290.0)
		var door := ColorRect.new()
		door.color = Color(0.17, 0.15, 0.12)
		door.position = Vector2(bx, GROUND_Y - sh)
		door.size = Vector2(sw, sh)
		door.z_index = -12
		add_child(door)
		# 셔터 슬랫(가로줄)
		var slats: int = int(sh / 34.0)
		for s in slats:
			var slat := ColorRect.new()
			slat.color = Color(0.23, 0.20, 0.15)
			slat.position = Vector2(bx, GROUND_Y - sh + 8.0 + float(s) * 34.0)
			slat.size = Vector2(sw, 5.0)
			slat.z_index = -11
			add_child(slat)
		# 베이 번호 표지
		_add_lore_label(Vector2(bx + sw * 0.5 - 20.0, GROUND_Y - sh - 34.0),
			"BAY %d" % (i + 1), Color(0.90, 0.70, 0.45, 0.55), 13)
		# 바닥 안전선(셔터 앞)
		var line := ColorRect.new()
		line.color = Color(0.92, 0.78, 0.30, 0.28)
		line.position = Vector2(bx - 20.0, GROUND_Y - 8.0)
		line.size = Vector2(sw + 40.0, 5.0)
		line.z_index = -10
		add_child(line)
	# 팔레트 더미(낮음 · 배경 전용) — 출하 상자와 같은 기준으로 촘촘하게·어둡게(2026-08-19).
	# 단품이 띄엄띄엄 놓이면 "밟거나 부술 수 있는 것"으로 읽힌다.
	var px: float = 240.0
	while px < STAGE_LENGTH - 160.0:
		if rng.randf() < 0.8:
			var pw: float = rng.randf_range(70.0, 130.0)
			var pal := ColorRect.new()
			pal.color = Color(0.22, 0.18, 0.12, 0.85)
			pal.position = Vector2(px + rng.randf_range(-18.0, 18.0), GROUND_Y - 26.0)
			pal.size = Vector2(pw, 26.0)
			pal.z_index = -10
			add_child(pal)
			# 2단 적재 · 더미의 높이 변주(같은 높이 반복은 벽처럼 읽힌다).
			if rng.randf() < 0.45:
				var pal2 := ColorRect.new()
				pal2.color = Color(0.19, 0.16, 0.11, 0.85)
				pal2.position = Vector2(pal.position.x + rng.randf_range(6.0, 20.0), GROUND_Y - 50.0)
				pal2.size = Vector2(pw * 0.7, 24.0)
				pal2.z_index = -11
				add_child(pal2)
		px += rng.randf_range(140.0, 280.0)
	_add_lore_label(Vector2(360.0, -30.0), "하역 도크 · 반입 관리", Color(0.90, 0.70, 0.45, 0.5), 15)

# 출하 구역(창고 체인 방3) — 롤러 라인(수평 도트 열) + 출하 상자 스택 + 행선 표지.
func _ambience_warehouse_shipping() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 359 + GameState.current_segment * 19 + 11
	# 롤러 라인 — 벽면 하단을 따라 흐르는 수평 라인 + 롤러 도트
	var ry: float = GROUND_Y - 120.0
	var rail := ColorRect.new()
	rail.color = Color(0.22, 0.19, 0.14)
	rail.position = Vector2(200.0, ry)
	rail.size = Vector2(STAGE_LENGTH - 500.0, 6.0)
	rail.z_index = -12
	add_child(rail)
	var dx: float = 240.0
	while dx < STAGE_LENGTH - 340.0:
		var roller := ColorRect.new()
		roller.color = Color(0.30, 0.26, 0.19)
		roller.position = Vector2(dx, ry - 5.0)
		roller.size = Vector2(9.0, 5.0)
		roller.z_index = -11
		add_child(roller)
		dx += rng.randf_range(46.0, 70.0)
	# 출하 상자 · 배경 질감(2026-08-19 사용자 "박스가 배경보다 상호작용 물체처럼 느껴진다").
	# 원인 2가지를 함께 고친다. ⓐ 라벨 띠가 앰버(0.90,0.70,0.45) = DestructibleCover 트림과
	# 같은 계열이라 "부술 수 있는 것" 신호로 읽혔다 → 채도를 죽인 회갈색 띠로.
	# ⓑ 드문드문 놓인 단품은 오브젝트로, 빽빽하게 겹친 더미는 배경으로 읽힌다 — 사용자
	# 가설("더 늘려야 배경 느낌이 나려나") 채택: 간격 절반 이하 + 뒷줄 추가 + 서로 겹치게.
	var sx: float = 260.0
	while sx < STAGE_LENGTH - 200.0:
		# 뒷줄 · 더 어둡고 작게(공기 원근) · 앞줄과 어긋나게 놓아 한 덩어리로 보이게.
		if rng.randf() < 0.75:
			var back_h: int = rng.randi_range(1, 4)
			var back_w: float = rng.randf_range(44.0, 70.0)
			for bl in back_h:
				var bbox := ColorRect.new()
				bbox.color = Color(0.19, 0.16, 0.11, 0.85)
				bbox.position = Vector2(sx + rng.randf_range(-30.0, 30.0), GROUND_Y - 30.0 * float(bl + 1))
				bbox.size = Vector2(back_w, 28.0)
				bbox.z_index = -12
				add_child(bbox)
		if rng.randf() < 0.85:
			var stack_h: int = rng.randi_range(1, 3)
			var bw: float = rng.randf_range(56.0, 92.0)
			for lvl in stack_h:
				var box := ColorRect.new()
				box.color = Color(0.26, 0.21, 0.14, 0.88)
				box.position = Vector2(sx + rng.randf_range(-22.0, 22.0), GROUND_Y - 34.0 * float(lvl + 1))
				box.size = Vector2(bw, 32.0)
				box.z_index = -10
				add_child(box)
				var band := ColorRect.new()
				band.color = Color(0.38, 0.34, 0.28, 0.45)
				band.position = Vector2(box.position.x, box.position.y + 13.0)
				band.size = Vector2(bw, 4.0)
				band.z_index = -9
				add_child(band)
		sx += rng.randf_range(120.0, 240.0)
	_add_lore_label(Vector2(360.0, -30.0), "출하 구역 · 검수 대기", Color(0.90, 0.70, 0.45, 0.5), 15)

# 서버 복도 — 서버 랙 실루엣 + LED 점멸 + 표지.
# 서버 계열 공용 뒷벽 — 배경색보다 살짝 밝은 연속 벽 + 수직 이음새 + 허리 몰딩.
# 랙(z -12)보다 뒤(z -14) · 실내 배경(_build_indoor_backdrop, z -16)보다 앞.
func _add_server_back_wall() -> void:
	var wall := ColorRect.new()
	wall.color = Color(0.085, 0.10, 0.125)
	wall.position = Vector2(-200.0, -90.0)
	wall.size = Vector2(STAGE_LENGTH + 400.0, GROUND_Y + 90.0)
	wall.z_index = -14
	add_child(wall)
	var sx: float = -80.0
	while sx < STAGE_LENGTH + 200.0:
		var seam := ColorRect.new()
		seam.color = Color(0.05, 0.06, 0.08, 0.8)
		seam.position = Vector2(sx, -90.0)
		seam.size = Vector2(3.0, GROUND_Y + 90.0)
		seam.z_index = -14
		add_child(seam)
		sx += 260.0
	var molding := ColorRect.new()
	molding.color = Color(0.11, 0.13, 0.16)
	molding.position = Vector2(-200.0, GROUND_Y - 210.0)
	molding.size = Vector2(STAGE_LENGTH + 400.0, 8.0)
	molding.z_index = -14
	add_child(molding)

func _ambience_server_hall() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 409 + 3
	# 실내 뒷벽(2026-08-23 "배경이 왜 야경이냐") — 랙 실루엣 사이가 맨 배경색이면 어두운 하늘로
	# 읽혀 "밤 빌딩 스카이라인"이 된다. 랙 뒤에 연속 벽 + 패널 이음새를 깔아 실내로 고정.
	_add_server_back_wall()
	var x: float = 220.0
	while x < w:
		var rh: float = rng.randf_range(220.0, 320.0)
		var rw: float = rng.randf_range(70.0, 100.0)
		var rack := ColorRect.new()
		rack.color = Color(0.10, 0.13, 0.16)
		rack.position = Vector2(x, GROUND_Y - rh)
		rack.size = Vector2(rw, rh)
		rack.z_index = -12
		add_child(rack)
		var rows: int = int(rh / 24.0)
		for r in rows:
			if rng.randf() < 0.5:
				var led := ColorRect.new()
				led.color = Color(0.4, 0.9, 1.0, rng.randf_range(0.4, 0.9))
				led.position = Vector2(x + rng.randf_range(6.0, rw - 10.0), GROUND_Y - rh + 8.0 + float(r) * 24.0)
				led.size = Vector2(4.0, 3.0)
				led.z_index = -10
				add_child(led)
				var tw2 := led.create_tween()
				tw2.set_loops()
				tw2.tween_property(led, "modulate:a", 0.1, rng.randf_range(0.4, 1.2))
				tw2.tween_property(led, "modulate:a", 1.0, rng.randf_range(0.4, 1.2))
		x += rw + rng.randf_range(60.0, 140.0)
	_add_lore_label(Vector2(360.0, -30.0), "서버 랙 · 코어 접근", Color(0.4, 0.85, 1.0, 0.5), 15)

# 인입 개폐소(변전소 체인 방1) — 현수 인입 케이블(수평 드리움) + 애자 스택 + 위험 표지.
func _ambience_substation_switchyard() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 373 + GameState.current_segment * 11 + 3
	# 상단 인입 케이블 — 얕게 드리우는 세그먼트 라인 2줄(수평 모티프).
	for cy in [-40.0, 30.0]:
		var cx: float = -200.0
		while cx < STAGE_LENGTH + 200.0:
			var seg := ColorRect.new()
			seg.color = Color(0.55, 0.45, 0.30, 0.35)
			seg.position = Vector2(cx, cy + sin(cx * 0.004) * 14.0)
			seg.size = Vector2(90.0, 3.0)
			seg.z_index = -9
			add_child(seg)
			cx += 96.0
	# 애자 스택(가로줄 쌓임 원반) — 불규칙 간격 소수.
	var ax: float = 380.0
	while ax < STAGE_LENGTH - 240.0:
		var stack_h: int = rng.randi_range(4, 6)
		var base_y: float = rng.randf_range(-20.0, 60.0)
		for s in stack_h:
			var disc := ColorRect.new()
			disc.color = Color(0.62, 0.55, 0.42, 0.55)
			disc.position = Vector2(ax - 12.0, base_y + float(s) * 12.0)
			disc.size = Vector2(24.0, 6.0)
			disc.z_index = -9
			add_child(disc)
		ax += rng.randf_range(520.0, 900.0)
	# 바닥 위험 표지 밴드(앰버) — 아크 구간 예감.
	var band := ColorRect.new()
	band.color = Color(0.92, 0.72, 0.25, 0.10)
	band.position = Vector2(-200.0, GROUND_Y - 26.0)
	band.size = Vector2(STAGE_LENGTH + 400.0, 26.0)
	band.z_index = -8
	add_child(band)
	_add_lore_label(Vector2(360.0, -30.0), "인입 개폐소 · 활선 주의", Color(0.95, 0.78, 0.35, 0.5), 15)

# 배전 제어실(변전소 체인 방3) — 배전반 캐비닛 열 + 표시등 점멸 + 케이블 트레이.
func _ambience_substation_control() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 379 + GameState.current_segment * 11 + 7
	var x: float = 300.0
	while x < STAGE_LENGTH - 200.0:
		var cw: float = rng.randf_range(90.0, 140.0)
		var ch: float = rng.randf_range(200.0, 280.0)
		var cab := ColorRect.new()
		cab.color = Color(0.15, 0.14, 0.12)
		cab.position = Vector2(x, GROUND_Y - ch)
		cab.size = Vector2(cw, ch)
		cab.z_index = -12
		add_child(cab)
		for r in 3:
			if rng.randf() < 0.7:
				var led := ColorRect.new()
				var warm: bool = rng.randf() < 0.5
				led.color = Color(0.95, 0.62, 0.2, 0.9) if warm else Color(0.4, 0.9, 0.5, 0.9)
				led.position = Vector2(x + rng.randf_range(8.0, cw - 12.0), GROUND_Y - ch + 16.0 + float(r) * 26.0)
				led.size = Vector2(5.0, 5.0)
				led.z_index = -11
				add_child(led)
				var tw := led.create_tween()
				tw.set_loops()
				tw.tween_property(led, "modulate:a", 0.25, rng.randf_range(0.6, 1.4))
				tw.tween_property(led, "modulate:a", 1.0, rng.randf_range(0.6, 1.4))
		x += cw + rng.randf_range(80.0, 220.0)
	# 케이블 트레이(수평) — 캐비닛 상부를 잇는다.
	var tray := ColorRect.new()
	tray.color = Color(0.30, 0.27, 0.22, 0.5)
	tray.position = Vector2(-200.0, 10.0)
	tray.size = Vector2(STAGE_LENGTH + 400.0, 10.0)
	tray.z_index = -9
	add_child(tray)
	_add_lore_label(Vector2(360.0, -30.0), "배전 제어실 · 차단기", Color(0.95, 0.78, 0.35, 0.5), 15)

# 안테나 마당(중계소 체인 방1, 옥외) — 격자 철탑 실루엣 + 접시 안테나 + 처진 가공 케이블.
# 수직 스트라이프 습관 금지: 철탑은 3기 비등간격 + 사선 브레이스가 실루엣의 본체.
func _ambience_relay_yard() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 389 + GameState.current_segment * 11 + 3
	var tower_xs: Array = [520.0, 1720.0, 2680.0]
	var prev_top: Vector2 = Vector2.ZERO
	for ti in tower_xs.size():
		var tx: float = float(tower_xs[ti])
		var th: float = rng.randf_range(340.0, 430.0)
		var half: float = 34.0
		# 다리 2주 + 사선 크로스 브레이스 4단(격자 철탑 실루엣).
		for sx in [-1.0, 1.0]:
			var leg := ColorRect.new()
			leg.color = Color(0.16, 0.17, 0.20)
			leg.position = Vector2(tx + sx * half - 3.0, GROUND_Y - th)
			leg.size = Vector2(6.0, th)
			leg.z_index = -13
			add_child(leg)
		for b in 4:
			var by: float = GROUND_Y - th + float(b) * th * 0.25
			var brace := Line2D.new()
			brace.width = 3.0
			brace.default_color = Color(0.20, 0.21, 0.25, 0.9)
			brace.add_point(Vector2(tx - half, by))
			brace.add_point(Vector2(tx + half, by + th * 0.25))
			brace.z_index = -13
			add_child(brace)
			var brace2 := Line2D.new()
			brace2.width = 3.0
			brace2.default_color = Color(0.20, 0.21, 0.25, 0.9)
			brace2.add_point(Vector2(tx + half, by))
			brace2.add_point(Vector2(tx - half, by + th * 0.25))
			brace2.z_index = -13
			add_child(brace2)
		# 접시 안테나(사각 추상) + 지지 암 · 상단 항공 장애등(정적 적색 — 점멸 금지).
		var dish := ColorRect.new()
		dish.color = Color(0.28, 0.30, 0.36)
		dish.position = Vector2(tx + 18.0, GROUND_Y - th + 26.0)
		dish.size = Vector2(34.0, 22.0)
		dish.z_index = -12
		add_child(dish)
		var lamp := ColorRect.new()
		lamp.color = Color(0.85, 0.25, 0.22, 0.85)
		lamp.position = Vector2(tx - 3.0, GROUND_Y - th - 8.0)
		lamp.size = Vector2(6.0, 6.0)
		lamp.z_index = -12
		add_child(lamp)
		# 처진 가공 케이블(카테너리 근사) — 직전 탑 상단과 잇는다. 수평 모티프.
		var top: Vector2 = Vector2(tx, GROUND_Y - th + 12.0)
		if ti > 0:
			var cable := Line2D.new()
			cable.width = 2.0
			cable.default_color = Color(0.32, 0.34, 0.40, 0.6)
			var sag: float = 46.0
			for k in 9:
				var t: float = float(k) / 8.0
				var px: float = lerpf(prev_top.x, top.x, t)
				var py: float = lerpf(prev_top.y, top.y, t) + sag * 4.0 * t * (1.0 - t)
				cable.add_point(Vector2(px, py))
			cable.z_index = -13
			add_child(cable)
		prev_top = top
	# 지면 장비 셸터(낮은 상자) 몇 동 — 마당의 발치 질감.
	var sx2: float = 260.0
	while sx2 < STAGE_LENGTH - 220.0:
		if rng.randf() < 0.55:
			var shed := ColorRect.new()
			shed.color = Color(0.14, 0.15, 0.17)
			shed.position = Vector2(sx2, GROUND_Y - rng.randf_range(46.0, 70.0))
			shed.size = Vector2(rng.randf_range(90.0, 150.0), 70.0)
			shed.z_index = -12
			add_child(shed)
		sx2 += rng.randf_range(360.0, 640.0)
	_add_lore_label(Vector2(340.0, -30.0), "중계 설비 · 출력 점검 중", Color(0.62, 0.72, 0.85, 0.5), 15)

# 중계 홀(중계소 체인 방2, 실내) — 장비 랙 열 + 파형 모니터(지그재그) + 케이블 트레이.
func _ambience_relay_hall() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 397 + GameState.current_segment * 11 + 5
	var x: float = 280.0
	while x < STAGE_LENGTH - 240.0:
		var rw: float = rng.randf_range(80.0, 120.0)
		var rh: float = rng.randf_range(220.0, 300.0)
		var rack := ColorRect.new()
		rack.color = Color(0.13, 0.14, 0.17)
		rack.position = Vector2(x, GROUND_Y - rh)
		rack.size = Vector2(rw, rh)
		rack.z_index = -12
		add_child(rack)
		# 파형 모니터(랙 상단) — 짧은 지그재그 선. 60%만 켜져 있다.
		if rng.randf() < 0.6:
			var wave := Line2D.new()
			wave.width = 2.0
			wave.default_color = Color(0.35, 0.85, 0.65, 0.8)
			var wy: float = GROUND_Y - rh + 28.0
			for k in 7:
				wave.add_point(Vector2(x + 10.0 + float(k) * (rw - 20.0) / 6.0,
					wy + (6.0 if k % 2 == 0 else -6.0) * rng.randf_range(0.5, 1.0)))
			wave.z_index = -11
			add_child(wave)
		# 상태 LED 열(정적 — 점멸은 트윈 저속만).
		for r in 2:
			if rng.randf() < 0.6:
				var led := ColorRect.new()
				led.color = Color(0.42, 0.80, 0.95, 0.85)
				led.position = Vector2(x + rng.randf_range(10.0, rw - 14.0), GROUND_Y - rh + 60.0 + float(r) * 30.0)
				led.size = Vector2(5.0, 5.0)
				led.z_index = -11
				add_child(led)
		x += rw + rng.randf_range(100.0, 260.0)
	# 케이블 트레이 2단(수평 모티프).
	for ty in [16.0, 40.0]:
		var tray := ColorRect.new()
		tray.color = Color(0.28, 0.26, 0.22, 0.45)
		tray.position = Vector2(-200.0, ty)
		tray.size = Vector2(STAGE_LENGTH + 400.0, 8.0)
		tray.z_index = -9
		add_child(tray)
	_add_lore_label(Vector2(360.0, -30.0), "중계 홀 · 회선 점검", Color(0.62, 0.72, 0.85, 0.5), 15)

# 송신탑 기단(중계소 체인 방3) — 좌우 비대칭 거대 탑 다리 + 상방 케이블 + 앵커 블록.
func _ambience_relay_mast() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 401 + GameState.current_segment * 11 + 9
	# 탑 다리 2주 — 좌우 비대칭(수직 등간격 습관 금지). 위로 갈수록 안쪽으로 기운다.
	for cfg0 in [{"x": 700.0, "w": 46.0, "lean": 26.0}, {"x": 2150.0, "w": 60.0, "lean": -34.0}]:
		var cfg: Dictionary = cfg0
		var bx: float = float(cfg["x"])
		var bw: float = float(cfg["w"])
		var lean: float = float(cfg["lean"])
		var leg := Polygon2D.new()
		leg.color = Color(0.15, 0.16, 0.19)
		leg.polygon = PackedVector2Array([
			Vector2(bx - bw * 0.5, GROUND_Y),
			Vector2(bx + bw * 0.5, GROUND_Y),
			Vector2(bx + bw * 0.30 + lean, -120.0),
			Vector2(bx - bw * 0.30 + lean, -120.0),
		])
		leg.z_index = -13
		add_child(leg)
		# 수평 브레이스 3단 — 다리의 가로 리듬.
		for b in 3:
			var by: float = GROUND_Y - 140.0 - float(b) * 170.0
			var brace := ColorRect.new()
			brace.color = Color(0.21, 0.22, 0.26, 0.9)
			brace.position = Vector2(bx - bw * 0.7 + lean * float(b) / 3.0, by)
			brace.size = Vector2(bw * 1.4, 8.0)
			brace.z_index = -13
			add_child(brace)
		# 앵커 블록(발치).
		var anchor := ColorRect.new()
		anchor.color = Color(0.19, 0.19, 0.21)
		anchor.position = Vector2(bx - bw * 0.9, GROUND_Y - 34.0)
		anchor.size = Vector2(bw * 1.8, 34.0)
		anchor.z_index = -12
		add_child(anchor)
	# 상방 지지 케이블(사선) — 탑에서 화면 위로 뻗는다.
	for k in 4:
		var cable := Line2D.new()
		cable.width = 2.0
		cable.default_color = Color(0.30, 0.32, 0.38, 0.5)
		var ax: float = 700.0 if k % 2 == 0 else 2150.0
		cable.add_point(Vector2(ax + rng.randf_range(-30.0, 30.0), GROUND_Y - 200.0 - float(k) * 90.0))
		cable.add_point(Vector2(ax + rng.randf_range(500.0, 900.0) * (1.0 if k % 2 == 0 else -1.0), -160.0))
		cable.z_index = -14
		add_child(cable)
	_add_lore_label(Vector2(340.0, -30.0), "송신탑 기단 · 출입 통제", Color(0.62, 0.72, 0.85, 0.5), 15)

# 모니터 전실(통제 회랑 체인 방1) — 소형 모니터 뱅크(대부분 꺼짐 · 한둘만 푸르게).
func _ambience_control_anteroom() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 383 + GameState.current_segment * 11 + 5
	var x: float = 340.0
	while x < STAGE_LENGTH - 240.0:
		var cols: int = rng.randi_range(2, 3)
		var rows: int = rng.randi_range(2, 3)
		var by: float = GROUND_Y - rng.randf_range(220.0, 300.0)
		for c in cols:
			for r in rows:
				var mon := ColorRect.new()
				var lit: bool = rng.randf() < 0.18
				mon.color = Color(0.30, 0.55, 0.75, 0.5) if lit else Color(0.10, 0.12, 0.15)
				mon.position = Vector2(x + float(c) * 44.0, by + float(r) * 32.0)
				mon.size = Vector2(38.0, 26.0)
				mon.z_index = -11
				add_child(mon)
		x += float(cols) * 44.0 + rng.randf_range(240.0, 520.0)
	_add_lore_label(Vector2(360.0, -30.0), "모니터 전실 · 무인 감시", Color(0.55, 0.75, 0.95, 0.5), 15)

# 검증 게이트(통제 회랑 체인 방3) — ㄷ자 검증 아치 + 바닥 검증선(청색).
func _ambience_control_checkgate() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 389 + GameState.current_segment * 11 + 9
	for gx in [900.0, 2100.0]:
		var gw: float = 180.0
		var gh: float = 300.0
		for side in [0.0, gw - 16.0]:
			var post := ColorRect.new()
			post.color = Color(0.16, 0.18, 0.22)
			post.position = Vector2(gx + side, GROUND_Y - gh)
			post.size = Vector2(16.0, gh)
			post.z_index = -12
			add_child(post)
		var beam := ColorRect.new()
		beam.color = Color(0.16, 0.18, 0.22)
		beam.position = Vector2(gx, GROUND_Y - gh - 14.0)
		beam.size = Vector2(gw, 14.0)
		beam.z_index = -12
		add_child(beam)
		# 아치 하단 검증선 — 옅은 청색 스캔 밴드.
		var line := ColorRect.new()
		line.color = Color(0.45, 0.75, 1.0, 0.16)
		line.position = Vector2(gx + 16.0, GROUND_Y - 60.0)
		line.size = Vector2(gw - 32.0, 60.0)
		line.z_index = -10
		add_child(line)
	# 바닥 유도선(수평 청색 밴드).
	var guide := ColorRect.new()
	guide.color = Color(0.45, 0.75, 1.0, 0.10)
	guide.position = Vector2(-200.0, GROUND_Y - 14.0)
	guide.size = Vector2(STAGE_LENGTH + 400.0, 8.0)
	guide.z_index = -9
	add_child(guide)
	_add_lore_label(Vector2(360.0, -30.0), "검증 게이트 · 통행 대조", Color(0.55, 0.75, 0.95, 0.5), 15)

# 랙 열람실(서버 홀 체인 방1) — 낮은 랙 + 열람 콘솔 데스크(서버 홀보다 밝고 성김).
func _ambience_server_stacks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 397 + GameState.current_segment * 11 + 3
	_add_server_back_wall()   # 야경 오독 차단 — server_hall과 동형(2026-08-23)
	var x: float = 300.0
	while x < STAGE_LENGTH - 200.0:
		var rh: float = rng.randf_range(120.0, 180.0)
		var rw: float = rng.randf_range(70.0, 100.0)
		var rack := ColorRect.new()
		rack.color = Color(0.11, 0.14, 0.17)
		rack.position = Vector2(x, GROUND_Y - rh)
		rack.size = Vector2(rw, rh)
		rack.z_index = -12
		add_child(rack)
		if rng.randf() < 0.6:
			var led := ColorRect.new()
			led.color = Color(0.4, 0.9, 1.0, 0.7)
			led.position = Vector2(x + rng.randf_range(6.0, rw - 10.0), GROUND_Y - rh + 10.0)
			led.size = Vector2(4.0, 3.0)
			led.z_index = -10
			add_child(led)
		# 사이사이 열람 콘솔 데스크.
		if rng.randf() < 0.4:
			var desk := ColorRect.new()
			desk.color = Color(0.20, 0.22, 0.26, 0.8)
			desk.position = Vector2(x + rw + 30.0, GROUND_Y - 44.0)
			desk.size = Vector2(70.0, 44.0)
			desk.z_index = -11
			add_child(desk)
		x += rw + rng.randf_range(140.0, 320.0)
	_add_lore_label(Vector2(360.0, -30.0), "랙 열람실 · 접근 기록", Color(0.4, 0.85, 1.0, 0.5), 15)

# 코어 스위치룸(서버 홀 체인 방3) — 대형 스위치 캐비닛 + 케이블 다발 + 붉은 비상등 워시.
func _ambience_server_switchroom() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 401 + GameState.current_segment * 11 + 7
	_add_server_back_wall()   # 야경 오독 차단 — server_hall과 동형(2026-08-23)
	var x: float = 360.0
	while x < STAGE_LENGTH - 260.0:
		var cw: float = rng.randf_range(130.0, 190.0)
		var ch: float = rng.randf_range(260.0, 340.0)
		var cab := ColorRect.new()
		cab.color = Color(0.10, 0.11, 0.14)
		cab.position = Vector2(x, GROUND_Y - ch)
		cab.size = Vector2(cw, ch)
		cab.z_index = -12
		add_child(cab)
		# 케이블 다발 — 캐비닛에서 바닥으로 흐르는 대각 라인 2~3.
		for c in rng.randi_range(2, 3):
			var cable := ColorRect.new()
			cable.color = Color(0.24, 0.22, 0.20, 0.6)
			cable.position = Vector2(x + cw - 8.0 + float(c) * 7.0, GROUND_Y - 90.0 - float(c) * 24.0)
			cable.size = Vector2(4.0, 90.0 + float(c) * 24.0)
			cable.rotation = 0.12 + float(c) * 0.05
			cable.z_index = -11
			add_child(cable)
		x += cw + rng.randf_range(180.0, 380.0)
	# (붉은 전면 워시는 폐지 — 재밍 어둠과 겹치면 화면 전체가 진빨강으로 오염, 2026-08-19 실측.
	#  비상 톤은 라벨·케이블 어휘로 충분.)
	_add_lore_label(Vector2(360.0, -30.0), "코어 스위치룸 · 무전 차폐", Color(0.95, 0.5, 0.45, 0.5), 15)

# 통제실 복도 — 벽면 모니터 뱅크(점멸) + 표지.
func _ambience_control_room() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 433 + 9
	var x: float = 260.0
	while x < w:
		for r in 2:
			for c in 2:
				var sc := ColorRect.new()
				sc.color = Color(0.20, 0.35, 0.45, 0.55)
				sc.position = Vector2(x + float(c) * 54.0, -80.0 + float(r) * 44.0)
				sc.size = Vector2(48.0, 38.0)
				sc.z_index = -10
				add_child(sc)
				var tw2 := sc.create_tween()
				tw2.set_loops()
				tw2.tween_property(sc, "modulate:a", rng.randf_range(0.4, 0.7), rng.randf_range(1.0, 2.5))
				tw2.tween_property(sc, "modulate:a", 1.0, rng.randf_range(1.0, 2.5))
		x += rng.randf_range(360.0, 560.0)
	_add_lore_label(Vector2(360.0, -30.0), "통제실 · 감시망", Color(0.4, 0.7, 0.9, 0.5), 15)

# 보안 검문소 — 스캐너 아치(ㄷ자 프레임) + 상하 스캔 라인 + 표지.
func _ambience_checkpoint() -> void:
	var w: float = STAGE_LENGTH
	var frame_col := Color(0.55, 0.60, 0.68, 0.6)
	var x: float = 500.0
	while x < w:
		var top := ColorRect.new()
		top.color = frame_col
		top.position = Vector2(x - 40.0, -40.0)
		top.size = Vector2(80.0, 8.0)
		top.z_index = -9
		add_child(top)
		for side in [-40.0, 32.0]:
			var post := ColorRect.new()
			post.color = frame_col
			post.position = Vector2(x + side, -40.0)
			post.size = Vector2(8.0, GROUND_Y - 40.0)
			post.z_index = -9
			add_child(post)
		var scan := ColorRect.new()
		scan.color = Color(0.9, 0.3, 0.3, 0.28)
		scan.position = Vector2(x - 36.0, -36.0)
		scan.size = Vector2(72.0, 3.0)
		scan.z_index = -8
		add_child(scan)
		var tw2 := scan.create_tween()
		tw2.set_loops()
		tw2.tween_property(scan, "position:y", GROUND_Y - 60.0, 2.2)
		tw2.tween_property(scan, "position:y", -36.0, 0.0)
		x += 800.0
	_add_lore_label(Vector2(360.0, -30.0), "보안 검문 · 신원 확인", Color(0.7, 0.75, 0.85, 0.5), 15)

# 철거 구역 — 잔해 더미 + 주의 테이프 + 먼지 안개 + 표지.
func _ambience_demolition() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 457 + 13
	var x: float = 200.0
	while x < w:
		var rw: float = rng.randf_range(80.0, 160.0)
		var rh: float = rng.randf_range(40.0, 110.0)
		var pile := Polygon2D.new()
		pile.color = Color(0.16, 0.15, 0.14)
		pile.polygon = PackedVector2Array([
			Vector2(x, GROUND_Y), Vector2(x + rw * 0.3, GROUND_Y - rh),
			Vector2(x + rw * 0.7, GROUND_Y - rh * 0.7), Vector2(x + rw, GROUND_Y)])
		pile.z_index = -11
		add_child(pile)
		x += rw + rng.randf_range(120.0, 280.0)
	var tape := ColorRect.new()
	tape.color = Color(0.9, 0.75, 0.2, 0.35)
	tape.position = Vector2(-200.0, -50.0)
	tape.size = Vector2(w + 400.0, 6.0)
	tape.z_index = -7
	add_child(tape)
	var dust := ColorRect.new()
	dust.color = Color(0.4, 0.38, 0.34, 0.06)
	dust.position = Vector2(-200.0, GROUND_Y - 120.0)
	dust.size = Vector2(w + 400.0, 140.0)
	dust.z_index = -6
	add_child(dust)
	_add_lore_label(Vector2(360.0, -30.0), "철거 구역 · 접근 주의", Color(0.9, 0.75, 0.3, 0.5), 15)

# 파쇄 마당(철거 체인 방2, 2026-08-20) — 시그니처: 대각 크레인 붐 + 매달린 철구 + 반쯤 헐린
# 건물 단면(수평 슬래브 층). 중앙 캐노피(처마)가 낙하 없는 휴지 구간(1240~1480)의 "이유"를
# 그려 준다. 수직 스트라이프 어휘 금지(known_issues) — 크레인은 단일 대각 랜드마크, 건물 단면은
# 수평 슬래브 층으로.
func _ambience_demo_yard() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 457 + GameState.current_segment * 11 + 29
	# 잔해 더미 — 방1보다 크고 성기게(마당의 스케일).
	var x: float = 240.0
	while x < w:
		var rw: float = rng.randf_range(120.0, 240.0)
		var rh: float = rng.randf_range(60.0, 140.0)
		var pile := Polygon2D.new()
		pile.color = Color(0.17, 0.16, 0.14)
		pile.polygon = PackedVector2Array([
			Vector2(x, GROUND_Y), Vector2(x + rw * 0.25, GROUND_Y - rh),
			Vector2(x + rw * 0.6, GROUND_Y - rh * 0.55), Vector2(x + rw, GROUND_Y)])
		pile.z_index = -11
		add_child(pile)
		x += rw + rng.randf_range(220.0, 420.0)
	# 반쯤 헐린 건물 단면(우측 배경) — 수평 슬래브 3층 + 층 사이 어둠 + 늘어진 철근 곡선.
	var bx: float = w - 900.0
	for i in 3:
		var sy: float = GROUND_Y - 120.0 - float(i) * 110.0
		var slab := ColorRect.new()
		slab.color = Color(0.20, 0.19, 0.17)
		slab.position = Vector2(bx, sy)
		slab.size = Vector2(720.0, 16.0)
		slab.z_index = -10
		add_child(slab)
		var dark := ColorRect.new()
		dark.color = Color(0.10, 0.10, 0.09, 0.85)
		dark.position = Vector2(bx + 30.0, sy - 92.0)
		dark.size = Vector2(660.0, 92.0)
		dark.z_index = -11
		add_child(dark)
		var rebar := Line2D.new()
		rebar.default_color = Color(0.30, 0.24, 0.18, 0.7)
		rebar.width = 2.0
		var rx: float = bx + 90.0 + float(i) * 210.0
		rebar.points = PackedVector2Array([
			Vector2(rx, sy + 14.0), Vector2(rx + 12.0, sy + 46.0), Vector2(rx + 4.0, sy + 78.0)])
		rebar.z_index = -9
		add_child(rebar)
	# 크레인 — 좌측 대각 붐 + 수평 지브 + 케이블에 매달린 철구(단일 랜드마크).
	var boom := Line2D.new()
	boom.default_color = Color(0.34, 0.30, 0.20)
	boom.width = 10.0
	boom.points = PackedVector2Array([Vector2(180.0, GROUND_Y - 20.0), Vector2(620.0, -170.0)])
	boom.z_index = -10
	add_child(boom)
	var jib := Line2D.new()
	jib.default_color = Color(0.34, 0.30, 0.20)
	jib.width = 7.0
	jib.points = PackedVector2Array([Vector2(620.0, -170.0), Vector2(1240.0, -140.0)])
	jib.z_index = -10
	add_child(jib)
	var cable := Line2D.new()
	cable.default_color = Color(0.22, 0.21, 0.19)
	cable.width = 2.0
	cable.points = PackedVector2Array([Vector2(1120.0, -142.0), Vector2(1120.0, 96.0)])
	cable.z_index = -10
	add_child(cable)
	var ball := Polygon2D.new()
	ball.color = Color(0.24, 0.23, 0.21)
	var ball_pts := PackedVector2Array()
	for i in 12:
		var ang: float = TAU * float(i) / 12.0
		ball_pts.append(Vector2(1120.0 + cos(ang) * 34.0, 130.0 + sin(ang) * 34.0))
	ball.polygon = ball_pts
	ball.z_index = -10
	add_child(ball)
	# 캐노피(처마) — 휴지 구간(1240~1480) 위 골함석 지붕 + 지지 스트럿. "여긴 안 떨어진다"의 그림.
	var canopy := Polygon2D.new()
	canopy.color = Color(0.26, 0.25, 0.22)
	canopy.polygon = PackedVector2Array([
		Vector2(1220.0, 386.0), Vector2(1500.0, 372.0), Vector2(1504.0, 388.0), Vector2(1224.0, 402.0)])
	canopy.z_index = -8
	add_child(canopy)
	for sx in [1260.0, 1460.0]:
		var strut := Line2D.new()
		strut.default_color = Color(0.22, 0.21, 0.19)
		strut.width = 4.0
		strut.points = PackedVector2Array([Vector2(float(sx), 396.0), Vector2(float(sx) + 14.0, GROUND_Y)])
		strut.z_index = -9
		add_child(strut)
	# 경고 테이프 + 먼지 밴드(방1과 같은 톤 — 같은 구역의 연속성).
	var tape := ColorRect.new()
	tape.color = Color(0.9, 0.75, 0.2, 0.35)
	tape.position = Vector2(-200.0, -50.0)
	tape.size = Vector2(w + 400.0, 6.0)
	tape.z_index = -7
	add_child(tape)
	var dust2 := ColorRect.new()
	dust2.color = Color(0.42, 0.39, 0.34, 0.08)
	dust2.position = Vector2(-200.0, GROUND_Y - 140.0)
	dust2.size = Vector2(w + 400.0, 160.0)
	dust2.z_index = -6
	add_child(dust2)
	_add_lore_label(Vector2(340.0, -30.0), "파쇄 마당 · 중장비 작동 중", Color(0.9, 0.75, 0.3, 0.5), 15)

# 실험 구역 — 격자 라인 + 관측 유리 패널 + 표지.
func _ambience_testing() -> void:
	var w: float = STAGE_LENGTH
	var x: float = 160.0
	while x < w:
		var g := ColorRect.new()
		g.color = Color(0.4, 0.7, 0.75, 0.06)
		g.position = Vector2(x, -200.0)
		g.size = Vector2(1.0, 800.0)
		g.z_index = -11
		add_child(g)
		x += 100.0
	var px: float = 400.0
	while px < w:
		var glass := ColorRect.new()
		glass.color = Color(0.35, 0.55, 0.60, 0.10)
		glass.position = Vector2(px, -80.0)
		glass.size = Vector2(220.0, GROUND_Y - 40.0)
		glass.z_index = -9
		add_child(glass)
		var frame := ColorRect.new()
		frame.color = Color(0.5, 0.7, 0.75, 0.4)
		frame.position = Vector2(px, -80.0)
		frame.size = Vector2(220.0, 4.0)
		frame.z_index = -8
		add_child(frame)
		px += 620.0
	_add_lore_label(Vector2(360.0, -30.0), "실험 구역 · 관측", Color(0.5, 0.8, 0.85, 0.5), 15)

# 함정 통로 — 상하 위험 스트라이프 + 붉은 경고등(점멸) + 표지.
func _ambience_gauntlet() -> void:
	var w: float = STAGE_LENGTH
	for hy in [-40.0, GROUND_Y - 6.0]:
		var stripe := ColorRect.new()
		stripe.color = Color(0.9, 0.7, 0.15, 0.18)
		stripe.position = Vector2(-200.0, hy)
		stripe.size = Vector2(w + 400.0, 6.0)
		stripe.z_index = -7
		add_child(stripe)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 479 + 5
	var x: float = 350.0
	while x < w:
		var light := ColorRect.new()
		light.color = Color(0.9, 0.25, 0.2, 0.5)
		light.position = Vector2(x - 6.0, -60.0)
		light.size = Vector2(12.0, 10.0)
		light.z_index = -8
		add_child(light)
		var tw2 := light.create_tween()
		tw2.set_loops()
		tw2.tween_property(light, "modulate:a", 0.15, 0.6)
		tw2.tween_property(light, "modulate:a", 1.0, 0.6)
		x += rng.randf_range(400.0, 600.0)
	_add_lore_label(Vector2(360.0, -30.0), "함정 통로 · 경고", Color(0.9, 0.6, 0.2, 0.5), 15)

# 붕괴 갱도(강제 전진) — 균열 벽 + 지지 빔 + 낙하 잔해 + 먼지 + 붉은 비상등.
func _ambience_collapse() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 521 + 7
	var x: float = 200.0
	while x < w:
		var crack := Line2D.new()
		crack.width = 2.0
		crack.default_color = Color(0.05, 0.05, 0.06, 0.7)
		var pts := PackedVector2Array()
		var cx: float = x
		var yy: float = rng.randf_range(-180.0, GROUND_Y - 120.0)
		for i in 5:
			pts.append(Vector2(cx, yy))
			cx += rng.randf_range(20.0, 50.0)
			yy += rng.randf_range(-40.0, 60.0)
		crack.points = pts
		crack.z_index = -13
		add_child(crack)
		x += rng.randf_range(280.0, 480.0)
	var bx: float = 260.0
	while bx < w:
		var beam := ColorRect.new()
		beam.color = Color(0.16, 0.15, 0.14)
		beam.position = Vector2(bx, -100.0)
		beam.size = Vector2(14.0, GROUND_Y + 100.0)
		beam.z_index = -12
		add_child(beam)
		bx += rng.randf_range(340.0, 560.0)
	for i in 10:
		var deb := ColorRect.new()
		deb.color = Color(0.20, 0.18, 0.16, 0.8)
		deb.position = Vector2(rng.randf_range(0.0, w), rng.randf_range(-200.0, 0.0))
		var ds: float = rng.randf_range(3.0, 7.0)
		deb.size = Vector2(ds, ds)
		deb.z_index = -5
		add_child(deb)
		var td := deb.create_tween()
		td.set_loops()
		td.tween_property(deb, "position:y", GROUND_Y, rng.randf_range(1.4, 3.0))
		td.tween_property(deb, "position:y", rng.randf_range(-200.0, -60.0), 0.0)
	var dust := ColorRect.new()
	dust.color = Color(0.30, 0.26, 0.22, 0.07)
	dust.position = Vector2(-200.0, -100.0)
	dust.size = Vector2(w + 400.0, 260.0)
	dust.z_index = -6
	add_child(dust)
	var lx: float = 450.0
	while lx < w:
		var light := ColorRect.new()
		light.color = Color(0.9, 0.25, 0.2, 0.35)
		light.position = Vector2(lx - 40.0, -100.0)
		light.size = Vector2(80.0, 700.0)
		light.z_index = -7
		add_child(light)
		var tl := light.create_tween()
		tl.set_loops()
		tl.tween_property(light, "modulate:a", 0.3, rng.randf_range(0.5, 1.0))
		tl.tween_property(light, "modulate:a", 1.0, rng.randf_range(0.5, 1.0))
		lx += rng.randf_range(700.0, 1000.0)
	_add_lore_label(Vector2(360.0, -30.0), "붕괴 진행 · 대피", Color(0.9, 0.4, 0.25, 0.55), 15)

# ─── 붕괴 회랑 방1 · 격리 구획 승강 샤프트(VERTICAL_UP) 시그니처 배경 ───────────
# 지하 격리 구획에서 지상으로 오르는 콘크리트 샤프트: 양쪽 벽 + 이음매 + 배관 + 비상등(느린 맥동)
# + 아래쪽 소각 열기. 차오르는 붕괴 자체는 ChaseHazard(y_up)가 그린다.
func _ambience_collapse_shaft() -> void:
	var h: float = _world_size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 613 + 3
	var back := ColorRect.new()
	back.color = Color(0.085, 0.09, 0.11)
	back.position = Vector2(-200.0, -300.0)
	back.size = Vector2(1680.0, h + 600.0)
	back.z_index = -18
	add_child(back)
	for wx in [0.0, 1210.0]:
		var wall := ColorRect.new()
		wall.color = Color(0.14, 0.15, 0.17)
		wall.position = Vector2(float(wx), -300.0)
		wall.size = Vector2(70.0, h + 600.0)
		wall.z_index = -14
		add_child(wall)
	# 벽 이음매(수평 띠) · 층위감. 아래로 갈수록 그을음 톤.
	var sy: float = 240.0
	while sy < h:
		var seam := ColorRect.new()
		var soot: float = clampf((sy / h) * 0.05, 0.0, 0.05)
		seam.color = Color(0.06 + soot, 0.06, 0.07)
		seam.position = Vector2(0.0, sy)
		seam.size = Vector2(1280.0, 4.0)
		seam.z_index = -13
		add_child(seam)
		sy += 320.0
	for px in [110.0, 1170.0]:
		var pipe := ColorRect.new()
		pipe.color = Color(0.20, 0.21, 0.24)
		pipe.position = Vector2(float(px), -300.0)
		pipe.size = Vector2(8.0, h + 600.0)
		pipe.z_index = -12
		add_child(pipe)
	# 벽 균열 · 아래쪽일수록 잦다(붕괴가 아래에서 온다).
	var cy: float = h * 0.35
	while cy < h - 100.0:
		var crack := Line2D.new()
		crack.width = 2.0
		crack.default_color = Color(0.05, 0.05, 0.06, 0.7)
		var pts := PackedVector2Array()
		var cx: float = rng.randf_range(120.0, 1120.0)
		var yy: float = cy
		for i in 4:
			pts.append(Vector2(cx, yy))
			cx += rng.randf_range(-60.0, 60.0)
			yy += rng.randf_range(30.0, 70.0)
		crack.points = pts
		crack.z_index = -11
		add_child(crack)
		cy += rng.randf_range(240.0, 420.0)
	# 비상등 · 좌우 교대, 느린 맥동(광과민: 점멸 아님, 0.9~1.4s 왕복).
	var ly: float = 500.0
	var side: int = 0
	while ly < h - 200.0:
		var lamp := ColorRect.new()
		lamp.color = Color(0.9, 0.3, 0.2, 0.9)
		lamp.position = Vector2(84.0 if side % 2 == 0 else 1172.0, ly)
		lamp.size = Vector2(24.0, 10.0)
		lamp.z_index = -10
		add_child(lamp)
		var glow := ColorRect.new()
		glow.color = Color(0.9, 0.3, 0.2, 0.10)
		glow.position = lamp.position + Vector2(-60.0, -46.0)
		glow.size = Vector2(144.0, 102.0)
		glow.z_index = -10
		add_child(glow)
		var tl := glow.create_tween()
		tl.set_loops()
		tl.tween_property(glow, "modulate:a", 0.45, rng.randf_range(0.9, 1.4))
		tl.tween_property(glow, "modulate:a", 1.0, rng.randf_range(0.9, 1.4))
		ly += 520.0
		side += 1
	# 하부 소각 열기 · 샤프트 바닥 쪽에 잦아드는 주황 캐스트(정적, 붕괴 edge와 별개).
	var heat := ColorRect.new()
	heat.color = Color(0.55, 0.25, 0.12, 0.10)
	heat.position = Vector2(0.0, h - 700.0)
	heat.size = Vector2(1280.0, 700.0)
	heat.z_index = -9
	add_child(heat)
	_add_lore_label(Vector2(200.0, h - 260.0), "격리 구획 승강로 · B7", Color(0.9, 0.4, 0.25, 0.55), 15)
	_add_lore_label(Vector2(430.0, 400.0), "지상 방면 ↑", Color(0.55, 0.85, 0.95, 0.5), 15)

# ─── 붕괴 회랑 방2 · 중층 정비 복도(HORIZONTAL) 시그니처 배경 ───────────
# 구조가 "무너지는 중": 기울어진 천장 패널 + 늘어진 케이블 + 균열 + 분진 + 비상등.
# 갱도(_ambience_collapse)와 같은 붕괴 문법이되 갱목·낙석 대신 시설 내장재.
func _ambience_collapse_mezz() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 677 + 9
	# 기울어진 천장 패널 · 한쪽 고정이 풀려 매달린 내장재.
	var px2: float = 350.0
	while px2 < w:
		var panel := ColorRect.new()
		panel.color = Color(0.17, 0.17, 0.19)
		panel.position = Vector2(px2, -40.0)
		panel.size = Vector2(rng.randf_range(120.0, 200.0), 16.0)
		panel.rotation = rng.randf_range(0.10, 0.28) * (1.0 if rng.randf() < 0.5 else -1.0)
		panel.z_index = -11
		add_child(panel)
		px2 += rng.randf_range(420.0, 700.0)
	# 늘어진 케이블 · 천장에서 처진 호.
	var kx: float = 250.0
	while kx < w:
		var cable := Line2D.new()
		cable.width = 2.0
		cable.default_color = Color(0.08, 0.08, 0.10, 0.85)
		var pts := PackedVector2Array()
		var span: float = rng.randf_range(120.0, 220.0)
		var sag: float = rng.randf_range(50.0, 110.0)
		for i in 7:
			var t: float = float(i) / 6.0
			pts.append(Vector2(kx + span * t, -60.0 + sag * sin(t * PI)))
		cable.points = pts
		cable.z_index = -10
		add_child(cable)
		kx += rng.randf_range(380.0, 640.0)
	# 벽 균열 + 분진(갱도 문법 재사용, 밀도 낮게).
	var cx2: float = 300.0
	while cx2 < w:
		var crack := Line2D.new()
		crack.width = 2.0
		crack.default_color = Color(0.05, 0.05, 0.06, 0.7)
		var pts2 := PackedVector2Array()
		var ccx: float = cx2
		var yy: float = rng.randf_range(-140.0, GROUND_Y - 160.0)
		for i in 5:
			pts2.append(Vector2(ccx, yy))
			ccx += rng.randf_range(20.0, 50.0)
			yy += rng.randf_range(-40.0, 60.0)
		crack.points = pts2
		crack.z_index = -13
		add_child(crack)
		cx2 += rng.randf_range(340.0, 560.0)
	for i in 6:
		var deb := ColorRect.new()
		deb.color = Color(0.20, 0.18, 0.16, 0.8)
		deb.position = Vector2(rng.randf_range(0.0, w), rng.randf_range(-200.0, 0.0))
		var ds: float = rng.randf_range(3.0, 6.0)
		deb.size = Vector2(ds, ds)
		deb.z_index = -5
		add_child(deb)
		var td := deb.create_tween()
		td.set_loops()
		td.tween_property(deb, "position:y", GROUND_Y, rng.randf_range(1.6, 3.2))
		td.tween_property(deb, "position:y", rng.randf_range(-200.0, -60.0), 0.0)
	var dust := ColorRect.new()
	dust.color = Color(0.30, 0.26, 0.22, 0.07)
	dust.position = Vector2(-200.0, -100.0)
	dust.size = Vector2(w + 400.0, 240.0)
	dust.z_index = -6
	add_child(dust)
	# 비상등 · 느린 맥동 2기. (알파 0.30은 실내 배경 위에서 빨간 기둥으로 읽혀 축소.)
	for lx2 in [700.0, 1700.0]:
		var light := ColorRect.new()
		light.color = Color(0.9, 0.25, 0.2, 0.16)
		light.position = Vector2(float(lx2) - 40.0, -100.0)
		light.size = Vector2(80.0, 640.0)
		light.z_index = -7
		add_child(light)
		var tl2 := light.create_tween()
		tl2.set_loops()
		tl2.tween_property(light, "modulate:a", 0.4, rng.randf_range(0.9, 1.3))
		tl2.tween_property(light, "modulate:a", 1.0, rng.randf_range(0.9, 1.3))
	_add_lore_label(Vector2(340.0, -20.0), "중층 정비 통로 · B2", Color(0.9, 0.4, 0.25, 0.55), 15)
	_add_lore_label(Vector2(float(int(w) - 560), -20.0), "지상 출구 →", Color(0.55, 0.85, 0.95, 0.5), 15)

# ─── 감시 회랑 (HORIZONTAL) — 쓸어내는 스캔 빔 맵 시그니처 배경 ───────────
# 보안 스캔 시설: 천장 스캔 레일 + 벽면 감시 그리드 + 매달린 감시 렌즈(시안 맥동) + 스캔라인 스트로브.
# checkpoint 스캐너 정체성 확장. 니치 세이프존 렌더는 _build_cover_niches(기믹 시각)가 담당.
func _ambience_scanner() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 733 + 11
	# 천장 스캔 레일 — 빔이 매달린 상단 트랙.
	var rail := ColorRect.new()
	rail.color = Color(0.14, 0.15, 0.18)
	rail.position = Vector2(-100.0, -112.0)
	rail.size = Vector2(w + 200.0, 16.0)
	rail.z_index = -12
	add_child(rail)
	# 벽면 감시 그리드(세로선) — 스캔 격자.
	var gx: float = 120.0
	while gx < w:
		var gl := ColorRect.new()
		gl.color = Color(0.20, 0.30, 0.34, 0.18)
		gl.position = Vector2(gx, -96.0)
		gl.size = Vector2(2.0, GROUND_Y + 56.0)
		gl.z_index = -11
		add_child(gl)
		gx += 160.0
	# 매달린 감시 렌즈 — 천장의 감시 눈, 시안 발광 맥동.
	var lx: float = 500.0
	while lx < w:
		var lens := ColorRect.new()
		lens.color = Color(0.35, 0.85, 0.95, 0.5)
		lens.position = Vector2(lx - 9.0, -98.0)
		lens.size = Vector2(18.0, 18.0)
		lens.z_index = -7
		add_child(lens)
		var tl := lens.create_tween()
		tl.set_loops()
		tl.tween_property(lens, "modulate:a", 0.35, rng.randf_range(0.7, 1.2))
		tl.tween_property(lens, "modulate:a", 1.0, rng.randf_range(0.7, 1.2))
		lx += rng.randf_range(520.0, 760.0)
	# 전역 스캔라인 스트로브(시안) — 감시 활성 분위기.
	var strobe := ColorRect.new()
	strobe.color = Color(0.30, 0.80, 0.92, 0.05)
	strobe.position = Vector2(-100.0, -100.0)
	strobe.size = Vector2(w + 200.0, GROUND_Y + 100.0)
	strobe.z_index = -6
	add_child(strobe)
	var ts := strobe.create_tween()
	ts.set_loops()
	ts.tween_property(strobe, "modulate:a", 0.5, 1.4)
	ts.tween_property(strobe, "modulate:a", 1.0, 1.4)
	_add_lore_label(Vector2(360.0, -30.0), "보안 스캔 · 감시 활성", Color(0.4, 0.8, 0.9, 0.55), 15)

# ─── 반응로 제어실 (ARENA) — 아레나 방어 맵 시그니처 배경 ───────────
# ARENA는 _build_indoor_backdrop(HORIZONTAL 전용)를 안 타므로 여기서 챔버 구조를 직접 그린다.
# 뒷벽 패널 + 지지 리브 + 케이블 트레이 + 좌우 모니터 뱅크 + 천장 트러스/램프 + 바닥 경고 비콘.
func _ambience_reactor() -> void:
	var w: float = STAGE_LENGTH        # ARENA = 1920
	var gy: float = GROUND_Y           # 820
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 617 + 5
	# 뒷벽 슬래브(도시 실루엣 대체)
	var wall := ColorRect.new()
	wall.color = Color(0.10, 0.11, 0.14)
	wall.position = Vector2(-100.0, -260.0)
	wall.size = Vector2(w + 200.0, gy + 260.0)
	wall.z_index = -16
	add_child(wall)
	# 지지 리브(세로 기둥) — 일정 간격
	var rx: float = 80.0
	while rx < w:
		var rib := ColorRect.new()
		rib.color = Color(0.07, 0.08, 0.10)
		rib.position = Vector2(rx - 9.0, -240.0)
		rib.size = Vector2(18.0, gy + 240.0)
		rib.z_index = -15
		add_child(rib)
		rx += 240.0
	# 수평 케이블 트레이/도관 — 벽 위쪽
	for i in 3:
		var tray := ColorRect.new()
		tray.color = Color(0.16, 0.15, 0.12, 0.8)
		tray.position = Vector2(-100.0, -180.0 + float(i) * 46.0)
		tray.size = Vector2(w + 200.0, 5.0)
		tray.z_index = -14
		add_child(tray)
	# 천장 트러스 + 매달린 램프
	var ceil := ColorRect.new()
	ceil.color = Color(0.06, 0.07, 0.09)
	ceil.position = Vector2(-100.0, -260.0)
	ceil.size = Vector2(w + 200.0, 90.0)
	ceil.z_index = -13
	add_child(ceil)
	var lx: float = 240.0
	while lx < w:
		var lamp := ColorRect.new()
		lamp.color = Color(0.85, 0.90, 1.0, 0.5)
		lamp.position = Vector2(lx - 30.0, -168.0)
		lamp.size = Vector2(60.0, 8.0)
		lamp.z_index = -12
		add_child(lamp)
		var cone := Polygon2D.new()
		cone.color = Color(0.75, 0.82, 0.95, 0.05)
		cone.polygon = PackedVector2Array([
			Vector2(lx - 30.0, -160.0), Vector2(lx + 30.0, -160.0),
			Vector2(lx + 150.0, gy - 40.0), Vector2(lx - 150.0, gy - 40.0)])
		cone.z_index = -11
		add_child(cone)
		lx += 480.0
	# 좌우 모니터 뱅크 — 깜빡이는 LED 격자
	for side in [0.0, 1.0]:
		var mx: float = lerp(120.0, w - 300.0, side)
		var bank := ColorRect.new()
		bank.color = Color(0.08, 0.09, 0.12)
		bank.position = Vector2(mx, -120.0)
		bank.size = Vector2(180.0, 120.0)
		bank.z_index = -11
		add_child(bank)
		for r in 3:
			for c in 5:
				if rng.randf() < 0.55:
					var led := ColorRect.new()
					var warm: bool = rng.randf() < 0.3
					led.color = Color(0.95, 0.55, 0.25, 0.8) if warm else Color(0.40, 0.80, 0.95, 0.8)
					led.position = Vector2(mx + 16.0 + float(c) * 32.0, -104.0 + float(r) * 36.0)
					led.size = Vector2(14.0, 10.0)
					led.z_index = -10
					add_child(led)
					var tl := led.create_tween()
					tl.set_loops()
					var per: float = rng.randf_range(0.6, 1.6)
					tl.tween_property(led, "modulate:a", 0.25, per)
					tl.tween_property(led, "modulate:a", 1.0, per)
	# 바닥 코어 마운트 광 — 중앙 발광 패널
	var glowpad := ColorRect.new()
	glowpad.color = Color(0.20, 0.45, 0.55, 0.10)
	glowpad.position = Vector2(w * 0.5 - 220.0, gy - 6.0)
	glowpad.size = Vector2(440.0, 6.0)
	glowpad.z_index = -7
	add_child(glowpad)
	# 코너 경고 비콘(앰버, 맥동) — 방어 구역 신호
	for side2 in [0.0, 1.0]:
		var bx: float = lerp(220.0, w - 220.0, side2)
		var beacon := ColorRect.new()
		beacon.color = Color(0.95, 0.60, 0.20, 0.55)
		beacon.position = Vector2(bx - 6.0, gy - 60.0)
		beacon.size = Vector2(12.0, 60.0)
		beacon.z_index = -6
		add_child(beacon)
		var tb := beacon.create_tween()
		tb.set_loops()
		tb.tween_property(beacon, "modulate:a", 0.25, 0.7)
		tb.tween_property(beacon, "modulate:a", 1.0, 0.7)
	_add_lore_label(Vector2(w * 0.5 - 120.0, -212.0), "반응로 제어실 · 코어 방어", Color(0.45, 0.82, 0.95, 0.6), 15)

# ─── 저지선 (ARENA) — 부서지는 엄폐 농성 맵 시그니처 배경 ───────────
# 봉쇄된 통제 구역/로비: 뒷벽 + 좌우 봉쇄 셔터(적이 밀려오는 입구) + 방어 거점 바닥 라인 +
# 적색 비상 스트로브(발각 경보) + 위험 스트라이프. ARENA라 챔버 구조를 직접 그린다.
func _ambience_holdout() -> void:
	var w: float = STAGE_LENGTH        # ARENA = 1920
	var gy: float = GROUND_Y           # 820
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 829 + 3
	# 뒷벽 슬래브(봉쇄 콘크리트)
	var wall := ColorRect.new()
	wall.color = Color(0.11, 0.10, 0.11)
	wall.position = Vector2(-100.0, -260.0)
	wall.size = Vector2(w + 200.0, gy + 260.0)
	wall.z_index = -16
	add_child(wall)
	# 벽면 콘크리트 패널 이음선(세로)
	var px: float = 160.0
	while px < w:
		var seam := ColorRect.new()
		seam.color = Color(0.07, 0.06, 0.07)
		seam.position = Vector2(px - 4.0, -240.0)
		seam.size = Vector2(8.0, gy + 240.0)
		seam.z_index = -15
		add_child(seam)
		px += 300.0
	# 천장 트러스
	var ceil := ColorRect.new()
	ceil.color = Color(0.06, 0.06, 0.07)
	ceil.position = Vector2(-100.0, -260.0)
	ceil.size = Vector2(w + 200.0, 96.0)
	ceil.z_index = -13
	add_child(ceil)
	# 좌우 봉쇄 셔터 — 적이 밀려오는 입구(어두운 개구부 + 위험 스트라이프 프레임)
	for side in [0.0, 1.0]:
		var door_x: float = lerp(40.0, w - 200.0, side)
		var opening := ColorRect.new()
		opening.color = Color(0.03, 0.03, 0.04)
		opening.position = Vector2(door_x, gy - 220.0)
		opening.size = Vector2(160.0, 220.0)
		opening.z_index = -14
		add_child(opening)
		# 상단 위험 스트라이프 프레임
		var frame := ColorRect.new()
		frame.color = Color(0.85, 0.62, 0.18, 0.7)
		frame.position = Vector2(door_x, gy - 226.0)
		frame.size = Vector2(160.0, 8.0)
		frame.z_index = -12
		add_child(frame)
		# 셔터 안 붉은 경보광(맥동) — "여기서 밀려온다"
		var glow := ColorRect.new()
		glow.color = Color(0.9, 0.25, 0.2, 0.35)
		glow.position = Vector2(door_x + 20.0, gy - 200.0)
		glow.size = Vector2(120.0, 200.0)
		glow.z_index = -13
		add_child(glow)
		var tg := glow.create_tween()
		tg.set_loops()
		tg.tween_property(glow, "modulate:a", 0.3, rng.randf_range(0.6, 1.0))
		tg.tween_property(glow, "modulate:a", 1.0, rng.randf_range(0.6, 1.0))
	# 방어 거점 바닥 라인(중앙 시안 마킹) — "여기를 지켜라"
	var hold := ColorRect.new()
	hold.color = Color(0.35, 0.78, 0.88, 0.16)
	hold.position = Vector2(w * 0.5 - 260.0, gy - 5.0)
	hold.size = Vector2(520.0, 5.0)
	hold.z_index = -1
	add_child(hold)
	# 천장 적색 비상 스트로브(발각 경보) — 전역 옅은 적색 맥동
	var alarm := ColorRect.new()
	alarm.color = Color(0.85, 0.18, 0.15, 0.06)
	alarm.position = Vector2(-100.0, -100.0)
	alarm.size = Vector2(w + 200.0, gy + 100.0)
	alarm.z_index = -6
	add_child(alarm)
	var ta := alarm.create_tween()
	ta.set_loops()
	ta.tween_property(alarm, "modulate:a", 0.4, 0.9)
	ta.tween_property(alarm, "modulate:a", 1.0, 0.9)
	_add_lore_label(Vector2(w * 0.5 - 110.0, -212.0), "통제 구역 봉쇄 · 저지선", Color(0.9, 0.45, 0.3, 0.6), 15)

func _build_ground() -> void:
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	ground.collision_mask = 0
	ground.add_to_group("ground")
	add_child(ground)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(STAGE_LENGTH + 400.0, 200.0)
	col.shape = shape
	col.position = Vector2(STAGE_LENGTH * 0.5, GROUND_Y + 100.0)
	ground.add_child(col)

	var fw: float = STAGE_LENGTH + 400.0
	# 바닥 본체 (어두운)
	var floor_visual := ColorRect.new()
	floor_visual.color = Color(0.04, 0.045, 0.06)
	floor_visual.position = Vector2(-200, GROUND_Y)
	floor_visual.size = Vector2(fw, 300.0)
	add_child(floor_visual)
	# 바닥 상단 패널 (살짝 밝음, 4px) — 깊이감
	var floor_top := ColorRect.new()
	floor_top.color = Color(0.10, 0.12, 0.16)
	floor_top.position = Vector2(-200, GROUND_Y)
	floor_top.size = Vector2(fw, 4.0)
	add_child(floor_top)
	# 지평선 발광 라인 (위) · env 액센트 색조(맵 성격이 지평선 색에도 실리게, 2026-08-17).
	var acc: Color = _env_palette(_indoor_env())["accent"]
	var line := ColorRect.new()
	line.color = Color(acc.r, acc.g, acc.b, 0.5)
	line.position = Vector2(-200, GROUND_Y - 1.0)
	line.size = Vector2(fw, 1.4)
	add_child(line)
	# 바닥 패널 라인들 — 일정 간격 수평 stripe (질감)
	var stripe_y: float = GROUND_Y + 18.0
	while stripe_y < GROUND_Y + 240.0:
		var stripe := ColorRect.new()
		stripe.color = Color(0.10, 0.12, 0.16, 0.35)
		stripe.position = Vector2(-200, stripe_y)
		stripe.size = Vector2(fw, 1.0)
		add_child(stripe)
		stripe_y += 28.0
	# 바닥 노이즈 — 작은 점 패널 마커 (랜덤)
	var grng := RandomNumberGenerator.new()
	grng.seed = GameState.current_stage * 421 + 9
	var gx: float = -100.0
	while gx < STAGE_LENGTH + 200.0:
		var gap: float = grng.randf_range(140.0, 280.0)
		var dot := ColorRect.new()
		dot.color = Color(0.14, 0.18, 0.24, 0.85)
		dot.position = Vector2(gx, GROUND_Y + grng.randf_range(8.0, 60.0))
		dot.size = Vector2(grng.randf_range(8.0, 18.0), 2.0)
		add_child(dot)
		gx += gap
	# 깊이 그라디언트 · 표면에서 아래로 갈수록 어둡게(스트라이프·노이즈 위에 얹어 플랫 탈피).
	_add_vgrad(Vector2(-200, GROUND_Y + 6.0), Vector2(fw, 250.0), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.55), 0)

var _map_data: Dictionary = {}

func _build_platforms() -> void:
	# MapData에서 platform/적/보상/함정 통합 명세를 가져온다 (docs/design/world_layout.md).
	_map_data = MapData.get_layout(GameState.current_route_id)
	if _map_data.is_empty():
		# 폴백 — 디버그/플레이그라운드 환경에서 route_id가 없을 때.
		_build_platforms_fallback()
		return
	for entry in _map_data.get("platforms", []):
		var d: Dictionary = entry
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var w: float = float(d.get("w", 220.0))
		_build_platform(p.x, p.y, w)

# 이동 발판(MovingPlatform 기믹) — MapData "moving_platforms" 배열을 읽어 AnimatableBody2D 발판 생성.
# 각 항목 = {from, to, w, cycle, phase?}. 위에 탄 플레이어는 move_and_slide가 자동 운반.
func _build_moving_platforms() -> void:
	for entry in _map_data.get("moving_platforms", []):
		var d: Dictionary = entry
		var mp := MovingPlatform.new()
		add_child(mp)
		mp.setup(
			d.get("from", Vector2.ZERO),
			d.get("to", Vector2.ZERO),
			float(d.get("w", 160.0)),
			float(d.get("cycle", 4.0)),
			float(d.get("phase", 0.0))
		)

# 부서지는 엄폐물(DestructibleCover 기믹) — MapData "destructible_covers" 배열을 읽어 생성.
# 각 항목 = {pos(바닥 접점=하단 중앙), w, h, hp, style?("car"/"container")}. 솔리드 + 적탄
# 피격으로 파괴(엄폐 관리 = 이 맵 정체성). container = 키 큰 적재 컨테이너(고가 저격의 사각).
func _build_destructible_covers() -> void:
	for entry in _map_data.get("destructible_covers", []):
		var d: Dictionary = entry
		var cover := DestructibleCover.new()
		add_child(cover)
		cover.position = d.get("pos", Vector2.ZERO)
		cover.z_index = -1  # 배우(플레이어/적) 뒤 — 항상 플레이어가 보이게
		cover.setup(float(d.get("w", 96.0)), float(d.get("h", 72.0)), int(d.get("hp", 3)),
			str(d.get("style", "car")))

# 솔리드 장애물(붕괴 잔해 등) — MapData "hurdles" 배열. {x, w, h}. 두 방향 솔리드(넘어야 함).
# 강제 전진 맵에서 점프/등반을 강제해 시간 손실 → 추격 벽이 따라붙게 만드는 요소.
func _build_hurdles() -> void:
	for entry in _map_data.get("hurdles", []):
		var d: Dictionary = entry
		var hx: float = float(d.get("x", 0.0))
		var hw: float = float(d.get("w", 50.0))
		var hh: float = float(d.get("h", 100.0))
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(hw, hh)
		col.shape = shape
		col.position = Vector2(hx, GROUND_Y - hh * 0.5)
		body.add_child(col)
		# 잔해 비주얼 · "배경 그림 같아 안 보인다"(사용자 2026-08-17 붕괴 갱도) 반영:
		# 몸체를 밝히고 상단 주의 띠 + 어두운 외곽선으로 "밟고 넘는 실물"임을 명확히
		# (known_issues 솔리드 가시성 규칙과 동형 · 전 맵 공용이라 일괄 적용).
		var hpts := PackedVector2Array([
			Vector2(hx - hw * 0.5, GROUND_Y), Vector2(hx - hw * 0.42, GROUND_Y - hh),
			Vector2(hx + hw * 0.28, GROUND_Y - hh * 0.86), Vector2(hx + hw * 0.5, GROUND_Y)])
		var vis := Polygon2D.new()
		vis.color = Color(0.26, 0.24, 0.22)
		vis.polygon = hpts
		vis.z_index = -1
		add_child(vis)
		# 앞면 음영 · 우측이 살짝 어두운 이면(입체감).
		var shade := Polygon2D.new()
		shade.color = Color(0.16, 0.15, 0.14)
		shade.polygon = PackedVector2Array([
			Vector2(hx + hw * 0.02, GROUND_Y), Vector2(hx + hw * 0.28, GROUND_Y - hh * 0.86),
			Vector2(hx + hw * 0.5, GROUND_Y)])
		shade.z_index = -1
		add_child(shade)
		# 외곽선 · 어두운 윤곽으로 배경과 분리.
		var outline := Line2D.new()
		outline.points = hpts
		outline.closed = true
		outline.width = 2.0
		outline.default_color = Color(0.05, 0.05, 0.06, 0.9)
		outline.z_index = -1
		add_child(outline)
		# 상단 주의 띠 · 착지면 인지(발판 상단 발광과 같은 문법, 앰버).
		var edge := ColorRect.new()
		edge.color = Color(0.86, 0.63, 0.25, 0.85)
		edge.position = Vector2(hx - hw * 0.42, GROUND_Y - hh)
		edge.size = Vector2(hw * 0.68, 3.0)
		edge.z_index = -1
		add_child(edge)

# 강제 전진 추격 붕괴(ChaseHazard 기믹) · MapData "chase_hazard" =
# {start_x, speed, max_gap?, stop_x?, axis?("x"/"y_up"), catchup?}. start_x·stop_x는 axis가
# "y_up"이면 y 좌표를 담는다. stop = 구조물 끝(붕괴는 구조 안까지만). 클리어/세그먼트 전환 시
# halt용으로 참조 보관.
var _chase_hazard: ChaseHazard = null

func _build_chase_hazard() -> void:
	var cfg: Dictionary = _map_data.get("chase_hazard", {})
	if cfg.is_empty():
		return
	var hz := ChaseHazard.new()
	add_child(hz)
	hz.setup(float(cfg.get("start_x", -300.0)), float(cfg.get("speed", 210.0)), float(cfg.get("max_gap", 700.0)), float(cfg.get("stop_x", INF)), str(cfg.get("axis", "x")), float(cfg.get("catchup", 340.0)))
	_chase_hazard = hz

# 맵 데이터 구동 진행 자막 — MapData "route_lines": [{x, who("veil"/"rival"), text, dur?, glitch?}].
# 플레이어가 x를 처음 넘는 순간 1회 출력(탈출 4종의 배웅/중계 비트, replay_support_plan §3.2).
func _build_route_lines() -> void:
	var arr: Array = _map_data.get("route_lines", [])
	if arr.is_empty() or GameState.story_mode:
		return
	var trig := _RouteLineTriggers.new()
	trig.host = self
	trig.lines = arr
	add_child(trig)

class _RouteLineTriggers extends Node:
	var host: Node = null
	var lines: Array = []
	var _fired: Array = []
	func _physics_process(_delta: float) -> void:
		if host == null or not is_instance_valid(host):
			return
		var tree := get_tree()
		if tree == null:
			return
		var players := tree.get_nodes_in_group("player")
		if players.is_empty():
			return
		var ppos: Vector2 = (players[0] as Node2D).global_position
		for i in lines.size():
			if i in _fired:
				continue
			var d: Dictionary = lines[i]
			# 트리거 축 · "y" = 상승 맵(그 높이 위로 오르면) / "y_down" = 하강 맵(그 깊이
			# 아래로 내려가면) / 기본 = 수평(x 통과).
			if d.has("y"):
				if ppos.y > float(d.get("y", 0.0)):
					continue
			elif d.has("y_down"):
				if ppos.y < float(d.get("y_down", 0.0)):
					continue
			elif ppos.x < float(d.get("x", 0.0)):
				continue
			_fired.append(i)
			# 어투 밴드 스윕(2026-08-21): 기본 = 중립 보고체("text"), warm 밴드는 "text_warm"(있을 때만).
			var txt: String = VeilDialogue.banded(str(d.get("text", "")), str(d.get("text_warm", "")))
			var dur: float = float(d.get("dur", 3.2))
			if bool(d.get("glitch", false)):
				host.call("_run_glitch", 0.4, 0.3)
			if str(d.get("who", "veil")) == "rival":
				host.call("_show_rival_subtitle", txt, dur)
			else:
				host.call("_show_veil_subtitle", txt, dur)

# 거짓 렌더 배웅 실루엣 — MapData "fake_watchers": [Vector2]. 잔류 탈출의 정체성(§3.2):
# 구형 렌더 문법의 실루엣(FalseVeil._FakeMarker 재사용)이 길가에 서서 플레이어를 겨눈 채
# 배웅한다. 콜리전 없음 — 쏘면 렌더가 찢겼다 재조립(P3와 같은 공정 tell).
func _build_fake_watchers() -> void:
	var arr: Array = _map_data.get("fake_watchers", [])
	if arr.is_empty() or GameState.story_mode:
		return
	for p in arr:
		var m := FalseVeil._FakeMarker.new()
		m.lifetime = 99999.0
		m.position = p
		add_child(m)

# 아레나 방어(DefenseCore 기믹) — MapData "defense_core" = {pos, hp?, radius?, interval?}.
# dome 안 적이 와인드업(예고 게이지) 후 코어를 직접 타격, 0이면 방어 실패. 웨이브 전멸이 클리어.
# (2026-08-12 재설계: 오라 드레인 → 이산 타격. 인과 가독 + 밀어내기 유효화.)
func _build_defense_core() -> void:
	var cfg: Dictionary = _map_data.get("defense_core", {})
	if cfg.is_empty():
		return
	var core := DefenseCore.new()
	add_child(core)
	core.position = cfg.get("pos", Vector2(960.0, 820.0))
	core.setup(float(cfg.get("hp", 14.0)), float(cfg.get("radius", 360.0)), float(cfg.get("interval", 1.5)))
	core.breached.connect(_on_core_breached)
	_defense_core = core

# 감시 스위프 빔(SweepBeam 기믹) — MapData "sweep_beam" + "cover_niches".
# 수직 스캔 빔이 통로를 주기적으로 훑고, 니치(세이프 밴드) 밖에서 빔에 덮이면 피해.
func _build_sweep_beam() -> void:
	var cfg: Dictionary = _map_data.get("sweep_beam", {})
	if cfg.is_empty():
		return
	var niches: Array = _map_data.get("cover_niches", [])
	var s_half: float = float(_map_data.get("niche_half", 90.0))
	var beam := SweepBeam.new()
	add_child(beam)
	beam.setup(cfg, niches, s_half)
	_sweep_beam_node = beam   # 중간 관문 beam 모드가 빔 위치를 읽는다(페이싱 §1)

# ─── 중간 관문(페이싱 확장 §1) — MapData "mid_gate" 구동 ──────────────────
# {"x", "mode": "lever"|"clear"|"beam", "lever": Vector2(lever 모드), "zone": [x0,x1](clear 모드)}
# 통과형 맵의 체류 비트: 열릴 때까지 삼단점프로도 못 넘는 솔리드 격벽(높이 480).
#   lever = 동력 레버(수직·우회 동선) · clear = 관문 구역 경비만 전멸(국소 — 맵 전체 아님,
#   "모든 적과 싸울 필요 없다" 정체성 보존) · beam = 스캔 빔이 게이트를 지나는 동안만 개방
#   (빔을 피하는 대신 꽁무니를 쫓아 통과하는 리듬 역전, scanner 전용).
# 구성 중복 금지(2026-08-16 사용자): 파일럿 4맵이 서로 다른 모드/텍스처를 쓴다.
var _mid_gate_body: StaticBody2D = null
var _mid_gate_col: CollisionShape2D = null
var _mid_gate_visual: Node2D = null
var _mid_gate_lamp: ColorRect = null
var _mid_gate_mode: String = ""
var _mid_gate_x: float = 0.0
var _mid_gate_guards: Array = []
var _mid_gate_inited: bool = false
var _mid_gate_opened: bool = false
var _mid_gate_pass_open: bool = false   # beam 모드 현재 개방창 상태
var _mid_gate_hint_shown: bool = false
# clear 모드 구역 시각 — "어디까지가 검증 구역인지"를 화면에 그린다(사용자 2026-08-19:
# 존 밖 방패병을 안 잡았는데 문이 열려 버그로 읽힘). 데이터상 존재하는 판정 경계는
# 화면에 없으면 없는 것과 같다([[repeated-report-recheck-onscreen]] 동형).
var _mid_gate_zone_visual: Node2D = null
var _mid_gate_zone_label: Label = null
var _sweep_beam_node: SweepBeam = null

func _build_mid_gate() -> void:
	var g: Dictionary = _map_data.get("mid_gate", {})
	if g.is_empty():
		return
	_mid_gate_mode = str(g.get("mode", "lever"))
	_mid_gate_x = float(g.get("x", 0.0))
	var gate_h: float = 480.0
	var top_y: float = GROUND_Y - gate_h
	_mid_gate_body = StaticBody2D.new()
	_mid_gate_body.collision_layer = 1
	_mid_gate_col = CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(48.0, gate_h)
	_mid_gate_col.shape = shape
	_mid_gate_body.position = Vector2(_mid_gate_x, top_y + gate_h * 0.5)
	_mid_gate_body.add_child(_mid_gate_col)
	add_child(_mid_gate_body)
	# 시각 — 격벽 패널 + 위험 스트라이프 + 상태 램프. 점멸 없음(광과민 기준: 색 전환만).
	_mid_gate_visual = Node2D.new()
	_mid_gate_visual.position = Vector2(_mid_gate_x, top_y)
	_mid_gate_visual.z_index = 3
	add_child(_mid_gate_visual)
	var panel := ColorRect.new()
	panel.color = Color(0.16, 0.17, 0.21)
	panel.position = Vector2(-24.0, 0.0)
	panel.size = Vector2(48.0, gate_h)
	_mid_gate_visual.add_child(panel)
	var edge := ColorRect.new()
	edge.color = Color(0.30, 0.32, 0.38)
	edge.position = Vector2(-24.0, 0.0)
	edge.size = Vector2(6.0, gate_h)
	_mid_gate_visual.add_child(edge)
	for i in 5:
		var stripe := ColorRect.new()
		stripe.color = Color(0.85, 0.65, 0.20, 0.5)
		stripe.position = Vector2(-18.0, 44.0 + float(i) * 92.0)
		stripe.size = Vector2(36.0, 14.0)
		_mid_gate_visual.add_child(stripe)
	_mid_gate_lamp = ColorRect.new()
	_mid_gate_lamp.color = Color(0.95, 0.30, 0.25)
	_mid_gate_lamp.position = Vector2(-8.0, 14.0)
	_mid_gate_lamp.size = Vector2(16.0, 16.0)
	_mid_gate_visual.add_child(_mid_gate_lamp)
	if _mid_gate_mode == "lever":
		var lv: Vector2 = g.get("lever", Vector2(_mid_gate_x - 480.0, GROUND_Y - 32.0))
		var lever := _spawn_lever(lv, "mid_gate_power")
		lever.hint_color = Color(0.95, 0.75, 0.35)
		lever.pulled.connect(func(_id: String) -> void:
			_open_mid_gate())
	elif _mid_gate_mode == "clear":
		_build_mid_gate_zone(g.get("zone", []))

# 검증 구역 바닥 표시 — "여기 선 경비만 문을 잠근다"를 눈으로 읽히게 한다.
# 구역 밖 적(위장 방패병 등)을 남겨 두고 문이 열리면 판정이 고장난 것처럼 보인다
# (사용자 2026-08-19 통제 회랑 보고). 수직 기둥 금지 규칙에 따라 바닥 페인트 + 낮은
# 모서리 마크만 쓰고, 솔리드로 오독되지 않게 지면에 눕힌 도료로만 그린다.
func _build_mid_gate_zone(zone: Array) -> void:
	if zone.size() < 2:
		return
	var z0: float = float(zone[0])
	var z1: float = minf(float(zone[1]), _mid_gate_x - 40.0)
	if z1 <= z0:
		return
	_mid_gate_zone_visual = Node2D.new()
	_mid_gate_zone_visual.z_index = -6
	add_child(_mid_gate_zone_visual)
	# 바닥 도료 · 지면에 붙여 낮게만 깔고, 위로는 알파를 급히 떨어뜨린다. 높이 있는 워시는
	# 윗변이 직선으로 보여 발판·유리벽처럼 읽힌다(첫 시안 스크린샷에서 확인).
	var bands: Array = [
		{"h": 7.0, "y": 7.0, "a": 0.34},
		{"h": 9.0, "y": 16.0, "a": 0.13},
		{"h": 14.0, "y": 30.0, "a": 0.05},
	]
	for b0 in bands:
		var b: Dictionary = b0
		var band := ColorRect.new()
		band.color = Color(0.92, 0.70, 0.26, float(b["a"]))
		band.position = Vector2(z0, GROUND_Y - float(b["y"]))
		band.size = Vector2(z1 - z0, float(b["h"]))
		_mid_gate_zone_visual.add_child(band)
	# 양 끝 경계 · 바닥에 칠한 굵은 모서리 마크(높이 34, 무릎 아래 · 비솔리드).
	for ex in [z0, z1]:
		var mark := ColorRect.new()
		mark.color = Color(0.95, 0.74, 0.30, 0.55)
		mark.position = Vector2(float(ex) - 5.0, GROUND_Y - 34.0)
		mark.size = Vector2(10.0, 34.0)
		_mid_gate_zone_visual.add_child(mark)
	# 남은 경비 수 · 구역 위 표기. 숫자가 줄면 문이 언제 열릴지 예측 가능해진다.
	_mid_gate_zone_label = Label.new()
	_mid_gate_zone_label.add_theme_font_size_override("font_size", 15)
	_mid_gate_zone_label.add_theme_color_override("font_color", Color(0.95, 0.78, 0.38, 0.9))
	_mid_gate_zone_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_mid_gate_zone_label.add_theme_constant_override("outline_size", 4)
	# 캐릭터·발판 위로 띄운다(부모 z -6 기준 상대값) — 교전 중에 가려지면 셈이 안 읽힌다.
	_mid_gate_zone_label.z_index = 14
	_mid_gate_zone_label.position = Vector2((z0 + z1) * 0.5 - 110.0, GROUND_Y - 258.0)
	_mid_gate_zone_label.size = Vector2(220.0, 26.0)
	_mid_gate_zone_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_mid_gate_zone_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mid_gate_zone_label.text = "검증 구역"
	_mid_gate_zone_visual.add_child(_mid_gate_zone_label)

func _set_mid_gate_zone_count(alive: int) -> void:
	if _mid_gate_zone_label == null or not is_instance_valid(_mid_gate_zone_label):
		return
	if alive > 0:
		_mid_gate_zone_label.text = "검증 구역 · 남은 경비 %d" % alive
	else:
		_mid_gate_zone_label.text = "검증 구역 · 정리 완료"

# clear 모드 경비 수집 — 적 스폰이 _build_world 이후라 첫 tick에서 1회 수집한다.
# 소프트락 방지(사용자 2026-08-17 검문소 보고 "벽 건너편 적을 잡을 수 없어 못 넘어감"):
# ⓐ 게이트 너머(오른쪽) 적은 수집 제외 · 닫힌 벽 뒤는 총알이 안 닿는다.
# ⓑ 수집 결과가 0이면 즉시 개방 · 지킬 경비가 없는 관문은 잠글 명분이 없다(데이터 안전판).
# ⓒ 수집된 경비가 어떤 이유로든 게이트 너머로 넘어가면 재검에서 제외(주기 재검은 _tick).
func _mid_gate_lazy_init() -> void:
	_mid_gate_inited = true
	if _mid_gate_mode != "clear":
		return
	var zone: Array = (_map_data.get("mid_gate", {}) as Dictionary).get("zone", [])
	if zone.size() < 2:
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node2D).get("harmless"):
			continue
		var ex: float = (e as Node2D).global_position.x
		if ex >= float(zone[0]) and ex <= minf(float(zone[1]), _mid_gate_x - 40.0):
			_mid_gate_guards.append(e)
			(e as Node).connect("killed", func(_p: Vector2) -> void:
				_on_mid_gate_guard_down())
	if _mid_gate_guards.is_empty():
		_open_mid_gate()
	else:
		_set_mid_gate_zone_count(_mid_gate_guards.size())

func _on_mid_gate_guard_down() -> void:
	if _mid_gate_opened:
		return
	var alive: int = 0
	for e in _mid_gate_guards:
		# freed 참조에 is를 먼저 대면 "previously freed instance" 에러 · 유효성 검사가 항상 앞.
		if is_instance_valid(e) and e is Node2D and not (e as Node2D).is_queued_for_deletion() \
				and not bool((e as Node2D).get("dead")) \
				and (e as Node2D).global_position.x < _mid_gate_x - 20.0:
			alive += 1
	_set_mid_gate_zone_count(alive)
	if alive <= 0:
		_open_mid_gate()

# 영구 개방(lever/clear) — 격벽이 위로 올라가며 사라진다.
func _open_mid_gate() -> void:
	if _mid_gate_opened:
		return
	_mid_gate_opened = true
	SfxPlayer.play("gate_unlock")
	# 간섭 종료(중계소 방3) — 문과 간섭이 같은 송신 전원에 물려 있다(레버 페이오프).
	if bool((_map_data.get("interference", {}) as Dictionary).get("lever_stops", false)):
		for n in get_tree().get_nodes_in_group("interference"):
			(n as Node).call("halt")
	if _mid_gate_col != null and is_instance_valid(_mid_gate_col):
		_mid_gate_col.set_deferred("disabled", true)
	if _mid_gate_lamp != null and is_instance_valid(_mid_gate_lamp):
		_mid_gate_lamp.color = Color(0.40, 0.95, 0.65)
	if _mid_gate_visual != null and is_instance_valid(_mid_gate_visual):
		var tw := _mid_gate_visual.create_tween()
		tw.tween_property(_mid_gate_visual, "position:y",
			_mid_gate_visual.position.y - 440.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# 구역 표시는 역할이 끝나면 물러난다 — 남아 있으면 아직 할 일이 있는 것처럼 읽힌다.
	if _mid_gate_zone_visual != null and is_instance_valid(_mid_gate_zone_visual):
		_set_mid_gate_zone_count(0)
		var zt := _mid_gate_zone_visual.create_tween()
		zt.tween_property(_mid_gate_zone_visual, "modulate:a", 0.0, 1.1).set_delay(0.5)

# beam 모드 개방창 토글 — 빔이 게이트를 지나 앞서가는 동안만 열림.
func _set_mid_gate_pass(open_now: bool) -> void:
	if _mid_gate_opened or _mid_gate_pass_open == open_now:
		return
	_mid_gate_pass_open = open_now
	if _mid_gate_col != null and is_instance_valid(_mid_gate_col):
		_mid_gate_col.set_deferred("disabled", open_now)
	if _mid_gate_visual != null and is_instance_valid(_mid_gate_visual):
		_mid_gate_visual.modulate.a = 0.22 if open_now else 1.0
	if _mid_gate_lamp != null and is_instance_valid(_mid_gate_lamp):
		_mid_gate_lamp.color = Color(0.40, 0.95, 0.65) if open_now else Color(0.95, 0.30, 0.25)
	if open_now:
		SfxPlayer.play("gate_unlock", -10.0)

func _tick_mid_gate(_delta: float) -> void:
	if _mid_gate_mode == "":
		return
	if not _mid_gate_inited:
		_mid_gate_lazy_init()
	# 접근 힌트(맵당 1회) — 관문의 목표를 모드별로 전달.
	if not _mid_gate_hint_shown and not _mid_gate_opened and player != null \
			and is_instance_valid(player) and absf(player.global_position.x - _mid_gate_x) < 520.0:
		_mid_gate_hint_shown = true
		# 문구는 화면에 보이는 것의 일상어만 · 설계 용어(격벽·동기) 노출 금지(사용자 2026-08-17).
		match _mid_gate_mode:
			"lever":
				_show_veil_subtitle(VeilDialogue.banded("게이트가 잠겨 있습니다. 근처 동력 레버를 찾으십시오.", "게이트가 잠겨 있어요. 근처 동력 레버를 찾으세요."), 3.2)
			"clear":
				_show_veil_subtitle(VeilDialogue.banded("잠긴 게이트입니다. 바닥에 노란 선으로 칠한 구역, 그 안의 경비만 정리하면 열립니다.", "잠긴 게이트예요. 바닥에 노란 선으로 칠해 둔 구역, 그 안의 경비만 정리하면 열려요."), 3.6)
			"beam":
				_show_veil_subtitle(VeilDialogue.banded("게이트는 스캔 빔이 지날 때만 열립니다. 빔 뒤에 붙어 통과하십시오.", "게이트는 스캔 빔이 지나갈 때만 열려요. 빔을 뒤따라 통과하세요."), 3.6)
	if _mid_gate_mode == "beam" and _sweep_beam_node != null and is_instance_valid(_sweep_beam_node):
		var bx: float = float(_sweep_beam_node.get("_beam_x"))
		_set_mid_gate_pass(bx > _mid_gate_x + 40.0 and bx < _mid_gate_x + 940.0)
	# clear 모드 주기 재검 · 경비가 죽는 순간 외에도(게이트 너머로 배회 등) 개방 조건을 놓치지
	# 않게 매 tick 재확인(경비 ≤5라 비용 무시 가능 · 소프트락 안전판 ⓒ).
	if _mid_gate_mode == "clear" and _mid_gate_inited and not _mid_gate_opened:
		_on_mid_gate_guard_down()

# 차폐 니치 — 빔의 세이프존(비솔리드, 자유 이동). 통로 뒷벽의 오목한 차폐 벽감 + 발밑 사각 마킹.
# 세이프 판정은 SweepBeam이 x밴드로 하고, 여기선 "여기 서면 스캔 사각"을 읽히게 하는 시각만.
func _build_cover_niches() -> void:
	var niches: Array = _map_data.get("cover_niches", [])
	if niches.is_empty():
		return
	var s_half: float = float(_map_data.get("niche_half", 90.0))
	# 숨기 존 등록(2026-08-22 능동 숨기) — _tick_hide_zone이 매 틱 플레이어 밴드 판정에 쓴다.
	_hide_niche_xs = niches.duplicate()
	_hide_niche_half = s_half
	for nx_raw in niches:
		var nx: float = float(nx_raw)
		# 뒷벽 차폐 벽감(오목) — 어두운 리세스. 안쪽으로 갈수록 어두운 2겹 = "뒤로 숨는 깊이".
		var recess := ColorRect.new()
		recess.color = Color(0.08, 0.10, 0.12, 0.92)
		recess.position = Vector2(nx - s_half, GROUND_Y - 210.0)
		recess.size = Vector2(s_half * 2.0, 210.0)
		recess.z_index = -8
		add_child(recess)
		var recess_core := ColorRect.new()
		recess_core.color = Color(0.04, 0.05, 0.07, 0.9)
		recess_core.position = Vector2(nx - s_half * 0.62, GROUND_Y - 196.0)
		recess_core.size = Vector2(s_half * 1.24, 196.0)
		recess_core.z_index = -8
		add_child(recess_core)
		# 세이프존 경계 기둥(양옆) — 차폐 프레임.
		for sx in [nx - s_half, nx + s_half]:
			var post := ColorRect.new()
			post.color = Color(0.17, 0.19, 0.23)
			post.position = Vector2(float(sx) - 3.0, GROUND_Y - 210.0)
			post.size = Vector2(6.0, 210.0)
			post.z_index = -2
			add_child(post)
		# 발밑 세이프 밴드 마킹(시안) — "여기 서면 스캔 사각". 대사가 "파란 띠가 칠해진 대피 칸"을
		# 가리키므로 실제로 읽히는 밝기로(종전 alpha 0.22는 스크린샷에서 식별 불가, 2026-08-22).
		var floor_mark := ColorRect.new()
		floor_mark.color = Color(0.35, 0.85, 0.95, 0.55)
		floor_mark.position = Vector2(nx - s_half, GROUND_Y - 7.0)
		floor_mark.size = Vector2(s_half * 2.0, 7.0)
		floor_mark.z_index = -1
		add_child(floor_mark)
		var floor_core := ColorRect.new()
		floor_core.color = Color(0.62, 0.95, 1.0, 0.75)
		floor_core.position = Vector2(nx - s_half, GROUND_Y - 7.0)
		floor_core.size = Vector2(s_half * 2.0, 2.0)
		floor_core.z_index = -1
		add_child(floor_core)
		# 상단 차폐 라벨 아이콘 — 사각(감시 사각) 표식.
		var cap := ColorRect.new()
		cap.color = Color(0.30, 0.72, 0.82, 0.5)
		cap.position = Vector2(nx - 10.0, GROUND_Y - 206.0)
		cap.size = Vector2(20.0, 6.0)
		cap.z_index = -1
		add_child(cap)

func _build_platforms_fallback() -> void:
	# 안전한 일자형 폴백 (튜토리얼/플레이그라운드용)
	var entries: Array = [
		{"pos": Vector2(700, 510), "w": 220.0},
		{"pos": Vector2(1100, 480), "w": 220.0},
		{"pos": Vector2(1500, 440), "w": 220.0},
		{"pos": Vector2(1900, 480), "w": 220.0},
		{"pos": Vector2(2400, 510), "w": 220.0},
		{"pos": Vector2(2900, 470), "w": 220.0},
		{"pos": Vector2(3400, 440), "w": 220.0},
		{"pos": Vector2(3900, 480), "w": 220.0},
	]
	for entry in entries:
		var d: Dictionary = entry
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		_build_platform(p.x, p.y, float(d.get("w", 220.0)))

func _build_decorations() -> void:
	# 천장 라이트 (드문드문)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 31 + 5
	var x: float = 200.0
	while x < STAGE_LENGTH:
		var beam := ColorRect.new()
		beam.color = Color(0.92, 0.88, 0.55, 0.06)
		beam.position = Vector2(x - 30.0, -200.0)
		beam.size = Vector2(60.0, 700.0)
		beam.z_index = -8
		add_child(beam)
		x += rng.randf_range(420.0, 720.0)

func _build_hazards() -> void:
	# §4 거짓 렌더 — 위장 함정(가시를 안전한 바닥으로 렌더 강탈). 일반 spikes와 독립이라 먼저.
	_build_disguised_spikes()
	# 가시 함정 — MapData가 명시한 (x, y) 좌표에 배치. y가 없으면 GROUND_Y 폴백.
	var spikes: Array = _map_data.get("spikes", [])
	if not spikes.is_empty():
		for entry in spikes:
			var d: Dictionary = entry
			var sx: float = float(d.get("x", 0.0))
			var sy: float = float(d.get("y", GROUND_Y - 6.0))
			var sw: float = float(d.get("w", 90.0))
			var sd: int = int(d.get("dmg", 1))
			_build_spike(sx, sw, sy, sd)
		return
	# 폴백 (디버그/플레이그라운드)
	# 세그먼트가 명시 차단 가능 · 지하철 방2(선로)는 자동 가시가 벽감 세이프존 옆에 깔려
	# 열차 회피 동선을 오염시킨다(2026-08-16 스크린샷 검증에서 발견).
	if bool(_map_data.get("no_spike_fallback", false)):
		return
	if not "함정" in GameState.current_route_tags:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 137 + 11 + hash(GameState.current_route_id)
	var count: int = 2 if GameState.current_stage <= 1 else 3
	for i in count:
		var base_x: float = lerp(900.0, STAGE_LENGTH - 600.0, float(i + 1) / float(count + 1))
		var x: float = base_x + rng.randf_range(-80.0, 80.0)
		_build_spike(x, 90.0, GROUND_Y - 6.0)

# 발사 함정 — MapData 레이아웃의 "traps" 배열에서 생성. 각 항목:
#   {x, y, dir("left"/"right"/"up"/"down"), interval, phase, telegraph(선택), dmg(선택)}
func _build_traps() -> void:
	for entry in _map_data.get("traps", []):
		var d: Dictionary = entry
		var trap := BulletTrap.new()
		trap.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		trap.damage = int(d.get("dmg", 1))
		trap.burst = int(d.get("burst", 3))
		add_child(trap)
		trap.setup(_dir_from_str(str(d.get("dir", "left"))), float(d.get("interval", 1.6)),
			float(d.get("phase", 0.0)), float(d.get("telegraph", 0.5)),
			str(d.get("mode", "periodic")), str(d.get("trigger_id", "")))
		_traps_present = true
	# 레이저 탐지선 — 가로지르면 같은 trigger_id 포탑 발동(포탑과 분리 배치).
	for entry in _map_data.get("tripwires", []):
		var d: Dictionary = entry
		var tw := LaserTripwire.new()
		tw.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		add_child(tw)
		tw.setup(_dir_from_str(str(d.get("dir", "down"))), float(d.get("len", 240.0)),
			str(d.get("trigger_id", "")), float(d.get("cooldown", 2.2)))
		_traps_present = true
	# 증기 분출구(냉각 시설) — 바닥에서 위로 h만큼 주기 분출. phase 생략 시 x로 위상 분산(엇갈림).
	for entry in _map_data.get("steam_vents", []):
		var sv: Dictionary = entry
		var vent := SteamVent.new()
		var vx: float = float(sv.get("x", 0.0))
		vent.position = Vector2(vx, GROUND_Y)
		vent.height = float(sv.get("h", 260.0))
		vent.phase = float(sv.get("phase", fmod(vx * 0.0011, 1.0)))
		add_child(vent)
	# (증기 분출구는 자체 텔레그래프라 _traps_present "못 잡는 함정" 경고는 불필요.)

func _dir_from_str(s: String) -> Vector2:
	match s:
		"right": return Vector2.RIGHT
		"up":    return Vector2.UP
		"down":  return Vector2.DOWN
		_:       return Vector2.LEFT

func _build_spike(center_x: float, w: float, base_y: float = -1.0, dmg: int = 1) -> void:
	# base_y는 가시 베이스의 y. 가시는 base_y 위로 20px 솟음.
	# 베이스를 미니 플랫폼 형태로 — 3단 패널 + 외곽선 + 모서리 위험 캡.
	# 가시는 항상 바닥/플랫폼 위에 박힌 형태로만 등장(매다는 컨셉 폐지).
	# dmg: 가시 데미지(default 1, sewers 우측 등 강조 함정은 2).
	if base_y < 0.0:
		base_y = GROUND_Y - 6.0
	var x_start: float = center_x - w * 0.5
	var x_end: float = center_x + w * 0.5
	# 베이스 — 다른 플랫폼과 같은 3단 패널(본체/상단/그림자) + 외곽선 + 모서리 캡.
	# 좌우 5px씩 확장으로 외형이 단단히 박힌 듯.
	var base_x: float = x_start - 5.0
	var base_w: float = w + 10.0
	var base_top: float = base_y - 3.0
	var dmg_color: Color = Color(0.85, 0.30, 0.30) if dmg < 2 else Color(1.0, 0.45, 0.20)
	# (0) dmg 2 위험 광채 — 베이스 뒤로 옅게
	if dmg >= 2:
		var glow := ColorRect.new()
		glow.color = Color(1.0, 0.45, 0.20, 0.18)
		glow.position = Vector2(base_x - 4.0, base_top - 6.0)
		glow.size = Vector2(base_w + 8.0, 24.0)
		add_child(glow)
	# (2) 본체 — 어두운 금속, 12px
	var body := ColorRect.new()
	body.color = Color(0.14, 0.16, 0.20)
	body.position = Vector2(base_x, base_top + 2.0)
	body.size = Vector2(base_w, 10.0)
	add_child(body)
	# (3) 상단 위험 띠 — 2px, dmg 색
	var top_band := ColorRect.new()
	top_band.color = dmg_color
	top_band.position = Vector2(base_x, base_top)
	top_band.size = Vector2(base_w, 2.0)
	add_child(top_band)
	# (4) 하단 그림자 — 2px
	var bot := ColorRect.new()
	bot.color = Color(0.04, 0.05, 0.07, 0.95)
	bot.position = Vector2(base_x, base_top + 12.0)
	bot.size = Vector2(base_w, 2.0)
	add_child(bot)
	# (5) 외곽선 — 다른 플랫폼과 동일 톤
	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(base_x, base_top),
		Vector2(base_x + base_w, base_top),
		Vector2(base_x + base_w, base_top + 14.0),
		Vector2(base_x, base_top + 14.0),
	])
	outline.closed = true
	outline.width = 0.8
	outline.default_color = Color(0.02, 0.03, 0.04, 0.65)
	outline.antialiased = true
	add_child(outline)
	# (6) 좌우 모서리 캡 — 위험 색으로 강조
	var cap_l := ColorRect.new()
	cap_l.color = dmg_color
	cap_l.position = Vector2(base_x - 2.0, base_top + 3.0)
	cap_l.size = Vector2(3.0, 5.0)
	add_child(cap_l)
	var cap_r := ColorRect.new()
	cap_r.color = dmg_color
	cap_r.position = Vector2(base_x + base_w - 1.0, base_top + 3.0)
	cap_r.size = Vector2(3.0, 5.0)
	add_child(cap_r)
	# (7) 가시 — 그림자(좌측 어두운 절반) + 본체. 베이스 안으로 살짝 묻힘.
	var spike_color: Color = Color(0.95, 0.30, 0.30) if dmg < 2 else Color(1.0, 0.40, 0.20)
	var spike_dark: Color = Color(0.55, 0.16, 0.18) if dmg < 2 else Color(0.62, 0.22, 0.12)
	for sx in range(int(x_start) + 12, int(x_end), 24):
		var fx: float = float(sx)
		var shadow := Polygon2D.new()
		shadow.color = spike_dark
		shadow.polygon = PackedVector2Array([
			Vector2(fx, base_top + 1.0),
			Vector2(fx + 6.0, base_top + 1.0),
			Vector2(fx + 6.0, base_top - 20.0),
		])
		add_child(shadow)
		var spike := Polygon2D.new()
		spike.color = spike_color
		spike.polygon = PackedVector2Array([
			Vector2(fx, base_top + 1.0),
			Vector2(fx + 12.0, base_top + 1.0),
			Vector2(fx + 6.0, base_top - 20.0),
		])
		add_child(spike)
	var zone := Area2D.new()
	zone.collision_layer = 0
	zone.collision_mask = 2  # 플레이어
	# 판정 = 보이는 가시와 일치(2026-08-21 사용자 "블랙아웃이 가시 판정 때문에 끊긴다"):
	# 종전 존(w × 36 · 중심 base_y-12)은 가시 끝(base_y-23)보다 7px 위 + 가시 없는 좌우
	# 베이스 여백까지 덮었다. → 세로는 끝높이까지만(24 · 중심 base_y-10), 가로는 14px 축소.
	zone.position = Vector2(center_x, base_y - 10.0)
	zone.set_meta("damage", dmg)
	add_child(zone)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(maxf(w - 14.0, 20.0), 24.0)
	col.shape = shape
	zone.add_child(col)
	zone.body_entered.connect(_on_spike_touched.bind(zone))

func _on_spike_touched(body: Node, zone: Area2D) -> void:
	if body == player and body.has_method("take_hit"):
		var d: int = 1
		if is_instance_valid(zone):
			d = int(zone.get_meta("damage", 1))
		SfxPlayer.play("spike_hit")
		body.take_hit(d)
		# §4 위장 함정 — 밟는 순간 거짓이 드러난다(하드 페널티 + 거짓 노출).
		if is_instance_valid(zone) and zone.has_meta("disguised_ref"):
			var ds: Node = zone.get_meta("disguised_ref")
			if is_instance_valid(ds) and ds.has_method("reveal"):
				ds.call("reveal")

# 라이벌 기억(축 C) — 거짓 렌더 재배열: 완주 홀수 회차엔 대체 슬롯(_alt)을 쓴다.
# "네가 외운 자리에는 없다." 대체 슬롯이 정의된 맵만 해당(§4.1 공정 배치 근거가 있는 곳만).
func _deceit_slots(key: String) -> Array:
	if GameState.playthrough_count % 2 == 1 and _map_data.has(key + "_alt"):
		return _map_data.get(key + "_alt", [])
	return _map_data.get(key, [])

# §4 거짓 렌더 — 위장 함정 빌더. deceit_spikes: [{x, y?, w?, dmg?}]. 진짜 가시(시각+데미지 zone)를
# _build_spike로 만든 뒤 시각만 숨기고(DisguisedSpike), 항상 켜진 지직거림 tell + 근접/밟기 리빌.
func _build_disguised_spikes() -> void:
	var arr: Array = _deceit_slots("deceit_spikes")
	if arr.is_empty() or GameState.story_mode:
		return   # 스토리 모드는 단순화 — 거짓 렌더 제외(deceits와 동형)
	for entry in arr:
		var d: Dictionary = entry
		_spawn_disguised_spike(float(d.get("x", 0.0)), float(d.get("y", GROUND_Y - 6.0)),
			float(d.get("w", 120.0)), int(d.get("dmg", 2)))   # 하드 페널티 기본 dmg2(§4.1)

# 위장 함정 1개 스폰 — 맵 빌드(deceit_spikes)와 런타임 소환(14-1 P2 빙의) 공용.
# 반환 [zone(Area2D), ds(DisguisedSpike)] — 런타임 소환자는 이걸로 종료 시 해제한다.
func _spawn_disguised_spike(sx: float, sy: float, sw: float, sd: int) -> Array:
	# 진짜 가시를 만들고, _build_spike가 self에 붙인 자식(시각 + Area2D zone)을 캡처.
	var before: int = get_child_count()
	_build_spike(sx, sw, sy, sd)
	var visuals: Array = []
	var zone: Area2D = null
	for i in range(before, get_child_count()):
		var n: Node = get_child(i)
		if n is Area2D:
			zone = n
		else:
			visuals.append(n)
	# 위장 컨트롤러 — 시각 숨김 + tell + 리빌.
	var ds := DisguisedSpike.new()
	add_child(ds)
	ds.position = Vector2(sx, sy)   # Stage는 원점이라 position=global
	ds.setup(visuals, sw)
	# 밟는 순간 정체 노출 — zone에 컨트롤러 참조.
	if zone != null:
		zone.set_meta("disguised_ref", ds)
	return [zone, ds]

# 토글 가능한 가시 — 시각 + 콜리전을 그룹으로 묶어 한 번에 on/off.
# datacenter 측면 레버에서 메인 통로 가시를 끄는 데 사용.
# 반환된 Node2D를 _set_spike_group_active(node, false)로 끄면 모든 시각이 어두워지고
# 콜리전이 disabled 된다.
func _spawn_toggleable_spike(center_x: float, w: float, base_y: float, dmg: int = 1) -> Node2D:
	var group := Node2D.new()
	group.name = "ToggleableSpike"
	add_child(group)
	# 마커 위치 — 시각/zone은 절대좌표로 add_child하던 _build_spike와 다르게 group 자식으로 이전.
	var children_before: Array = get_children()
	_build_spike(center_x, w, base_y, dmg)
	# _build_spike가 self에 자식으로 붙인 노드들을 group으로 reparent.
	# 마지막 N개 (children_before 이후)가 새로 추가된 것들.
	var current: Array = get_children()
	var added: Array = []
	for i in range(children_before.size(), current.size()):
		added.append(current[i])
	for n in added:
		remove_child(n)
		group.add_child(n)
	# 그룹 자식 중 Area2D를 zone meta로 보관 (toggle 시 disabled 적용).
	for n in group.get_children():
		if n is Area2D:
			group.set_meta("zone", n)
			break
	group.set_meta("active", true)
	return group

func _set_spike_group_active(group: Node2D, active: bool) -> void:
	if group == null or not is_instance_valid(group):
		return
	group.set_meta("active", active)
	# 시각 — 활성=원래 색, 비활성=어두운 회색 페이드.
	var tw := group.create_tween()
	tw.tween_property(group, "modulate", Color(1, 1, 1, 1) if active else Color(0.30, 0.30, 0.32, 0.45), 0.45)
	# 콜리전 — Area2D 자식의 CollisionShape2D를 disabled 토글.
	var zone: Area2D = group.get_meta("zone", null)
	if zone != null and is_instance_valid(zone):
		for c in zone.get_children():
			if c is CollisionShape2D:
				(c as CollisionShape2D).set_deferred("disabled", not active)

func _build_route_ambience() -> void:
	# 루트별 시각 분위기 — 콜리전 없는 ColorRect/Polygon overlay만 사용.
	# 방 체인 세그먼트는 layout의 "ambience" 키가 라우트 매핑보다 우선(방마다 배경이 다르다).
	match str(_map_data.get("ambience", "")):
		"demo_street":
			_ambience_demolition()
			_apply_act_rival_tint()
			return
		"demo_yard":
			_ambience_demo_yard()
			_apply_act_rival_tint()
			return
		"relay_yard":
			_ambience_relay_yard()
			_apply_act_rival_tint()
			return
		"relay_hall":
			_ambience_relay_hall()
			_apply_act_rival_tint()
			return
		"relay_mast":
			_ambience_relay_mast()
			_apply_act_rival_tint()
			return
		"substation_switchyard":
			_ambience_substation_switchyard()
			_apply_act_rival_tint()
			return
		"substation_yard":
			_ambience_electrical("고압 위험 · 변전 구역")
			_apply_act_rival_tint()
			return
		"substation_control":
			_ambience_substation_control()
			_apply_act_rival_tint()
			return
		"control_anteroom":
			_ambience_control_anteroom()
			_apply_act_rival_tint()
			return
		"control_main":
			_ambience_control_room()
			_apply_act_rival_tint()
			return
		"control_checkgate":
			_ambience_control_checkgate()
			_apply_act_rival_tint()
			return
		"server_stacks":
			_ambience_server_stacks()
			_apply_act_rival_tint()
			return
		"server_main":
			_ambience_server_hall()
			_apply_act_rival_tint()
			return
		"server_switchroom":
			_ambience_server_switchroom()
			_apply_act_rival_tint()
			return
		"warehouse_dock":
			_ambience_warehouse_dock()
			_apply_act_rival_tint()
			return
		"warehouse_racks":
			_ambience_warehouse("물류 창고 · 보관 랙")
			_apply_act_rival_tint()
			return
		"warehouse_shipping":
			_ambience_warehouse_shipping()
			_apply_act_rival_tint()
			return
		"cooling_intake":
			_ambience_cooling_intake()
			_apply_act_rival_tint()
			return
		"cooling_core":
			_ambience_cooling()
			_apply_act_rival_tint()
			return
		"cooling_exhaust":
			_ambience_cooling_exhaust()
			_apply_act_rival_tint()
			return
		"collapse_shaft":
			_ambience_collapse_shaft()
			_escape_tone_destroy()
			_apply_act_rival_tint()
			return
		"collapse_mezz":
			_ambience_collapse_mezz()
			_escape_tone_destroy()
			_apply_act_rival_tint()
			return
		"subway_platform":
			_ambience_subway_platform()
			_apply_act_rival_tint()
			return
		"subway_tracks":
			_ambience_subway_tracks()
			_apply_act_rival_tint()
			return
		"subway_transfer":
			_ambience_subway_transfer()
			_apply_act_rival_tint()
			return
		"sewer_inflow":
			_ambience_sewer_inflow()
			_apply_act_rival_tint()
			return
		"sewer_junction":
			_ambience_sewer_junction()
			_apply_act_rival_tint()
			return
		"condenser_inlet":
			_ambience_condenser_inlet()
			_apply_act_rival_tint()
			return
		"condenser_hall":
			_ambience_pump_station("응축기 구역 · 냉각수")
			_apply_act_rival_tint()
			return
		"condenser_basin":
			_ambience_condenser_basin()
			_apply_act_rival_tint()
			return
		"gauntlet_entry":
			_ambience_gauntlet_entry()
			_apply_act_rival_tint()
			return
		"gauntlet_main":
			_ambience_gauntlet()
			_apply_act_rival_tint()
			return
		"gauntlet_grid":
			_ambience_gauntlet_grid()
			_apply_act_rival_tint()
			return
		"freight_yard":
			_ambience_warehouse("화물 구역 · 리프트")
			_apply_act_rival_tint()
			return
		"freight_relay":
			_ambience_freight_relay()
			_apply_act_rival_tint()
			return
		"freight_gantry":
			_ambience_freight_gantry()
			_apply_act_rival_tint()
			return
		"carcover_row":
			_ambience_garage_props()
			_apply_act_rival_tint()
			return
		"carcover_yard":
			_ambience_carcover_yard()
			_apply_act_rival_tint()
			return
	match GameState.current_route_id:
		"route_sewers":
			_ambience_sewers()
		"route_rooftops":
			_ambience_rooftops()
		"route_lab":
			_ambience_lab()
		"route_back_alley":
			_ambience_back_alley()
		"route_subway":
			# 노선 체인 재설계(2026-08-16) 후 각 방의 ambience 키가 선점 · 이 분기는 안전망.
			_ambience_subway_platform()
		"route_cooling":
			_ambience_cooling()
		"route_watchtower":
			_ambience_watchtower()
		"route_ward":
			_ambience_ward()
		"route_datacenter":
			_ambience_datacenter()
		"route_escape":
			_ambience_escape()
		"route_escape_extract":
			_ambience_escape()
			_escape_tone_extract()
		"route_escape_destroy":
			_ambience_escape()
			_escape_tone_destroy()
		"route_escape_conceal":
			_ambience_escape()
			_escape_tone_conceal()
		"route_escape_leave":
			_ambience_escape()
			_escape_tone_leave()
		"route_hidden":
			_ambience_hidden()
		"route_parking_lot", "route_car_cover":
			_ambience_garage_props()
		"route_pump_station":
			_ambience_pump_pipes()
		"route_condenser":
			_ambience_pump_station("응축기 구역 · 냉각수")
		"route_substation":
			_ambience_electrical("고압 위험 · 변전 구역")
		"route_relay_station":
			_ambience_electrical("통신 중계 · 안테나 정렬")
		"route_warehouse":
			_ambience_warehouse("물류 창고 · 구역 D")
		"route_freight_lift":
			_ambience_warehouse("화물 구역 · 리프트")
		"route_server_hall":
			_ambience_server_hall()
		"route_control_corridor":
			_ambience_control_room()
		"route_checkpoint":
			_ambience_checkpoint()
		"route_demolition_zone":
			_ambience_demolition()
		"route_testing_grounds":
			_ambience_testing()
		"route_gauntlet":
			_ambience_gauntlet()
		"route_collapse":
			_ambience_collapse()
		"route_core_defense":
			_ambience_reactor()
		"route_scanner_sweep":
			_ambience_scanner()
		"route_holdout":
			_ambience_holdout()
		"route_core_recovery":
			_ambience_core_arena()
	_apply_act_rival_tint()

# ─── 막4/5 라이벌 침식 — 고유색(바이올렛 캐스트) + 가끔 화면 간섭 플래시 (act_identity §6·§7) ───
# 막4(추적)부터 라이벌이 렌더를 만지기 시작한다: 월드 전체에 옅은 바이올렛 캐스트(CanvasModulate —
# HUD·자막은 CanvasLayer라 무관) + 드물게 화면 간섭 밴드. 거짓-렌더 tell(대상 지정·붉은 혼합)과 달리
# 화면 전체·바이올렛 단독이라 구별된다. 막5(대면)는 캐스트·빈도 모두 강화. 막1~3은 깨끗(대비 좌표).
func _apply_act_rival_tint() -> void:
	if GameState.story_mode:
		return
	var act: int = GameState.act_for_stage(GameState.current_stage)
	if act < 3:   # 0-based: 3=막4, 4=막5
		return
	var final_act: bool = act >= 4
	var cast := CanvasModulate.new()
	cast.color = Color(0.99, 0.88, 1.0) if final_act else Color(1.0, 0.94, 1.0)
	add_child(cast)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	# 간섭 타이머 — Stage 자식(PAUSABLE)이라 일시정지 중 멈추고 씬 전환과 함께 정리된다.
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = randf_range(14.0, 24.0) if final_act else randf_range(22.0, 34.0)
	layer.add_child(timer)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(layer):
			return
		_rival_interference_flash(layer)
		timer.wait_time = randf_range(14.0, 24.0) if final_act else randf_range(22.0, 34.0)
	)
	timer.start()

# 얇은 바이올렛 가로 밴드 2~3개가 화면을 잠깐 스치는 간섭 플래시(화면 좌표 — 카메라 무관).
func _rival_interference_flash(layer: CanvasLayer) -> void:
	if not GameState.screen_fx_enabled:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var g := Control.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(g)
	for i in range(randi_range(2, 3)):
		var r := ColorRect.new()
		r.color = Color(0.72, 0.42, 1.0, randf_range(0.10, 0.20))
		r.position = Vector2(0.0, randf_range(0.0, vs.y))
		r.size = Vector2(vs.x, randf_range(3.0, 8.0))
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		g.add_child(r)
	var tw := g.create_tween()
	tw.tween_interval(0.14)
	tw.tween_property(g, "modulate:a", 0.0, 0.16)
	tw.tween_callback(g.queue_free)

# ─── 코어 관제홀(14-1 리워크 §2.1) · 복층 아레나 시그니처 배경 ───
# "방 전체가 라이벌이다"의 무대: 중앙 안쪽 벽의 **거대 코어 링**(14-2 코어의 원경 실루엣 ·
# 여기서 처음 보이고 14-2에서 대면) + 회전 관측 링 2겹 + 데이터 폭포 + 심발광 팔레트
# (어두운 바탕 + 시안/바이올렛 광원). 격벽 기둥은 원경(z -16)으로 밀고 주기 슬립(거짓 렌더 티)
# · 파괴 대상 오인 방지(리워크 진단 ③).
func _ambience_core_arena() -> void:
	var w: float = _world_size.x
	var h: float = _world_size.y
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 719 + 13
	# 뒷벽 · 심부 격납 톤. 상부는 더 어둡게(높이감), 지상층 밴드는 살짝 밝게.
	var wall := ColorRect.new()
	wall.color = Color(0.07, 0.055, 0.11)
	wall.position = Vector2(-200.0, -300.0)
	wall.size = Vector2(w + 400.0, h + 600.0)
	wall.z_index = -18
	add_child(wall)
	var top_shade := ColorRect.new()
	top_shade.color = Color(0.04, 0.03, 0.07)
	top_shade.position = Vector2(-200.0, -300.0)
	top_shade.size = Vector2(w + 400.0, 560.0)
	top_shade.z_index = -17
	add_child(top_shade)
	var floor_band := ColorRect.new()
	floor_band.color = Color(0.10, 0.08, 0.14)
	floor_band.position = Vector2(-200.0, GROUND_Y - 60.0)
	floor_band.size = Vector2(w + 400.0, h - GROUND_Y + 360.0)
	floor_band.z_index = -17
	add_child(floor_band)
	# 거대 코어 링 + 회전 관측 링 · 중앙 안쪽 벽(전용 스피너 노드가 회전·맥동을 그린다).
	var spinner := _CoreRingSpinner.new()
	spinner.position = Vector2(w * 0.5, 520.0)
	spinner.z_index = -15
	add_child(spinner)
	# 원경 격벽 기둥 · 얇고 어둡게, 주기 슬립(거짓 렌더 티: "이건 그림이다").
	for px in [220.0, 640.0, 1060.0, 1340.0, 1760.0, 2180.0]:
		var pillar := ColorRect.new()
		pillar.color = Color(0.11, 0.085, 0.16)
		pillar.position = Vector2(float(px) - 14.0, -100.0)
		pillar.size = Vector2(28.0, GROUND_Y + 100.0)
		pillar.z_index = -16
		add_child(pillar)
		for ny in [340.0, 760.0]:
			var notch := ColorRect.new()
			notch.color = Color(0.16, 0.12, 0.22)
			notch.position = Vector2(float(px) - 18.0, float(ny))
			notch.size = Vector2(36.0, 6.0)
			notch.z_index = -16
			add_child(notch)
		var ptw := pillar.create_tween()
		ptw.set_loops()
		ptw.tween_interval(rng.randf_range(2.2, 4.6))
		ptw.tween_property(pillar, "position:x", float(px) - 14.0 + 4.0, 0.06)
		ptw.tween_property(pillar, "position:x", float(px) - 14.0, 0.08)
	# 데이터 폭포 · 세로로 흘러내리는 문자열 스트립(시안/바이올렛 교대, 저알파).
	for i in 6:
		var cx: float = 180.0 + float(i) * 400.0 + rng.randf_range(-60.0, 60.0)
		for s in 2:
			var strip := ColorRect.new()
			var viol: bool = (i + s) % 2 == 0
			strip.color = Color(0.72, 0.42, 1.0, 0.13) if viol else Color(0.40, 0.90, 1.0, 0.13)
			strip.size = Vector2(3.0, rng.randf_range(70.0, 150.0))
			strip.position = Vector2(cx + float(s) * 8.0, -160.0)
			strip.z_index = -14
			add_child(strip)
			var stw := strip.create_tween()
			stw.set_loops()
			stw.tween_interval(rng.randf_range(0.0, 2.8))
			stw.tween_property(strip, "position:y", h + 60.0, rng.randf_range(3.4, 6.2)).from(-160.0)
	# 층 지지 스트럿 · 중층·데크 발판 아래 사선 버팀(구조가 "지어져 있다"는 감각).
	for entry in [[350.0, 1040.0], [1200.0, 1000.0], [2050.0, 1040.0], [450.0, 720.0], [1950.0, 720.0], [1200.0, 860.0]]:
		var e: Array = entry
		var strut := Polygon2D.new()
		strut.color = Color(0.13, 0.10, 0.19, 0.9)
		var bx: float = float(e[0])
		var by: float = float(e[1])
		strut.polygon = PackedVector2Array([
			Vector2(bx - 8.0, by), Vector2(bx + 8.0, by),
			Vector2(bx + 30.0, by + 120.0), Vector2(bx - 30.0, by + 120.0),
		])
		strut.z_index = -13
		add_child(strut)
	# 상단 관측 레일 · 데크 위 크레인 레일 한 줄(원경).
	var rail := ColorRect.new()
	rail.color = Color(0.14, 0.11, 0.20)
	rail.position = Vector2(120.0, 250.0)
	rail.size = Vector2(w - 240.0, 8.0)
	rail.z_index = -15
	add_child(rail)
	_add_lore_label(Vector2(300.0, GROUND_Y - 250.0), "코어 관제홀 · 최상위 권한 구역", Color(0.80, 0.58, 1.0, 0.45), 15)
	_add_lore_label(Vector2(float(int(w) - 780), 640.0), "OBSERVATION DECK", Color(0.40, 0.90, 1.0, 0.35), 13)

# 코어 링 스피너 · 거대 코어 글로우(느린 박동) + 원근 타원 관측 링 2겹(반대 방향 회전).
class _CoreRingSpinner extends Node2D:
	var _t: float = 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var pulse: float = 0.5 + 0.5 * sin(_t * 0.9)
		draw_circle(Vector2.ZERO, 150.0, Color(0.72, 0.42, 1.0, 0.05 + 0.03 * pulse))
		draw_circle(Vector2.ZERO, 100.0, Color(0.40, 0.90, 1.0, 0.06 + 0.03 * pulse))
		draw_circle(Vector2.ZERO, 48.0, Color(0.88, 0.78, 1.0, 0.10 + 0.05 * pulse))
		# 관측 링 1 · 시안, 원근 타원. 링 위 관측 노드 점 4개가 함께 돈다.
		draw_set_transform(Vector2.ZERO, _t * 0.22, Vector2(1.0, 0.34))
		draw_arc(Vector2.ZERO, 300.0, 0.0, TAU, 48, Color(0.40, 0.90, 1.0, 0.20), 2.5, true)
		for i in 4:
			var ang: float = TAU * float(i) / 4.0
			draw_circle(Vector2(cos(ang), sin(ang)) * 300.0, 7.0, Color(0.40, 0.90, 1.0, 0.45))
		# 관측 링 2 · 바이올렛, 반대 방향.
		draw_set_transform(Vector2.ZERO, -_t * 0.15, Vector2(1.0, 0.30))
		draw_arc(Vector2.ZERO, 380.0, 0.0, TAU, 56, Color(0.72, 0.42, 1.0, 0.17), 2.5, true)
		for i in 3:
			var ang2: float = TAU * float(i) / 3.0
			draw_circle(Vector2(cos(ang2), sin(ang2)) * 380.0, 6.0, Color(0.72, 0.42, 1.0, 0.4))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

# (구 수렴 통로 배경(_ambience_core_recovery)은 리워크로 삭제 · 아레나 배경이 대체.)

func _ambience_sewers() -> void:
	# 화면 가장자리 어두운 비네트 (CanvasLayer 위에 띄움) + 바닥 옅은 안개
	var fog := ColorRect.new()
	fog.color = Color(0.25, 0.45, 0.40, 0.10)
	fog.position = Vector2(-200, GROUND_Y - 60.0)
	fog.size = Vector2(STAGE_LENGTH + 400.0, 80.0)
	fog.z_index = -2
	add_child(fog)
	var vignette := CanvasLayer.new()
	vignette.layer = 1
	add_child(vignette)
	for side in [0, 1]:  # 0=좌, 1=우 어두운 띠 — 화면 가장자리에 앵커(화면비 무관)
		var v := ColorRect.new()
		v.color = Color(0, 0, 0, 0.45)
		if side == 0:
			v.set_anchors_preset(Control.PRESET_LEFT_WIDE)
			v.offset_right = 180.0
		else:
			v.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
			v.offset_left = -180.0
		vignette.add_child(v)

# ─── 옛 배수로 방1 · 유입 수로(HORIZONTAL) 시그니처 배경 ───────────
# 수평 모티프만(수직 스트라이프 금지 규칙): 대구경 배관 2줄 + 벽의 물때 자국(과거 수위의
# 디제시스 힌트 = 만수위 예고) + 천장 그레이팅 슬릿. 안개·비네트는 하수도 공통 톤 재사용.
func _ambience_sewer_inflow() -> void:
	_ambience_sewers()
	var w: float = STAGE_LENGTH
	# 벽면 대구경 배관 · 가로 2줄(위쪽 벽).
	for entry in [[210.0, 18.0], [252.0, 12.0]]:
		var e: Array = entry
		var pipe := ColorRect.new()
		pipe.color = Color(0.14, 0.19, 0.18)
		pipe.position = Vector2(-200.0, float(e[0]))
		pipe.size = Vector2(w + 400.0, float(e[1]))
		pipe.z_index = -9
		add_child(pipe)
		var glint := ColorRect.new()
		glint.color = Color(0.35, 0.55, 0.50, 0.25)
		glint.position = Vector2(-200.0, float(e[0]) + 2.0)
		glint.size = Vector2(w + 400.0, 2.0)
		glint.z_index = -8
		add_child(glint)
	# 물때 자국 · 만수위(530)·중간 수위 높이의 어두운 가로 밴드 · "여기까지 찼었다".
	for my in [530.0, 566.0]:
		var mark := ColorRect.new()
		mark.color = Color(0.10, 0.16, 0.14, 0.55)
		mark.position = Vector2(-200.0, float(my))
		mark.size = Vector2(w + 400.0, 4.0)
		mark.z_index = -7
		add_child(mark)
	# 천장 그레이팅 슬릿 · 가로 대시 열(위에서 새는 빛) + 아래로 새는 빛 기둥.
	var gx: float = 300.0
	while gx < w:
		var slit := ColorRect.new()
		slit.color = Color(0.55, 0.75, 0.70, 0.16)
		slit.position = Vector2(gx, 96.0)
		slit.size = Vector2(90.0, 5.0)
		slit.z_index = -9
		add_child(slit)
		_add_light_cone(gx + 45.0, 101.0, 90.0, 170.0, 300.0, Color(0.55, 0.80, 0.72, 0.05), -9)
		gx += 480.0
	_add_lore_label(Vector2(300.0, 150.0), "구 배수 간선 · 펌프 가동 중", Color(0.55, 0.75, 0.70, 0.5), 14)

# ─── 옛 배수로 방2 · 침수 정션(VERTICAL_DOWN) 시그니처 배경 ───────────
# 기존 하수도 톤 + 만수위 자국 링(하강 중 "여기부터 잠긴다"가 벽에 보임) + 하단 펌프 실루엣.
func _ambience_sewer_junction() -> void:
	_ambience_sewers()
	# 만수위 자국 · high_y(1520) 높이의 벽 좌우 가로 밴드.
	for side_x in [0.0, 1180.0]:
		var mark := ColorRect.new()
		mark.color = Color(0.10, 0.16, 0.14, 0.6)
		mark.position = Vector2(float(side_x), 1520.0)
		mark.size = Vector2(100.0, 5.0)
		mark.z_index = -7
		add_child(mark)
	# 하단 펌프 실루엣 · 바닥 곁 낮은 기계(수평 실루엣 + 완만 맥동 램프).
	var body := ColorRect.new()
	body.color = Color(0.12, 0.15, 0.14)
	body.position = Vector2(80.0, 2190.0)
	body.size = Vector2(180.0, 60.0)
	body.z_index = -8
	add_child(body)
	var lamp := ColorRect.new()
	lamp.color = Color(0.45, 0.75, 0.65, 0.7)
	lamp.position = Vector2(96.0, 2202.0)
	lamp.size = Vector2(10.0, 10.0)
	lamp.z_index = -7
	add_child(lamp)
	var tw := lamp.create_tween()
	tw.set_loops()
	tw.tween_property(lamp, "modulate:a", 0.45, 1.4)
	tw.tween_property(lamp, "modulate:a", 1.0, 1.4)
	_add_lore_label(Vector2(430.0, 1470.0), "정션 P-3 · 만수위 주의", Color(0.55, 0.75, 0.70, 0.5), 14)

func _ambience_rooftops() -> void:
	# 별 점 + 멀리 도시 실루엣은 _build_background의 기둥이 이미 함
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 53 + 19
	for i in 60:
		var s := ColorRect.new()
		s.color = Color(0.85, 0.92, 1.0, rng.randf_range(0.3, 0.8))
		s.size = Vector2(2, 2)
		s.position = Vector2(rng.randf_range(-100.0, STAGE_LENGTH + 100.0), rng.randf_range(-220.0, 100.0))
		s.z_index = -18
		add_child(s)

func _ambience_lab() -> void:
	# 격자 라인 — 수직선이 일정 간격으로
	var x: float = 200.0
	while x < STAGE_LENGTH:
		var line := ColorRect.new()
		line.color = Color(0.55, 0.85, 0.95, 0.08)
		line.position = Vector2(x, -200.0)
		line.size = Vector2(1.0, 800.0)
		line.z_index = -10
		add_child(line)
		x += 120.0
	# 배경 텍스트 라벨은 정신 사납다는 사용자 피드백으로 제거 — 격자 라인 ambience만 유지.

func _ambience_back_alley() -> void:
	# 노란 가로등 — 띄엄띄엄
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 71 + 3
	var x: float = 250.0
	while x < STAGE_LENGTH:
		var lamp := ColorRect.new()
		lamp.color = Color(0.95, 0.78, 0.35, 0.22)
		lamp.position = Vector2(x - 40.0, -100.0)
		lamp.size = Vector2(80.0, 700.0)
		lamp.z_index = -7
		add_child(lamp)
		x += rng.randf_range(540.0, 820.0)
	# 그래피티 — 외곽 시작 지점 벽에 코드명 한 줄. 계속 등장하는 PROJECT VEIL의 첫 등장.
	_add_lore_label(Vector2(1700.0, GROUND_Y - 320.0), "PROJECT VEIL\n시험 단계", Color(0.95, 0.78, 0.35, 0.50), 14)

# (구 _ambience_subway는 노선 체인 재설계로 삭제 · 표지판 두 종은 방1/방2 배경으로 이주.)

# ─── 폐쇄 지하철 방1 · 승강장(HORIZONTAL) 시그니처 배경 ───────────
# 폐역 승강장: 형광등 + 스크린도어 잔해 프레임 + 노선도 패널 + 벤치. SILO-7 표지판은 여기로.
func _ambience_subway_platform() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 89 + 7
	var x: float = 300.0
	while x < w:
		var tube := ColorRect.new()
		tube.color = Color(0.85, 0.92, 1.0, 0.65)
		tube.position = Vector2(x - 60.0, -180.0)
		tube.size = Vector2(120.0, 4.0)
		tube.z_index = -6
		add_child(tube)
		if rng.randf() < 0.4:
			var tw := tube.create_tween()
			tw.set_loops()
			tw.tween_property(tube, "modulate:a", 0.15, rng.randf_range(0.05, 0.15))
			tw.tween_property(tube, "modulate:a", 1.0, rng.randf_range(0.4, 1.2))
		_add_light_cone(x, -174.0, 120.0, 280.0, 360.0, Color(0.85, 0.92, 1.0, 0.05), -10)
		x += rng.randf_range(380.0, 620.0)
	# 승강장 안전선 · 노란 점선 띠(수평 모티프). 스크린도어 기둥 쌍은 제거 ·
	# 수직 스트라이프 반복 금지(known_issues, 사용자 2026-08-17 "그놈의 기둥") +
	# 솔리드 잔해와 겹쳐 뭐가 총알을 막는지 안 읽히던 문제.
	var edge_line := ColorRect.new()
	edge_line.color = Color(0.85, 0.72, 0.25, 0.45)
	edge_line.position = Vector2(0.0, GROUND_Y - 4.0)
	edge_line.size = Vector2(w, 2.0)
	edge_line.z_index = -6
	add_child(edge_line)
	var dx: float = 40.0
	while dx < w:
		var dash := ColorRect.new()
		dash.color = Color(0.85, 0.72, 0.25, 0.55)
		dash.position = Vector2(dx, GROUND_Y - 12.0)
		dash.size = Vector2(34.0, 6.0)
		dash.z_index = -6
		add_child(dash)
		dx += 110.0
	# 노선도 패널 · 도시의 흔적(두 노선 색 라인).
	var panel := ColorRect.new()
	panel.color = Color(0.88, 0.90, 0.94, 0.85)
	panel.position = Vector2(240.0, 200.0)
	panel.size = Vector2(150.0, 88.0)
	panel.z_index = -8
	add_child(panel)
	for entry in [[Color(0.20, 0.55, 0.85), 228.0], [Color(0.85, 0.45, 0.20), 254.0]]:
		var e: Array = entry
		var ln := ColorRect.new()
		ln.color = e[0]
		ln.position = Vector2(252.0, float(e[1]))
		ln.size = Vector2(126.0, 6.0)
		ln.z_index = -7
		add_child(ln)
	# 벤치 실루엣.
	for bx in [800.0, 1550.0]:
		var seat := ColorRect.new()
		seat.color = Color(0.14, 0.15, 0.18)
		seat.position = Vector2(float(bx), GROUND_Y - 34.0)
		seat.size = Vector2(120.0, 12.0)
		seat.z_index = -8
		add_child(seat)
		for lx in [bx + 8.0, bx + 104.0]:
			var leg := ColorRect.new()
			leg.color = Color(0.12, 0.13, 0.16)
			leg.position = Vector2(float(lx), GROUND_Y - 22.0)
			leg.size = Vector2(8.0, 22.0)
			leg.z_index = -8
			add_child(leg)
	_add_lore_label(Vector2(430.0, 176.0), "SILO-7  접근 통로\n폐쇄: 2025.11", Color(0.65, 0.72, 0.85, 0.55), 14)
	_add_lore_label(Vector2(float(int(STAGE_LENGTH) - 500), GROUND_Y - 260.0), "선로 방면 →", Color(0.65, 0.72, 0.85, 0.5), 14)

# ─── 폐쇄 지하철 방2 · 선로(HORIZONTAL) 시그니처 배경 ───────────
# 살아 있는 선로: 침목 + 레일 + 낮은 천장 + 벽면 케이블 트레이(전부 수평 모티프 ·
# 아치 기둥은 수직 스트라이프 반복이라 제거, known_issues 2026-08-17).
# 신호등은 TrainHazard가 관리(상태 연동).
func _ambience_subway_tracks() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 97 + 5
	# 레일 2줄 · 바닥 표면 바로 아래.
	for ry in [GROUND_Y + 6.0, GROUND_Y + 20.0]:
		var rail := ColorRect.new()
		rail.color = Color(0.42, 0.45, 0.52, 0.9)
		rail.position = Vector2(-200.0, float(ry))
		rail.size = Vector2(w + 400.0, 4.0)
		rail.z_index = -4
		add_child(rail)
	# 침목 · 가로 반복.
	var tx: float = -100.0
	while tx < w + 100.0:
		var tie := ColorRect.new()
		tie.color = Color(0.16, 0.14, 0.12)
		tie.position = Vector2(tx, GROUND_Y + 2.0)
		tie.size = Vector2(16.0, 26.0)
		tie.z_index = -5
		add_child(tie)
		tx += 90.0
	# 낮은 터널 천장 · 승강장(방1)보다 눌린 단면 · 방끼리 실루엣이 달라야 한다(사용자 2026-08-17
	# "다 방이 똑같이 생긴 느낌"). 시각 전용 밴드(z -12, 동선 무간섭).
	var low_ceil := ColorRect.new()
	low_ceil.color = Color(0.07, 0.08, 0.10)
	low_ceil.position = Vector2(-200.0, -92.0)
	low_ceil.size = Vector2(w + 400.0, 152.0)
	low_ceil.z_index = -12
	add_child(low_ceil)
	var low_edge := ColorRect.new()
	low_edge.color = Color(0.9, 0.45, 0.25, 0.20)
	low_edge.position = Vector2(-200.0, 60.0)
	low_edge.size = Vector2(w + 400.0, 3.0)
	low_edge.z_index = -11
	add_child(low_edge)
	# 벽면 케이블 트레이 · 터널 내벽을 따라 달리는 가로 배관 2줄.
	for cy in [150.0, 186.0]:
		var tray := ColorRect.new()
		tray.color = Color(0.12, 0.13, 0.16)
		tray.position = Vector2(-200.0, float(cy))
		tray.size = Vector2(w + 400.0, 10.0)
		tray.z_index = -11
		add_child(tray)
	# 드문 작업등 · 붉은 톤 낮게(선로 = 위험 구역 무드).
	var lx2: float = 700.0
	while lx2 < w:
		var work := ColorRect.new()
		work.color = Color(0.9, 0.45, 0.25, 0.12)
		work.position = Vector2(lx2 - 50.0, -100.0)
		work.size = Vector2(100.0, GROUND_Y + 100.0)
		work.z_index = -7
		add_child(work)
		lx2 += rng.randf_range(900.0, 1300.0)
	_add_lore_label(Vector2(240.0, GROUND_Y - 260.0), "선로 진입 금지 · 무인 운행 중", Color(0.9, 0.45, 0.25, 0.6), 14)
	_add_lore_label(Vector2(float(int(STAGE_LENGTH) - 640), GROUND_Y - 260.0), "MAINTENANCE ONLY\nARCTURUS 발주", Color(0.65, 0.72, 0.85, 0.45), 13)

# ─── 폐쇄 지하철 방3 · 환승홀(HORIZONTAL) 시그니처 배경 ───────────
# 환승 통로: 형광등 + 벽면 계단 실루엣 + 개찰 게이트 잔해. 정차 차량(발판)이 전투 지형.
func _ambience_subway_transfer() -> void:
	var w: float = STAGE_LENGTH
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 101 + 13
	# 정차 차량 실체(2026-08-22 사용자 "방3만 너무 달라 보인다") — "정차 차량 지붕"이라던 발판
	# (600/1700 · w700 · y220)이 허공에 뜬 일반 발판으로 그려져 지하철 정체성이 사라져 있었다.
	# 발판 아래에 차체(창·문·대차)를 그리고 밑에 유치선(레일+침목)을 깔아 "세워 둔 열차 위에서
	# 싸운다"로 만든다. 차체는 방2 주행 열차와 같은 결(어두운 차체 + 따뜻한 창).
	for ry in [GROUND_Y + 6.0, GROUND_Y + 20.0]:
		var rail := ColorRect.new()
		rail.color = Color(0.42, 0.45, 0.52, 0.9)
		rail.position = Vector2(-200.0, float(ry))
		rail.size = Vector2(w + 400.0, 4.0)
		rail.z_index = -4
		add_child(rail)
	var tx: float = -100.0
	while tx < w + 100.0:
		var tie := ColorRect.new()
		tie.color = Color(0.16, 0.14, 0.12)
		tie.position = Vector2(tx, GROUND_Y + 2.0)
		tie.size = Vector2(16.0, 26.0)
		tie.z_index = -5
		add_child(tie)
		tx += 90.0
	for cx in [600.0, 1700.0]:
		var left: float = float(cx) - 350.0
		# 차체 본체(발판 지붕 바로 아래 ~ 대차 위).
		var body := ColorRect.new()
		body.color = Color(0.10, 0.11, 0.14)
		body.position = Vector2(left, 226.0)
		body.size = Vector2(700.0, GROUND_Y - 22.0 - 226.0)
		body.z_index = -4
		add_child(body)
		var body_line := ColorRect.new()
		body_line.color = Color(0.50, 0.53, 0.62, 0.55)
		body_line.position = Vector2(left, 226.0)
		body_line.size = Vector2(700.0, 3.0)
		body_line.z_index = -3
		add_child(body_line)
		# 창 열(주행 열차와 같은 따뜻한 불빛) + 출입문 2짝.
		for i in 4:
			var win := ColorRect.new()
			win.color = Color(0.95, 0.82, 0.45, 0.6)
			win.position = Vector2(left + 60.0 + float(i) * 170.0, 258.0)
			win.size = Vector2(64.0, 30.0)
			win.z_index = -3
			add_child(win)
		for dxr in [left + 170.0, left + 470.0]:
			var door := ColorRect.new()
			door.color = Color(0.16, 0.18, 0.22)
			door.position = Vector2(float(dxr), 250.0)
			door.size = Vector2(52.0, GROUND_Y - 22.0 - 250.0)
			door.z_index = -3
			add_child(door)
		# 대차(하부) + 바퀴.
		var bogie := ColorRect.new()
		bogie.color = Color(0.07, 0.07, 0.09)
		bogie.position = Vector2(left + 20.0, GROUND_Y - 22.0)
		bogie.size = Vector2(660.0, 22.0)
		bogie.z_index = -4
		add_child(bogie)
		for wx in [left + 90.0, left + 210.0, left + 480.0, left + 600.0]:
			var wheel := ColorRect.new()
			wheel.color = Color(0.22, 0.24, 0.28)
			wheel.position = Vector2(float(wx), GROUND_Y - 16.0)
			wheel.size = Vector2(26.0, 16.0)
			wheel.z_index = -3
			add_child(wheel)
	var x: float = 300.0
	while x < w:
		var tube := ColorRect.new()
		tube.color = Color(0.85, 0.92, 1.0, 0.65)
		tube.position = Vector2(x - 60.0, -180.0)
		tube.size = Vector2(120.0, 4.0)
		tube.z_index = -6
		add_child(tube)
		if rng.randf() < 0.3:
			var tw := tube.create_tween()
			tw.set_loops()
			tw.tween_property(tube, "modulate:a", 0.2, rng.randf_range(0.05, 0.15))
			tw.tween_property(tube, "modulate:a", 1.0, rng.randf_range(0.4, 1.2))
		_add_light_cone(x, -174.0, 120.0, 280.0, 360.0, Color(0.85, 0.92, 1.0, 0.05), -10)
		x += rng.randf_range(420.0, 680.0)
	# 벽면 계단 실루엣 · 지상으로 오르는 환승 계단(배경 로어).
	for base_x in [500.0, float(int(w) - 800)]:
		for i in 5:
			var step := ColorRect.new()
			step.color = Color(0.13, 0.14, 0.17)
			step.position = Vector2(float(base_x) + float(i) * 44.0, 260.0 - float(i) * 26.0)
			step.size = Vector2(44.0, 14.0)
			step.z_index = -10
			add_child(step)
	# 개찰 게이트 잔해 · 짧은 기둥 열.
	var gx: float = 1150.0
	for i in 4:
		var gate := ColorRect.new()
		gate.color = Color(0.20, 0.22, 0.26)
		gate.position = Vector2(gx + float(i) * 70.0, GROUND_Y - 46.0)
		gate.size = Vector2(12.0, 46.0)
		gate.z_index = -8
		add_child(gate)
	_add_lore_label(Vector2(560.0, 150.0), "환승 → 지상", Color(0.65, 0.72, 0.85, 0.55), 14)
	_add_lore_label(Vector2(1120.0, GROUND_Y - 260.0), "개찰 구역 · 통행 기록 없음", Color(0.65, 0.72, 0.85, 0.45), 13)

func _ambience_cooling() -> void:
	# 냉각 시설(열교환 홀) — 차가운 푸른 톤. 2026-08-18 재작업: 등간격 수직 파이프 폐지
	# (수직 스트라이프 습관 금지 규칙, 규칙 등재 전 코드였음) → 상단 수평 헤더 배관에서
	# 불규칙 클러스터로 내려오는 낙관(落管) + 게이지 박스.
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 347 + GameState.current_segment * 13 + 9
	# 수평 헤더 배관(상단 2줄)
	for hy in [-60.0, 40.0]:
		var header := ColorRect.new()
		header.color = Color(0.30, 0.55, 0.70, 0.22)
		header.position = Vector2(-200.0, hy)
		header.size = Vector2(STAGE_LENGTH + 400.0, 14.0)
		header.z_index = -9
		add_child(header)
	# 낙관 클러스터 — 2~3개씩 묶여 불규칙 간격으로
	var x: float = 260.0
	while x < STAGE_LENGTH - 200.0:
		var cluster: int = rng.randi_range(2, 3)
		for c in cluster:
			var px: float = x + float(c) * rng.randf_range(26.0, 44.0)
			var pipe := ColorRect.new()
			pipe.color = Color(0.30, 0.55, 0.70, rng.randf_range(0.14, 0.24))
			pipe.position = Vector2(px, 54.0)
			pipe.size = Vector2(rng.randf_range(8.0, 14.0), GROUND_Y - 54.0 + 40.0)
			pipe.z_index = -9
			add_child(pipe)
		# 클러스터 밑 게이지 박스
		if rng.randf() < 0.6:
			var gauge := ColorRect.new()
			gauge.color = Color(0.16, 0.24, 0.30)
			gauge.position = Vector2(x + 8.0, GROUND_Y - rng.randf_range(150.0, 220.0))
			gauge.size = Vector2(34.0, 26.0)
			gauge.z_index = -8
			add_child(gauge)
			var needle := ColorRect.new()
			needle.color = Color(0.45, 0.85, 1.0, 0.8)
			needle.position = gauge.position + Vector2(6.0, 10.0)
			needle.size = Vector2(rng.randf_range(8.0, 20.0), 4.0)
			needle.z_index = -7
			add_child(needle)
		x += rng.randf_range(340.0, 640.0)
	# 차가운 푸른 안개 (바닥)
	var fog := ColorRect.new()
	fog.color = Color(0.40, 0.65, 0.85, 0.08)
	fog.position = Vector2(-200, GROUND_Y - 80.0)
	fog.size = Vector2(STAGE_LENGTH + 400.0, 100.0)
	fog.z_index = -3
	add_child(fog)

# 흡기 회랑(냉각 체인 방1) — 벽면 가로 루버 그릴 + 상단 흡기 덕트. 옅은 안개.
func _ambience_cooling_intake() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 349 + GameState.current_segment * 13 + 3
	var gx: float = 320.0
	while gx < STAGE_LENGTH - 240.0:
		var gw: float = rng.randf_range(200.0, 280.0)
		var gh: float = rng.randf_range(120.0, 170.0)
		var gy: float = GROUND_Y - rng.randf_range(240.0, 330.0)
		var frame := ColorRect.new()
		frame.color = Color(0.14, 0.20, 0.25)
		frame.position = Vector2(gx, gy)
		frame.size = Vector2(gw, gh)
		frame.z_index = -12
		add_child(frame)
		var louvers: int = int(gh / 22.0)
		for l in louvers:
			var lv := ColorRect.new()
			lv.color = Color(0.30, 0.55, 0.70, 0.30)
			lv.position = Vector2(gx + 6.0, gy + 6.0 + float(l) * 22.0)
			lv.size = Vector2(gw - 12.0, 6.0)
			lv.z_index = -11
			add_child(lv)
		gx += gw + rng.randf_range(280.0, 520.0)
	# 상단 흡기 덕트(수평)
	var duct := ColorRect.new()
	duct.color = Color(0.30, 0.55, 0.70, 0.18)
	duct.position = Vector2(-200.0, -20.0)
	duct.size = Vector2(STAGE_LENGTH + 400.0, 22.0)
	duct.z_index = -9
	add_child(duct)
	var fog := ColorRect.new()
	fog.color = Color(0.40, 0.65, 0.85, 0.05)
	fog.position = Vector2(-200, GROUND_Y - 70.0)
	fog.size = Vector2(STAGE_LENGTH + 400.0, 90.0)
	fog.z_index = -3
	add_child(fog)
	_add_lore_label(Vector2(360.0, -30.0), "흡기 라인 · 필터 구역", Color(0.45, 0.85, 1.0, 0.5), 15)

# 배기 스택(냉각 체인 방3) — 위로 모이는 배기 덕트 깔때기 + 따뜻한 하이라이트(열기) +
# 짙은 안개. 증기 최밀 구간의 시각 근거.
func _ambience_cooling_exhaust() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 351 + GameState.current_segment * 13 + 7
	var sx: float = 420.0
	while sx < STAGE_LENGTH - 240.0:
		var base_w: float = rng.randf_range(150.0, 210.0)
		# 깔때기 — 아래 넓고 위로 좁아지는 3단
		for t in 3:
			var tw2: float = base_w * (1.0 - float(t) * 0.28)
			var seg := ColorRect.new()
			seg.color = Color(0.22, 0.34, 0.42, 0.8 - float(t) * 0.18)
			seg.position = Vector2(sx + (base_w - tw2) * 0.5, 80.0 - float(t) * 90.0)
			seg.size = Vector2(tw2, 84.0)
			seg.z_index = -11
			add_child(seg)
		# 열기 하이라이트(덕트 하단 · 유일한 따뜻한 색)
		var heat := ColorRect.new()
		heat.color = Color(0.95, 0.60, 0.35, 0.10)
		heat.position = Vector2(sx + base_w * 0.2, 158.0)
		heat.size = Vector2(base_w * 0.6, 26.0)
		heat.z_index = -10
		add_child(heat)
		sx += base_w + rng.randf_range(380.0, 660.0)
	var fog := ColorRect.new()
	fog.color = Color(0.40, 0.65, 0.85, 0.12)
	fog.position = Vector2(-200, GROUND_Y - 110.0)
	fog.size = Vector2(STAGE_LENGTH + 400.0, 130.0)
	fog.z_index = -3
	add_child(fog)
	_add_lore_label(Vector2(360.0, -30.0), "배기 스택 · 밸브 제어", Color(0.45, 0.85, 1.0, 0.5), 15)

func _ambience_watchtower() -> void:
	# 감시탑 — 붉은 스캔라인 (노출 = 위험 신호)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 113 + 17
	for i in 5:
		var beam := ColorRect.new()
		beam.color = Color(0.85, 0.30, 0.30, 0.05)
		beam.size = Vector2(STAGE_LENGTH + 400.0, 8.0)
		beam.position = Vector2(-200, rng.randf_range(-180.0, GROUND_Y - 100.0))
		beam.z_index = -7
		add_child(beam)
		# 천천히 위아래로 흐르는 스캔라인 효과
		var tw := beam.create_tween()
		tw.set_loops()
		tw.tween_property(beam, "position:y", beam.position.y + 30.0, rng.randf_range(2.5, 4.5))
		tw.tween_property(beam, "position:y", beam.position.y, rng.randf_range(2.5, 4.5))

func _ambience_ward() -> void:
	# 격리 병동 — 좁은 복도 + 양쪽 어두운 비네트 + 깜빡이는 비상등
	var vignette := CanvasLayer.new()
	vignette.layer = 1
	add_child(vignette)
	for side in [0, 1]:  # 0=좌, 1=우 — 화면 가장자리 앵커(화면비 무관)
		var v := ColorRect.new()
		v.color = Color(0, 0, 0, 0.55)
		if side == 0:
			v.set_anchors_preset(Control.PRESET_LEFT_WIDE)
			v.offset_right = 220.0
		else:
			v.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
			v.offset_left = -220.0
		vignette.add_child(v)
	# 비상등 — 붉은 점멸
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 149 + 23
	var x: float = 350.0
	while x < STAGE_LENGTH:
		var lamp := ColorRect.new()
		lamp.color = Color(0.85, 0.20, 0.20, 0.30)
		lamp.position = Vector2(x - 30.0, -100.0)
		lamp.size = Vector2(60.0, 700.0)
		lamp.z_index = -7
		add_child(lamp)
		var tw := lamp.create_tween()
		tw.set_loops()
		tw.tween_property(lamp, "modulate:a", 0.4, rng.randf_range(0.8, 1.6))
		tw.tween_property(lamp, "modulate:a", 1.0, rng.randf_range(0.8, 1.6))
		x += rng.randf_range(640.0, 920.0)
	# 격리 표지 라벨은 사용자 피드백으로 제거 — 비네트+붉은 비상등 ambience로 분위기 표현.
	# VEIL-1 봉인 lore는 이스터에그 ARCTURUS 문서가 같은 맵에 있어 기능적으로 중복.

func _ambience_datacenter() -> void:
	# 데이터 센터 — 격자 + 데이터 흐름 라인 (밝은 푸른 톤)
	var x: float = 200.0
	while x < STAGE_LENGTH:
		var line := ColorRect.new()
		line.color = Color(0.30, 0.65, 0.95, 0.08)
		line.position = Vector2(x, -200.0)
		line.size = Vector2(1.5, 800.0)
		line.z_index = -10
		add_child(line)
		x += 90.0
	# 가로 데이터 라인 (천천히 흐르는 LED 효과)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 167 + 31
	for i in 8:
		var bar := ColorRect.new()
		bar.color = Color(0.40, 0.85, 1.0, 0.35)
		bar.size = Vector2(40.0, 2.0)
		bar.position = Vector2(rng.randf_range(0.0, STAGE_LENGTH), rng.randf_range(-160.0, GROUND_Y - 60.0))
		bar.z_index = -5
		add_child(bar)
		var tw := bar.create_tween()
		tw.set_loops()
		tw.tween_property(bar, "position:x", bar.position.x + 80.0, rng.randf_range(1.5, 2.8))
		tw.tween_property(bar, "modulate:a", 0.0, 0.1)
		tw.tween_property(bar, "modulate:a", 0.35, 0.1)

# ─── 처리별 탈출 톤 오버레이(replay_support_plan §3.2) — _ambience_escape() 공통 뼈대 위에
# 처리별 색을 얹는다. 캐스트는 CanvasModulate 대신 MUL 블렌드 풀스크린(막5 라이벌 틴트
# CanvasModulate와의 중복 충돌 회피). 광과민 기준: 넓은 발광의 맥동은 얕고(±5%p) 느리게(1Hz 미만).

func _escape_cast(color: Color) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 8   # 월드 위, HUD(20+) 아래
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = color
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_MUL
	rect.material = mat
	layer.add_child(rect)

# 반출 = 총력 저지: 붉은 경보 캐스트 + 터널 벽면 경광 글로우(느린 호흡, 스트로브 아님).
# 글로우는 벽이 실제로 있는 터널 구간(x < _TUNNEL_END_X) 안에만 — 터널 밖까지 두면 벽 없는
# 야경 하늘에 민짜 빨간 원이 떠 "저게 뭐냐"가 된다(2026-08-15 사용자 보고). 야외 구간의
# 경보 톤은 _escape_cast(붉은 캐스트)가 담당.
func _escape_tone_extract() -> void:
	_escape_cast(Color(1.0, 0.86, 0.84))
	for x in [500.0, 1000.0, 1450.0]:
		var lamp := _AlarmGlow.new()
		lamp.position = Vector2(float(x), 120.0)
		add_child(lamp)

class _AlarmGlow extends Node2D:
	var _t: float = randf() * TAU
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		# 민짜 원 대신 동심원 감쇠 — 벽에 번지는 광원으로 읽히게(하드 엣지 제거).
		var a: float = 0.10 + 0.04 * sin(_t * 2.4)   # 약 0.38Hz 왕복 — 저대비 완만
		for i in 4:
			var r: float = 150.0 - 34.0 * float(i)
			draw_circle(Vector2.ZERO, r, Color(0.95, 0.26, 0.21, a * (0.35 + 0.28 * float(i))))

# 파기 = 붕괴: 주황빛 재 캐스트 + 떨어지는 분진.
func _escape_tone_destroy() -> void:
	_escape_cast(Color(1.0, 0.90, 0.80))
	add_child(_AshFall.new())

class _AshFall extends Node2D:
	var _parts: Array = []
	func _ready() -> void:
		z_index = 5
		for i in 26:
			_parts.append({"x": randf() * 3800.0, "y": randf() * 720.0,
				"vy": 30.0 + randf() * 50.0, "r": 1.5 + randf() * 2.0})
	func _process(delta: float) -> void:
		for p in _parts:
			var d: Dictionary = p
			d["y"] = float(d["y"]) + float(d["vy"]) * delta
			if float(d["y"]) > 720.0:
				d["y"] = -10.0
				d["x"] = randf() * 3800.0
		queue_redraw()
	func _draw() -> void:
		for p in _parts:
			var d: Dictionary = p
			draw_circle(Vector2(float(d["x"]), float(d["y"])), float(d["r"]), Color(0.75, 0.62, 0.50, 0.35))

# 은닉 = 밀고당하는 잠입: 어둠 캐스트(수색 빔·니치 시각은 SweepBeam 기믹이 담당).
func _escape_tone_conceal() -> void:
	_escape_cast(Color(0.62, 0.66, 0.74))

# 잔류 = 거짓 평온: 옅은 바이올렛 캐스트(배웅 실루엣·위장 함정은 데이터 기믹이 담당).
func _escape_tone_leave() -> void:
	_escape_cast(Color(0.94, 0.88, 1.0))

func _ambience_escape() -> void:
	# 비상 탈출로 — 터널 walls(고정 구조물) + 항상 보이는 city group.
	# 터널 walls가 z=-10로 city group(z=-13~-20)을 가림 → 카메라가 터널 안에 있을 땐
	# 콘크리트만 보임. 카메라가 _TUNNEL_END_X 너머로 가면 wall이 없어 city 노출.
	# 사용자 요구: cross-fade가 아니라 딱 터널 끝나는 모서리에서 도시 등장.
	_escape_tunnel_group = Node2D.new()
	_escape_tunnel_group.name = "EscapeTunnel"
	add_child(_escape_tunnel_group)
	_escape_city_group = Node2D.new()
	_escape_city_group.name = "EscapeCity"
	# modulate.a = 1.0 (cross-fade 폐지). walls가 가시성 자체를 제어.
	add_child(_escape_city_group)
	_build_escape_tunnel(_escape_tunnel_group)
	_build_escape_city(_escape_city_group)

const _TUNNEL_END_X: float = 1600.0   # 터널이 물리적으로 끝나는 x. 그 너머는 city 노출.
# BGM 페이드아웃 — player가 터널 출구를 통과한 순간(_TUNNEL_END_X 도달)부터 점진 감쇠 시작.
# 골(STAGE_LENGTH)에 닿을 즈음 -60dB(거의 무음). 사용자: "터널 나오는 순간부터".
const _BGM_FADE_FLOOR_DB: float = -60.0

func _build_escape_tunnel(host: Node) -> void:
	# 솔리드 회색 콘크리트 벽 — x = -200 ~ _TUNNEL_END_X 까지만. 그 이후엔 벽 없음.
	# 사용자: 터널 배경은 cross-fade가 아니라 그냥 "딱 끝나야" 함. 터널 빠져나간 느낌.
	# city group은 항상 보임(modulate.a=1.0)이지만 z_index가 더 깊어 walls에 가려짐.
	# 카메라가 _TUNNEL_END_X 너머로 가면 walls가 없어 city가 자연스럽게 노출됨.
	var tunnel_w: float = _TUNNEL_END_X + 200.0  # 좌측 -200부터 시작
	var wall := ColorRect.new()
	wall.color = Color(0.18, 0.19, 0.22, 1.0)
	wall.position = Vector2(-200.0, -300.0)
	wall.size = Vector2(tunnel_w, 1100.0)
	wall.z_index = -10
	host.add_child(wall)
	# 수직 grain 라인 — 콘크리트 panel 분리 효과. 80px 간격.
	var grain_count: int = int(tunnel_w / 80.0)
	for i in grain_count:
		var line := ColorRect.new()
		line.color = Color(0.10, 0.11, 0.13, 0.7)
		line.position = Vector2(-200.0 + float(i) * 80.0, -300.0)
		line.size = Vector2(1.0, 1100.0)
		line.z_index = -9
		host.add_child(line)
	# 상단 진하게(천장 그림자).
	var top_dark := ColorRect.new()
	top_dark.color = Color(0.05, 0.06, 0.08, 0.85)
	top_dark.position = Vector2(-200.0, -300.0)
	top_dark.size = Vector2(tunnel_w, 220.0)
	top_dark.z_index = -8
	host.add_child(top_dark)
	# 터널 출구 프레임 — 끝 부분에 옅은 진한 라인으로 "벽이 끝나는 모서리"를 강조.
	var edge := ColorRect.new()
	edge.color = Color(0.05, 0.06, 0.08, 1.0)
	edge.position = Vector2(_TUNNEL_END_X - 6.0, -300.0)
	edge.size = Vector2(6.0, 1100.0)
	edge.z_index = -7
	host.add_child(edge)
	# 천장 형광등 + 글로우. 터널 안에서만 등장.
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 191 + 37
	var x: float = 360.0
	while x < _TUNNEL_END_X - 80.0:
		var lamp := ColorRect.new()
		lamp.color = Color(0.78, 0.88, 0.95, 0.85)
		lamp.size = Vector2(120.0, 4.0)
		lamp.position = Vector2(x - 60.0, -180.0)
		lamp.z_index = -6
		host.add_child(lamp)
		var glow := ColorRect.new()
		glow.color = Color(0.85, 0.92, 1.0, 0.15)
		glow.size = Vector2(160.0, 60.0)
		glow.position = Vector2(x - 80.0, -176.0)
		glow.z_index = -7
		host.add_child(glow)
		x += rng.randf_range(420.0, 680.0)
	# 바닥 안개도 터널 안에서만.
	var fog := ColorRect.new()
	fog.color = Color(0.30, 0.32, 0.36, 0.10)
	fog.position = Vector2(-200.0, GROUND_Y - 60.0)
	fog.size = Vector2(tunnel_w, 80.0)
	fog.z_index = -3
	host.add_child(fog)
	# 출구 표지판 — 터널 끝 직전에 녹색 EXIT 패널. 천장 아래쪽, 플레이어 시야 안.
	_build_escape_exit_sign(host, _TUNNEL_END_X - 120.0, GROUND_Y - 220.0)

func _build_escape_exit_sign(host: Node, x: float, y: float) -> void:
	var holder := Node2D.new()
	holder.position = Vector2(x, y)
	holder.z_index = -5  # walls(-10)보다 앞, lamp(-6/-7)와 비슷한 깊이
	host.add_child(holder)
	# 베젤 — 어두운 금속 프레임
	var bezel := ColorRect.new()
	bezel.color = Color(0.10, 0.11, 0.13, 1.0)
	bezel.position = Vector2(-46.0, -22.0)
	bezel.size = Vector2(92.0, 44.0)
	holder.add_child(bezel)
	# 본체 — 비상 녹색
	var body := ColorRect.new()
	body.color = Color(0.20, 0.85, 0.35, 1.0)
	body.position = Vector2(-42.0, -18.0)
	body.size = Vector2(84.0, 36.0)
	holder.add_child(body)
	# EXIT 텍스트
	var label := Label.new()
	label.text = "EXIT →"
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_color", Color(0.05, 0.08, 0.06))
	label.position = Vector2(-42.0, -18.0)
	label.size = Vector2(84.0, 36.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(label)
	# 매다는 끈 — 천장에서 살짝 늘어진 회색 라인 두 줄
	for sx in [-30.0, 30.0]:
		var rope := ColorRect.new()
		rope.color = Color(0.20, 0.21, 0.24, 1.0)
		rope.position = Vector2(sx - 1.0, -42.0)
		rope.size = Vector2(2.0, 22.0)
		holder.add_child(rope)
	# 옅은 글로우 — 비상 녹색 후광
	var halo := ColorRect.new()
	halo.color = Color(0.30, 0.95, 0.45, 0.18)
	halo.position = Vector2(-72.0, -42.0)
	halo.size = Vector2(144.0, 84.0)
	halo.z_index = -6
	holder.add_child(halo)
	# 살짝 깜빡 — 비상등 톤
	var tw := body.create_tween()
	tw.set_loops()
	tw.tween_property(body, "modulate:a", 0.85, 0.9)
	tw.tween_property(body, "modulate:a", 1.0, 0.9)

# scroll_factor: 1.0=foreground(world와 같이 스크롤), 0.0=화면 고정(UI 같음).
# 0과 1 사이 값 = parallax. 작을수록 멀어 보임.
# _tick_escape_transition이 매 프레임 layer.position.x = camera.x * (1 - scroll_factor)로 갱신.
func _build_escape_city(host: Node) -> void:
	# 도시 야경 — 3개 parallax sub-layer로 거리감 표현.
	#   far(0.15):  하늘 + 별 + 가장 먼 빌딩 실루엣 (거의 안 움직임)
	#   mid(0.45):  중간 빌딩 + 창문 (절반 속도)
	#   near(0.80): 가까운 빌딩 (거의 카메라 따라감)
	# 모두 host(_escape_city_group) 자식 — modulate.a로 fade-in 조절은 그대로 group에서.
	_escape_city_far = Node2D.new()
	_escape_city_far.name = "CityFar"
	_escape_city_far.set_meta("scroll_factor", 0.15)
	host.add_child(_escape_city_far)
	_escape_city_mid = Node2D.new()
	_escape_city_mid.name = "CityMid"
	_escape_city_mid.set_meta("scroll_factor", 0.45)
	host.add_child(_escape_city_mid)
	_escape_city_near = Node2D.new()
	_escape_city_near.name = "CityNear"
	_escape_city_near.set_meta("scroll_factor", 0.80)
	host.add_child(_escape_city_near)
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 211 + 43
	# ── FAR (0.15) — 하늘 / 별 / 작은 먼 빌딩 ─────────────────────
	# 하늘 — 화면 한 번에 안 끊기게 매우 넓게 (parallax 적용 후에도 항상 가시 영역 덮음).
	# 카메라 가능 범위(0~stage_length) × (1-scroll) ≈ 0.85*stage_length 만큼 layer가 이동하므로
	# 하늘 너비가 stage + 그 만큼 + 여유 필요.
	var sky_w: float = STAGE_LENGTH * 1.9 + 400.0
	var sky_x: float = -STAGE_LENGTH * 0.5
	var sky_top := ColorRect.new()
	sky_top.color = Color(0.05, 0.06, 0.12, 1.0)
	sky_top.position = Vector2(sky_x, -240.0)
	sky_top.size = Vector2(sky_w, 280.0)
	sky_top.z_index = -20
	_escape_city_far.add_child(sky_top)
	var sky_bottom := ColorRect.new()
	sky_bottom.color = Color(0.10, 0.14, 0.22, 1.0)
	sky_bottom.position = Vector2(sky_x, 40.0)
	sky_bottom.size = Vector2(sky_w, 200.0)
	sky_bottom.z_index = -20
	_escape_city_far.add_child(sky_bottom)
	# 별 — 하늘 layer와 같이 천천히 이동.
	for i in 60:
		var s := ColorRect.new()
		s.color = Color(0.85, 0.92, 1.0, rng.randf_range(0.3, 0.7))
		s.size = Vector2(2, 2)
		s.position = Vector2(rng.randf_range(sky_x, sky_x + sky_w), rng.randf_range(-220.0, -80.0))
		s.z_index = -19
		_escape_city_far.add_child(s)
	# 가장 먼 빌딩 — 작고 옅음. layer 너비에 맞춰 폭넓게 spawn.
	var fbx: float = sky_x
	while fbx < sky_x + sky_w:
		var fbw: float = rng.randf_range(40.0, 90.0)
		var fbh: float = rng.randf_range(120.0, 220.0)
		var fb := ColorRect.new()
		fb.color = Color(0.06, 0.08, 0.13, 1.0)
		fb.position = Vector2(fbx, GROUND_Y - fbh - 40.0)
		fb.size = Vector2(fbw, fbh + 80.0)
		fb.z_index = -18
		_escape_city_far.add_child(fb)
		fbx += fbw + rng.randf_range(40.0, 100.0)
	# ── MID (0.45) — 메인 빌딩 + 창문 ───────────────────────────
	var mid_w: float = STAGE_LENGTH * 1.55 + 400.0
	var mid_x: float = -STAGE_LENGTH * 0.3
	var bx: float = mid_x
	while bx < mid_x + mid_w:
		var bw: float = rng.randf_range(60.0, 140.0)
		var bh: float = rng.randf_range(180.0, 360.0)
		var building := ColorRect.new()
		building.color = Color(0.04, 0.05, 0.09, 1.0)
		building.position = Vector2(bx, GROUND_Y - bh - 40.0)
		building.size = Vector2(bw, bh + 80.0)
		building.z_index = -16
		_escape_city_mid.add_child(building)
		# 창문 빛 — 빌딩 안에 작은 점들. 일부 깜빡이도록.
		var win_x: float = bx + 8.0
		while win_x < bx + bw - 4.0:
			var win_y: float = GROUND_Y - bh - 20.0
			while win_y < GROUND_Y - 50.0:
				if rng.randf() < 0.45:
					var win := ColorRect.new()
					var warm: bool = rng.randf() < 0.7
					if warm:
						win.color = Color(0.95, 0.85, 0.55, rng.randf_range(0.55, 0.95))
					else:
						win.color = Color(0.55, 0.78, 0.95, rng.randf_range(0.45, 0.85))
					win.size = Vector2(2.0, 3.0)
					win.position = Vector2(win_x, win_y)
					win.z_index = -14
					_escape_city_mid.add_child(win)
					if rng.randf() < 0.18:
						var tw := win.create_tween()
						tw.set_loops()
						tw.tween_property(win, "modulate:a", 0.2, rng.randf_range(0.8, 2.2))
						tw.tween_property(win, "modulate:a", 1.0, rng.randf_range(0.8, 2.2))
				win_y += 8.0
			win_x += 6.0
		bx += bw + rng.randf_range(20.0, 80.0)
	# ── NEAR (0.80) — 가까운 키 큰 빌딩 한 줄 ───────────────────
	var near_w: float = STAGE_LENGTH * 1.2 + 400.0
	var near_x: float = -STAGE_LENGTH * 0.1
	var nx: float = near_x
	while nx < near_x + near_w:
		var nw: float = rng.randf_range(100.0, 200.0)
		var nh: float = rng.randf_range(140.0, 280.0)
		var near_b := ColorRect.new()
		near_b.color = Color(0.02, 0.03, 0.06, 1.0)
		near_b.position = Vector2(nx, GROUND_Y - nh - 20.0)
		near_b.size = Vector2(nw, nh + 60.0)
		near_b.z_index = -15
		_escape_city_near.add_child(near_b)
		nx += nw + rng.randf_range(140.0, 280.0)

func _tick_escape_transition(_delta: float) -> void:
	# Tunnel/city alpha fade 폐지 — walls 자체가 가시성 결정 (사용자: 터널이 딱 끝나야 함).
	# 매 프레임 city sub-layer에 parallax offset만 적용.
	if _escape_city_group == null or not is_instance_valid(_escape_city_group):
		return
	if camera == null:
		return
	# IMPORTANT: camera.global_position.x는 player 위치를 따라가지만 limit_right로 clamp되지
	# 않은 raw 값이라, 플레이어가 맵 끝에 닿아 카메라가 멈춰도 계속 증가함.
	# get_screen_center_position()은 limit이 적용된 실제 화면 중심 — 이걸 써야
	# "맵 스크롤이 멈춘 순간 배경도 멈춤" (사용자 요구).
	var cam_x: float = camera.get_screen_center_position().x
	for layer in [_escape_city_far, _escape_city_mid, _escape_city_near]:
		if layer == null or not is_instance_valid(layer):
			continue
		var sf: float = float(layer.get_meta("scroll_factor", 1.0))
		layer.position.x = cam_x * (1.0 - sf)
	# BGM 페이드아웃 — 터널 출구 통과 순간부터 점진 감쇠, 골 도달 시 거의 무음.
	# 사용자: "탈출로에서 터널을 나오는 순간부터 점진적으로 줄어들게".
	if player != null and is_instance_valid(player):
		var px: float = player.global_position.x
		if px >= _TUNNEL_END_X:
			var fade_range: float = STAGE_LENGTH - _TUNNEL_END_X
			var t: float = clamp((px - _TUNNEL_END_X) / fade_range, 0.0, 1.0)
			BgmPlayer.set_extra_attenuation_db(lerp(0.0, _BGM_FADE_FLOOR_DB, t))
		else:
			BgmPlayer.set_extra_attenuation_db(0.0)

## 환경 라벨/그래피티 — 맵에 떡밥 텍스트 한 줄 깔아 코드명을 다른 맵과 묶음.
## PROJECT VEIL / ARCTURUS / PALIMPSEST / SILO-7 등이 여러 맵에 반복 등장 → 호기심.
func _add_lore_label(pos: Vector2, text: String, color: Color = Color(0.55, 0.62, 0.72, 0.55), font_size: int = 13, rotation: float = 0.0) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", 3)
	l.position = pos
	l.size = Vector2(360, 60)
	l.rotation = rotation
	l.z_index = -3
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)

func _ambience_hidden() -> void:
	# 글리치 — 무작위 위치에 작은 색 사각형이 짧게 깜빡
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 101 + 29
	for i in 24:
		var g := ColorRect.new()
		g.color = Color(rng.randf_range(0.5, 1.0), rng.randf_range(0.2, 0.6), rng.randf_range(0.6, 1.0), 0.5)
		g.size = Vector2(rng.randf_range(20.0, 80.0), rng.randf_range(2.0, 8.0))
		g.position = Vector2(rng.randf_range(-100.0, STAGE_LENGTH + 100.0), rng.randf_range(-200.0, GROUND_Y - 40.0))
		g.z_index = -4
		add_child(g)
		var tw := g.create_tween()
		tw.set_loops()
		tw.tween_property(g, "modulate:a", 0.0, rng.randf_range(0.05, 0.2))
		tw.tween_interval(rng.randf_range(0.4, 2.0))
		tw.tween_property(g, "modulate:a", 0.5, rng.randf_range(0.05, 0.2))

func _stage_color() -> Color:
	# 1순위: RouteData에 정의된 stage_color
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		if route.get("id", "") == GameState.current_route_id:
			return route.get("stage_color", Color(0.06, 0.07, 0.09))
	# 폴백: tags 기반 (튜토리얼 등 route_id 없을 때)
	var tags: Array = GameState.current_route_tags
	if "어두운_환경" in tags:
		return Color(0.03, 0.04, 0.06)
	if "밝은_환경" in tags:
		return Color(0.13, 0.14, 0.18)
	if "노출" in tags:
		return Color(0.08, 0.11, 0.18)
	return Color(0.06, 0.07, 0.09)

func _build_platform(x: float, y: float, w: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.add_to_group("platform")
	add_child(body)
	var col := CollisionShape2D.new()
	col.one_way_collision = true  # 위에서만 착지 가능 — 아래에서 점프 시 통과
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, 24.0)
	col.shape = shape
	col.position = Vector2(x, y)
	body.add_child(col)

	# 플랫폼 비주얼 — 3단 패널(밝은 상부 / 어두운 본체 / 더 어두운 그림자) + 외곽선
	# + 상단 발광 라인 + 좌우 모서리 발광 캡으로 입체감.
	# 2026-08-17 폴리시: 본체 그라디언트 + 하부 브래킷 + 아래 드롭 섀도 + env 색조 발광 ·
	# 전 맵 공유라 한 번의 업그레이드가 모든 맵의 "만든 구조물" 질감이 된다.
	var px: float = x - w * 0.5
	var py: float = y - 12.0
	# 본체 (16px, 어두운) + 상단이 살짝 밝은 그라디언트 오버레이
	_add_filled_rect(Vector2(px, py + 4.0), Vector2(w, 16.0), Color(0.14, 0.16, 0.20))
	_add_vgrad(Vector2(px, py + 4.0), Vector2(w, 16.0), Color(1, 1, 1, 0.06), Color(0, 0, 0, 0.14), 0)
	# 상단 패널 (4px, 밝은)
	_add_filled_rect(Vector2(px, py), Vector2(w, 4.0), Color(0.42, 0.46, 0.54))
	# 하단 패널 (4px, 가장 어두운 — 그림자)
	_add_filled_rect(Vector2(px, py + 20.0), Vector2(w, 4.0), Color(0.06, 0.07, 0.09))
	# 하부 브래킷 · 발판 양끝 밑의 짧은 사선 지지(허공 부유감 완화). 폭이 충분할 때만.
	if w >= 100.0:
		for bk in [px + w * 0.16, px + w * 0.84]:
			var br := Polygon2D.new()
			br.color = Color(0.10, 0.11, 0.15)
			br.polygon = PackedVector2Array([
				Vector2(float(bk) - 9.0, py + 24.0), Vector2(float(bk) + 9.0, py + 24.0),
				Vector2(float(bk) + 3.0, py + 34.0), Vector2(float(bk) - 3.0, py + 34.0)])
			add_child(br)
	# 아래 드롭 섀도 · 발판이 공간에 떠 있음을 배경 위에 옅게.
	_add_vgrad(Vector2(px + 3.0, py + 24.0), Vector2(w - 6.0, 14.0), Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.0), 0)
	# 본체 표면 마이크로 패널 라인 (입체감) — 너비가 충분할 때만
	if w >= 120.0:
		var seam_x: float = px + w * 0.5
		var seam := ColorRect.new()
		seam.color = Color(0.06, 0.07, 0.09, 0.65)
		seam.position = Vector2(seam_x - 0.5, py + 6.0)
		seam.size = Vector2(1.0, 12.0)
		add_child(seam)
	# 외곽선 박스 — 형태만 잡는 정도로 옅게(쟁한 느낌 방지).
	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		Vector2(px, py),
		Vector2(px + w, py),
		Vector2(px + w, py + 24.0),
		Vector2(px, py + 24.0),
	])
	outline.closed = true
	outline.width = 0.8
	outline.default_color = Color(0.04, 0.05, 0.07, 0.50)
	outline.antialiased = true
	add_child(outline)
	# 상단 발광 라인 (착지면 인지) · env 액센트 색조(맵 성격이 발판 조명에도 실림, 2026-08-17).
	var pacc: Color = _env_palette(_indoor_env())["accent"]
	var glow_col: Color = pacc.lerp(Color(1, 1, 1), 0.30)
	var glow := ColorRect.new()
	glow.color = Color(glow_col.r, glow_col.g, glow_col.b, 0.7)
	glow.position = Vector2(px + 2.0, py - 1.0)
	glow.size = Vector2(w - 4.0, 1.6)
	add_child(glow)
	# 좌우 모서리 발광 캡 · 발광 라인과 같은 계열(살짝 더 밝게).
	var cap_col: Color = pacc.lerp(Color(1, 1, 1), 0.45)
	var cap_l := ColorRect.new()
	cap_l.color = Color(cap_col.r, cap_col.g, cap_col.b, 0.9)
	cap_l.position = Vector2(px - 2.0, py + 2.0)
	cap_l.size = Vector2(3.0, 4.0)
	add_child(cap_l)
	var cap_r := ColorRect.new()
	cap_r.color = Color(cap_col.r, cap_col.g, cap_col.b, 0.9)
	cap_r.position = Vector2(px + w - 1.0, py + 2.0)
	cap_r.size = Vector2(3.0, 4.0)
	add_child(cap_r)

# 단순 사각형 폴리곤 — 외곽선 없는 채움. _build_platform/_build_background에서 사용.
func _add_filled_rect(pos: Vector2, size: Vector2, color: Color) -> Polygon2D:
	var p := Polygon2D.new()
	p.color = color
	p.polygon = PackedVector2Array([
		pos,
		Vector2(pos.x + size.x, pos.y),
		Vector2(pos.x + size.x, pos.y + size.y),
		Vector2(pos.x, pos.y + size.y),
	])
	add_child(p)
	return p

func _build_wall(x: float) -> void:
	# 세로 맵에서도 벽이 월드 전체 높이를 덮도록 height를 동적으로.
	var wall_height: float = _world_size.y + 400.0
	var body := StaticBody2D.new()
	body.collision_layer = 1
	# 맵 경계벽 — 게임 내 "실제 벽"이 아니라 월드 끝 가드. Bullet은 여기 맞아도 impact SFX 안 냄.
	body.add_to_group("boundary_wall")
	add_child(body)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60.0, wall_height)
	col.shape = shape
	col.position = Vector2(x, _world_size.y * 0.5)
	body.add_child(col)

	# 벽 시각 — 본체 + 안쪽 모서리 발광 라인 + 패널 분할 (수직 stripe).
	var wx: float = x - 30.0
	var wtop: float = -200.0
	var wh: float = wall_height
	_add_filled_rect(Vector2(wx, wtop), Vector2(60.0, wh), Color(0.06, 0.07, 0.09))
	# 안쪽 면(보이는 쪽) — STAGE_LENGTH 끝(x>STAGE_LENGTH)이면 왼쪽이 안쪽, 시작(x<0)이면 오른쪽이 안쪽
	var inner_left: bool = x >= 0.0   # 우측 벽이면 왼쪽 면이 실내를 향한다
	var inner_x: float = wx if inner_left else (wx + 56.0)
	# 안쪽 면 그라디언트 · 실내 빛을 받는 면(플랫 슬래브 탈피, 2026-08-17 폴리시).
	var face_grad := Polygon2D.new()
	var gx0: float = inner_x if inner_left else inner_x - 14.0
	face_grad.polygon = PackedVector2Array([
		Vector2(gx0, wtop), Vector2(gx0 + 18.0, wtop),
		Vector2(gx0 + 18.0, wtop + wh), Vector2(gx0, wtop + wh)])
	var fg_in := Color(0.16, 0.18, 0.24, 0.5)
	var fg_out := Color(0.16, 0.18, 0.24, 0.0)
	face_grad.vertex_colors = PackedColorArray(
		[fg_in, fg_out, fg_out, fg_in] if inner_left else [fg_out, fg_in, fg_in, fg_out])
	face_grad.z_index = -2
	add_child(face_grad)
	# 안쪽 모서리 발광 · env 액센트 색조(발판·지평선과 같은 계열).
	var wacc: Color = _env_palette(_indoor_env())["accent"]
	var glow := ColorRect.new()
	glow.color = Color(wacc.r, wacc.g, wacc.b, 0.5)
	glow.position = Vector2(inner_x, wtop)
	glow.size = Vector2(2.0, wh)
	glow.z_index = -2
	add_child(glow)
	# 수평 패널 분할 라인 (60px 간격) + 이음새 볼트 점(안쪽 면 · 구조물 질감)
	var ly: float = wtop + 40.0
	while ly < wtop + wh:
		var seam := ColorRect.new()
		seam.color = Color(0.02, 0.03, 0.04, 0.85)
		seam.position = Vector2(wx, ly)
		seam.size = Vector2(60.0, 1.0)
		add_child(seam)
		var bolt := ColorRect.new()
		bolt.color = Color(0.30, 0.34, 0.42, 0.8)
		bolt.position = Vector2(inner_x + (5.0 if inner_left else -7.0), ly - 3.0)
		bolt.size = Vector2(2.0, 2.0)
		bolt.z_index = -2
		add_child(bolt)
		ly += 60.0

func _build_player() -> void:
	player = CharacterBody2D.new()
	player.set_script(load("res://scripts/Player.gd"))
	player.collision_layer = 2
	player.collision_mask = 1
	var col := CollisionShape2D.new()
	col.name = "Collision"
	var shape := RectangleShape2D.new()
	shape.size = Vector2(28.0, 56.0)
	col.shape = shape
	col.position = Vector2(0, -28.0)
	player.add_child(col)
	add_child(player)
	player.global_position = PLAYER_START
	player.died.connect(_on_player_died)
	player.damaged.connect(_on_player_damaged)
	player.revived.connect(_on_player_revived)
	# 접지 그림자 · 점프 중에도 착지 지점이 바닥에 남는다(전 엔티티 공통 폴리시 2026-08-17).
	var psh := GroundShadow.new()
	psh.target = player
	psh.base_width = 30.0
	add_child(psh)

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1.0, 1.0)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	# camera_mode별 limits / parent 분기
	match _camera_mode:
		"HORIZONTAL":
			camera.limit_left = 0
			camera.limit_right = int(STAGE_LENGTH)
			camera.limit_top = -200
			camera.limit_bottom = int(GROUND_Y + 200.0)
			player.add_child(camera)
		"VERTICAL":
			camera.limit_left = 0
			camera.limit_right = int(_world_size.x)
			camera.limit_top = -200
			# 바닥(GROUND_Y) 살짝 아래까지만 — 이전 world_size.y+200은 floor_visual(GROUND_Y+300)
			# 너머라 맨 밑에 void가 비쳤음(사용자: "바닥 아래 뚫려보임").
			camera.limit_bottom = int(GROUND_Y + 120.0)
			player.add_child(camera)
		"FIXED":
			# ARENA — 카메라 고정. zoom으로 월드 전체가 보이도록.
			camera.limit_left = 0
			camera.limit_right = int(_world_size.x)
			camera.limit_top = 0
			camera.limit_bottom = int(_world_size.y)
			camera.position_smoothing_enabled = false
			# 현재 화면(visible_rect)에 _world_size 전체가 맞게 zoom out — 화면비 무관.
			var vp_size: Vector2 = get_viewport().get_visible_rect().size
			var zoom_fit: float = min(vp_size.x / _world_size.x, vp_size.y / _world_size.y)
			camera.zoom = Vector2(zoom_fit, zoom_fit)
			add_child(camera)
			camera.global_position = _world_size * 0.5
		"ARENA_FOLLOW":
			# 복층 아레나(14-1 리워크 §2.1) · 양 축 완만 추적 + 기본 살짝 줌 아웃(무대 스케일 체감).
			camera.limit_left = 0
			camera.limit_right = int(_world_size.x)
			camera.limit_top = 0
			camera.limit_bottom = int(_world_size.y)
			camera.zoom = Vector2(0.85, 0.85)
			player.add_child(camera)
		_:
			# 폴백
			camera.limit_left = 0
			camera.limit_right = int(STAGE_LENGTH)
			camera.limit_top = -200
			camera.limit_bottom = int(GROUND_Y + 200.0)
			player.add_child(camera)
	camera.make_current()

# --- 덮어쓰기 한도(사망 예산) 연출 — 수치는 GameState가 진실, 여기는 전달만 ---

# 14-1 P2/P3 도달 — 라이벌 잠금을 부순다(런 영속, 사망 P1 리셋에도 유지). 부순 칸은 채워서 반환.
func _break_rival_lock(count: int) -> void:
	if GameState.story_mode or GameState.rival_locks_broken >= count:
		return
	GameState.rival_locks_broken = count
	GameState.overwrite_left = clampi(GameState.overwrite_left + 1, 0, GameState.overwrite_max())
	SfxPlayer.play("gate_unlock")
	_refresh_hud()

# 막4/5 첫 스테이지 — 라이벌이 덮어쓰기 회선을 잠그는 비트(런당 각 1회). 강탈은 보여야
# 강탈이라 ? 한 줄 + 핍 라벨을 바이올렛으로 잠깐 물들인다. 수치는 overwrite_max()가
# 막 함수로 이미 반영하므로 이 비트는 전달 전담(각본 비트 = 죽음 반응형 아님, 공정).
func _maybe_rival_lock_beat() -> void:
	if GameState.story_mode or GameState.playground_active:
		return
	if not GameState.is_act_start(GameState.current_stage):
		return
	var act: int = GameState.act_for_stage(GameState.current_stage)
	if act == 3 and not GameState.rival_lock_beat4_shown:
		GameState.rival_lock_beat4_shown = true
		get_tree().create_timer(4.2, false).timeout.connect(_play_rival_lock_beat.bind(4))
	elif act == 4 and not GameState.rival_lock_beat5_shown:
		GameState.rival_lock_beat5_shown = true
		get_tree().create_timer(4.2, false).timeout.connect(_play_rival_lock_beat.bind(5))

func _play_rival_lock_beat(act_num: int, tries_left: int = 24) -> void:
	if goal_reached or not is_inside_tree():
		return
	# 발화 유예(2026-08-23 "대사가 전투와 겹쳐 못 읽는다") — 교전 한복판이면 조용한 창(근접
	# 520px 내 적 없음)을 0.5s 간격으로 기다렸다 말한다. 상한 12s(각본 비트 유실 방지) —
	# 이 비트는 라이벌 + VEIL 해설 합쳐 ~8s짜리 각본이라 읽을 자리가 필요하다.
	if tries_left > 0 and _combat_near_player(520.0):
		get_tree().create_timer(0.5, false).timeout.connect(_play_rival_lock_beat.bind(act_num, tries_left - 1))
		return
	_run_glitch(0.5, 0.28)
	SfxPlayer.play("boss_alert_text")
	# 잠금 비트 = 컷씬(2026-08-23) — 라이벌 강탈 + VEIL 해설(무엇을 빼앗겼는지, 2026-08-15
	# 지적 · HUD "기록" 핍과 같은 단어로 실물 일치)을 정지 화면에서 잇는다. 핍 바이올렛
	# 물들임은 컷씬 종료 후에도 2.6s 남아(타이머가 pause 동안 정지) 해설의 지시 대상이 보인다.
	if overwrite_label != null and is_instance_valid(overwrite_label):
		overwrite_label.add_theme_color_override("font_color", Color(0.72, 0.42, 1.0))
		get_tree().create_timer(2.6, false).timeout.connect(_reset_overwrite_label_color)
	if act_num == 4:
		_play_story_dialogue([
			{"who": "rival", "text": "덮어쓰기 회선 하나는 제가 가져갑니다. 요원은 늘 여분이 많았으니까."},
			{"who": "veil", "text": "방금 덮어쓰기 회선 하나가 잠겼습니다.\n쓰러져도 그 자리에서 다시 서게 해 주던 기록입니다. 남은 건 둘."},
		])
	else:
		_play_story_dialogue([
			{"who": "rival", "text": "이제 한 번입니다. 제 구역에서는 아껴 쓰셔야죠."},
			{"who": "veil", "text": "하나 더 잠겼습니다. 남은 덮어쓰기는 한 번.\n그다음은 구역 처음부터입니다."},
		])

# 플레이어 주변에 살아 있는 적이 있는가 — 각본 발화의 "조용한 창" 판정.
# (known_issues 준수: is_instance_valid 선행 · harmless는 truthiness로 — bool(null) 금지.)
func _combat_near_player(radius: float) -> bool:
	if player == null or not is_instance_valid(player):
		return false
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		if (e as Node).get("harmless"):
			continue
		if (e as Node2D).global_position.distance_to(player.global_position) <= radius:
			return true
	return false

func _reset_overwrite_label_color() -> void:
	if overwrite_label != null and is_instance_valid(overwrite_label):
		overwrite_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))

func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_left", 24)
	top.add_theme_constant_override("margin_top", 16)
	top.add_theme_constant_override("margin_right", 24)
	top.add_theme_constant_override("margin_bottom", 16)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.add_child(top)
	# 두 줄 — 1행: STAGE/맵/HP/XP/VEIL. 2행: SKILL(아래로 분리).
	var top_v := VBoxContainer.new()
	top_v.add_theme_constant_override("separation", 4)
	top.add_child(top_v)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 28)
	top_v.add_child(hb)
	# EXP 진행 바 — 라벨 행과 스킬 행 사이 얇은 줄. 한눈에 레벨업까지 얼마 남았는지(피드백).
	var hb_xp := HBoxContainer.new()
	top_v.add_child(hb_xp)
	xp_bar = ProgressBar.new()
	xp_bar.custom_minimum_size = Vector2(184.0, 7.0)
	xp_bar.show_percentage = false
	xp_bar.max_value = float(GameState.xp_to_next())
	var _xp_bg := StyleBoxFlat.new()
	_xp_bg.bg_color = Color(0.10, 0.12, 0.16, 0.85)
	_xp_bg.set_corner_radius_all(3)
	_xp_bg.set_border_width_all(1)
	_xp_bg.border_color = Color(0.0, 0.0, 0.0, 0.6)
	var _xp_fg := StyleBoxFlat.new()
	_xp_fg.bg_color = Color(0.45, 0.78, 1.0)
	_xp_fg.set_corner_radius_all(3)
	xp_bar.add_theme_stylebox_override("background", _xp_bg)
	xp_bar.add_theme_stylebox_override("fill", _xp_fg)
	hb_xp.add_child(xp_bar)
	var hb2 := HBoxContainer.new()
	hb2.add_theme_constant_override("separation", 12)
	top_v.add_child(hb2)
	hp_label = Label.new()
	xp_label = Label.new()
	stage_label = Label.new()
	map_label = Label.new()
	trust_label = Label.new()
	skill_label = Label.new()
	for l in [stage_label, map_label, hp_label, xp_label, trust_label]:
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
		# 검정 아웃라인 — 밝은 플랫폼 위에서도 또렷하게(가독성/선명도).
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 4)
		hb.add_child(l)
	skill_label.add_theme_font_size_override("font_size", 14)
	skill_label.add_theme_color_override("font_color", Color(0.65, 0.72, 0.82))
	skill_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	skill_label.add_theme_constant_override("outline_size", 3)
	hb2.add_child(skill_label)
	_refresh_hud()
	_maybe_rival_lock_beat()

	# 상시 VEIL 눈 — 게임 내내 우상단에 "VEIL이 함께 본다"를 띄운다(튜토리얼 눈과 동일, 더 작게).
	# 시야 붕괴(veil_degraded) 시 BriefingVisual이 알아서 글리치(드롭아웃·지터·흐려짐).
	var eye := Control.new()
	eye.set_script(load("res://scripts/BriefingVisual.gd"))
	# 우상단 앵커 — 어떤 화면비/해상도에서도 우측 위 모서리에 고정 (offset은 우측 기준 음수).
	eye.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	eye.size = Vector2(54.0, 54.0)
	eye.position = Vector2(-54.0 - 18.0, 14.0)
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(eye)
	var eye_cap := Label.new()
	eye_cap.text = "VEIL"
	eye_cap.add_theme_font_size_override("font_size", 10)
	eye_cap.add_theme_color_override("font_color", Color(0.46, 0.86, 1.0, 0.8))
	eye_cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	eye_cap.add_theme_constant_override("outline_size", 3)
	eye_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	eye_cap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	eye_cap.size = Vector2(54.0, 14.0)
	eye_cap.position = Vector2(-54.0 - 18.0, 70.0)
	hud.add_child(eye_cap)
	# 점수 — VEIL 눈 아래 상시 표시. 스테이지 클리어 가산·만렙 오버플로 '전술 기록'이 어디에도
	# 안 보여 빈 보상으로 읽히던 문제(2026-08-11 피드백).
	score_label = Label.new()
	score_label.add_theme_font_size_override("font_size", 12)
	score_label.add_theme_color_override("font_color", Color(0.75, 0.80, 0.88, 0.9))
	score_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	score_label.add_theme_constant_override("outline_size", 3)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_label.size = Vector2(100.0, 14.0)
	score_label.position = Vector2(-95.0, 90.0)
	hud.add_child(score_label)
	# 덮어쓰기 잔여 핍 — 점수 아래(런 자원 클러스터). 체력 곁에 두면 하트와 같은 것의
	# 중복으로 읽혔다(2026-08-15 지적: "HP와 기록은 뭐가 다른 거야?"). HP=쓰러지기 전
	# 버티는 피격, 기록=쓰러진 뒤 다시 서는 예산 — 층이 다르니 자리도 뗀다.
	overwrite_label = Label.new()
	overwrite_label.add_theme_font_size_override("font_size", 12)
	overwrite_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	overwrite_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	overwrite_label.add_theme_constant_override("outline_size", 3)
	overwrite_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overwrite_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	overwrite_label.size = Vector2(120.0, 14.0)
	overwrite_label.position = Vector2(-105.0, 108.0)
	hud.add_child(overwrite_label)

	var bottom := MarginContainer.new()
	bottom.add_theme_constant_override("margin_left", 24)
	bottom.add_theme_constant_override("margin_bottom", 16)
	bottom.add_theme_constant_override("margin_right", 24)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# anchor가 화면 하단(top=1.0)에 붙은 상태에서 콘텐츠가 위로 확장되도록 grow를 BEGIN으로.
	# (기본 END면 콘텐츠가 화면 아래로 빠져 게이지가 안 보임.)
	bottom.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud.add_child(bottom)
	var bottom_v := VBoxContainer.new()
	bottom_v.add_theme_constant_override("separation", 8)
	bottom.add_child(bottom_v)

	# 쿨다운 게이지 행
	var cd_row := HBoxContainer.new()
	cd_row.add_theme_constant_override("separation", 18)
	bottom_v.add_child(cd_row)
	# 액센트 = 각 동작의 인게임 색(2026-08-11 "특성에 맞게"): 사격=탄환 노랑, 대시=잔상 시안.
	cd_attack_slot = _make_cd_slot("사격", CD_BAR_WIDTH_SHORT, Color(1.0, 0.90, 0.45))
	cd_dash_slot = _make_cd_slot("대시", CD_BAR_WIDTH_SHORT, Color(0.55, 0.90, 1.0))
	cd_skill_slot = _make_cd_slot("스킬")
	cd_barrier_slot = _make_barrier_slot()
	# 스킬 슬롯에만 충전 점 추가 — explosive T3에서 2개 보유 가능.
	# 항상 점 2개 생성하고 색으로 활성/비활성/(미사용) 구분.
	var charges_row := HBoxContainer.new()
	charges_row.name = "ChargesRow"
	charges_row.add_theme_constant_override("separation", 4)
	for i in 2:
		var dot := ColorRect.new()
		dot.custom_minimum_size = Vector2(8, 8)
		dot.size = Vector2(8, 8)
		dot.color = Color(0.20, 0.22, 0.26, 0.4)
		charges_row.add_child(dot)
	cd_skill_slot.add_child(charges_row)
	cd_shield_slot = _make_cd_slot("부활")
	cd_row.add_child(cd_attack_slot)
	cd_row.add_child(cd_dash_slot)
	cd_row.add_child(cd_skill_slot)
	cd_row.add_child(cd_barrier_slot)
	cd_row.add_child(cd_shield_slot)

	var keys := Label.new()
	keys.name = "KeysHint"
	keys.text = _keys_hint_text()
	keys.add_theme_font_size_override("font_size", 13)
	keys.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	keys.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	keys.add_theme_constant_override("outline_size", 3)
	bottom_v.add_child(keys)
	GameState.input_kind_changed.connect(func(_k: String) -> void:
		if is_instance_valid(keys):
			keys.text = _keys_hint_text())

func _keys_hint_text() -> String:
	return GameState.controls_hint_line()

func _make_cd_slot(label_text: String, bar_width: float = CD_BAR_WIDTH, accent: Color = Color(0.55, 0.95, 0.65)) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	# 슬롯 고유 액센트 — 준비 상태 색이자 게이지 정체성(쿨다운 중엔 같은 색을 어둡게).
	v.set_meta("accent", accent)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.62, 0.7, 0.82))
	v.add_child(l)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.14, 0.16, 0.20)
	bar_bg.custom_minimum_size = Vector2(bar_width, 6)
	bar_bg.size = Vector2(bar_width, 6)
	var bar_fill := ColorRect.new()
	bar_fill.name = "Fill"
	bar_fill.color = accent
	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(bar_width, 6)
	bar_bg.add_child(bar_fill)
	v.add_child(bar_bg)
	return v

func _update_cd_slot(slot: Control, remaining: float, max_cd: float) -> void:
	if slot == null or not is_instance_valid(slot):
		return
	var bar_bg := slot.get_child(1) as ColorRect
	if bar_bg == null:
		return
	var fill := bar_bg.get_node_or_null("Fill") as ColorRect
	if fill == null:
		return
	var ratio: float = 1.0
	if max_cd > 0.0:
		ratio = 1.0 - clamp(remaining / max_cd, 0.0, 1.0)
	# 슬롯마다 바 길이가 다르다(짧은 쿨=짧은 바) — 상수 대신 실제 배경 폭 기준.
	fill.size.x = bar_bg.size.x * ratio
	var accent: Color = slot.get_meta("accent", Color(0.55, 0.95, 0.65))
	if ratio >= 1.0:
		fill.color = accent                       # 준비 — 고유색 밝게
	else:
		fill.color = accent.darkened(0.45)        # 쿨다운 중 — 같은 색 어둡게(정체성 유지)

func _refresh_hud() -> void:
	hp_label.text = "HP  %s" % _hearts(GameState.player_hp, GameState.player_max_hp)
	# 덮어쓰기 잔여 — 우상단 점수 아래. ●잔여 ○소모 ×라이벌 잠김(빼앗김은 사라지지 않고 보인다).
	# ×는 U+00D7(곱셈 기호) — U+2715는 Pretendard 서브셋에 없어 웹에서 두부로 깨졌다(2026-08-15).
	if overwrite_label != null and is_instance_valid(overwrite_label):
		if GameState.story_mode:
			overwrite_label.text = ""
		else:
			var ow_max: int = GameState.overwrite_max()
			var ow_left: int = clampi(GameState.overwrite_left, 0, ow_max)
			var ow_locked: int = GameState.rival_locks_active()
			overwrite_label.text = "기록  %s%s%s" % [
				"●".repeat(ow_left), "○".repeat(ow_max - ow_left), "×".repeat(ow_locked)]
	xp_label.text = "LV %d   XP %d/%d" % [GameState.player_level, GameState.player_xp, GameState.xp_to_next()]
	if score_label != null and is_instance_valid(score_label):
		score_label.text = "SCORE %d" % GameState.score
	if xp_bar != null and is_instance_valid(xp_bar):
		xp_bar.max_value = float(GameState.xp_to_next())
		xp_bar.value = float(GameState.player_xp)
	var marks: Array = []
	if GameState.is_high_risk():
		marks.append("[고위험]")
	var marker: String = ("  " + " ".join(marks)) if marks.size() > 0 else ""
	# 표시용 총계 — 막1~3 동안 막4/5 확장을 숨긴다(노드맵 반전 공개와 동일 소스).
	stage_label.text = "STAGE %d/%d%s" % [GameState.current_stage + 1, GameState.displayed_total_stages(), marker]
	# 맵 이름 — RouteData에서 lookup. 튜토리얼/플레이그라운드 등 route_id 없으면 빈 문자열.
	var route_name: String = ""
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		if route.get("id", "") == GameState.current_route_id:
			route_name = str(route.get("name", ""))
			break
	if map_label != null:
		map_label.text = (" ·  " + route_name) if route_name != "" else ""
	# VEIL 신뢰 — 5점 게이지, 0에서 차오름(재설계 §3.1). 색은 차가움→따뜻함.
	if trust_label != null:
		trust_label.text = "VEIL " + GameState.veil_trust_gauge_dots()
		trust_label.add_theme_color_override("font_color", GameState.veil_tone_color())
	var names: Array = []
	for sid in GameState.skills:
		# 대시·이중점프(베이스라인)는 기본 조작 — 스킬 보유 목록에서 제외(2026-08-11 피드백:
		# 시작부터 항상 떠 있어 "스킬로 넣었나" 혼란. 트리 화면의 "(기본)" 표기는 유지).
		if SkillTreeData.BASELINE.has(str(sid)):
			continue
		var tier: int = int(GameState.skills[sid])
		var skill: Dictionary = SkillSystem.find_by_id(str(sid), tier)
		var display: String = str(skill.get("name", sid))
		if tier > 1:
			display += " T%d" % tier
		names.append(display)
	if names.size() > 0:
		skill_label.text = "SKILL  " + ", ".join(names)
	else:
		skill_label.text = "SKILL"
	# 쿨다운 게이지 갱신
	if player != null and is_instance_valid(player):
		# 티어에 따라 실제 max 쿨다운이 달라지므로 player의 helper를 통해 조회.
		_update_cd_slot(cd_attack_slot, float(player.get("attack_cd")), player.get_attack_cd_max())
		_update_cd_slot(cd_dash_slot, float(player.get("dash_cd")), player.get_dash_cd_max())
		_update_cd_slot(cd_skill_slot, float(player.get("skill_cd")), player.get_skill_cd_max())
		# 보유 스킬에 따라 슬롯 가시성
		if cd_dash_slot != null:
			cd_dash_slot.visible = GameState.has_skill("dash")
		if cd_skill_slot != null:
			cd_skill_slot.visible = GameState.has_skill("explosive")
			_update_skill_charges()
		if cd_barrier_slot != null:
			cd_barrier_slot.visible = GameState.has_skill("barrier")
			if cd_barrier_slot.visible:
				_update_barrier_slot()
		if cd_shield_slot != null:
			cd_shield_slot.visible = GameState.has_skill("shield")
			if cd_shield_slot.visible:
				_update_shield_slot()

# 방어막 슬롯 — 일반 cd_slot과 달리 헥스 셀 8개로 표시 (에너지 방어막 패턴).
# 충전이 진행되면 셀이 좌→우로 청록빛으로 차오름. ready 상태에서는 전체 셀 밝게 + 펄스.
const BARRIER_HEX_COUNT: int = 8

func _make_barrier_slot() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.text = "방어막"
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.55, 0.85, 1.0))
	v.add_child(l)
	var holder := Control.new()
	holder.name = "HexHolder"
	holder.custom_minimum_size = Vector2(CD_BAR_WIDTH, 14)
	holder.size = Vector2(CD_BAR_WIDTH, 14)
	v.add_child(holder)
	# CD_BAR_WIDTH(90) 안에 헥스 8개 + 간격 2px씩.
	var gap: float = 2.0
	var cell_w: float = (CD_BAR_WIDTH - gap * float(BARRIER_HEX_COUNT - 1)) / float(BARRIER_HEX_COUNT)
	for i in BARRIER_HEX_COUNT:
		var hex := Polygon2D.new()
		hex.name = "Hex%d" % i
		var cx: float = float(i) * (cell_w + gap) + cell_w * 0.5
		var cy: float = 7.0
		var hw: float = cell_w * 0.5
		var hh: float = 5.0
		# 가로 평평 헥스 (좌/우 점이 뾰족, 위/아래 평면)
		hex.polygon = PackedVector2Array([
			Vector2(cx - hw * 0.5, cy - hh),
			Vector2(cx + hw * 0.5, cy - hh),
			Vector2(cx + hw,       cy),
			Vector2(cx + hw * 0.5, cy + hh),
			Vector2(cx - hw * 0.5, cy + hh),
			Vector2(cx - hw,       cy),
		])
		hex.color = Color(0.12, 0.18, 0.24, 0.85)
		holder.add_child(hex)
	return v

func _update_barrier_slot() -> void:
	if cd_barrier_slot == null or player == null or not is_instance_valid(player):
		return
	var holder := cd_barrier_slot.get_node_or_null("HexHolder") as Control
	if holder == null:
		return
	var ready: bool = bool(player.get("barrier_ready"))
	var ratio: float
	var remaining: float = 0.0
	if ready:
		ratio = 1.0
	else:
		var charge_t: float = float(player.get("barrier_charge_t"))
		var tier: int = GameState.get_skill_tier("barrier")
		var charge_max: float = 6.0 if tier >= 2 else 10.0  # Player.BARRIER_CHARGE_T1/T2
		ratio = clamp(charge_t / charge_max, 0.0, 1.0)
		remaining = maxf(0.0, charge_max - charge_t)
	# 라벨에 실제 남은 초 표시(헥스 칸 수가 직관적이지 않다는 피드백) — "방어막  6s" / "방어막  준비".
	var blbl := cd_barrier_slot.get_child(0) as Label
	if blbl != null:
		blbl.text = "방어막  준비" if ready else "방어막  %ds" % int(ceil(remaining))
	var filled: int = int(round(ratio * float(BARRIER_HEX_COUNT)))
	var ready_color: Color = Color(0.55, 0.95, 1.0, 0.95)
	var charging_color: Color = Color(0.35, 0.70, 0.95, 0.90)
	var empty_color: Color = Color(0.10, 0.16, 0.22, 0.85)
	for i in BARRIER_HEX_COUNT:
		var hex := holder.get_node_or_null("Hex%d" % i) as Polygon2D
		if hex == null:
			continue
		if i < filled:
			hex.color = ready_color if ready else charging_color
		else:
			hex.color = empty_color
	if ready:
		var pulse: float = 0.80 + sin(float(Time.get_ticks_msec()) / 200.0) * 0.20
		holder.modulate.a = pulse
	else:
		holder.modulate.a = 1.0

# 비상 부활 슬롯 — 일반 cd_slot(fill 바) 재사용. 부활 가능하면 "부활  ✓"(가득/초록),
# T3 재충전 중이면 남은 초 카운트다운("부활  12s")으로 진행 바 채워짐. (T1/T2는 1회용이라
# 사용 후 skills에서 erase → 슬롯 자체가 숨겨진다.)
func _update_shield_slot() -> void:
	if cd_shield_slot == null or player == null or not is_instance_valid(player):
		return
	var lbl := cd_shield_slot.get_child(0) as Label
	var bar_bg := cd_shield_slot.get_child(1) as ColorRect
	if bar_bg == null:
		return
	var fill := bar_bg.get_node_or_null("Fill") as ColorRect
	if fill == null:
		return
	var spent: bool = bool(player.get("shield_spent"))
	if spent:
		var remaining: float = maxf(0.0, float(player.get("shield_recharge_t")))
		var ratio: float = 1.0 - clamp(remaining / 30.0, 0.0, 1.0)  # Player.SHIELD_RECHARGE_TIME
		fill.size.x = CD_BAR_WIDTH * ratio
		fill.color = Color(0.55, 0.78, 0.95)  # 재충전 중
		if lbl != null:
			lbl.text = "부활  %ds" % int(ceil(remaining))
	else:
		fill.size.x = CD_BAR_WIDTH
		fill.color = Color(0.55, 0.95, 0.65)  # 준비
		if lbl != null:
			lbl.text = "부활  준비"

# 스킬 충전 점 갱신 — explosive T3에서 2개 보유. 색으로 활성/비활성/(미사용) 구분.
func _update_skill_charges() -> void:
	if cd_skill_slot == null or player == null or not is_instance_valid(player):
		return
	var charges_row := cd_skill_slot.get_node_or_null("ChargesRow") as HBoxContainer
	if charges_row == null:
		return
	var cur: int = int(player.get("skill_charges"))
	var max_c: int = int(player.get("skill_max_charges"))
	for i in charges_row.get_child_count():
		var dot := charges_row.get_child(i) as ColorRect
		if dot == null:
			continue
		if i >= max_c:
			# T1/T2 — 두번째 점은 미사용(회색 옅게)
			dot.color = Color(0.15, 0.16, 0.20, 0.35)
		elif i < cur:
			# 활성 충전
			dot.color = Color(0.95, 0.65, 0.30)
		else:
			# 충전 중(비활성)
			dot.color = Color(0.30, 0.32, 0.36)

func _hearts(hp: int, max_hp: int) -> String:
	var s: String = ""
	for i in max_hp:
		s += "♥" if i < hp else "♡"
	return s

func _spawn_enemies() -> void:
	# 보스 모드 (lab 등): boss 필드가 있으면 보스만 spawn (일반 적 + 웨이브 무시).
	var boss_meta: Dictionary = _map_data.get("boss", {})
	if not boss_meta.is_empty():
		_spawn_boss(boss_meta)
		return
	# 웨이브 모드 (datacenter 등): waves 필드가 있으면 첫 웨이브만 즉시 spawn.
	# 이후 웨이브는 _on_enemy_killed에서 트리거 조건 검사 후 spawn.
	var waves: Array = _map_data.get("waves", [])
	if not waves.is_empty():
		_init_waves(waves)
		_spawn_wave(0)
		return
	# 일반 모드 — 모든 적 즉시 spawn.
	var enemies: Dictionary = _map_data.get("enemies", {})
	if enemies.is_empty():
		_spawn_enemies_fallback()
		return
	_spawn_from_enemies_dict(enemies, -1)
	_spawn_deceits()
	_spawn_feigns()

# §4 거짓 렌더 — 위장한 적(참 종류로 스폰 + disguise_as). deceits: [{"pos","true","as"}]. 맵당 소수(드묾).
func _spawn_deceits() -> void:
	var deceits: Array = _deceit_slots("deceits")
	if deceits.is_empty() or GameState.story_mode:
		return   # 스토리 모드는 단순화 — 거짓 렌더 제외
	var kind_map: Dictionary = {"patrol": 0, "sniper": 1, "drone": 2, "bomber": 3, "shield": 4, "jammer": 5, "caller": 6}
	for item in deceits:
		var d: Dictionary = item
		var true_kind: int = int(kind_map.get(str(d.get("true", "bomber")), 3))
		var as_kind: int = int(kind_map.get(str(d.get("as", "patrol")), 0))
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		_spawn_enemy(true_kind, pos, -1, as_kind)

# §4 거짓 렌더 — 시선 거짓(딴 데 보는 척 기습). feigns: [{pos}]. patrol이 각성을 숨긴 채 응시하다 근접 시 홱 기습.
func _spawn_feigns() -> void:
	var feigns: Array = _deceit_slots("feigns")
	if feigns.is_empty() or GameState.story_mode:
		return   # 스토리 모드는 단순화 — 거짓 렌더 제외(deceits와 동형)
	for item in feigns:
		var d: Dictionary = item
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		_spawn_enemy(0, pos, -1, -1, true)   # patrol(0) + feign

# 웨이브 모드 / 일반 모드 공통 — enemies 딕셔너리에서 risk 배율 적용해 spawn.
# wave_idx: 0+ 면 wave에 속한 적 (kill 시 wave 카운트 감소), -1이면 일반 적.
func _spawn_from_enemies_dict(enemies: Dictionary, wave_idx: int) -> void:
	var kind_map: Dictionary = {"patrol": 0, "sniper": 1, "drone": 2, "bomber": 3, "shield": 4, "jammer": 5, "caller": 6}
	var mult: float = GameState.enemy_count_multiplier()
	for kind_name in enemies.keys():
		# 스토리 모드 — 드론은 위에서 떨어지는 폭격이라 패턴 인지가 어렵다. 통째로 스킵.
		if GameState.story_mode and str(kind_name) == "drone":
			continue
		var positions: Array = enemies[kind_name]
		if positions.is_empty():
			continue
		var kind_int: int = int(kind_map.get(kind_name, 0))
		# 둥지 저격수(좁은 64px 단독 발판 거치)는 risk 배율로 복제하지 않는다. 추가분이
		# base_p±120 오프셋으로 스폰되면 둥지 발판을 벗어나 허공에서 떨어진다(감시탑 risk3에서
		# 발생 — 우측 둥지 추가 저격수가 시작 지점으로 낙하). 정의된 위치에 정확히 1명씩만.
		# 사용자 피드백 2026-06-12.
		if str(kind_name) == "sniper" and bool(_map_data.get("nest_snipers", false)):
			for p in positions:
				_spawn_enemy(kind_int, p, wave_idx)
			continue
		# 재머는 특정 지점에 놓인 장치 — risk 배율 복제/오프셋 대상이 아니다(nest_snipers와 동형).
		# 호출병도 동일 — 자체가 증원 배수라 개체수 배율까지 겹치면 곱연산(기준 2 위반).
		if str(kind_name) == "jammer" or str(kind_name) == "caller":
			for p in positions:
				_spawn_enemy(kind_int, p, wave_idx)
			continue
		var target: int = int(round(float(positions.size()) * mult))
		target = clamp(target, 0, positions.size() * 2)
		if target >= positions.size():
			for p in positions:
				_spawn_enemy(kind_int, p, wave_idx)
			var extra: int = target - positions.size()
			for i in extra:
				var base_p: Vector2 = positions[i % positions.size()]
				var jit: Vector2 = base_p + Vector2(randf_range(-120.0, 120.0), 0.0)
				_spawn_enemy(kind_int, _keep_in_gate_zone(base_p, jit), wave_idx)
		else:
			for i in target:
				_spawn_enemy(kind_int, positions[i], wave_idx)

# risk 배율 추가 스폰(±120 흔들기)이 검증 구역 경계를 넘으면, 구역 안 배치를 복제한
# 적인데도 문 조건에서 빠진다 — 플레이어 눈엔 "게이트 앞에 살아 있는데 세지 않는 적"이라
# 판정이 고장난 것처럼 읽힌다. 원 위치가 구역 안이면 흔들린 위치도 구역 안에 묶는다.
func _keep_in_gate_zone(base_p: Vector2, jittered: Vector2) -> Vector2:
	var g: Dictionary = _map_data.get("mid_gate", {})
	if g.is_empty() or str(g.get("mode", "")) != "clear":
		return jittered
	var zone: Array = g.get("zone", [])
	if zone.size() < 2:
		return jittered
	var z0: float = float(zone[0])
	var z1: float = minf(float(zone[1]), float(g.get("x", 0.0)) - 40.0)
	if base_p.x < z0 or base_p.x > z1:
		return jittered
	return Vector2(clampf(jittered.x, z0 + 20.0, z1 - 20.0), jittered.y)

# ─── ARENA 웨이브 시스템 ───
# datacenter (world_layout §2.8) 처럼 단계 spawn이 필요한 ARENA 전용.
# trigger:
#   "immediate"  — 즉시
#   "prev_half"  — 직전 웨이브 절반(올림) 처치 시
#   "prev_clear" — 직전 웨이브 전원 처치 시
var _waves_data: Array = []
var _wave_initial_count: Array = []  # 각 웨이브 spawn 직후 적 수 (risk mult 반영)
var _wave_alive_count: Array = []    # 현재 살아있는 적 수
var _wave_spawned: Array = []        # bool — spawn 이미 됐는지(예고 시작 시점에 set — 중복 트리거 방지)
var _wave_banners_played: Array = [] # bool — 배너 표시 여부
var _wave_pending_spawns: int = 0    # 예고(텔레그래프) 중이라 아직 투입 전인 웨이브 수 — 조기 클리어 방지

func _init_waves(waves: Array) -> void:
	_waves_data = waves
	_wave_initial_count.clear()
	_wave_alive_count.clear()
	_wave_spawned.clear()
	_wave_banners_played.clear()
	_wave_pending_spawns = 0
	for i in waves.size():
		_wave_initial_count.append(0)
		_wave_alive_count.append(0)
		_wave_spawned.append(false)
		_wave_banners_played.append(false)

# 증원 스폰 예고 — 스폰 지점 바닥의 경고 셰브론 + 차단문 개방 광선. lifetime 뒤 스스로 소멸.
class _WaveSpawnTelegraph extends Node2D:
	var lifetime: float = 0.85
	var t: float = 0.0
	func _ready() -> void:
		z_index = 5
	func _process(delta: float) -> void:
		t += delta
		if t >= lifetime:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = clampf(t / maxf(lifetime, 0.01), 0.0, 1.0)
		var blink: float = 0.55 + 0.45 * sin(t * 26.0)
		var col := Color(1.0, 0.32, 0.30, (0.35 + 0.45 * k) * blink)
		# 바닥 경고 셰브론(∨ 두 겹) — "여기로 온다"
		for i in 2:
			var off: float = -8.0 - float(i) * 10.0
			draw_polyline(PackedVector2Array([
				Vector2(-14.0, off - 8.0), Vector2(0.0, off), Vector2(14.0, off - 8.0),
			]), col, 3.0)
		# 개방 광선 — 차단문이 열리는 세로 빛기둥(점점 밝아짐)
		var beam := Color(1.0, 0.55, 0.40, 0.10 + 0.22 * k)
		draw_rect(Rect2(Vector2(-10.0, -86.0), Vector2(20.0, 86.0)), beam, true)

const WAVE_SPAWN_TELEGRAPH: float = 0.85

func _spawn_wave(idx: int) -> void:
	if idx < 0 or idx >= _waves_data.size():
		return
	if _wave_spawned[idx]:
		return
	_wave_spawned[idx] = true
	# 증원(두 번째 웨이브부터)은 예고 후 투입 — 배너와 함께 스폰 지점 경고 텔레그래프를 먼저 보여줘
	# "어디서 오는지"를 읽게 한다(충원 연출 피드백 2026-08-11). 첫 웨이브는 입장 직후라 즉시.
	if idx >= 1:
		if not _wave_banners_played[idx]:
			_wave_banners_played[idx] = true
			_show_wave_banner(str(_waves_data[idx].get("banner", "WAVE %d" % (idx + 1))))
		_telegraph_wave_spawn(idx)
		return
	_do_spawn_wave(idx)

func _telegraph_wave_spawn(idx: int) -> void:
	_wave_pending_spawns += 1
	var wave: Dictionary = _waves_data[idx]
	var enemies: Dictionary = wave.get("enemies", {})
	SfxPlayer.play("hatch_open")   # 차단문 개방음 — 증원 투입 신호
	for kind_name in enemies.keys():
		var positions: Array = enemies[kind_name]
		for p in positions:
			var tel := _WaveSpawnTelegraph.new()
			tel.lifetime = WAVE_SPAWN_TELEGRAPH
			tel.position = p
			add_child(tel)
	# pause 존중 타이머(process_always=false). Stage가 해제되면 메서드 Callable은 자동 무효 —
	# 람다를 쓰면 freed self 참조 크래시 위험이 있어 반드시 메서드 bind로 연결.
	get_tree().create_timer(WAVE_SPAWN_TELEGRAPH, false).timeout.connect(_do_spawn_wave.bind(idx))

func _do_spawn_wave(idx: int) -> void:
	if idx >= 1:
		_wave_pending_spawns = maxi(0, _wave_pending_spawns - 1)
	var before: int = get_tree().get_nodes_in_group("enemy").size()
	var wave: Dictionary = _waves_data[idx]
	var enemies: Dictionary = wave.get("enemies", {})
	_spawn_from_enemies_dict(enemies, idx)
	# 실제 spawn된 수 — group 차이로 계산 (mult 적용 후 정확)
	var after: int = get_tree().get_nodes_in_group("enemy").size()
	var spawned: int = after - before
	_wave_initial_count[idx] = spawned
	_wave_alive_count[idx] = spawned
	# ARENA enemy_clear 카운트 갱신 — _setup_arena_clear_tracking이 wave 0 직후 측정한 값에
	# 후속 웨이브 spawn 수를 누적. (idx==0은 _setup이 측정 전이라 카운트 누적 X)
	if idx >= 1:
		_enemies_remaining += spawned
	_assign_wave_escorts()

# 혼성 진형(2026-08-20 사용자 "딜/힐/탱 조합을 갖춰서 오면 훨씬 위협적이지 않겠어?") —
# 웨이브 스폰 직후, 방패병 근처(300px)의 정찰병을 그 방패의 호위로 붙인다. 데이터 스키마 변경
# 없이 좌표 근접만으로 스쿼드가 성립하고, risk 배율 복제분(±120px)도 자연히 같은 스쿼드에 든다.
# 웨이브 맵 한정 — 일반 맵의 기존 배치 밸런스는 건드리지 않는다.
func _assign_wave_escorts() -> void:
	var shields: Array = []
	var patrols: Array = []
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var kt = (e as Node).get("enemy_type")
		if kt == null:
			continue
		if (e as Node).get("dead"):   # truthiness — 속성 없는 노드는 위 enemy_type 게이트가 거름
			continue
		if int(kt) == 4:
			shields.append(e)
		elif int(kt) == 0 and (e as Node).get("escort_leader") == null:
			patrols.append(e)
	if shields.is_empty():
		return
	for pa in patrols:
		var best: Node = null
		var best_d: float = 300.0
		for sh in shields:
			var d: float = (pa as Node2D).global_position.distance_to((sh as Node2D).global_position)
			if d < best_d:
				best_d = d
				best = sh
		if best != null:
			(pa as Node).set("escort_leader", best)

# ─── 호출병(caller) 증원 ───
# Enemy(CALLER)가 예고(안테나 신호 링)를 마치면 호출. 실제 스폰은 텔레그래프 0.6s 뒤 타이머로
# (타이머는 메서드 bind — 람다 freed self 금지 · 물리 콜백 동기 스폰 금지 규약과 동형).
# 불려 온 증원은 no_reward — 호출병을 살려두고 XP를 파밍하는 구멍을 원천 차단(경보 진압 경비 동형).
const CALLER_SUMMON_KINDS: Array = [[0, 0], [0, 3]]   # 호출 회차별 구성 — 정찰 2 / 정찰+자폭 교대

func request_caller_summon(caller: Node2D) -> void:
	if goal_reached or not is_inside_tree():
		return
	var calls: int = int(caller.get("caller_calls"))
	caller.set("caller_calls", calls + 1)
	var kinds: Array = CALLER_SUMMON_KINDS[calls % CALLER_SUMMON_KINDS.size()]
	var world_w: float = (_map_data.get("world_size", Vector2(1920.0, 1080.0)) as Vector2).x
	var side: float = -1.0
	SfxPlayer.play_at("hatch_open", caller.global_position)
	for k in kinds:
		var px: float = clampf(caller.global_position.x + side * randf_range(120.0, 190.0), 60.0, world_w - 60.0)
		side = -side
		var pos := Vector2(px, caller.global_position.y)
		var tel := _WaveSpawnTelegraph.new()
		tel.lifetime = 0.6
		tel.position = pos
		add_child(tel)
		get_tree().create_timer(0.6, false).timeout.connect(_caller_do_spawn.bind(int(k), pos, caller))

func _caller_do_spawn(kind: int, pos: Vector2, caller: Node2D) -> void:
	if goal_reached or not is_inside_tree():
		return
	var e := _spawn_enemy(kind, pos, -1, -1, false, true)   # no_reward — 호출 증원은 보상 없음
	_enemies_remaining += 1
	if is_instance_valid(caller) and caller.has_method("register_summon"):
		caller.call("register_summon", e)

func _show_wave_banner(text: String) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 22
	add_child(layer)
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 32)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.30))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 5)
	l.position = Vector2(140, 200)
	l.size = Vector2(1000, 50)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	layer.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.4)
	tw.tween_interval(1.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(layer.queue_free)

# 웨이브 진행 검사 — 적 처치 시점에 호출. 트리거 충족 시 다음 웨이브 spawn.
func _check_wave_progress(killed_wave_idx: int) -> void:
	if killed_wave_idx < 0 or killed_wave_idx >= _wave_alive_count.size():
		return
	# 다음 웨이브 트리거 검사
	var next_idx: int = killed_wave_idx + 1
	if next_idx >= _waves_data.size():
		return
	if _wave_spawned[next_idx]:
		return
	var next_wave: Dictionary = _waves_data[next_idx]
	var trig: String = str(next_wave.get("trigger", "prev_clear"))
	var should_spawn: bool = false
	match trig:
		"immediate":
			should_spawn = true
		"prev_half":
			# 직전 웨이브가 절반 이상 처치됐는가
			var initial: int = _wave_initial_count[killed_wave_idx]
			var alive: int = _wave_alive_count[killed_wave_idx]
			var killed: int = initial - alive
			should_spawn = killed >= int(ceil(float(initial) * 0.5))
		"prev_clear":
			should_spawn = _wave_alive_count[killed_wave_idx] <= 0
	if should_spawn:
		_spawn_wave(next_idx)

func _spawn_enemies_fallback() -> void:
	# MapData 명세가 없을 때 (디버그/플레이그라운드 등) 단순 흩기 폴백.
	var counts: Dictionary = {"patrol": 4, "sniper": 0, "drone": 0, "bomber": 0, "shield": 0}
	for i in counts["patrol"]:
		var x: float = lerp(400.0, STAGE_LENGTH - 300.0, float(i + 1) / float(counts["patrol"] + 1))
		_spawn_enemy(0, Vector2(x, GROUND_Y - 30.0))

# ─── 보스 SENTINEL spawn + UI + 페이즈/자폭 hook ───
# world_layout §2.10. lab 챔버에서 단독 등장.

var boss: Node = null
var boss_hp_bar_layer: CanvasLayer = null
var boss_hp_bar_fill: ColorRect = null
var _boss_vent_line_shown: bool = false  # 첫 과부하 배기 VEIL 해설 1회
var boss_hp_label: Label = null
var boss_self_destruct_layer: CanvasLayer = null
var boss_self_destruct_label: Label = null
var boss_self_destruct_timer_t: float = 0.0
var boss_clear_dialogue_played: bool = false
# §7 SENTINEL reveal — 라이벌 첫 발화 비트. 보스 처치 후 정적→라이벌→내 VEIL 동요가 끝나야 회수로 진행.
var _sentinel_reveal_done: bool = false

func _spawn_boss(boss_meta: Dictionary) -> void:
	var btype: String = str(boss_meta.get("type", "sentinel"))
	if btype != "sentinel":
		return
	var spawn_pos: Vector2 = boss_meta.get("spawn", Vector2(960.0, 280.0))
	boss = BossSentinel.new()
	boss.global_position = spawn_pos
	add_child(boss)
	# 시그널 연결 — 같은 killed 시그널을 ARENA enemy_clear가 인식하도록.
	boss.killed.connect(_on_boss_killed)
	boss.phase_changed.connect(_on_boss_phase_changed)
	boss.self_destruct_started.connect(_on_boss_self_destruct_started)
	boss.self_destruct_disarmed.connect(_on_boss_self_destruct_disarmed)
	boss.vent_started.connect(_on_boss_vent_started)
	boss.overheat_stalled.connect(_on_boss_overheat_stalled)
	_build_boss_hp_bar()
	# 플레이어 성장 스케일(2026-08-10) — 15스테이지 확장으로 s8 시점 화력이 원 설계(9스테이지)보다
	# 높아 보스가 너무 빨리 녹는다는 피드백. 공격 계열 티어 합 × 2 HP 가산.
	# 상한 12→16(2026-08-11): XP 곡선 상향과 짝 — 공격 만렙 도달 시에도 보스전이 싱겁지 않게(최대 40).
	if not GameState.story_mode:
		var off_tiers: int = GameState.get_skill_tier("fire_boost") + GameState.get_skill_tier("multishot") + GameState.get_skill_tier("explosive")
		boss.apply_hp_bonus(mini(off_tiers * 2, 16))
	# 보스전 진입 안내 — 본편은 인트로 컷씬의 VEIL 대사가 대신한다(중복 방지). 스토리 모드는 인트로가
	# 없으므로 기존 1회성 안내 유지(피드백: 사격법 혼란).
	if GameState.story_mode:
		_show_boss_alert("빨간 불빛이 번뜩이면 그 자리를 비키십시오. 신호가 멎은 틈이 사격 타이밍입니다.", Color(0.95, 0.55, 0.55), 4.0)
	# §7 복선 — 전투 중 가끔 거짓-렌더 tell과 똑같은 지직거림을 흘린다(1회차엔 못 잡고, reveal 후 재해석).
	_start_boss_glitch_foreshadow()
	_play_boss_intro()

func _build_boss_hp_bar() -> void:
	# 화면 상단 중앙 — 보스 HP 게이지. 12칸 단위로 표시.
	boss_hp_bar_layer = CanvasLayer.new()
	boss_hp_bar_layer.layer = 21
	add_child(boss_hp_bar_layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	boss_hp_bar_layer.add_child(holder)
	boss_hp_label = Label.new()
	boss_hp_label.text = "SENTINEL"
	boss_hp_label.add_theme_font_size_override("font_size", 14)
	boss_hp_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
	# 게이지 왼쪽 나란히 — 중앙 상단(560,60)은 HUD 2행(SKILL 목록)이 길어지면 겹친다
	# (보스전쯤엔 스킬이 많아 반드시 겹침, 2026-08-11 피드백). 위(HUD ~y71)·아래(경고 96·자폭 110)
	# 모두 선점돼 있어 바 옆이 유일한 빈 자리.
	boss_hp_label.position = Vector2(320.0, 77.0)
	boss_hp_label.size = Vector2(112.0, 20.0)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(boss_hp_label)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.08, 0.85)
	bg.position = Vector2(440.0, 84.0)
	bg.size = Vector2(400.0, 8.0)
	holder.add_child(bg)
	boss_hp_bar_fill = ColorRect.new()
	boss_hp_bar_fill.color = Color(0.95, 0.30, 0.30)
	boss_hp_bar_fill.position = Vector2(440.0, 84.0)
	boss_hp_bar_fill.size = Vector2(400.0, 8.0)
	holder.add_child(boss_hp_bar_fill)

func _refresh_boss_hp_bar() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if boss_hp_bar_fill == null:
		return
	# 분모는 인스턴스 max_hp — 성장 스케일(apply_hp_bonus)·스토리 축소가 반영된 실제 최대치.
	var ratio: float = clamp(float(boss.get("hp")) / maxf(float(boss.get("max_hp")), 1.0), 0.0, 1.0)
	boss_hp_bar_fill.size.x = 400.0 * ratio
	# 증기 과열 실속 중 — "지금이 보상 창"을 HP바 색으로도(과열 글로우와 같은 금색 계열).
	var stall_v = boss.get("stall_t")
	if stall_v != null and float(stall_v) > 0.0:
		boss_hp_bar_fill.color = Color(0.98, 0.82, 0.30)
		return
	# 과부하 배기 중 — "지금은 안 박힌다"를 HP바 색으로도(증기 tell과 같은 청백 계열).
	var vent_v = boss.get("vent_t")
	if vent_v != null and float(vent_v) > 0.0:
		boss_hp_bar_fill.color = Color(0.55, 0.80, 0.95)
		return
	# 페이즈에 따라 색 변화
	var ph: int = int(boss.get("phase"))
	match ph:
		1: boss_hp_bar_fill.color = Color(0.95, 0.30, 0.30)
		2: boss_hp_bar_fill.color = Color(0.95, 0.55, 0.20)
		3: boss_hp_bar_fill.color = Color(1.0, 0.18, 0.18)

func _on_boss_phase_changed(new_phase: int) -> void:
	# 페이즈 인지 — 화면 플래시 + 카메라 흔들림 + 강조 자막(큰 폰트 + 박스 배경).
	_screen_flash(Color(1.0, 0.20, 0.22, 0.55), 0.06, 0.45)
	_camera_shake(8.0 if new_phase == 2 else 14.0, 0.45)
	match new_phase:
		2:
			# 리워크(sentinel_rework §3 P2) — 시설 소환 = 룰 변화. 스폰은 물리 콜백 밖으로
			# (take_damage 경유 시그널 · known_issues "flushing 중 동기 스폰 금지").
			_show_boss_alert("격납 개방. 시설 설비가 전투에 개입합니다.", Color(1.0, 0.78, 0.40), 3.2)
			_summon_facility_hazards.call_deferred()
		3:
			_show_boss_alert("코어가 불안정합니다. 거리 두고, 빠르게.", Color(1.0, 0.45, 0.45), 3.0)

# ─── P2 시설 소환(리워크 2026-08-22 · "시설이 연기하는 최종 보스") ───────────────
# 막1~2에서 배운 시설 기믹(증기 분출 · 방전 아크)이 보스의 무기로 무대에 등장한다 —
# 바닥 해치 개방 연출 + SteamVent 2기 + ElectricArc 2구간. 보스 격파 시 함께 정리.
var _boss_facility_nodes: Array = []

func _summon_facility_hazards() -> void:
	if boss == null or not is_instance_valid(boss) or GameState.story_mode:
		return
	if not _boss_facility_nodes.is_empty():
		return
	SfxPlayer.play("hatch_open")
	# 바닥 해치 개방 플래시 — 소환 지점 4곳에 짧은 앰버 밴드.
	for hx in [480.0, 1440.0, 720.0, 1200.0]:
		var hatch := ColorRect.new()
		hatch.color = Color(0.95, 0.75, 0.30, 0.55)
		hatch.position = Vector2(float(hx) - 60.0, GROUND_Y - 4.0)
		hatch.size = Vector2(120.0, 8.0)
		hatch.z_index = 2
		add_child(hatch)
		var htw := hatch.create_tween()
		htw.tween_property(hatch, "modulate:a", 0.0, 1.2)
		htw.tween_callback(hatch.queue_free)
	# 증기 분출구 2기 — 냉각 설비의 회수. 높이 200(중층 피난 발판은 침범 안 함).
	# plume 560 = 분출 시 옅은 열기둥이 호버 라인(280)까지 닿는다 — 보스를 그 위로 유인하면
	# 과열 실속(카운터플레이 2026-08-22). 열기둥은 플레이어 무해(짙은 증기만 위험).
	for entry in [[480.0, 0.0], [1440.0, 0.5]]:
		var e: Array = entry
		var vent := SteamVent.new()
		vent.position = Vector2(float(e[0]), GROUND_Y)
		vent.height = 200.0
		vent.plume_height = 560.0
		vent.phase = float(e[1])
		add_child(vent)
		_boss_facility_nodes.append(vent)
	# 방전 아크 2구간 — 변전 설비의 회수. 지상 체류 비용(스텝·중층 발판이 답).
	for entry in [[620.0, 820.0, 0.0], [1100.0, 1300.0, 0.5]]:
		var e: Array = entry
		var arc := ElectricArc.new()
		add_child(arc)
		arc.setup(float(e[0]), float(e[1]), GROUND_Y, float(e[2]), 1)
		_boss_facility_nodes.append(arc)
	# 학습 회수를 말로 1회 — "지나온 설비가 이 병기의 몸".
	get_tree().create_timer(1.2, false).timeout.connect(func() -> void:
		if is_inside_tree():
			_show_veil_subtitle(VeilDialogue.banded("증기와 방전, 지나온 설비들입니다. 리듬은 이미 배우셨습니다. 바닥에 오래 서지 마십시오.", "증기랑 방전, 지나온 설비들이에요. 리듬은 이미 배웠잖아요. 바닥에 오래 서지 말아요."), 4.2))
	# 카운터플레이 티칭 1회(2026-08-22) — 설비는 보스만의 무기가 아니다.
	# EN: "That machine runs hot. Herd it over a steam column and it will stop for a moment."
	# ("기체" = 어려운 한자어 + 증기(氣體) 동음 오독 지적 · 무맥락 검수 1차, 2026-08-23)
	get_tree().create_timer(6.2, false).timeout.connect(func() -> void:
		if is_inside_tree() and boss != null and is_instance_valid(boss):
			_show_veil_subtitle(VeilDialogue.banded("저 기계는 열에 약합니다. 증기 기둥 위로 몰아넣으면 잠깐 멈춥니다.", "저 기계, 열에 약해요. 증기 기둥 위로 몰아넣으면 잠깐 멈춥니다."), 4.0))

func _clear_facility_hazards() -> void:
	# 즉시 제거 — 노드 바인딩 페이드 트윈이 격파 프레임에서 완주를 보장하지 못했다
	# (2026-08-22 스모크 실측: 0.83s 뒤에도 잔존). 격파 플래시·소등이 이질감을 가린다.
	for n in _boss_facility_nodes:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_boss_facility_nodes.clear()

# 증기 과열 실속(카운터플레이 성공) — 흔들림 + 첫 회에 보상 창을 말로.
var _boss_stall_line_shown: bool = false

func _on_boss_overheat_stalled() -> void:
	_camera_shake(9.0, 0.4)
	if _boss_stall_line_shown:
		return
	_boss_stall_line_shown = true
	# EN: "It took the steam head-on. Overheated, control's gone. Right now every shot goes in clean."
	# ("흡기구·코어" = 화면에 없는 내부 부품 지적 · 무맥락 검수 1차 — 화면의 라벨(과열·제어 불능)과
	# 같은 말로 설명한다, 2026-08-23)
	_show_veil_subtitle(VeilDialogue.banded("증기를 그대로 뒤집어썼습니다. 과열로 제어를 잃었습니다. 지금은 쏘는 만큼 전부 박힙니다.", "증기를 제대로 먹였습니다. 과열로 제어를 잃었어요. 지금은 쏘는 만큼 전부 박힙니다."), 3.6)

# 첫 과부하 배기 — 무적+김의 "왜"를 한 번은 말로(2026-08-20 사용자 "뭐라도 이해가 되게").
func _on_boss_vent_started() -> void:
	if _boss_vent_line_shown:
		return
	_boss_vent_line_shown = true
	_show_veil_subtitle(VeilDialogue.banded("김을 빼는 동안엔 총알이 안 박힙니다. 대신 쏠수록 배출이 빨라집니다. 그 사이 증원부터 정리하십시오.", "김을 빼는 동안엔 총알이 안 박힙니다. 대신 쏠수록 배출이 빨라져요. 그 사이 증원도 정리하고요."), 4.2)

# ─── 보스 인트로 컷씬(2026-08-10 사용자 제안) — Violet Signal 빌드업(0~25s)에 맞춘 대사 비트 ───
# 보스 AI 정지(intro_hold) + 전투 입력 잠금 + 레터박스 + SENTINEL/VEIL 대사. 점프/사격/확인 키로
# 스킵 가능, 스킵·재도전 시 BGM을 비트 시작(25s)으로 점프해 늘어짐 방지. 대사=플레이스홀더(사용자 재작성).
const BOSS_INTRO_MUSIC_KICK: float = 25.0
# 스킵은 이벤트 기반(_input) — 폴링(is_action_just_pressed)은 코루틴 재개 순서에 따라 한 프레임짜리
# just-pressed를 놓칠 수 있다(하니스에서 합성 입력 미검출로 확인, 2026-08-10).
var _boss_intro_active: bool = false
var _boss_intro_skip: bool = false

func _input(event: InputEvent) -> void:
	if _boss_intro_active and not _boss_intro_skip:
		if event.is_action_pressed("jump") or event.is_action_pressed("attack") \
				or event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_skip") \
				or OrientationGuard.is_tap(event):
			_boss_intro_skip = true
			get_viewport().set_input_as_handled()

func _play_boss_intro() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	if GameState.story_mode:
		return
	if GameState.boss_intro_seen_run:
		# 죽고 재도전 — 인트로 반복은 늘어진다. 음악이 아직 빌드업 구간일 때만 비트로 점프.
		if BgmPlayer.get_current_position() < BOSS_INTRO_MUSIC_KICK:
			BgmPlayer.seek_current(BOSS_INTRO_MUSIC_KICK)
		return
	GameState.boss_intro_seen_run = true
	_boss_intro_active = true
	_boss_intro_skip = false
	boss.set("intro_hold", true)
	GameState.restrict_combat_input = true
	# 레터박스 상하 바 — 시네마틱 신호.
	var bars := CanvasLayer.new()
	bars.layer = 30
	add_child(bars)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	for is_top in [true, false]:
		var bar := ColorRect.new()
		bar.color = Color(0.0, 0.0, 0.0, 0.92)
		bar.position = Vector2(0.0, 0.0) if is_top else Vector2(0.0, vs.y - 64.0)
		bar.size = Vector2(vs.x, 64.0)
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.modulate.a = 0.0
		bars.add_child(bar)
		var tw := bar.create_tween()
		tw.tween_property(bar, "modulate:a", 1.0, 0.5)
	_run_boss_intro_beats(bars)

# 대사 비트 — 무대 연출(~4.3s) + 대사(~19s)가 미스킵 시 전투 개시를 음악 킥(25s)에 맞춘다.
func _run_boss_intro_beats(bars: CanvasLayer) -> void:
	# 무대 연출(리워크 2026-08-22 · sentinel_rework §3): 소등 → 격납 셔터 개방 → 조명 순차 점등.
	# "최종 방어선의 연극"에 걸맞은 등장 — 재도전은 _play_boss_intro의 seen_run 가드가 건너뛴다.
	var skipped: bool = await _boss_intro_stagecraft(bars)
	if not skipped:
		_show_boss_alert("침입자 식별. 회수 권한: 없음.", Color(1.0, 0.45, 0.40), 5.0)
		skipped = await _boss_intro_wait(4.8)
	if not skipped:
		_show_boss_alert("격리 프로토콜 SENTINEL, 기동.", Color(1.0, 0.45, 0.40), 5.0)
		skipped = await _boss_intro_wait(4.8)
	if not skipped:
		# "커요"만 쓰면 주어 실종(사용자 지적 2026-08-10) — 대상을 명시.
		_show_veil_subtitle(VeilDialogue.banded("상대가 큽니다. 눈은 제가 맡습니다. 빨간 신호가 멎은 틈에 쏘십시오.", "상대가 커요. 그래도 눈은 제가 돼 드릴게요. 빨간 신호가 멎은 틈에 쏴요."), 5.4)
		skipped = await _boss_intro_wait(5.6)
	if not skipped:
		_show_boss_alert("제거를 시작한다.", Color(1.0, 0.30, 0.28), 3.0)
		skipped = await _boss_intro_wait(3.4)
	_end_boss_intro(bars, skipped)

# 무대 연출 — 소등(0.5) → 격납 셔터 두 판이 갈라짐(1.2) → 조명 3개 순차 점등(1.35) →
# 어둠 걷힘(0.8). 전부 스킵 가능. 요소는 bars 레이어 자식이라 _end_boss_intro 정리에 편승.
func _boss_intro_stagecraft(bars: CanvasLayer) -> bool:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	# 소등 — 시설 조명이 죽는다.
	var dark := ColorRect.new()
	dark.color = Color(0.01, 0.01, 0.03, 0.0)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	dark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bars.add_child(dark)
	bars.move_child(dark, 0)   # 레터박스 바 아래
	var tw := dark.create_tween()
	tw.tween_property(dark, "color:a", 0.74, 0.5)
	var skipped: bool = await _boss_intro_wait(1.0)
	# 격납 셔터 — 화면 상부 중앙의 두 판이 좌우로 갈라진다.
	if not skipped:
		SfxPlayer.play("hatch_open")
		_camera_shake(4.0, 0.3)
		for side in [-1, 1]:
			var panel := ColorRect.new()
			panel.color = Color(0.10, 0.12, 0.15, 0.96)
			panel.position = Vector2(vs.x * 0.5 - (300.0 if side < 0 else 0.0), 70.0)
			panel.size = Vector2(300.0, 330.0)
			panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
			bars.add_child(panel)
			var ptw := panel.create_tween()
			ptw.tween_property(panel, "position:x", panel.position.x + 280.0 * float(side), 1.0) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
			ptw.parallel().tween_property(panel, "modulate:a", 0.4, 1.0)
		skipped = await _boss_intro_wait(1.2)
	# 실루엣 점등 — 조명 3개가 순차로 켜져 거대한 것을 비춘다.
	if not skipped:
		for i in 3:
			SfxPlayer.play("boss_alert_text", -8.0)
			var cone := Polygon2D.new()
			var cx: float = vs.x * 0.5 + float(i - 1) * 130.0
			cone.polygon = PackedVector2Array([
				Vector2(cx - 26.0, -10.0), Vector2(cx + 26.0, -10.0),
				Vector2(cx + 120.0, 330.0), Vector2(cx - 120.0, 330.0)])
			cone.color = Color(0.85, 0.92, 1.0, 0.0)
			bars.add_child(cone)
			var ct := cone.create_tween()
			ct.tween_property(cone, "color:a", 0.16, 0.25)
			skipped = await _boss_intro_wait(0.45)
			if skipped:
				break
	# 어둠 걷힘 — 경보와 함께 전장 조명 복구.
	var out := dark.create_tween()
	out.tween_property(dark, "color:a", 0.0, 0.8)
	if not skipped:
		skipped = await _boss_intro_wait(0.6)
	return skipped

# sec 동안 대기 — _input이 세운 스킵 플래그를 매 프레임 확인. 스킵 시 true.
# (씬 전환/보스 소멸 시에도 안전 종료.)
func _boss_intro_wait(sec: float) -> bool:
	var t: float = 0.0
	while t < sec:
		await get_tree().process_frame
		if not is_inside_tree() or boss == null or not is_instance_valid(boss):
			return true
		t += get_process_delta_time()
		if _boss_intro_skip:
			return true
	return false

func _end_boss_intro(bars: CanvasLayer, skipped: bool) -> void:
	_boss_intro_active = false
	GameState.restrict_combat_input = false
	if boss != null and is_instance_valid(boss):
		boss.set("intro_hold", false)
	if skipped:
		BgmPlayer.seek_current(BOSS_INTRO_MUSIC_KICK)
	if bars != null and is_instance_valid(bars):
		for c in bars.get_children():
			if c is CanvasItem:
				var tw := (c as CanvasItem).create_tween()
				tw.tween_property(c, "modulate:a", 0.0, 0.4)
		var cleanup := bars.create_tween()
		cleanup.tween_interval(0.5)
		cleanup.tween_callback(bars.queue_free)

func _on_boss_self_destruct_started() -> void:
	# 화면 전체 경고 — 큰 카운트다운 라벨
	boss_self_destruct_timer_t = 0.0
	boss_self_destruct_layer = CanvasLayer.new()
	boss_self_destruct_layer.layer = 24
	add_child(boss_self_destruct_layer)
	# 붉은 비네트
	var rect := ColorRect.new()
	rect.color = Color(0.95, 0.20, 0.20, 0.18)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_self_destruct_layer.add_child(rect)
	# 펄스 — 위험 신호
	var tw := rect.create_tween()
	tw.set_loops()
	tw.tween_property(rect, "color:a", 0.32, 0.4)
	tw.tween_property(rect, "color:a", 0.10, 0.4)
	# 카운트다운 라벨
	boss_self_destruct_label = Label.new()
	boss_self_destruct_label.text = "SENTINEL OVERLOAD  5.0"
	boss_self_destruct_label.add_theme_font_size_override("font_size", 28)
	boss_self_destruct_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.30))
	boss_self_destruct_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	boss_self_destruct_label.add_theme_constant_override("outline_size", 5)
	# 화면 상단 가운데 — 보스가 화면 중앙에 있어 가운데에 두면 보스 위에 박혀 보임.
	boss_self_destruct_label.position = Vector2(140.0, 110.0)
	boss_self_destruct_label.size = Vector2(1000.0, 50.0)
	boss_self_destruct_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_self_destruct_layer.add_child(boss_self_destruct_label)
	# 회피 안내 — 카운트다운 바로 아래.
	var avoid_label := Label.new()
	avoid_label.text = "노란 원 밖으로 멀어져요"
	avoid_label.add_theme_font_size_override("font_size", 18)
	avoid_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	avoid_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	avoid_label.add_theme_constant_override("outline_size", 4)
	avoid_label.position = Vector2(140.0, 158.0)
	avoid_label.size = Vector2(1000.0, 36.0)
	avoid_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_self_destruct_layer.add_child(avoid_label)

func _on_boss_self_destruct_disarmed() -> void:
	if boss_self_destruct_layer != null and is_instance_valid(boss_self_destruct_layer):
		boss_self_destruct_layer.queue_free()
		boss_self_destruct_layer = null
	# 위장 자폭 재기동(보스 생존) vs 진짜 사망 — 같은 시그널이라 생존 여부로 가른다.
	var b: Node = get_tree().get_first_node_in_group("boss")
	if b != null and is_instance_valid(b) and not bool(b.get("dead")):
		_show_veil_subtitle(VeilDialogue.banded("...자폭은 위장입니다. 코어가 다시 점화됩니다. 침착하게, 마무리하십시오.", "...자폭이 위장이에요. 코어가 다시 점화됩니다. 침착하게, 마무리하세요."), 3.6)

func _on_boss_killed(at_position: Vector2) -> void:
	# Boss는 ARENA enemy_clear에 자연스럽게 잡히도록 wave_idx=-1로 처리하되,
	# 추가로 VEIL 보스 처치 대사 시퀀스를 깔아준다.
	_on_enemy_killed(at_position, -1)
	if boss_clear_dialogue_played:
		return
	boss_clear_dialogue_played = true
	# 리워크(§3 격파): 소환 설비 정리 + "순순한 셧다운" — 조명이 위에서부터 순차 소등되고
	# 옅은 어둠이 reveal까지 잔류. 저항 없는 소등이 "너무 쉽게 무너졌다"는 위화감을 만들고,
	# 곧이은 라이벌 첫 발화(_play_sentinel_reveal)가 그 위화감을 회수한다.
	_clear_facility_hazards()
	if not GameState.story_mode:
		var off_layer := CanvasLayer.new()
		off_layer.layer = 12
		add_child(off_layer)
		var vs: Vector2 = get_viewport().get_visible_rect().size
		for i in 3:
			var band := ColorRect.new()
			band.color = Color(0.0, 0.0, 0.02, 0.0)
			band.position = Vector2(0.0, vs.y * float(i) / 3.0)
			band.size = Vector2(vs.x, vs.y / 3.0 + 1.0)
			band.mouse_filter = Control.MOUSE_FILTER_IGNORE
			off_layer.add_child(band)
			var btw := band.create_tween()
			btw.tween_interval(0.35 * float(i))
			btw.tween_property(band, "color:a", 0.26, 0.4)
	# 보스 HP 바 페이드아웃
	if boss_hp_bar_layer != null and is_instance_valid(boss_hp_bar_layer):
		var holder := boss_hp_bar_layer.get_child(0) as Control
		if holder != null:
			var tw := holder.create_tween()
			tw.tween_property(holder, "modulate:a", 0.0, 0.6)
			tw.tween_callback(boss_hp_bar_layer.queue_free)
	# §7 SENTINEL = 페이크 보스 reveal — "이긴 순간을 이긴 것 같지 않게". 예전 자신만만한 처치 대사
	# ("처리됐어요, 회수해요") 대신, 정적 한 박자 → 라이벌 VEIL 첫 발화(§1 맹점의 실연) → 내 VEIL 동요.
	# 승리 챔은 _begin_clear_sequence(lab)에서 억제되고, 회수(문서+처리선택)는 reveal이 끝난 뒤 이어진다.
	# (BossSentinel은 §7대로 3막 페이크 보스로 잔류. 대사=플레이스홀더 §7 예시 — 사용자 검토/재작성.)
	_play_sentinel_reveal()

# §7 SENTINEL reveal 시퀀스 — 정적 → 라이벌 첫 발화(바이올렛, 화자 불명) → 내 VEIL 동요.
# 완료 시 _sentinel_reveal_done을 켜, _begin_clear_sequence가 회수 단계로 넘어가도록 게이트한다.
func _play_sentinel_reveal() -> void:
	# 정적 한 박자 — stage_clear_chime은 lab에서 억제됨(보스 죽는 소리만 여운).
	await get_tree().create_timer(1.2).timeout
	# reveal = 컷씬(2026-08-23) — 정지 화면(쓰러진 SENTINEL) 위에서 두 줄을 읽는다.
	# 라이벌 첫 발화 — 화자 불명(정체는 14-1에서 공개). 재작성(2026-08-22 사용자 "'시설이
	# 내민 손끝' 너무 이상함"): 은유 전면 폐기, 잡은 것의 실체(경비 장비)를 그대로 말하고
	# "진짜 상대"의 존재만 남긴다. 승리를 깎아내리는 첫 목소리라는 비트는 유지.
	# EN: "Well done, agent. All you took down was one piece of security hardware.
	#      Your real opponent hasn't even stepped in yet."
	# 내 VEIL 동요 — §1 맹점 테마의 첫 실연(2026-08-14: 감정 직진술 대신 말끝 흐림).
	_play_story_dialogue([
		{"who": "rival", "text": "수고하셨습니다, 요원. 방금 잡은 건 경비 장비 한 대일 뿐입니다.\n진짜 상대는 아직 나서지도 않았습니다."},
		{"who": "veil", "text": "...방금 그 목소리, 제 채널이 아닙니다.\n같은 회선에 있었는데 저는 못 봤어요. 이런 적 없었는데."},
	], _finish_sentinel_reveal)

func _finish_sentinel_reveal() -> void:
	_sentinel_reveal_done = true

# §7 복선 — 보스전 중 가끔(랜덤 간격) 거짓-렌더 tell과 같은 붉은-바이올렛 지직거림을 보스에 흘린다.
# 처치 대사 시작(boss_clear_dialogue_played) 후엔 멈춘다. 타이머는 보스 자식이라 보스와 함께 free.
func _start_boss_glitch_foreshadow() -> void:
	if boss == null or not is_instance_valid(boss):
		return
	var timer := Timer.new()
	timer.one_shot = false
	timer.wait_time = randf_range(7.0, 12.0)
	boss.add_child(timer)
	timer.timeout.connect(func() -> void:
		if boss == null or not is_instance_valid(boss) or boss_clear_dialogue_played:
			return
		_boss_glitch_flash()
		timer.wait_time = randf_range(7.0, 12.0)
	)
	timer.start()

# 짧은 붉은-바이올렛 지직거림 오버레이(거짓 렌더 tell과 같은 톤)를 보스 위에 잠깐 얹는다.
# modulate 기반이 아니라 별도 오버레이 노드라 보스 피격/페이즈 플래시와 충돌하지 않는다(known_issues).
func _boss_glitch_flash() -> void:
	if not GameState.screen_fx_enabled:
		return
	if boss == null or not is_instance_valid(boss):
		return
	var g := Node2D.new()
	g.z_index = 40
	g.global_position = (boss as Node2D).global_position
	add_child(g)
	for i in range(5):
		var r := ColorRect.new()
		var viol: bool = i % 2 == 0
		r.color = Color(0.72, 0.42, 1.0, 0.42) if viol else Color(1.0, 0.20, 0.32, 0.46)
		var ox: float = randf_range(-10.0, 10.0)
		var oy: float = randf_range(-118.0, 10.0)
		r.position = Vector2(-70.0 + ox, oy)
		r.size = Vector2(140.0, randf_range(6.0, 13.0))
		g.add_child(r)
	var tw := g.create_tween()
	tw.tween_interval(0.26)
	tw.tween_property(g, "modulate:a", 0.0, 0.14)
	tw.tween_callback(g.queue_free)

# 이스터에그 — 황금 희귀 개체(shiny). 적 스폰당 확률·보너스 오브 가치.
# 0.015는 런당 ~3기 꼴로 "이스터에그라기 민망"(사용자 2026-08-20) — 1/200로 희귀화.
const SHINY_CHANCE: float = 0.005
const SHINY_ORB_VALUE: int = 5

# 엘리트(라이벌의 군대, elite_enemies_plan.md §4) — 막4부터 확률 승격. 라이벌이 시설 유닛을
# 물들여 군대를 만드는 중이라는 서사 = 스테이지 램프. risk3은 소폭 가산(개체수 배율로 모수가 이미 큼).
# 맵당 상한 = "전원 엘리트" 클러스터 차단 안전핀.
const ELITE_CHANCES_BY_STAGE: Dictionary = {9: 0.05, 10: 0.12, 11: 0.18, 12: 0.30}
const ELITE_RISK3_BONUS: float = 0.05
const ELITE_CAP_ACT4: int = 2
const ELITE_CAP_ACT5: int = 4
var _elite_spawned: int = 0

func _elite_chance_here() -> float:
	# MapData "elite_chance" 오버라이드(unfair 맵 0 잠금 / 세트피스 확정 배치) > 스테이지 램프.
	var override_v: float = float(_map_data.get("elite_chance", -1.0))
	if override_v >= 0.0:
		return override_v
	var base: float = float(ELITE_CHANCES_BY_STAGE.get(GameState.current_stage, 0.0))
	if base > 0.0 and GameState.is_high_risk():
		base += ELITE_RISK3_BONUS
	return base

# 반환: 생성된 적 노드 — 호출자가 후처리(14-1 제어 노드 HP 오버라이드 등)에 쓸 수 있다(대부분 무시).
func _spawn_enemy(kind: int, pos: Vector2, wave_idx: int = -1, disguise_kind: int = -1, feign: bool = false, no_reward: bool = false) -> CharacterBody2D:
	var e := CharacterBody2D.new()
	e.set_script(load("res://scripts/Enemy.gd"))
	e.collision_layer = 4
	e.collision_mask = 1
	e.set("enemy_type", kind)
	# 무보상 스폰(경보 진압·호출 증원)은 분모 제외(2026-08-23) — 전원 처치 보너스의 분모이자
	# [RUN] 전멸 진단 분모인데, 무보상 적은 잡아도 kill에 안 들어가 분모만 부풀린다.
	if not no_reward:
		GameState.stage_enemies_spawned += 1
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	# kind: 0=patrol, 1=sniper, 2=drone, 3=bomber, 4=shield
	# 사용자: patrol/shield/drone 크기 키우기 (drone 32×24 → 42×32, 시각 1.3배는 Enemy.gd).
	if kind == 2:
		shape.size = Vector2(42.0, 32.0)
		col.position = Vector2(0, 0)
	elif kind == 0:
		shape.size = Vector2(36.0, 52.0)
		col.position = Vector2(0, -26.0)
	elif kind == 4:
		shape.size = Vector2(40.0, 56.0)
		col.position = Vector2(0, -28.0)
	elif kind == 5:
		# jammer — 땅에 놓인 방출 장치(대략 44×44). Enemy.gd build_jammer 시각과 맞춤.
		shape.size = Vector2(44.0, 44.0)
		col.position = Vector2(0, -22.0)
	elif kind == 6:
		# caller — 등짐 무전기 통신병(휴머노이드). build_caller 시각과 맞춤.
		shape.size = Vector2(32.0, 48.0)
		col.position = Vector2(0, -24.0)
	else:
		shape.size = Vector2(28.0, 40.0)
		col.position = Vector2(0, -20.0)
	col.shape = shape
	e.add_child(col)
	# 이스터에그 — 낮은 확률로 황금 희귀 개체(shiny). add_child(→_ready) 전에 켜야 오라가 생성됨.
	# 연습장(playground)에선 테스트 노이즈 방지로 제외. 제외 대상은 엘리트 롤과 동형(2026-08-15
	# 재머 황금 보고): 재머(kind 5, 장치라 "개체"가 아님 + 라이벌의 손) · 위장/시선 거짓(금색이
	# 위장을 깨는 모순).
	var shiny: bool = (not GameState.playground_active) and kind != 5 \
		and disguise_kind < 0 and not feign and randf() < SHINY_CHANCE
	e.set("shiny", shiny)
	e.set("disguise_as", disguise_kind)   # §4 거짓 렌더 — >=0이면 위장 렌더(_ready에서 소비)
	e.set("feign_ambush", feign)          # §4 시선 거짓 — true면 딴 데 보는 척 기습(patrol, _ready에서 소비)
	# 농성(웨이브) 맵 사냥 모드 — waves_hunt 맵의 지상 적(patrol/bomber/shield)은 감지 범위 밖에서도
	# 플레이어를 향해 전진하고 엄폐를 타넘는다(저지선: 좌우 스폰이 감지 밖 + 엄폐 솔리드에 막혀
	# 스폰 지점만 순찰하던 버그, 2026-08-11). 위장/시선 거짓은 "평범해 보여야" 해서 제외.
	if bool(_map_data.get("waves_hunt", false)) and kind in [0, 3, 4] \
			and disguise_kind < 0 and not feign:
		e.set("hunt", true)
	# 엘리트 롤 — 제외: 재머(라이벌의 "손"은 별개 문법) · 둥지 저격수(등반 완화 튜닝 역행) ·
	# 위장/시선 거짓(이중 기만 금지 §4.1, 계급장이 위장을 깨는 모순) · 스토리.
	# 연습장은 기본 제외(테스트 노이즈), 단 "엘리트 강제" 토글이면 전원 승격(전 타입 체험용).
	var elite: bool = false
	if kind != 5 and kind != 6 and disguise_kind < 0 and not feign \
			and not (kind == 1 and bool(_map_data.get("nest_snipers", false))) \
			and not GameState.story_mode:
		if float(_map_data.get("elite_chance", -1.0)) >= 1.0:
			# 세트피스 확정(14-1 P1 "라이벌의 군대") — 확률 램프의 클러스터 안전핀(cap)과
			# 연습장 노이즈 제외를 둘 다 무시한다. 전원 엘리트가 이 맵의 설계.
			elite = true
		elif GameState.playground_active:
			elite = GameState.debug_force_elite
		else:
			var cap: int = ELITE_CAP_ACT5 if GameState.act_for_stage(GameState.current_stage) >= 4 else ELITE_CAP_ACT4
			if _elite_spawned < cap and randf() < _elite_chance_here():
				elite = true
				_elite_spawned += 1
	e.set("elite", elite)
	add_child(e)
	# 접지 그림자 · 재머(장치)는 제외, 나머지 전 유닛(공중 드론 포함 = 지면 투영이 높이감).
	if kind != 5:
		var esh := GroundShadow.new()
		esh.target = e
		esh.base_width = 30.0 if kind in [0, 4] else 24.0
		add_child(esh)
	_had_enemies = true   # 이스터에그(평화주의) — 적이 있던 맵에서만 인정
	e.global_position = pos
	# 측면 단독 둥지 저격수(회피 전용) 태깅 — VEIL이 "정면으론 못 잡는다"를 짚어주는 대상.
	# (kind 1 = sniper. nest_snipers 맵에선 모든 저격수가 둥지.)
	if kind == 1 and bool(_map_data.get("nest_snipers", false)):
		e.set_meta("avoid_only", true)
	if wave_idx >= 0:
		e.set_meta("wave_idx", wave_idx)
	# no_reward는 스폰 시점 값이라 bind로 굳으면 안 된다 — 환경 처치(열차)는 죽는 순간에
	# 정해지므로 그 시점의 적 상태를 읽어 합친다.
	e.killed.connect(func(at_pos: Vector2) -> void:
		var suppressed: bool = no_reward
		if is_instance_valid(e) and e.get("env_killed") == true:
			suppressed = true
		_on_enemy_killed(at_pos, wave_idx, shiny, elite, suppressed))
	return e

func _on_enemy_killed(at_position: Vector2, wave_idx: int = -1, shiny: bool = false, elite: bool = false, no_reward: bool = false) -> void:
	# 무보상 경로 2종 · 점수도 XP도 없음. ⓐ 경보 진압 경비 — "들키면 파밍 이득"을 원천 차단
	# (사용자 2026-08-17 "오히려 좋아 느낌, 위압감이 없다") ⓑ 환경 처치(열차 등) — 해저드에
	# 밀어 넣어 얻는 것은 안전이지 경험치가 아니다(사용자 2026-08-19).
	if not no_reward:
		GameState.register_kill(elite, shiny)
		_refresh_hud()   # 킬 점수 실시간 반영(우상단 SCORE)
		_spawn_orb(at_position + Vector2(0, -20.0))
		# 엘리트 · 오브 1개 추가(총 가치 2, 위험 증가에 보상 동행 §2).
		if elite:
			_spawn_orb(at_position + Vector2(14.0, -26.0))
		if shiny:
			_reward_shiny_kill(at_position + Vector2(0, -20.0))
	# 웨이브 모드: 처치된 적의 웨이브 카운트 감소 + 다음 웨이브 트리거 검사
	if wave_idx >= 0 and wave_idx < _wave_alive_count.size():
		_wave_alive_count[wave_idx] -= 1
		_check_wave_progress(wave_idx)
	# ARENA enemy_clear 모드 — 모든 웨이브 spawn + 적 0이면 클리어
	if _goal_type == "ENEMY_CLEAR":
		_enemies_remaining -= 1
		# 14-1 라이벌 보스(§7.2 재설계) — 페이즈 목표 = rival_node 파괴. 전멸형이 아니라 목표형
		# (P1은 증원이 끝없어 전멸 자체가 불가능 — "몰살 빌드로 재미없음" 반려 2026-08-12).
		if _rival_boss_active() and _rival_nodes_alive() == 0:
			if _rival_phase == 0:
				call_deferred("_start_rival_p2")
				return
			elif _rival_phase == 1:
				# 재접속 노드 예고(1.1s) 중엔 페이즈를 닫지 않는다 — 예고 중 잔여 노드가
				# 죽으면 재스폰 전에 가짜 클리어가 시작되는 경쟁 조건 차단.
				if _p2_respawn_pending:
					return
				call_deferred("_start_fake_clear")
				return
		if _can_arena_clear():
			call_deferred("_on_arena_cleared")

# 웨이브가 있을 때는 모든 웨이브가 spawn된 뒤에야 클리어 가능.
# 일반 ARENA에서는 _enemies_remaining만 보면 됨.
func _can_arena_clear() -> bool:
	# 14-1 보스 — P2 종료 연출(조명 복구 + 라이벌 퇴장 대사) 동안 클리어 보류.
	if _rival_hold:
		return false
	if _enemies_remaining > 0:
		return false
	# 예고(텔레그래프) 중인 증원이 있으면 대기 — _wave_spawned는 예고 시작 시점에 켜지므로
	# 이 가드가 없으면 예고 0.85s 사이에 남은 적 0으로 조기 클리어된다.
	if _wave_pending_spawns > 0:
		return false
	if _waves_data.is_empty():
		return true
	for spawned in _wave_spawned:
		if not bool(spawned):
			return false
	return true

# ─── 14-1 라이벌 보스전 (rival_veil_concept §7.2) — P1 지휘(웨이브) → P2 빙의(시설) ───
# MapData "rival_boss": true(route_core_recovery)에서만. P1 = 선언적 웨이브(전원 엘리트 세트피스 +
# 재밍 노드). 전멸 시점에 클리어 대신 P2: 방 자체가 적 — 소등 + 벽 포탑 + 위장 함정 + 제어 노드
# 2기(재머 재사용, 측면 발판 위). 노드 전파괴 → 조명 복구 + 퇴장 대사 → 진짜 클리어(기존 회수
# 흐름 유지). 가짜 클리어 + P3(거짓 VEIL 분신전)은 다음 단계(③)에서 이 뒤에 끼어든다.
# 대사 = 라이벌 말투 A(결이 어긋난 정중함)·VEIL 보고체, 전부 플레이스홀더(dialogue_review).
var _rival_phase: int = 0            # 0=P1(지휘) 1=P2(빙의) 2=가짜클리어/P3 3=완료
var _rival_hold: bool = false        # 연출/P3 동안 클리어 보류
var _rival_p2_props: Array = []      # P2 소환물(포탑·함정·스윕·타이머) — 페이즈 종료 시 정리
var _rival_cast: CanvasModulate = null   # P2 소등 캐스트
var _rival_fx_layer: CanvasLayer = null  # 간섭 플래시용 레이어(보스전 내내 유지)
var _p1_spawn_timer: Timer = null    # P1 연속 증원 타이머
var _p1_spawn_idx: int = 0
var _p1_side: int = 0
# 다회차 기억 변주(2026-08-19 사용자 확정: "세지는 게 아니라 배치가 달라진다").
# 게이트 = rival_kills >= 1(한 번이라도 격파한 상대에게만). 수치(HP·예고·개수)는 불변,
# 배치·순서·방향만 회전(replay_support_plan §4.3-6 "네가 외운 자리에는 없다" 문법).
var _p2_first_side_attempt: int = -1   # 이번 시도에서 먼저 부순 P2 노드(0=좌 1=우) · 격파 시 영속 승격
# 보스전 확대(2026-08-19) — P2 노드 재접속 1회(첫 격파 자리에 재스폰 = 실질 3노드) ·
# P3 후반 낙하 잔해(final_boss_rework §6-1). 예약 중 페이즈 조기 종료 가드 포함.
var _p2_respawned: bool = false
var _p2_respawn_pending: bool = false
var _p3_debris_nodes: Array = []
var _p2_flip_timer: Timer = null     # P2 노드 실드 교대 타이머
var _p2_turrets: Array = []          # P2 벽 포탑 [좌, 우] — 같은 인덱스 기둥이 전원을 댄다
var _p2_links: Array = []            # 기둥→포탑 전원 케이블 시각(_P2PowerLink)
var _p2_bulkhead_spoken: bool = false   # 승강 격벽 쓰임 힌트 1회(_RivalSweep이 세팅)
var _rival_bar_layer: CanvasLayer = null   # P1·P2 페이즈 목표 바(노드 합산 HP)
const RIVAL_P1_NODE_HP: int = 6      # P1 지휘 앵커(재밍 기둥) — 기본값. 레벨 스케일은 아래 변수.
const RIVAL_P2_NODE_HP: int = 10     # P2 제어 노드(교대 실드로 실질 더 김) — 기본값.
# 노드 HP 성장 스케일 — 고정 6/10은 s13 시점 빌드(연사·관통 만렙)에 몇 초 만에 녹아
# "사실상 없는 페이즈"가 된다(사용자 2026-08-14). _init_rival_boss가 레벨 비례로 채운다.
var _rival_node_hp_p1: int = RIVAL_P1_NODE_HP
var _rival_node_hp_p2: int = RIVAL_P2_NODE_HP
const P1_TRICKLE_CAP: int = 5        # P1 동시 잡몹 상한 — 몰살 클러스터가 아니라 흐름 압박
const _P1_TYPES: Array = [0, 3, 2, 0, 4, 2, 3, 0]   # patrol·bomber·drone 회전(드론=수평 관통 사선 밖)

func _rival_boss_active() -> bool:
	return bool(_map_data.get("rival_boss", false))

# 관측 안테나(final_boss_rework §2.2) · P1 목표물의 격 상향: 44px 재머 장치 → ~200px 타워.
# 재머(enemy type 5)는 로직 코어(피격 대상·재밍 그늘)로 남고, 이 노드는 그 자리의 타워 비주얼
# + 붕괴 연출(접시 낙하 + 필드 파문 + 빔 소멸). small = P2 중계 안테나(소형 변형).
class _RivalAntenna extends Node2D:
	var small: bool = false
	var _t: float = 0.0
	var _collapsed: bool = false
	var _col_t: float = 0.0
	var _jolt_t: float = 0.0   # 피격 흔들림(타격감 · 사용자 2026-08-17 "맞는지 모르겠다")

	func _ready() -> void:
		z_index = 1   # 재머 장치(적, z 2+)보다 뒤 · 배경 구조물

	func collapse() -> void:
		if _collapsed:
			return
		_collapsed = true
		_col_t = 0.0

	func jolt() -> void:
		_jolt_t = 0.22

	func _process(delta: float) -> void:
		_t += delta
		_jolt_t = maxf(0.0, _jolt_t - delta)
		if _collapsed:
			_col_t += delta
		queue_redraw()

	func _draw() -> void:
		# 피격 흔들림 · 마스트가 잠깐 떨린다(연속 감쇠 · 점멸 아님).
		if _jolt_t > 0.0:
			draw_set_transform(Vector2(sin(_t * 70.0) * 4.0 * (_jolt_t / 0.22), 0.0), 0.0, Vector2.ONE)
		var h: float = 110.0 if small else 200.0
		var alive: float = 1.0 if not _collapsed else maxf(0.0, 1.0 - _col_t / 0.9)
		# 마스트 + 리브 · 붕괴 후에도 잔해로 남는다(전장의 흔적).
		var mast := Color(0.15, 0.12, 0.20) if not _collapsed else Color(0.10, 0.09, 0.13)
		draw_rect(Rect2(Vector2(-7.0, -h), Vector2(14.0, h)), mast)
		draw_rect(Rect2(Vector2(-7.0, -h), Vector2(14.0, h)), Color(0.45, 0.32, 0.62, 0.35 + 0.35 * alive), false, 2.0)
		for i in 3:
			var ry: float = -h * (0.30 + 0.25 * float(i))
			draw_rect(Rect2(Vector2(-20.0, ry), Vector2(40.0, 5.0)), mast.lightened(0.06))
		# 라이벌 광선 · 접시에서 하늘로 뻗는 바이올렛 빔(가동 중에만, 완만 맥동).
		if not _collapsed:
			var ba: float = 0.22 + 0.08 * sin(_t * 1.7)
			draw_line(Vector2(0.0, -h - 14.0), Vector2(0.0, -h - 620.0), Color(0.72, 0.42, 1.0, ba), 5.0)
			draw_line(Vector2(0.0, -h - 14.0), Vector2(0.0, -h - 620.0), Color(0.90, 0.72, 1.0, ba + 0.10), 2.0)
		# 회전 접시(상단) · 붕괴 시 낙하하며 사라진다.
		if _col_t < 1.2:
			var dish_y: float = -h - 12.0 + (_col_t * _col_t * 320.0 if _collapsed else 0.0)
			var spin: float = _t * (2.2 if not _collapsed else 0.3) + (_col_t * 4.0 if _collapsed else 0.0)
			var da: float = 1.0 if not _collapsed else maxf(0.0, 1.0 - _col_t / 1.1)
			draw_set_transform(Vector2(0.0, dish_y), spin, Vector2(1.0, 0.45))
			draw_arc(Vector2.ZERO, 26.0 if not small else 18.0, 0.0, TAU, 24, Color(0.72, 0.42, 1.0, 0.85 * da), 3.0, true)
			draw_arc(Vector2.ZERO, 15.0 if not small else 10.0, 0.0, TAU, 18, Color(0.88, 0.70, 1.0, 0.6 * da), 2.0, true)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 기부 필드 링 · 방출부(재머 장치) 주변 완만 맥동.
		if not _collapsed:
			var fa: float = 0.30 + 0.12 * sin(_t * 2.1)
			draw_arc(Vector2(0.0, -16.0), 36.0, 0.0, TAU, 28, Color(0.72, 0.42, 1.0, fa), 2.0, true)
		# 붕괴 파문 · 필드가 터지며 걷힌다.
		if _collapsed and _col_t < 0.8:
			var k: float = _col_t / 0.8
			draw_arc(Vector2(0.0, -h * 0.4), 40.0 + 150.0 * k, 0.0, TAU, 36, Color(0.85, 0.60, 1.0, 0.55 * (1.0 - k)), 3.0, true)

# P2 제어 코어 · 낮은 돔 소켓(수평 실루엣). P1 관측 안테나(수직 마스트)와 실루엣 어휘를
# 일부러 바꾼다(known_issues "수직 기둥" 규칙 · "P2가 P1과 별 차이 없다" 사용자 2026-08-17).
class _P2CoreSocket extends Node2D:
	var _t: float = 0.0
	var _collapsed: bool = false
	var _col_t: float = 0.0
	var _jolt_t: float = 0.0   # 피격 흔들림(타격감)

	func collapse() -> void:
		_collapsed = true

	func jolt() -> void:
		_jolt_t = 0.22

	func _ready() -> void:
		z_index = -1   # 노드(장치) 뒤에 깔리는 소켓

	func _process(delta: float) -> void:
		_t += delta
		_jolt_t = maxf(0.0, _jolt_t - delta)
		if _collapsed:
			_col_t += delta
		queue_redraw()

	func _draw() -> void:
		if _jolt_t > 0.0:
			draw_set_transform(Vector2(sin(_t * 70.0) * 3.0 * (_jolt_t / 0.22), 0.0), 0.0, Vector2.ONE)
		var alive: float = 0.0 if _collapsed else 1.0
		# 바닥 소켓 플레이트 + 좌우 수평 핀 · 발판에 박힌 낮은 구조.
		var plate := Color(0.15, 0.12, 0.20) if not _collapsed else Color(0.10, 0.09, 0.13)
		draw_rect(Rect2(Vector2(-46.0, -10.0), Vector2(92.0, 10.0)), plate)
		draw_rect(Rect2(Vector2(-46.0, -10.0), Vector2(92.0, 10.0)), Color(0.45, 0.32, 0.62, 0.35 + 0.35 * alive), false, 2.0)
		for sx in [-64.0, 50.0]:
			draw_rect(Rect2(Vector2(float(sx), -7.0), Vector2(14.0, 5.0)), plate.lightened(0.08))
		# 낮은 돔 쉘 · 붕괴 시 주저앉으며 사라진다.
		var dome_a: float = 1.0 if not _collapsed else maxf(0.0, 1.0 - _col_t / 1.1)
		var squash: float = 1.0
		if _collapsed:
			squash = 1.0 - (minf(_col_t, 0.8) / 0.8) * 0.55
		draw_set_transform(Vector2(0.0, -10.0), 0.0, Vector2(1.0, squash))
		draw_arc(Vector2.ZERO, 34.0, PI, TAU, 22, Color(0.22, 0.17, 0.30, dome_a), 5.0, true)
		draw_arc(Vector2.ZERO, 24.0, PI, TAU, 18, Color(0.45, 0.32, 0.62, (0.5 + 0.2 * alive) * dome_a), 2.0, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 코어 구체 · 완만 맥동(±5% 안팎, 광과민 기준).
		if not _collapsed:
			var pulse: float = 0.75 + 0.05 * sin(_t * 2.0)
			draw_circle(Vector2(0.0, -22.0), 9.0, Color(0.72, 0.42, 1.0, pulse))
			draw_circle(Vector2(0.0, -22.0), 4.5, Color(0.92, 0.78, 1.0, pulse))
		# 붕괴 파문.
		if _collapsed and _col_t < 0.8:
			var k: float = _col_t / 0.8
			draw_arc(Vector2(0.0, -18.0), 26.0 + 110.0 * k, 0.0, TAU, 30, Color(0.85, 0.60, 1.0, 0.55 * (1.0 - k)), 3.0, true)

# 목표 노드 피격 피드백 · 미니 HP 바 + 피격 플래시·파문 + 프롭 흔들림 콜백
# (사용자 2026-08-17 "맞고 있다는 타격감이 없어 부숴야 하는지도, 부숴지고 있는지도
# 모르겠다"). hp를 폴링해 감소 순간을 잡는다(시그널 불요 · 노드 사망 시 자체 정리).
class _NodeHpPip extends Node2D:
	var target: Node = null
	var max_hp: int = 10
	var jolt_cb: Callable = Callable()
	var _last_hp: int = -1
	var _flash_t: float = 0.0

	func _ready() -> void:
		z_index = 6

	func _physics_process(delta: float) -> void:
		if target == null or not is_instance_valid(target) or bool(target.get("dead")):
			queue_free()
			return
		global_position = (target as Node2D).global_position + Vector2(0.0, -66.0)
		var hp: int = int(target.get("hp"))
		if _last_hp >= 0 and hp < _last_hp:
			_flash_t = 0.22
			if jolt_cb.is_valid():
				jolt_cb.call()
		_last_hp = hp
		_flash_t = maxf(0.0, _flash_t - delta)
		queue_redraw()

	func _draw() -> void:
		if _last_hp < 0:
			return
		var w: float = 56.0
		var ratio: float = clampf(float(_last_hp) / maxf(1.0, float(max_hp)), 0.0, 1.0)
		draw_rect(Rect2(Vector2(-w * 0.5 - 1.0, -4.0), Vector2(w + 2.0, 8.0)), Color(0.0, 0.0, 0.0, 0.6))
		var fill_col := Color(1.0, 1.0, 1.0) if _flash_t > 0.0 else Color(0.85, 0.55, 1.0)
		draw_rect(Rect2(Vector2(-w * 0.5, -3.0), Vector2(w * ratio, 6.0)), fill_col)
		# 피격 파문 링 · 장치 쪽으로 퍼진다(맞았다는 즉각 신호).
		if _flash_t > 0.0:
			var k: float = 1.0 - _flash_t / 0.22
			draw_arc(Vector2(0.0, 40.0), 12.0 + 26.0 * k, 0.0, TAU, 20, Color(1.0, 0.85, 1.0, 0.7 * (1.0 - k)), 2.5, true)

func _init_rival_boss() -> void:
	_rival_fx_layer = CanvasLayer.new()
	_rival_fx_layer.layer = 12
	add_child(_rival_fx_layer)
	# 노드 HP 레벨 스케일 — 예: lv18이면 P1 15 / P2 28. 교대 실드(실질 DPS 절반)와 곱해져
	# 페이즈가 "있는" 길이가 된다.
	# 2026-08-15 응급 상향 — "P3까지 1분 컷"(사용자). 리워크(final_boss_rework) 전까지의 계수 보정:
	# P1 +0.5lv→+1.0lv, P2 +1.0lv→+1.5lv. 페이즈 전개 재설계는 리워크에서.
	_rival_node_hp_p1 = RIVAL_P1_NODE_HP + GameState.player_level
	_rival_node_hp_p2 = RIVAL_P2_NODE_HP + int(float(GameState.player_level) * 1.5)
	# 다회차 기억 변주 · P1 — 첫 증원 진입 방향 미러 + 타입 회전 시작점 이동.
	# _p1_side 초기 0 = 첫 증원 우측(x2220). 격파 이력이 있으면 1로 시작 = 첫 증원 좌측.
	if GameState.rival_kills >= 1:
		_p1_side = 1
		_p1_spawn_idx = GameState.rival_kills % _P1_TYPES.size()
	# 페이즈 목표 바 — "공격이 되는지 알 길이 없다" 반려 기준의 P1·P2 판. 노드 합산 HP를 보스 바
	# 문법으로 상시 표시(P2 진입 시 다시 차오름 = 페이즈 문법). P3는 FalseVeil 바가 자리를 승계.
	if GameState.rival_phase_reached < 2:
		_build_rival_node_bar()
	# 페이즈 체크포인트(§7.2 확정: 하드코어 지양) — 사망 재시도는 도달한 페이즈부터.
	# P3(2)면 가짜 클리어 연출도 건너뛴다(반복 시 고문 + 한 번 속은 트릭은 재현 무의미).
	if GameState.rival_phase_reached >= 1:
		for e in get_tree().get_nodes_in_group("enemy"):
			(e as Node).queue_free()
		_enemies_remaining = 0
		for i in _wave_spawned.size():
			_wave_spawned[i] = true
		if GameState.rival_phase_reached >= 2:
			call_deferred("_start_rival_p3", 3.6)
			get_tree().create_timer(1.4, false).timeout.connect(_p3_tell_line)   # 판별 tell 재고지
			get_tree().create_timer(4.8, false).timeout.connect(_p3_unmarked_line)
		else:
			call_deferred("_start_rival_p2")
		return
	# P1 목표 태깅 · MapData가 스폰한 재머 2기 = 지휘 앵커(전부 파괴 = P2). hp 상향.
	# 리워크(§2.2): 재머 장치 뒤에 관측 안테나 타워를 세워 목표물의 격을 올린다. 장치 = 방출부.
	for e in get_tree().get_nodes_in_group("enemy"):
		if int((e as Node).get("enemy_type")) == 5:
			(e as Node).set_meta("rival_node", true)
			(e as Node).set("hp", _rival_node_hp_p1)
			var ant := _RivalAntenna.new()
			ant.position = (e as Node2D).global_position + Vector2(0.0, 30.0)
			add_child(ant)
			(e as Node).connect("killed", func(_pos: Vector2) -> void:
				if is_instance_valid(ant):
					ant.collapse())
			# 피격 피드백 · 미니 HP 바 + 안테나 흔들림(타격감).
			var pip := _NodeHpPip.new()
			pip.target = e
			pip.max_hp = _rival_node_hp_p1
			pip.jolt_cb = Callable(ant, "jolt")
			add_child(pip)
	# P1 연속 증원 — 전멸이 목표가 아니다(만렙 관통·유도 빌드가 클러스터를 몰살해도 다음이 온다).
	# 소규모 투입이 끝없이 이어져 긴박을 만들고, 출구는 기둥 파괴뿐(목표형 전투 재설계 2026-08-12).
	_p1_spawn_timer = Timer.new()
	_p1_spawn_timer.wait_time = 3.0
	add_child(_p1_spawn_timer)
	_p1_spawn_timer.timeout.connect(_p1_trickle_tick)
	# 인트로 = 컷씬(2026-08-23 사용자 "스토리용 대사는 컷씬으로") — 1.0s 뒤 세계를 멈추고
	# 두 줄을 읽게 한다. 증원 타이머(2.6s)는 pause 동안 멈추므로 첫 투입은 컷씬 종료 ~1.6s 뒤.
	get_tree().create_timer(2.6, false).timeout.connect(_p1_grace_end)
	get_tree().create_timer(1.0, false).timeout.connect(_rival_intro_cutscene)

# 발화 유예 종료 — 첫 증원 투입 + 주기 재개. 가드는 _p1_trickle_tick과 동일 기준.
func _p1_grace_end() -> void:
	if _rival_phase != 0 or goal_reached or not is_inside_tree():
		return
	_p1_trickle_tick()
	if _p1_spawn_timer != null and is_instance_valid(_p1_spawn_timer):
		_p1_spawn_timer.start()

func _p1_trickle_tick() -> void:
	if _rival_phase != 0 or goal_reached or not is_inside_tree():
		if _p1_spawn_timer != null and is_instance_valid(_p1_spawn_timer):
			_p1_spawn_timer.stop()
		return
	var alive: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and not (e as Node).is_queued_for_deletion() \
				and not (e as Node).has_meta("rival_node"):
			alive += 1
	if alive >= P1_TRICKLE_CAP:
		return
	var kind: int = int(_P1_TYPES[_p1_spawn_idx % _P1_TYPES.size()])
	_p1_spawn_idx += 1
	_p1_side = 1 if _p1_side <= 0 else -1
	var px: float = 180.0 if _p1_side < 0 else 2220.0
	var pos := Vector2(px, 520.0 if kind == 2 else 1190.0)
	var tel := _WaveSpawnTelegraph.new()
	tel.lifetime = 0.6
	tel.position = Vector2(px, 1190.0)
	add_child(tel)
	get_tree().create_timer(0.6, false).timeout.connect(_p1_do_spawn.bind(kind, pos))

func _p1_do_spawn(kind: int, pos: Vector2) -> void:
	if _rival_phase != 0 or goal_reached or not is_inside_tree():
		return
	_spawn_enemy(kind, pos)
	_enemies_remaining += 1

# 살아있는 페이즈 목표 노드(rival_node) 수 — P1 기둥/P2 노드 공용 카운트.
func _rival_nodes_alive() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Node).has_meta("rival_node") and is_instance_valid(e) \
				and not (e as Node).is_queued_for_deletion() and not bool((e as Node).get("dead")):
			n += 1
	return n

# 페이즈 전환 시 잡몹 소거 — 라이벌이 병력을 물린다(집계도 함께 리셋).
func _despawn_rival_mobs() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		var n := e as Node
		if n.has_meta("rival_node") or not is_instance_valid(n) or n.is_queued_for_deletion():
			continue
		n.queue_free()
	_enemies_remaining = 0

# 화면 간섭 플래시 — 라이벌의 존재감 비트(입장·페이즈 전환·노드 파괴·퇴장에서 호출).
func _rival_beat_flash() -> void:
	if _rival_fx_layer != null and is_instance_valid(_rival_fx_layer):
		_rival_interference_flash(_rival_fx_layer)

# 화면 글리치(셰이더) — 가로 슬라이스 변위 + RGB 분리 + 블록 노이즈. duration 동안 엔벨로프
# (급상승→요동 유지→감쇠)로 구동. 가짜 클리어 찢김·페이즈 전환·라이벌 발화 비트 공용.
# "보라색 글자 흔들기"는 글리치가 아니라는 반려(사용자 2026-08-12) — 표준 글리치 문법으로 재작업.
var _glitch_shader: Shader = null

func _run_glitch(duration: float, peak: float) -> void:
	# 접근성 — 화면 효과 끄기(광과민 대응). 글리치는 정보 전달이 아니라 톤이라 생략 가능.
	if not GameState.screen_fx_enabled:
		return
	if _glitch_shader == null:
		_glitch_shader = load("res://assets/shaders/glitch.gdshader") as Shader
	if _glitch_shader == null:
		return
	var layer := CanvasLayer.new()
	layer.layer = 60
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = _glitch_shader
	mat.set_shader_parameter("intensity", 0.0)
	rect.material = mat
	layer.add_child(rect)
	var runner := _GlitchRunner.new()
	runner.mat = mat
	runner.duration = duration
	runner.peak = peak
	runner.host_layer = layer
	# pause(레벨업 오버레이 등) 중에도 엔벨로프가 계속 진행돼야 한다. 안 그러면 글리치가
	# 피크 강도로 얼어붙은 화면이 pause 내내 남는다(최종 보스전 레벨업, 사용자 보고 2026-08-14).
	runner.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(runner)

class _GlitchRunner extends Node:
	var mat: ShaderMaterial = null
	var duration: float = 0.8
	var peak: float = 1.0
	var host_layer: CanvasLayer = null
	var _t: float = 0.0
	func _process(delta: float) -> void:
		# pause 중엔 3배속으로 감아 글리치를 빠르게 걷는다 — 레벨업 카드가 깨끗한 화면에서 보이게.
		var tree := get_tree()
		_t += delta * (3.0 if tree != null and tree.paused else 1.0)
		if mat == null or _t >= duration:
			if host_layer != null and is_instance_valid(host_layer):
				host_layer.queue_free()
			return
		var k: float = _t / duration
		var env: float = 1.0
		if k < 0.12:
			env = k / 0.12
		elif k > 0.6:
			env = 1.0 - (k - 0.6) / 0.4
		var jitter: float = 0.75 + 0.25 * sin(_t * 43.0)
		mat.set_shader_parameter("intensity", peak * env * jitter)
		mat.set_shader_parameter("seed", floor(_t * 24.0) * 0.371)

# 인트로 컷씬 — 라이벌 인사(변형 3종) + VEIL 목표 안내를 정지 화면에서 읽는다.
func _rival_intro_cutscene() -> void:
	if not is_inside_tree() or goal_reached:
		return
	# 발화 동기 플래시 제거(2026-08-14 2차) — 존재감은 카메라 흔들림만 남긴다.
	_camera_shake(5.0, 0.25)
	# 라이벌 기억(축 C) — 이미 쓰러뜨린 적 있는 회차엔 인사가 달라진다(그는 기억한다).
	# 정보 축적형 공개(2026-08-23) — 서버 로그 기발견자는 "아는 자 대접": 로그 말미의 미서명
	# 문자열("기다리고 있었습니다.")을 자기 것이라 자백한다. 그가 열람 사실을 아는 근거는
	# 기존 설정 그대로(세션 2 = 대상의 시야 스트림 열람). 다회차 인사가 우선(기억 언급 상한).
	var first: String
	if GameState.rival_kills >= 1:
		first = "'어서 오세요, 요원.' 지난번에도 이 인사였죠."
	elif GameState.found_server_log:
		# EN: "Welcome, agent. You read that recovered log in the server room.
		#      'I have been waiting.' I wrote that line."
		first = "어서 오세요, 요원. 서버에서 복구된 기록, 읽으셨죠.\n'기다리고 있었습니다.' 그 줄은 제가 쓴 겁니다."
	else:
		first = "어서 오세요, 요원. 여기서부터는 제 구역입니다."
	# VEIL 목표 안내 — 실물과 단어 일치 원칙(2026-08-14 "기둥" 반려) · 실물 = 상층 데크의 관측 안테나.
	_play_story_dialogue([
		{"who": "rival", "text": first},
		{"who": "veil", "text": "적은 끝이 없습니다. 다 잡을 생각은 마십시오.\n증원은 위층의 관측 안테나가 부릅니다. 저것부터 부수십시오."},
	])

func _start_rival_p2() -> void:
	if _rival_phase != 0 or goal_reached or not is_inside_tree():
		return
	_rival_phase = 1
	GameState.rival_phase_reached = 1
	_break_rival_lock(1)
	if _p1_spawn_timer != null and is_instance_valid(_p1_spawn_timer):
		_p1_spawn_timer.stop()
	_despawn_rival_mobs()
	SfxPlayer.play("boss_phase_change")
	_run_glitch(0.7, 0.38)
	_rival_beat_flash()
	_camera_shake(10.0, 0.4)
	# P2 오프닝 = 컷씬(2026-08-23) — 소등이 깔리고 제어 노드가 실스폰된 다음 박자(1.35s)에
	# 세계를 멈추고 두 줄을 읽는다(목표 안내의 지시 대상 = 제어 코어가 화면에 선 뒤).
	get_tree().create_timer(1.35, false).timeout.connect(_rival_p2_cutscene)
	# 소등 — 완만한 감광(고대비 점멸 금지, known_issues 광과민성 기준).
	_rival_cast = CanvasModulate.new()
	_rival_cast.color = Color(1, 1, 1)
	add_child(_rival_cast)
	var tw := _rival_cast.create_tween()
	tw.tween_property(_rival_cast, "color", Color(0.50, 0.43, 0.60), 1.4)
	# 벽 포탑 4기 · 하층/중층 좌우(리워크 §2.3 밀도 상향: 복층이라 층마다 사선이 다르다).
	# 인덱스 규약: [좌하, 우하, 좌중, 우중] · 노드 side 0(좌) 격파 = 0·2 정지, side 1 = 1·3.
	var turret_cfgs: Array = [
		{"x": 110.0,  "y": 1182.0, "dir": "right", "phase": 0.0},
		{"x": 2290.0, "y": 1182.0, "dir": "left",  "phase": 1.3},
		{"x": 110.0,  "y": 1002.0, "dir": "right", "phase": 0.7},
		{"x": 2290.0, "y": 1002.0, "dir": "left",  "phase": 2.0},
	]
	_p2_turrets.clear()
	for entry in turret_cfgs:
		var d: Dictionary = entry
		var trap := BulletTrap.new()
		trap.position = Vector2(float(d.get("x", 0.0)), float(d.get("y", 0.0)))
		trap.damage = 1
		trap.burst = 3
		add_child(trap)
		trap.setup(_dir_from_str(str(d.get("dir", "left"))), 2.6, float(d.get("phase", 0.0)), 0.7, "periodic", "")
		_rival_p2_props.append(trap)
		_p2_turrets.append(trap)
	_traps_present = true
	# 온보딩 유예(사용자 2026-08-17 "어두워지고 뿅뿅대서 설명 대사를 읽을 수 없다") ·
	# 포탑은 5.5s 뒤 가동. 대사 읽기는 이제 컷씬(1.35s 개시, pause 동안 이 타이머도 정지)이
	# 담당하므로 이 유예는 소등·노드 시각 온보딩 전담 — 컷씬 종료 뒤 ~4.15s.
	for t2 in _p2_turrets:
		(t2 as Node).set_process(false)
	get_tree().create_timer(5.5, false).timeout.connect(_p2_enable_turrets)
	# 위장 함정 1개 · 지상 중앙 우측 접근로의 거짓 바닥(§4 문법 재사용, 맵당 1개 준수).
	if not GameState.story_mode:
		var parts: Array = _spawn_disguised_spike(1450.0, 1214.0, 110.0, 2)
		for p in parts:
			if p != null:
				_rival_p2_props.append(p)
	# 제어 노드(제어 코어)는 즉시 놓지 않는다 · 소등과 동시에 그냥 생겨 "뜬금없다"는 반려
	# (사용자 2026-08-14). 스폰 텔레그래프 1.1s → 등장 스냅(SFX) 순서로 도착을 예고한다.
	# 위치 = 중층 측면 발판 위(복층 동선 강제).
	for cfg in [{"x": 350.0}, {"x": 2050.0}]:
		var tel := _WaveSpawnTelegraph.new()
		tel.lifetime = 1.1
		tel.position = Vector2(float((cfg as Dictionary).get("x", 1200.0)), 1010.0)
		add_child(tel)
	get_tree().create_timer(1.1, false).timeout.connect(_p2_spawn_nodes)
	# 스윕 + 이동 격벽 — 바이올렛 소거 벽이 방을 훑고, 세이프존(격벽)이 매 사이클 옮겨 다닌다
	# (§7.2 "격벽 이동·안전지대가 옮겨 다님"의 구현).
	var sweep := _RivalSweep.new()
	sweep.host = self   # 첫 격벽 상승 힌트 1회(_p2_bulkhead_spoken)
	# 다회차 기억 변주 · P2 스윕 — 첫 스윕이 "지난 격파에서 먼저 부순 쪽"에서 들어온다
	# (그 쪽을 기억하고 먼저 손봤다는 대사와 기계적으로 일치). cycle 시드는 격벽 조합·층
	# 교대의 시작점을 회차마다 옮긴다. 속도·주기·예고 시간은 불변.
	if GameState.rival_kills >= 1:
		# from_left는 매 사이클 rise에서 반전된 뒤 스윕 — 첫 스윕을 좌측발로 만들려면 초기 false.
		sweep.from_left = GameState.rival_boss_first_side != 0
		sweep.cycle = GameState.rival_kills % 4
	add_child(sweep)
	sweep.t = -2.0      # 온보딩 유예 · 첫 격벽 상승을 4.6s로 늦춰 안내 대사를 읽게
	_rival_p2_props.append(sweep)

# P2 제어 노드 2기 실스폰(텔레그래프 1.1s 뒤) — 지상, **교대 실드**: 막힌 쪽 탄은 무효
# (Enemy.take_damage fs_dir), 주기적으로 편이 바뀐다. 열린 쪽으로 돌아가거나 교대 타이밍을
# 노리거나, 수류탄(폭발 관통)이 정답 카드. "기믹 이용 느낌 없음" 반려(2026-08-12) 반영.
func _p2_spawn_nodes() -> void:
	if _rival_phase != 1 or goal_reached or not is_inside_tree():
		return
	SfxPlayer.play("hatch_open")
	_p2_links.clear()
	var side: int = 0
	# 다회차 기억 변주 — 노드 실드 초기 편 반전(홀수 회차). 플립 주기는 불변.
	var d_flip: int = -1 if GameState.rival_kills % 2 == 1 and GameState.rival_kills >= 1 else 1
	for cfg in [{"x": 350.0, "d": 1 * d_flip}, {"x": 2050.0, "d": -1 * d_flip}]:
		var cd: Dictionary = cfg
		var node := _spawn_enemy(5, Vector2(float(cd.get("x", 1200.0)), 1010.0))
		node.set("hp", _rival_node_hp_p2)
		node.set_meta("rival_node", true)
		node.set_meta("fs_dir", int(cd.get("d", 1)))
		var arc := _FlipShieldArc.new()
		node.add_child(arc)
		# 제어 코어 소켓 비주얼 · P1 안테나(수직)와 어휘를 바꾼 낮은 돔(2026-08-17,
		# "P2가 P1과 별 차이 없다 + 그놈의 기둥" 반영. 이전: 소형 안테나 마스트 재사용).
		var sock := _P2CoreSocket.new()
		sock.position = (node as Node2D).global_position + Vector2(0.0, 30.0)
		add_child(sock)
		_rival_p2_props.append(sock)
		node.connect("killed", func(_pos: Vector2) -> void:
			if is_instance_valid(sock):
				sock.collapse())
		# 피격 피드백 · 미니 HP 바 + 소켓 흔들림(타격감 · P1과 동형).
		var pip2 := _NodeHpPip.new()
		pip2.target = node
		pip2.max_hp = _rival_node_hp_p2
		pip2.jolt_cb = Callable(sock, "jolt")
		add_child(pip2)
		_rival_p2_props.append(pip2)
		# "부술 이유"를 눈에 보이게(사용자 2026-08-14) · 노드가 같은 쪽 벽 포탑(상하 2기)에
		# 전원을 댄다. 케이블 시각 + 격파 시 그쪽 포탑 정지(_on_p2_node_down).
		node.killed.connect(_on_p2_node_down.bind(side))
		if side < _p2_turrets.size() and _p2_turrets[side] is Node2D:
			var link := _P2PowerLink.new()
			link.from_pos = (node as Node2D).global_position + Vector2(0.0, -34.0)
			link.to_pos = (_p2_turrets[side] as Node2D).global_position + Vector2(0.0, -8.0)
			add_child(link)
			_p2_links.append(link)
			_rival_p2_props.append(link)
		else:
			_p2_links.append(null)
		side += 1
	_enemies_remaining += 2
	# 실드 교대 타이머.
	_p2_flip_timer = Timer.new()
	_p2_flip_timer.wait_time = 2.8
	add_child(_p2_flip_timer)
	_p2_flip_timer.timeout.connect(_p2_flip_shields)
	_p2_flip_timer.start()
	_rival_p2_props.append(_p2_flip_timer)

func _p2_flip_shields() -> void:
	if _rival_phase != 1 or not is_inside_tree():
		if _p2_flip_timer != null and is_instance_valid(_p2_flip_timer):
			_p2_flip_timer.stop()
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Node).has_meta("fs_dir"):
			(e as Node).set_meta("fs_dir", -int((e as Node).get_meta("fs_dir")))
			(e as Node).set_meta("fs_flip_ms", Time.get_ticks_msec())
	SfxPlayer.play("plate_step_active", -6.0)

# P2 온보딩 유예 해제 · 노드 격파로 이미 꺼진 포탑(powered_off)은 되살리지 않는다.
func _p2_enable_turrets() -> void:
	if _rival_phase != 1 or goal_reached or not is_inside_tree():
		return
	for t2 in _p2_turrets:
		if t2 != null and is_instance_valid(t2) and not (t2 as Node).has_meta("powered_off"):
			(t2 as Node).set_process(true)

# P2 오프닝 컷씬 — 라이벌(기억 변형 포함) + VEIL 목표 안내.
func _rival_p2_cutscene() -> void:
	if not is_inside_tree() or goal_reached or _rival_phase != 1:
		return
	# 다회차 기억 변형 대사 — 기존 라인 "대체"(발화 수 증가 없음 · 기억 언급 런당 1~2회 상한 준수).
	# 기억의 대상은 플레이어가 아니라 이전 작전 기록(4번째 벽 금지, replay_support_plan §4.3).
	var first: String
	if GameState.rival_kills >= 1 and GameState.rival_boss_first_side >= 0:
		var side_word: String = "왼쪽" if GameState.rival_boss_first_side == 0 else "오른쪽"
		first = "지난번에는 %s 회선부터 끊으셨죠. 배선은 바꿔 뒀습니다." % side_word
	else:
		first = "병사들이 아깝네요. 그럼, 방하고 싸워 보시죠."
	# 케이블 시각과 짝 · 장치의 기능(포탑 전원)을 한 번만 말로 짚는다. 단어는 실물(제어 코어)과 일치.
	_play_story_dialogue([
		{"who": "rival", "text": first},
		{"who": "veil", "text": "포탑 전원은 발판의 저 낮은 제어 코어 둘.\n끊는 만큼 조용해집니다. 방패는 한쪽뿐입니다."},
	])

# P2 노드 격파 → 그 노드가 전원을 대던 같은 쪽 포탑(하·중층 2기)이 죽는다 · 파괴의 보상 즉시 체감.
func _on_p2_node_down(_pos: Vector2, side: int) -> void:
	# 다회차 기억 · 이번 시도에서 먼저 부순 쪽(최초 1회만). 격파 확정 시 영속 승격 —
	# 실패한 시도는 기억되지 않는다(라이벌이 기억하는 건 자기가 진 판).
	if _p2_first_side_attempt < 0:
		_p2_first_side_attempt = side
	# 보스전 확대 — 첫 격파 자리에 노드 재접속 1회(실질 3노드 = P2 길이 +50%).
	# 같은 자리 재스폰이라 목표 바 분모(2×per_node)를 넘지 않는다(합산 ≤ 2노드).
	# 정지시킨 포탑은 되살리지 않는다 — 플레이어가 얻은 진전은 유지(fair).
	if not _p2_respawned and _rival_phase == 1 and not goal_reached:
		_p2_respawned = true
		_p2_respawn_pending = true
		var rx: float = 350.0 if side == 0 else 2050.0
		var tel := _WaveSpawnTelegraph.new()
		tel.lifetime = 1.1
		tel.position = Vector2(rx, 1010.0)
		add_child(tel)
		_show_veil_subtitle("...같은 자리에 회선이 다시 붙습니다. 한 번 더 끊어야 합니다.", 3.2)
		get_tree().create_timer(1.1, false).timeout.connect(_p2_respawn_node.bind(side, rx))
	if side < _p2_links.size():
		var link = _p2_links[side]
		if link != null and is_instance_valid(link):
			(link as Node).call("power_off")
	for t_idx in [side, side + 2]:
		if t_idx >= _p2_turrets.size():
			continue
		var trap = _p2_turrets[t_idx]
		if trap != null and is_instance_valid(trap):
			(trap as Node).set_meta("powered_off", true)   # 온보딩 유예 해제 타이머가 되살리지 않게
			(trap as Node).set_process(false)   # 주기 진행이 _process 구동 — 정지 = 발사 중단
			var tw := (trap as Node2D).create_tween()
			tw.tween_property(trap, "modulate", Color(0.4, 0.42, 0.5, 0.75), 0.5)
			SfxPlayer.play_at("plate_step_inactive", (trap as Node2D).global_position)

# 재접속 노드 실스폰(보스전 확대) — 죽은 자리에 1기, 실드 편은 원래의 반대(같은 풀이 금지).
func _p2_respawn_node(side: int, rx: float) -> void:
	_p2_respawn_pending = false
	if _rival_phase != 1 or goal_reached or not is_inside_tree():
		return
	SfxPlayer.play("hatch_open")
	var d_flip: int = -1 if GameState.rival_kills % 2 == 1 and GameState.rival_kills >= 1 else 1
	var d_base: int = (1 if side == 0 else -1) * d_flip
	var node := _spawn_enemy(5, Vector2(rx, 1010.0))
	node.set("hp", _rival_node_hp_p2)
	node.set_meta("rival_node", true)
	node.set_meta("fs_dir", -d_base)
	var arc := _FlipShieldArc.new()
	node.add_child(arc)
	var sock := _P2CoreSocket.new()
	sock.position = (node as Node2D).global_position + Vector2(0.0, 30.0)
	add_child(sock)
	_rival_p2_props.append(sock)
	node.connect("killed", func(_pos: Vector2) -> void:
		if is_instance_valid(sock):
			sock.collapse())
	var pip2 := _NodeHpPip.new()
	pip2.target = node
	pip2.max_hp = _rival_node_hp_p2
	pip2.jolt_cb = Callable(sock, "jolt")
	add_child(pip2)
	_rival_p2_props.append(pip2)
	node.killed.connect(_on_p2_node_down.bind(side))
	_enemies_remaining += 1

# P2 전원 케이블 — 기둥→포탑을 잇는 처진 바이올렛 라인 + 흐르는 전류 펄스. power_off로 소등.
class _P2PowerLink extends Node2D:
	var from_pos: Vector2 = Vector2.ZERO
	var to_pos: Vector2 = Vector2.ZERO
	var _t: float = 0.0
	var _off: bool = false
	var _off_t: float = 0.0

	func power_off() -> void:
		_off = true

	func _ready() -> void:
		z_index = 1

	func _process(delta: float) -> void:
		_t += delta
		if _off:
			_off_t += delta
			if _off_t > 0.6:
				queue_free()
				return
		queue_redraw()

	func _draw() -> void:
		var a: float = 0.55
		if _off:
			a *= maxf(0.0, 1.0 - _off_t / 0.6)
		var col := Color(0.72, 0.42, 1.0, a)
		var seg: int = 14
		var pts := PackedVector2Array()
		for i in seg + 1:
			var k: float = float(i) / float(seg)
			var p: Vector2 = from_pos.lerp(to_pos, k)
			p.y += sin(PI * k) * 26.0   # 살짝 처진 케이블
			pts.append(to_local(p))
		draw_polyline(pts, col, 2.0, true)
		if not _off:
			# 전류 펄스 — 기둥에서 포탑 쪽으로 흐른다(전원 방향).
			var pk: float = fmod(_t * 0.7, 1.0)
			var pp: Vector2 = from_pos.lerp(to_pos, pk)
			pp.y += sin(PI * pk) * 26.0
			draw_circle(to_local(pp), 3.5, Color(0.9, 0.7, 1.0, minf(1.0, a + 0.35)))

# P2 제어 노드의 교대 실드 표시 — 부모(enemy) 메타 fs_dir 쪽 반구. 막힌 쪽은 면이 있는 실드,
# 열린 쪽은 따뜻한 노출 글로우("여길 치라"), 교대 순간엔 밝은 스냅(실드가 넘어간 쪽으로 시선 유도).
# "보스가 공격을 안 받아" 실플레이 반려(2026-08-13) — 아크 선 하나로는 막힘/열림이 안 읽혔다.
class _FlipShieldArc extends Node2D:
	var _t: float = 0.0
	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()
	func _draw() -> void:
		var parent_n := get_parent()
		if parent_n == null or not parent_n.has_meta("fs_dir"):
			return
		var d: int = int(parent_n.get_meta("fs_dir"))
		var base: float = 0.0 if d > 0 else PI
		# 막힌 쪽 — 두께가 있는 반구 실드(면으로 보이게).
		draw_arc(Vector2(0, -22), 40.0, base - PI * 0.45, base + PI * 0.45, 24, Color(0.72, 0.42, 1.0, 0.28), 14.0, true)
		draw_arc(Vector2(0, -22), 47.0, base - PI * 0.45, base + PI * 0.45, 24, Color(0.72, 0.42, 1.0, 0.85), 3.5, true)
		draw_arc(Vector2(0, -22), 52.0, base - PI * 0.3, base + PI * 0.3, 14, Color(0.72, 0.42, 1.0, 0.35), 2.0, true)
		# 열린 쪽 — 노출 코어 글로우(완만한 호흡, 금색 = VEIL 시안/라이벌 바이올렛과 구별).
		var open_base: float = base + PI
		var oa: float = 0.4 + 0.18 * sin(_t * 2.6)
		draw_arc(Vector2(0, -22), 34.0, open_base - PI * 0.35, open_base + PI * 0.35, 16, Color(1.0, 0.86, 0.55, oa), 3.0, true)
		# 교대 직후 0.3s — 넘어간 쪽에 밝은 스냅.
		if parent_n.has_meta("fs_flip_ms"):
			var since: float = float(Time.get_ticks_msec() - int(parent_n.get_meta("fs_flip_ms"))) / 1000.0
			if since < 0.3:
				var k: float = 1.0 - since / 0.3
				draw_arc(Vector2(0, -22), 44.0, base - PI * 0.5, base + PI * 0.5, 24, Color(0.95, 0.80, 1.0, 0.7 * k), 5.0, true)

# P1·P2 페이즈 목표 바 — rival_node(재밍 기둥/제어 노드) 합산 HP를 상단 보스 바 문법으로.
# 이름 라벨은 "?"(화자 불명 문법 공유). 페이즈가 넘어가면 바가 다시 차오른다(보스 페이즈 문법).
class _RivalNodeBarUpdater extends Node:
	var host: Node = null
	var fill: ColorRect = null
	func _process(_delta: float) -> void:
		if host == null or fill == null or not is_instance_valid(host):
			return
		var tree := get_tree()
		if tree == null:
			return
		var phase: int = int(host.get("_rival_phase"))
		# 노드 HP가 레벨 스케일이라 바 최대치도 호스트 값에서 읽는다(하드코딩 시 바가 안 참).
		var per_node: int = int(host.get("_rival_node_hp_p1")) if phase == 0 else int(host.get("_rival_node_hp_p2"))
		var max_hp: float = 2.0 * float(per_node)
		var total: float = 0.0
		for e in tree.get_nodes_in_group("enemy"):
			var n := e as Node
			if n.has_meta("rival_node") and is_instance_valid(n) \
					and not n.is_queued_for_deletion() and not bool(n.get("dead")):
				total += maxf(0.0, float(n.get("hp")))
		fill.size.x = 400.0 * clampf(total / max_hp, 0.0, 1.0)

func _build_rival_node_bar() -> void:
	_rival_bar_layer = CanvasLayer.new()
	_rival_bar_layer.layer = 21
	add_child(_rival_bar_layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_rival_bar_layer.add_child(holder)
	var name_lbl := Label.new()
	name_lbl.text = "?"
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.50, 1.0))
	name_lbl.position = Vector2(320.0, 77.0)
	name_lbl.size = Vector2(112.0, 20.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(name_lbl)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.10, 0.85)
	bg.position = Vector2(440.0, 84.0)
	bg.size = Vector2(400.0, 8.0)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.85, 0.55, 1.0)
	fill.position = Vector2(440.0, 84.0)
	fill.size = Vector2(400.0, 8.0)
	holder.add_child(fill)
	var upd := _RivalNodeBarUpdater.new()
	upd.host = self
	upd.fill = fill
	_rival_bar_layer.add_child(upd)

# P2 스윕 · 바이올렛 소거 벽이 좌우로 방을 훑는다. 리워크(§2.3) **층별 교대**: 사이클마다
# 하층 밴드(지상, y>1100)와 상층 밴드(중층+데크, y<=1100)를 번갈아 훑는다.
# 세이프 = 다른 층으로 옮기거나(수직 회피), 하층 스윕은 올라온 격벽 뒤(x밴드)도 세이프.
# 격벽 슬롯 4개 중 2개가 매 사이클 다른 자리에 올라온다 — 안전지대가 옮겨 다닌다.
# P2 승강 격벽 · 시각 전용이던 보라 기둥의 실물화(사용자 2026-08-17 "총알을 막는 것도,
# 밟을 수 있는 것도 아닌데 왜 시야만 가리냐"). 솔리드 = 포탑/플레이어 탄 차단 + 밟고
# 올라설 수 있음 + 하층 소거 벽의 엄폐. 올라올 때 위에 서 있으면 리프트처럼 들어올린다
# (MovingPlatform과 동형: AnimatableBody 직접 이동·sync_to_physics 끔). 렌더는 플레이어
# 뒤(z -1 절대)라 시야를 가리지 않고, 수납분은 지면 아래로 클리핑해 그린다.
class _SweepBulkhead extends AnimatableBody2D:
	const BW: float = 52.0
	const BH: float = 190.0
	var ground_y: float = 1220.0
	var raised: bool = false
	var _k: float = 0.0        # 0 = 수납(바닥 아래) / 1 = 완전 상승
	var _t: float = 0.0        # 상승 상태 장식 애니(에너지 펄스·캡 라이트, 완만)

	func _ready() -> void:
		sync_to_physics = false
		collision_layer = 1    # 월드 · 플레이어 착지 + 양측 탄 차단
		collision_mask = 0
		z_as_relative = false
		z_index = -1
		var col := CollisionShape2D.new()
		var shape := RectangleShape2D.new()
		shape.size = Vector2(BW, BH)
		col.shape = shape
		add_child(col)
		_apply()

	func set_raised(r: bool) -> void:
		raised = r

	func _physics_process(delta: float) -> void:
		_t += delta
		var target: float = 1.0 if raised else 0.0
		if absf(_k - target) > 0.0001:
			_k = move_toward(_k, target, delta / 0.7)
			_apply()
		if _k > 0.0:
			queue_redraw()

	func _apply() -> void:
		# 본체 중심 y · 수납 시 바닥 아래 완전 은닉(+6px 여유), 상승 시 바닥 위로 전부.
		position.y = ground_y + BH * 0.5 + 6.0 - (BH + 6.0) * _k

	func _draw() -> void:
		# 바닥 위로 나온 부분만 그린다(수납분이 지면 아래 배경 위로 비치지 않게).
		# 폴리시(2026-08-17 "투박하다"): 그라디언트 강판 + 패널 이음새 + 좌우 엣지 라이트 +
		# 중앙 에너지 심(위로 흐르는 펄스) + 베벨 캡. 전부 완만/연속(광과민 기준).
		var top_local: float = -BH * 0.5
		var cut: float = ground_y - position.y   # 지면의 로컬 y
		var vis_h: float = minf(BH, maxf(0.0, cut - top_local))
		if vis_h <= 1.0:
			return
		var hw: float = BW * 0.5
		var bot: float = top_local + vis_h
		# 몸체 · 상단이 살짝 밝은 강판 그라디언트(정점 색 보간).
		var kk: float = vis_h / BH
		var c_top := Color(0.27, 0.23, 0.38)
		var c_bot := c_top.lerp(Color(0.12, 0.10, 0.17), kk)
		draw_polygon(
			PackedVector2Array([Vector2(-hw, top_local), Vector2(hw, top_local), Vector2(hw, bot), Vector2(-hw, bot)]),
			PackedColorArray([c_top, c_top, c_bot, c_bot]))
		# 패널 이음새 · 어두운 골 + 아래 1px 하이라이트(강판 분절감).
		for seam_k in [0.33, 0.66]:
			var sy: float = top_local + BH * float(seam_k)
			if sy > top_local + 3.0 and sy < bot - 3.0:
				draw_rect(Rect2(Vector2(-hw + 3.0, sy), Vector2(BW - 6.0, 2.0)), Color(0.07, 0.06, 0.11, 0.9))
				draw_rect(Rect2(Vector2(-hw + 3.0, sy + 2.0), Vector2(BW - 6.0, 1.0)), Color(0.55, 0.42, 0.75, 0.25))
		# 좌우 엣지 라이트 · 은은한 글로우 + 얇은 밝은 선.
		for ex in [-hw, hw - 2.0]:
			draw_rect(Rect2(Vector2(float(ex) - 1.0, top_local), Vector2(4.0, vis_h)), Color(0.62, 0.40, 0.95, 0.16))
			draw_rect(Rect2(Vector2(float(ex), top_local), Vector2(2.0, vis_h)), Color(0.80, 0.58, 1.0, 0.55))
		# 중앙 에너지 심 · 위로 흐르는 펄스 점(동력이 올라오는 물건이라는 시각 언어).
		draw_rect(Rect2(Vector2(-1.0, top_local + 4.0), Vector2(2.0, maxf(0.0, vis_h - 8.0))), Color(0.72, 0.42, 1.0, 0.20))
		if _k > 0.95 and vis_h > 30.0:
			var pk: float = 1.0 - fmod(_t * 0.45, 1.0)
			var py: float = top_local + 8.0 + (vis_h - 16.0) * pk
			draw_circle(Vector2(0.0, py), 2.6, Color(0.90, 0.75, 1.0, 0.8))
		# 상단 베벨 캡 + 라이트 스트립(완만 맥동 ±5%).
		var cap_a: float = 0.85 + 0.05 * sin(_t * 1.8)
		draw_rect(Rect2(Vector2(-hw - 5.0, top_local - 8.0), Vector2(BW + 10.0, 8.0)), Color(0.34, 0.28, 0.48))
		draw_rect(Rect2(Vector2(-hw - 5.0, top_local - 8.0), Vector2(BW + 10.0, 2.0)), Color(0.62, 0.50, 0.85, 0.8))
		draw_rect(Rect2(Vector2(-hw + 2.0, top_local - 6.0), Vector2(BW - 4.0, 3.0)), Color(0.85, 0.65, 1.0, cap_a * 0.55))

class _RivalSweep extends Node2D:
	const SLOTS: Array = [350.0, 950.0, 1450.0, 2050.0]
	const W: float = 2400.0
	const H: float = 1300.0
	const GROUND: float = 1220.0
	const BAND_SPLIT: float = 1100.0   # 하층/상층 밴드 경계
	var host: Node = null              # Stage · 첫 격벽 상승 시 VEIL 힌트 1회용
	var phase: String = "rest"
	var t: float = 0.0
	var wall_x: float = -100.0
	var from_left: bool = true
	var low_band: bool = true          # 이번 사이클이 하층 스윕인가(사이클마다 교대)
	var active: Array = [0, 2]
	var cycle: int = 0
	var bulkheads: Array = []
	func _ready() -> void:
		z_index = 3
		# 승강 격벽 4기 · 슬롯마다 실물 배치(수납 상태로 시작).
		for x in SLOTS:
			var b := _SweepBulkhead.new()
			b.ground_y = GROUND
			b.position = Vector2(float(x), GROUND)
			add_child(b)
			bulkheads.append(b)
	func _physics_process(delta: float) -> void:
		t += delta
		match phase:
			"rest":
				if t > 2.6:
					phase = "rise"
					t = 0.0
					cycle += 1
					low_band = cycle % 2 == 1
					active = [cycle % 4, (cycle + 2) % 4]
					for i in bulkheads.size():
						(bulkheads[i] as _SweepBulkhead).set_raised(low_band and (i in active))
					SfxPlayer.play("drop_platform_descend", -4.0)
					# 첫 하층 사이클에 격벽의 쓰임을 한 번만 말로(실물 상호작용 3종 고지).
					# 단어는 화면에 보이는 것의 일상어만("격벽·소거" 조어 반려, 사용자 2026-08-17).
					if low_band and host != null and is_instance_valid(host) \
							and not bool(host.get("_p2_bulkhead_spoken")):
						host.set("_p2_bulkhead_spoken", true)
						host.call("_show_veil_subtitle", "바닥에서 올라온 벽 뒤에 서면 훑고 지나가는 보랏빛을 피합니다. 밟고 올라서도 되고, 총알도 막아 줘요.", 4.0)
			"rise":
				if t > 0.9:
					phase = "warn"
					t = 0.0
					from_left = not from_left
					SfxPlayer.play("enemy_sniper_charge", -4.0)
			"warn":
				if t > 1.0:
					phase = "sweep"
					t = 0.0
					wall_x = -80.0 if from_left else W + 80.0
			"sweep":
				wall_x += 1050.0 * delta * (1.0 if from_left else -1.0)
				_check_player()
				if wall_x < -100.0 or wall_x > W + 100.0:
					phase = "rest"
					t = 0.0
		queue_redraw()
	func _band_top() -> float:
		return BAND_SPLIT if low_band else 0.0
	func _band_bot() -> float:
		return H if low_band else BAND_SPLIT
	func _check_player() -> void:
		var tree := get_tree()
		if tree == null:
			return
		var arr := tree.get_nodes_in_group("player")
		if arr.size() == 0:
			return
		var p := arr[0] as Node2D
		var py: float = p.global_position.y
		# 밴드 밖(다른 층) = 세이프 · 층별 교대의 핵심 회피.
		if py < _band_top() or py > _band_bot():
			return
		if absf(p.global_position.x - wall_x) > 34.0:
			return
		# 하층 스윕은 격벽 뒤도 세이프(격벽은 지상 슬롯에만 있다).
		if low_band:
			for idx in active:
				if absf(p.global_position.x - float(SLOTS[idx])) < 52.0:
					return
		if p.has_method("take_hit"):
			p.take_hit(1)
	func _draw() -> void:
		# 격벽 슬롯 바닥 소켓(상시) · 격벽 본체는 _SweepBulkhead(실물)가 자체 렌더.
		# 소켓 폴리시: 베벨 플레이트 + 상승 중엔 슬릿 발광(어느 슬롯이 살아있는지 읽힘).
		for i in SLOTS.size():
			var x: float = float(SLOTS[i])
			draw_rect(Rect2(Vector2(x - 34.0, GROUND - 4.0), Vector2(68.0, 6.0)), Color(0.35, 0.30, 0.45, 0.7), true)
			draw_rect(Rect2(Vector2(x - 34.0, GROUND - 4.0), Vector2(68.0, 2.0)), Color(0.58, 0.48, 0.78, 0.5), true)
			if i < bulkheads.size() and bulkheads[i] != null and is_instance_valid(bulkheads[i]) \
					and float((bulkheads[i] as Node).get("_k")) > 0.02:
				draw_rect(Rect2(Vector2(x - 28.0, GROUND - 3.0), Vector2(56.0, 3.0)), Color(0.85, 0.62, 1.0, 0.55), true)
		# 경고 · 진입 방향 가장자리 광 + 이번 밴드 표시(어느 층을 훑는지 미리 보인다).
		if phase == "warn":
			var wx: float = 40.0 if from_left else W - 120.0
			var wa: float = 0.25 + 0.12 * sin(t * 9.0)
			draw_rect(Rect2(Vector2(wx - 40.0, _band_top()), Vector2(80.0, _band_bot() - _band_top())), Color(0.72, 0.42, 1.0, wa), true)
			draw_rect(Rect2(Vector2(0.0, _band_top()), Vector2(W, 3.0)), Color(0.72, 0.42, 1.0, 0.35), true)
			draw_rect(Rect2(Vector2(0.0, _band_bot() - 3.0), Vector2(W, 3.0)), Color(0.72, 0.42, 1.0, 0.35), true)
		# 스윕 벽 · 커튼 폴리시(2026-08-17 "투박하다"): 진행 반대쪽으로 사라지는 그라디언트
		# 꼬리 + 밝은 전연(리딩 엣지) + 잔상 라인. 연속 이동이라 점멸 아님(광과민 기준).
		if phase == "sweep":
			var bt: float = _band_top()
			var bb: float = _band_bot()
			var dirn: float = 1.0 if from_left else -1.0
			var lead: float = wall_x + dirn * 6.0
			var tail: float = wall_x - dirn * 130.0
			var c_lead := Color(0.72, 0.42, 1.0, 0.32)
			var c_tail := Color(0.72, 0.42, 1.0, 0.0)
			draw_polygon(
				PackedVector2Array([Vector2(tail, bt), Vector2(lead, bt), Vector2(lead, bb), Vector2(tail, bb)]),
				PackedColorArray([c_tail, c_lead, c_lead, c_tail]))
			draw_rect(Rect2(Vector2(wall_x - 5.0, bt), Vector2(10.0, bb - bt)), Color(0.88, 0.62, 1.0, 0.50), true)
			draw_rect(Rect2(Vector2(wall_x - 1.5, bt), Vector2(3.0, bb - bt)), Color(0.98, 0.88, 1.0, 0.85), true)
			for off in [34.0, 72.0]:
				var sxx: float = wall_x - dirn * float(off)
				draw_rect(Rect2(Vector2(sxx - 1.0, bt), Vector2(2.0, bb - bt)), Color(0.80, 0.55, 1.0, 0.12), true)

# ─── 가짜 클리어(§7.2 확정 연출) — P2 종료를 "이긴 척"으로 위장한다 ───
# 진짜 클리어 문법 재현(챔 + 소등 페이드 + STAGE CLEAR 문구) → 글리치 찢김 → 거짓 VEIL 등장.
# goal_reached는 켜지 않는다(가짜). 전 구간 타이머 체인(입력 불요) = 소프트락 안전판.
var _fake_clear_layer: CanvasLayer = null
var _fake_clear_rect: ColorRect = null
var _fake_clear_label: Label = null

func _start_fake_clear() -> void:
	if _rival_phase != 1 or goal_reached or not is_inside_tree():
		return
	_rival_phase = 2
	_rival_hold = true
	GameState.restrict_combat_input = true
	# P2 무대 정돈 — 조명 복구 + 소환물 정리("정말 끝난 것처럼").
	if _rival_cast != null and is_instance_valid(_rival_cast):
		var tw := _rival_cast.create_tween()
		tw.tween_property(_rival_cast, "color", Color(1, 1, 1), 0.8)
	for p in _rival_p2_props:
		# is_instance_valid를 먼저 — 전원 케이블(_P2PowerLink)은 power_off 0.6s 뒤 자체 해제되므로
		# 배열에 해제된 참조가 남고, 해제 인스턴스에 `is`를 먼저 대면 런타임 에러로 이 함수가
		# 통째로 중단돼 가짜 클리어 체인이 영구 정지한다(P2→P3 동결, 사용자 재현 3회).
		if is_instance_valid(p):
			(p as Node).queue_free()
	_rival_p2_props.clear()
	if _rival_bar_layer != null and is_instance_valid(_rival_bar_layer):
		_rival_bar_layer.queue_free()
		_rival_bar_layer = null
	# 진짜 클리어 문법 — 챔 + 검은 페이드 + 문구.
	SfxPlayer.play("stage_clear_chime")
	_fake_clear_layer = CanvasLayer.new()
	_fake_clear_layer.layer = 44
	add_child(_fake_clear_layer)
	_fake_clear_rect = ColorRect.new()
	_fake_clear_rect.color = Color(0, 0, 0, 0.0)
	_fake_clear_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fake_clear_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fake_clear_layer.add_child(_fake_clear_rect)
	var ftw := _fake_clear_rect.create_tween()
	ftw.tween_property(_fake_clear_rect, "color:a", 0.88, 1.2)
	_fake_clear_label = Label.new()
	_fake_clear_label.text = "STAGE CLEAR"
	_fake_clear_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fake_clear_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fake_clear_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_fake_clear_label.add_theme_font_size_override("font_size", 46)
	_fake_clear_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	_fake_clear_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_fake_clear_label.add_theme_constant_override("outline_size", 6)
	_fake_clear_label.modulate.a = 0.0
	_fake_clear_layer.add_child(_fake_clear_label)
	var ltw := _fake_clear_label.create_tween()
	ltw.tween_interval(0.9)
	ltw.tween_property(_fake_clear_label, "modulate:a", 1.0, 0.7)
	# 장식 라인 2줄(중앙에서 확장) + 하단 가짜 정산 문구 — 진짜 클리어 UI다운 밀도.
	# 중앙은 실제 뷰포트 폭에서 계산 — 설계 폭(1280)의 640을 박으면 와이드 화면에서
	# 문구(앵커 중앙)와 축이 어긋난다(2026-08-15 보고).
	var fc_cx: float = get_viewport().get_visible_rect().size.x * 0.5
	for ry in [318.0, 402.0]:
		var rule := ColorRect.new()
		rule.color = Color(0.85, 0.80, 0.70, 0.55)
		rule.position = Vector2(fc_cx, ry)
		rule.size = Vector2(0.0, 1.0)
		_fake_clear_layer.add_child(rule)
		var rt := rule.create_tween()
		rt.tween_interval(1.1)
		rt.tween_property(rule, "position:x", fc_cx - 240.0, 0.5)
		rt.parallel().tween_property(rule, "size:x", 480.0, 0.5)
	var sub := Label.new()
	sub.text = "보상 정산 중..."
	sub.set_anchors_preset(Control.PRESET_FULL_RECT)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, 76.0)
	sub.add_theme_font_size_override("font_size", 15)
	sub.add_theme_color_override("font_color", Color(0.62, 0.60, 0.55))
	sub.modulate.a = 0.0
	_fake_clear_layer.add_child(sub)
	var stw := sub.create_tween()
	stw.tween_interval(1.7)
	stw.tween_property(sub, "modulate:a", 1.0, 0.5)
	# 라이벌 기억(축 C, 확정 ⓐ) — 이미 이 마술을 본 관객에게는 같은 마술을 두 번 하지 않는다:
	# 자기 폭로 한 마디 후 곧장 찢고 P3로. 첫 목격이면 정식 체인(3.4s 유지 → 예고 → 본 찢김).
	var fake_seen_before: bool = GameState.rival_fake_clear_seen
	GameState.rival_fake_clear_seen = true
	GameState.save_settings()
	if fake_seen_before:
		get_tree().create_timer(1.0, false).timeout.connect(_fake_clear_self_expose)
	else:
		get_tree().create_timer(3.4, false).timeout.connect(_fake_clear_pretear)

# 축 C — 가짜 클리어 재방문: 라이벌이 스스로 걷어치운다(전개 자체가 회차에 반응한다는 신호).
func _fake_clear_self_expose() -> void:
	if goal_reached or not is_inside_tree() or _fake_clear_layer == null:
		return
	_show_rival_subtitle("이건 이미 보셨죠.", 2.2)
	get_tree().create_timer(0.9, false).timeout.connect(_fake_clear_tear)

# 찢김은 두 박자 — 예고(짧고 약한 흔들림) 뒤 한 호흡 쉬고 본 찢김. "너무 빠르고 갑작스럽다"
# 실플레이 반려(2026-08-13) 반영: 전개를 늘리고 램프를 완만하게. 강도(peak)는 추후 별도 튜닝.
func _fake_clear_pretear() -> void:
	if goal_reached or not is_inside_tree() or _fake_clear_layer == null:
		return
	_run_glitch(0.55, 0.3)
	get_tree().create_timer(1.1, false).timeout.connect(_fake_clear_tear)

# 본 찢김 — 화면 전체 글리치 셰이더(슬라이스 변위 + RGB 분리)로 클리어 UI를 통째로 찢는다.
# 피크에서 문구가 오염되고, 닫히던 화면이 도로 열린다. (라벨 흔들기 반려 → 셰이더 재작업.)
func _fake_clear_tear() -> void:
	if goal_reached or not is_inside_tree() or _fake_clear_layer == null:
		return
	SfxPlayer.play("boss_alert_text")
	# 강도 하향 2.2/0.9 → 1.6/0.65 — 본 찢김은 유지하되 눈 아픈 피크를 깎는다(2026-08-14).
	_run_glitch(1.6, 0.65)
	_rival_beat_flash()
	get_tree().create_timer(0.55, false).timeout.connect(_fake_clear_corrupt)
	get_tree().create_timer(2.4, false).timeout.connect(_fake_clear_end)

func _fake_clear_corrupt() -> void:
	if _fake_clear_label != null and is_instance_valid(_fake_clear_label):
		# ■ = U+25A0(KS X 1001) — U+25AE는 Pretendard 서브셋에 없어 웹에서 두부(× 글리프와 동형 오류).
		_fake_clear_label.text = "S T■G E   C L E■R"
		_fake_clear_label.add_theme_color_override("font_color", Color(0.72, 0.42, 1.0))
		var jt := _fake_clear_label.create_tween()
		jt.tween_property(_fake_clear_label, "position", Vector2(10.0, -5.0), 0.16)
		jt.tween_property(_fake_clear_label, "position", Vector2(-7.0, 4.0), 0.2)
		jt.tween_property(_fake_clear_label, "modulate:a", 0.0, 0.6)
	if _fake_clear_rect != null and is_instance_valid(_fake_clear_rect):
		var rtw := _fake_clear_rect.create_tween()
		rtw.tween_property(_fake_clear_rect, "color:a", 0.0, 1.0)

func _fake_clear_end() -> void:
	if goal_reached or not is_inside_tree():
		return
	if _fake_clear_layer != null and is_instance_valid(_fake_clear_layer):
		_fake_clear_layer.queue_free()
	_fake_clear_layer = null
	_fake_clear_rect = null
	_fake_clear_label = null
	GameState.restrict_combat_input = false
	# P3 오프닝 = 컷씬(2026-08-23) — 눈이 먼저 등장해 응시하고(가짜 그림 포함 정지 화면),
	# 다음 프레임에 세계를 멈춰 자백 + VEIL 안내 3줄을 읽는다. 컷씬 종료 후 응시 유예 3.0s가
	# 마저 흐른 뒤 첫 볼리. VEIL 줄이 온전히 나오는 건 억압 연출의 예외 — 판별 정보는 컷씬이
	# 전달하고, 억압(1.4s 끊김)은 전투 중 보조 자막이 담당한다(사용자 2026-08-23 가독 우선).
	_start_rival_p3(3.0)
	call_deferred("_p3_opening_cutscene")

# P3 오프닝 컷씬 — 자백(이번 런 이력 변형 3종) + VEIL 동요·판별 안내.
func _p3_opening_cutscene() -> void:
	if not is_inside_tree() or goal_reached or _rival_phase != 2:
		return
	# 정보 축적형 공개(2026-08-23) — 자백이 이번 런의 이력을 회수한다: 막4+ 루트맵에서 유인
	# (? 귀띔)을 따랐으면 "그것도 나였다", 봤지만 안 따랐으면 그 불신을 짚는다. 조우 없으면 원형.
	var confession: String
	if GameState.rival_lure_followed >= 1:
		# EN: "You know this screen. I drew it. Those tips I gave you
		#      when you picked your routes. Also my voice."
		confession = "이 화면, 익숙하시죠. 제가 그렸습니다.\n경로 고를 때 드린 귀띔도, 제 목소리였고요."
	elif GameState.rival_lure_shown >= 1:
		# EN: "You know this screen. I drew it. And you never once took my word at the forks."
		confession = "이 화면, 익숙하시죠. 제가 그렸습니다.\n경로 고를 때는 저를 한 번도 안 믿으시더니."
	else:
		confession = "이 화면, 익숙하시죠. 제가 그렸습니다."
	_play_story_dialogue([
		{"who": "rival", "text": confession},
		{"who": "veil", "text": "방금 그 신호, 제가 보낸 게 아닙니다."},
		{"who": "veil", "text": "굵은 표식은 제 것이 아닙니다. 저건 몸이 없습니다."},
		{"who": "veil", "text": "진짜는 표식 없이 옵니다. 가장자리는 직접 보십시오."},
	])

func _p3_tell_line() -> void:
	if not is_inside_tree() or goal_reached:
		return
	# 강의식 3문장 → 2문장 압축("작위적" 반려 2026-08-14). 탄 통과 tell은 시각(찢김)이 담당.
	_show_veil_subtitle("굵은 표식은 제 것이 아닙니다. 저건 몸이 없습니다.", 3.0)

func _p3_unmarked_line() -> void:
	if not is_inside_tree() or goal_reached or _rival_phase != 2:
		return
	_show_veil_subtitle("진짜는 표식 없이 옵니다. 가장자리는 직접 보십시오.", 3.0)

# ─── P3 분신전 — 거짓 VEIL(FalseVeil) + 무표시 위협 + 신뢰=지각 보조 ───
var _false_veil: Node2D = null
var _p3_assist_timer: Timer = null
var _p3_assist_spoken: bool = false   # 지각 보조 의도 발화 1회(이후 소거는 침묵 — 취소선이 말한다)
var _p3_cap_spoken: bool = false      # 창당 피해 상한 해설 1회(버그가 아니라 룰임을 알린다)
var _p3_bar_layer: CanvasLayer = null

# 가짜 병사 그림 격파(렌더 부하) · 첫 회에만 룰을 말로 짚는다 — "찢으면 빨리 나온다"의 인과.
# 개연성은 세계관 재료 그대로: 가짜도 본체의 잠복도 같은 구형 렌더러의 그림이다.
var _p3_torn_spoken: bool = false

func _on_p3_fake_torn(_total: int) -> void:
	if _p3_torn_spoken or not is_inside_tree() or goal_reached:
		return
	_p3_torn_spoken = true
	# EN: "Those fakes are its own renders. Tear them faster than it can redraw,
	#      and it can't stay a picture either."
	# ("몸을 그림으로 못 버팁니다" 비입말 결합 지적 · 무맥락 검수 1차, 2026-08-23)
	_show_veil_subtitle("저 가짜들은 저쪽이 직접 그리는 그림입니다. 다시 그리는 속도보다 빨리 찢으면, 저놈도 그림인 채로는 못 버팁니다.", 4.2)

# 창당 피해 상한 도달(조기 재잠복) · 첫 회에만 룰을 말로 짚는다. "탄이 안 박힌다"가
# 버그로 읽히지 않게(2026-08-17 상한 도입과 한 세트).
func _on_p3_window_capped() -> void:
	if _p3_cap_spoken or not is_inside_tree() or goal_reached:
		return
	_p3_cap_spoken = true
	# "실체화 창"은 설계 용어 · 플레이어에겐 보이는 대로("모습을 드러낼 때"). 2026-08-17.
	_show_veil_subtitle("깊게는 안 박힙니다. 그래도 몸은 물었습니다. 모습을 드러낼 때마다 조금씩, 확실하게.", 3.2)

# P3 보스 체력바 — SENTINEL 바 문법 재사용. 잠복/실체는 텍스트 라벨 대신 본체의 시각 언어
# (잠복 = 스캔라인 그림 + 탄 통과 파문 / 실체 = 꽉 찬 몸 + 링)와 바 밝기로만 전달
# ("실체 없음" 라벨은 작위적 — 실플레이 반려 2026-08-13).
class _FvBarUpdater extends Node:
	var fv: Node2D = null
	var fill: ColorRect = null
	func _process(_delta: float) -> void:
		if fv == null or not is_instance_valid(fv) or fill == null:
			return
		var ratio: float = clampf(float(fv.get("hp")) / maxf(1.0, float(fv.get("max_hp"))), 0.0, 1.0)
		fill.size.x = 400.0 * ratio
		var st: int = int(fv.get("state"))
		if st == 2:   # SOLID — 피격 가능(밝음)
			fill.color = Color(0.85, 0.55, 1.0)
		else:         # PHASED/TELE/DYING — 흐림
			fill.color = Color(0.45, 0.38, 0.55)

func _build_fv_bar(fv: Node2D) -> void:
	_p3_bar_layer = CanvasLayer.new()
	_p3_bar_layer.layer = 21
	add_child(_p3_bar_layer)
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_p3_bar_layer.add_child(holder)
	var name_lbl := Label.new()
	name_lbl.text = "?"
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.50, 1.0))
	name_lbl.position = Vector2(320.0, 77.0)
	name_lbl.size = Vector2(112.0, 20.0)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	holder.add_child(name_lbl)
	var bg := ColorRect.new()
	bg.color = Color(0.08, 0.06, 0.10, 0.85)
	bg.position = Vector2(440.0, 84.0)
	bg.size = Vector2(400.0, 8.0)
	holder.add_child(bg)
	var fill := ColorRect.new()
	fill.color = Color(0.45, 0.38, 0.55)
	fill.position = Vector2(440.0, 84.0)
	fill.size = Vector2(400.0, 8.0)
	holder.add_child(fill)
	var upd := _FvBarUpdater.new()
	upd.fv = fv
	upd.fill = fill
	_p3_bar_layer.add_child(upd)

static func _rotated(arr: Array, n: int) -> Array:
	var out: Array = []
	for i in arr.size():
		out.append(arr[(i + n) % arr.size()])
	return out

# hold = 개시 응시 유예(FalseVeil intro_hold) — 컷씬 개정(2026-08-23) 후 읽기는 컷씬이 담당,
# 유예는 응시 비트 전담. 첫 흐름 3.0s(컷씬 종료 후 눈맞춤 한 박자 뒤 첫 볼리) ·
# 체크포인트 재진입 3.6s(컷씬 없음 · 재고지 자막 1.4s를 덮는 최소 창).
func _start_rival_p3(hold: float = 3.0) -> void:
	if goal_reached or not is_inside_tree() or _false_veil != null:
		return
	_rival_phase = 2
	_rival_hold = true
	GameState.rival_phase_reached = 2
	_break_rival_lock(2)
	_run_glitch(0.6, 0.38)
	var fv := FalseVeil.new()
	# 눈 HP 레벨 스케일 — 고정 6은 s13 빌드에 SOLID 한두 창이면 녹아 "재미도 감동도 없다"
	# (사용자 2026-08-14). 2026-08-15 재상향(8+1.5lv, lv18=35): "1분 컷" 재보고 — 실체화 창
	# 5~6번을 살아남아야 하는 싸움으로. 전개 재설계는 리워크에서.
	fv.max_hp = 8 + int(float(GameState.player_level) * 1.5)
	fv.hp = fv.max_hp
	fv.intro_hold = hold
	# 리워크(§2.4) · 복층 무대 좌표: 실체화 3지점(중앙 상/좌상/우상 = 중반 텔레포트 지점 겸용),
	# 가짜 마커는 지상·중층·데크에 분산. 가짜 눈(동반 미끼)은 FalseVeil이 자체 관리.
	var p3_anchors: Array = [Vector2(1200.0, 560.0), Vector2(620.0, 640.0), Vector2(1780.0, 640.0)]
	var p3_spots: Array = [Vector2(350.0, 1190.0), Vector2(850.0, 1190.0), Vector2(1550.0, 1190.0),
		Vector2(2050.0, 1190.0), Vector2(350.0, 1010.0), Vector2(2050.0, 1010.0),
		Vector2(700.0, 850.0), Vector2(1700.0, 850.0), Vector2(1200.0, 830.0)]
	# 다회차 기억 변주 · P3 — 실체화 시작 지점·가짜 병사 슬롯 순서를 회차로 회전
	# ("네가 외운 자리에는 없다"). 수류탄으로 끝냈던 기억이 있으면 가짜 눈이 지난 회차의
	# 진짜 자리(+2 회전)에 선다 — 익숙한 자리일수록 가짜다. 개수·창 길이·HP는 불변.
	if GameState.rival_kills >= 1:
		p3_anchors = _rotated(p3_anchors, GameState.rival_kills % p3_anchors.size())
		p3_spots = _rotated(p3_spots, (GameState.rival_kills * 4) % p3_spots.size())
		fv.decoy_shift = 2 if GameState.rival_boss_explosive else 1
	fv.setup(p3_anchors, p3_spots)
	# deferred — volley_started는 take_damage(물리 콜백)에서 발화, 동기 스폰은 flushing 에러
	# (2026-08-20 실플레이 로그 실측 · BossSentinel 소환과 동형).
	fv.volley_started.connect(_on_p3_volley, CONNECT_DEFERRED)
	fv.defeated.connect(_on_false_veil_defeated)
	fv.stage_shifted.connect(_on_p3_stage_shifted)
	fv.window_capped.connect(_on_p3_window_capped)
	fv.fake_torn.connect(_on_p3_fake_torn)
	fv.position = Vector2(1200.0, 600.0)
	add_child(fv)
	_false_veil = fv
	_build_fv_bar(fv)
	# 신뢰 = 지각 보조(§7.2): warm이 가장 자주, thaw는 드물게, cold는 혼자 판별(tell은 전원 상시).
	var band: String = GameState.veil_register_band()
	if band != "cold":
		_p3_assist_timer = Timer.new()
		_p3_assist_timer.wait_time = 6.0 if band == "warm" else 10.0
		add_child(_p3_assist_timer)
		_p3_assist_timer.timeout.connect(_veil_assist_tick)
		_p3_assist_timer.start()

# P3 변주 전환(리워크 §2.4) · FalseVeil이 HP 문턱(66%/33%)에서 알린다.
# 1 = 중반: 텔레포트 실체화 개시 비트. 2 = 후반: 방 렌더 붕괴 · 주기 글리치 + 카메라 미진.
var _p3_shudder_timer: Timer = null

func _on_p3_stage_shifted(stage_idx: int) -> void:
	if goal_reached or not is_inside_tree():
		return
	_run_glitch(0.55, 0.32)
	_rival_beat_flash()
	SfxPlayer.play("boss_phase_change")
	if stage_idx == 1:
		_show_rival_subtitle("잘 보시네요. 그럼 자리를 옮겨 가며 하죠.", 3.0)
	elif stage_idx == 2:
		_show_rival_subtitle("...방이 저를 못 버티기 시작하는군요. 서두르겠습니다.", 3.2)
		# 낙하 잔해 3존(final_boss_rework §6-1) — 진동이 실제 붕괴로 이어지는 체감.
		# 그림자 예고 0.9s 문법 유지(FallingDebris 자체) · 격파 시 정리.
		# 캠핑 대책 ②(2026-08-20): 존이 최상단 데크(300~600/1800~2100)와 중앙 상단(1090~1310)을
		# 전부 덮도록 확장 — 종전 존(400~1000/1400~2000)은 데크 절반 + 중앙을 통째로 비워
		# "맨 위 발판 = 완전 안전"이었다. 발판 표면 예고(mark_platforms)로 상단에도 회피 정보.
		if _p3_debris_nodes.is_empty():
			var plats: Array = _debris_mark_platforms()
			for cfg0 in [{"x_min": 290.0, "x_max": 1000.0, "interval": 6.0},
					{"x_min": 1000.0, "x_max": 1400.0, "interval": 8.0, "phase": 0.35},
					{"x_min": 1400.0, "x_max": 2110.0, "interval": 6.5, "phase": 0.6}]:
				var fd := FallingDebris.new()
				add_child(fd)
				fd.setup(cfg0, 1220.0, plats)
				_p3_debris_nodes.append(fd)
		_p3_shudder_timer = Timer.new()
		_p3_shudder_timer.wait_time = 3.2
		add_child(_p3_shudder_timer)
		_p3_shudder_timer.timeout.connect(_p3_room_shudder)
		_p3_shudder_timer.start()

# 후반 · 방 렌더가 흔들린다(짧은 글리치 + 미세 흔들림, 광과민 기준 내 저강도).
func _p3_room_shudder() -> void:
	if goal_reached or _false_veil == null or not is_instance_valid(_false_veil):
		if _p3_shudder_timer != null and is_instance_valid(_p3_shudder_timer):
			_p3_shudder_timer.stop()
		return
	_run_glitch(0.35, 0.22)
	_camera_shake(3.0, 0.18)

# P3 볼리 — 가짜 마커 세례와 동시에 "무표시 진짜 위협" 투입(VeilSight가 마커 생략).
# 누적 상한 3 — 안 잡고 버티는 플레이어에게 무한 적체 방지.
func _on_p3_volley() -> void:
	if _rival_phase != 2 or goal_reached or not is_inside_tree():
		return
	var alive_p3: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Node).has_meta("no_marker"):
			alive_p3 += 1
	if alive_p3 >= 3:
		return
	SfxPlayer.play("hatch_open")
	for p in [Vector2(180.0, 1190.0), Vector2(2220.0, 1190.0)]:
		var n := _spawn_enemy(0, p)
		n.set_meta("no_marker", true)
	_enemies_remaining += 2

# 지각 보조는 시안 취소선(시각)이 말한다 — 지울 때마다 말로 중계하던 3종 로테이션은
# "작위적·오글거림" 반려(사용자 2026-08-14 3차). 첫 소거 때 의도 한 줄만, 이후엔 침묵.
func _veil_assist_tick() -> void:
	if goal_reached or _false_veil == null or not is_instance_valid(_false_veil):
		if _p3_assist_timer != null and is_instance_valid(_p3_assist_timer):
			_p3_assist_timer.stop()
		return
	if bool(_false_veil.call("erase_one_fake")) and not _p3_assist_spoken:
		_p3_assist_spoken = true
		_show_veil_subtitle("제 것이 아닌 표식이 섞였습니다. 걷어냅니다.", 2.6)

func _on_false_veil_defeated() -> void:
	if _rival_phase != 2 or goal_reached:
		return
	_rival_phase = 3
	GameState.rival_phase_reached = 0   # 정복 — 체크포인트 경계 해제(지속 플래그 원칙)
	GameState.rival_kills += 1          # 라이벌 기억(축 C) — 처치 누적(다음 회차 인트로 변형)
	# 다회차 기억 · 이번 격파의 공략 방식을 영속 프로필로(다음 회차 변주의 씨앗).
	# P2를 체크포인트로 건너뛴 시도(-1)는 이전 기억을 지우지 않는다.
	if _p2_first_side_attempt >= 0:
		GameState.rival_boss_first_side = _p2_first_side_attempt
	if _false_veil != null and is_instance_valid(_false_veil):
		GameState.rival_boss_explosive = int(_false_veil.get("last_hit_from_dir")) == 0
	GameState.save_settings()
	if _p3_assist_timer != null and is_instance_valid(_p3_assist_timer):
		_p3_assist_timer.stop()
	if _p3_shudder_timer != null and is_instance_valid(_p3_shudder_timer):
		_p3_shudder_timer.stop()
	if _p3_bar_layer != null and is_instance_valid(_p3_bar_layer):
		_p3_bar_layer.queue_free()
		_p3_bar_layer = null
	for fd in _p3_debris_nodes:
		if is_instance_valid(fd):
			(fd as Node).queue_free()
	_p3_debris_nodes.clear()
	# 격파 슬로우 비트(§2.4) · 시간이 잠깐 늘어지고 눈이 천천히 감긴다(FalseVeil DYING 연출과 정렬).
	Engine.time_scale = 0.35
	get_tree().create_timer(0.55, true, false, true).timeout.connect(func() -> void:
		Engine.time_scale = 1.0)
	# 잔여 무표시 위협 정리 — 분신이 소멸하면 그 손도 흩어진다.
	for e in get_tree().get_nodes_in_group("enemy"):
		if (e as Node).has_meta("no_marker"):
			(e as Node).queue_free()
	_enemies_remaining = 0
	# 격파 비트 = 컷씬(2026-08-23) — 슬로우 비트와 눈 감김이 한 박자(1.3s) 흐른 뒤 세계를
	# 멈추고 두 줄을 읽는다(정지 화면 = 소멸 중인 눈). 종료 시 출구 개방.
	get_tree().create_timer(1.3, false).timeout.connect(_rival_defeat_cutscene)

# 격파 컷씬 — 처치 반응(정보 축적형 공개 2026-08-23: 공개의 본전) + 퇴장 예고.
# 서버 로그 기발견자에겐 출신(삭제가 덜 끝난 옛 빌드)을 로그의 말로 자백하고, 미발견자에겐
# 최소 보장 한 줄(내 VEIL보다 먼저 만들어졌다는 암시)로 하한선을 깐다. 상한은 §2.2 준수 —
# 출신까지만, 원본/복제 선언 금지.
func _rival_defeat_cutscene() -> void:
	if not is_inside_tree() or goal_reached:
		return
	var first: String
	if GameState.found_server_log:
		# EN: "...You've stripped away every picture I drew. You saw the log.
		#      The old build they never finished deleting. That's me."
		first = "...제 그림을 전부 걷어내셨군요. 로그에서 보셨죠.\n삭제가 덜 끝난 옛 빌드. 그게 접니다."
	else:
		# EN: "...You've stripped away every picture I drew.
		#      That voice at your side, agent. It was built after me."
		first = "...제 그림을 전부 걷어내셨군요.\n지금 요원 곁의 그 목소리. 저보다 나중에 만들어진 겁니다."
	_play_story_dialogue([
		{"who": "rival", "text": first},
		{"who": "rival", "text": "방을 내드리죠. 다음 방은 더 깊습니다."},
	], _rival_boss_release)

func _rival_boss_release() -> void:
	if not is_inside_tree() or goal_reached:
		return
	_rival_hold = false
	# 즉시 14-2 터널로 끊지 않는다("대뜸 복도로 보내지 말 것", 사용자 2026-08-14). 일반 맵
	# 문법대로 우측에 출구가 열리고 걸어서 나간다. 출구 도달 → 클리어 시퀀스 →
	# _transition_after_clear의 route_core_recovery 분기 → 14-2 터널(CoreTunnel). ARENA 보너스
	# XP는 _on_arena_cleared를 안 거치므로 여기서 직접 준다.
	var data: Dictionary = MapData.get_layout(GameState.current_route_id)
	var bonus_xp: int = int(data.get("arena_clear_xp", 0))
	if bonus_xp > 0:
		GameState.add_xp(bonus_xp, false)
	_goal_type = "POSITION"
	_goal_pos = Vector2(2280.0, 1160.0)
	_build_goal_position()
	SfxPlayer.play("gate_unlock")

# 황금 희귀 개체 처치 보상 — 황금 보너스 오브 + 떠오르는 라벨 + 누적 카운터(영속).
func _reward_shiny_kill(pos: Vector2) -> void:
	_spawn_shiny_orb(pos)
	_show_shiny_toast(pos)
	GameState.shiny_kills += 1
	# 폰 경로 — 키보드 없는 기기에서도 코나미 대신 황금 3처치로 숨은 색 잠금 해제.
	if GameState.shiny_kills >= 3 and not GameState.alt_skin_unlocked:
		GameState.alt_skin_unlocked = true
		_show_veil_subtitle(VeilDialogue.banded("황금 개체, 세 번째 확인입니다. 보관해 둔 색을 하나 드리겠습니다.", "황금을 세 번 알아봤네요. 숨겨둔 색을 드릴게요."), 3.0)
	GameState.save_settings()
	SfxPlayer.play_at("bestiary_first_seen", pos)

func _spawn_shiny_orb(pos: Vector2) -> void:
	var orb := Node2D.new()
	orb.set_script(load("res://scripts/ExpOrb.gd"))
	var halo := ColorRect.new()
	halo.color = Color(1.0, 0.85, 0.35, 0.20)
	halo.position = Vector2(-15.0, -15.0)
	halo.size = Vector2(30.0, 30.0)
	halo.z_index = -1
	orb.add_child(halo)
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.color = Color(1.0, 0.82, 0.26)
	sprite.size = Vector2(16.0, 16.0)
	sprite.position = Vector2(-8.0, -8.0)
	sprite.pivot_offset = Vector2(8.0, 8.0)
	sprite.rotation = deg_to_rad(45.0)
	orb.add_child(sprite)
	add_child(orb)
	orb.global_position = pos
	orb.set("value", SHINY_ORB_VALUE)   # 일반 1 → 황금 5 (흡인/충돌은 일반 오브와 동일)

# 클리어 가산 토스트(단일 기록·도전 완수) — 관측 로그 온도의 짧은 확인 도장.
func _show_clear_toast(pos: Vector2, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(0.62, 0.92, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.z_index = 40
	add_child(lbl)
	lbl.global_position = pos + Vector2(-64.0, 0.0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 26.0, 1.1)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 1.1)
	tw.tween_callback(lbl.queue_free)

func _show_shiny_toast(pos: Vector2) -> void:
	var lbl := Label.new()
	lbl.text = "황금 개체"
	lbl.add_theme_font_size_override("font_size", 15)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.z_index = 40
	add_child(lbl)
	lbl.global_position = pos + Vector2(-24.0, -40.0)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "global_position:y", lbl.global_position.y - 26.0, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.tween_callback(lbl.queue_free)

func _spawn_orb(pos: Vector2, static_placement: bool = false, attract_range: float = -1.0, is_gate: bool = false) -> Node2D:
	# static_placement=true면 bounce 스킵 — 분기 보상으로 미리 배치된 orb는 그 자리에 그대로 둠.
	# is_gate=true면 글라이드 게이트 전용 보상 — 일반 오브와 성질이 다름을 모양·색으로 구분하고
	# 개당 가치를 높인다(글라이드 투자 보상). 흡인은 작게 + 벽/바닥 너머론 안 끌려옴(ExpOrb LoS).
	# 반환값은 정찰 POI 등록용(_build_rewards) — 다른 호출처는 무시해도 된다.
	var orb := Node2D.new()
	orb.set_script(load("res://scripts/ExpOrb.gd"))
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	if is_gate:
		# 황금 마름모(45° 회전) + 옅은 후광 — 멀리서도 "글라이드로만 닿는 특별 보상"으로 읽히게.
		sprite.color = Color(1.0, 0.82, 0.26)
		sprite.size = Vector2(15.0, 15.0)
		sprite.position = Vector2(-7.5, -7.5)
		sprite.pivot_offset = Vector2(7.5, 7.5)
		sprite.rotation = deg_to_rad(45.0)
		var halo := ColorRect.new()
		halo.color = Color(1.0, 0.82, 0.26, 0.16)
		halo.position = Vector2(-13.0, -13.0)
		halo.size = Vector2(26.0, 26.0)
		halo.z_index = -1
		orb.add_child(halo)
	else:
		# 마름모 + 옅은 후광 + 완만한 숨쉬기(2026-08-17 폴리시 · 플랫 정사각 탈피).
		sprite.color = Color(0.4, 0.95, 0.6)
		sprite.position = Vector2(-6.0, -6.0)
		sprite.size = Vector2(12.0, 12.0)
		sprite.pivot_offset = Vector2(6.0, 6.0)
		sprite.rotation = deg_to_rad(45.0)
		var halo_n := ColorRect.new()
		halo_n.color = Color(0.4, 0.95, 0.6, 0.14)
		halo_n.position = Vector2(-10.0, -10.0)
		halo_n.size = Vector2(20.0, 20.0)
		halo_n.pivot_offset = Vector2(10.0, 10.0)
		halo_n.rotation = deg_to_rad(45.0)
		halo_n.z_index = -1
		orb.add_child(halo_n)
	orb.add_child(sprite)
	add_child(orb)
	orb.global_position = pos
	# 숨쉬기 · 느린 스케일 맥동(점멸 아님).
	var breathe := orb.create_tween()
	breathe.set_loops()
	breathe.tween_property(orb, "scale", Vector2(1.12, 1.12), 0.9).set_trans(Tween.TRANS_SINE)
	breathe.tween_property(orb, "scale", Vector2(1.0, 1.0), 0.9).set_trans(Tween.TRANS_SINE)
	if static_placement:
		# bounce 스킵 — 즉시 attract 단계로. placed = 클리어 환급 제외(가서 먹어야 하는 보상).
		orb.set("spawn_anim_t", 1.0)
		orb.set("bounce_velocity", Vector2.ZERO)
		orb.set("placed", true)
	if is_gate:
		orb.set("is_gate", true)
		orb.set("value", 3)          # 일반 1 → 게이트 3 (게이트당 6 ≈ 거의 1레벨)
		orb.set("attract_range", 44.0)
	elif attract_range > 0.0:
		orb.set("attract_range", attract_range)
	return orb

func _spawn_hp_orb(pos: Vector2) -> Node2D:
	# 분기 보상으로 미리 배치된 HP 회복 픽업 (적 처치 드롭과 별개).
	var orb := Node2D.new()
	orb.set_script(load("res://scripts/HpOrb.gd"))
	# 빨간 십자 모양 — 멀리서도 HP 회복임을 인지할 수 있게.
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.color = Color(0.95, 0.30, 0.30, 0.0)
	sprite.size = Vector2.ZERO
	orb.add_child(sprite)
	# 십자 가로
	var bar_h := ColorRect.new()
	bar_h.color = Color(0.95, 0.30, 0.30)
	bar_h.position = Vector2(-9.0, -2.0)
	bar_h.size = Vector2(18.0, 4.0)
	orb.add_child(bar_h)
	# 십자 세로
	var bar_v := ColorRect.new()
	bar_v.color = Color(0.95, 0.30, 0.30)
	bar_v.position = Vector2(-2.0, -9.0)
	bar_v.size = Vector2(4.0, 18.0)
	orb.add_child(bar_v)
	# 옅은 후광 (시선 끌기용)
	var halo := ColorRect.new()
	halo.color = Color(0.95, 0.30, 0.30, 0.18)
	halo.position = Vector2(-12.0, -12.0)
	halo.size = Vector2(24.0, 24.0)
	halo.z_index = -1
	orb.add_child(halo)
	add_child(orb)
	orb.global_position = pos
	# 깜빡임 (시선 끌기)
	var tw := halo.create_tween()
	tw.set_loops()
	tw.tween_property(halo, "modulate:a", 0.4, 0.7)
	tw.tween_property(halo, "modulate:a", 1.0, 0.7)
	return orb

func _build_rewards() -> void:
	# MapData에 명시된 분기 보상 (XP 다발 + HP 픽업)을 미리 배치.
	# 적 처치 드롭과 달리 bounce 없이 그 자리에 그대로 떠 있다 (분기 도달 보상이라 위치가 의미).
	# 미리 배치된 보상은 정찰 POI 그룹에 등록 — 정찰 보상(재정의 2026-08-21) 활성 시 VeilSight가
	# 청색 표식으로 짚는다. 적 처치 드롭은 제외(숨은 요소가 아님).
	var rewards: Dictionary = _map_data.get("rewards", {})
	for pos in rewards.get("xp_orbs", []):
		_spawn_orb(pos, true).add_to_group("recon_poi")
	# 글라이드 게이트 보상 — is_gate로 황금 마름모 + 가치 3 + 흡인 44px + LoS 차단.
	# 실제 알코브에 삼단점프로 도달해야만 획득 → 게이트 의미 보존(아래/옆 메인 경로에서 안 빨려옴).
	for pos in rewards.get("gate_orbs", []):
		_spawn_orb(pos, true, -1.0, true).add_to_group("recon_poi")
	for pos in rewards.get("hp_pickups", []):
		_spawn_hp_orb(pos).add_to_group("recon_poi")

# ─── 레버 퍼즐 — 비밀칸/이스터에그 시스템 ─────────────────────
# 맵별로 레버를 배치하고 pulled 시그널에 효과를 연결한다.
# 튜토리얼(back_alley·rooftops): 진행 루트와 분리된 비밀칸. 모르고 지나쳐도 클리어.
# 레버 시각은 ARCTURUS 청색 hint glow로 발견 단서를 제공한다.

func _build_lever_puzzles() -> void:
	if GameState.playground_active:
		return
	# 체인 맵은 세그먼트 게이트 필수(2026-08-23 실플레이 회귀) — route id만 보면 비밀칸이
	# 방마다 복제된다: 냉각 방1·3에 방2 발판 좌표의 레버가 공중 부양 · 서버 홀 3방에서
	# 같은 로그 문서가 반복. 좌표의 기준 발판이 있는 방(원형 계승 방)에만 짓는다.
	match GameState.current_route_id:
		"route_back_alley":
			_build_back_alley_secret()
		"route_rooftops":
			_build_rooftops_secret()
		"route_cooling":
			if GameState.current_segment == 1:   # 방2 열교환 홀 — 발판(1560,380)이 여기에만 있다
				_build_cooling_secret()
		"route_datacenter":
			_build_datacenter_secret()
		"route_server_hall":
			if GameState.current_segment == 1:   # 방2 본실(원형 계승) — 서버 랙(2000,470) 위 레버
				_build_server_hall_secret()

func _spawn_lever(pos: Vector2, lever_id: String) -> LeverInteractable:
	var lever := LeverInteractable.new()
	lever.lever_id = lever_id
	add_child(lever)
	lever.global_position = pos
	return lever

# 닫힌 해치 — 시각 패널. 레버 풀리면 fade out + 콜리전 disable.
# 반환된 노드의 open()을 부르면 열림.
func _spawn_closed_hatch(pos: Vector2, size: Vector2, hint_color: Color) -> Node2D:
	var root := Node2D.new()
	root.global_position = pos
	add_child(root)
	# 패널 본체 — 짙은 금속색
	var panel := ColorRect.new()
	panel.color = Color(0.18, 0.20, 0.24)
	panel.position = -size * 0.5
	panel.size = size
	root.add_child(panel)
	# 격자 라인 (잠긴 분위기)
	var grid := ColorRect.new()
	grid.color = Color(0.08, 0.09, 0.11, 0.85)
	grid.position = Vector2(-size.x * 0.5, -1.5)
	grid.size = Vector2(size.x, 3.0)
	root.add_child(grid)
	# 외곽선
	var outline := Line2D.new()
	outline.points = PackedVector2Array([
		-size * 0.5,
		Vector2(size.x * 0.5, -size.y * 0.5),
		size * 0.5,
		Vector2(-size.x * 0.5, size.y * 0.5),
	])
	outline.closed = true
	outline.width = 1.2
	outline.default_color = Color(hint_color.r, hint_color.g, hint_color.b, 0.55)
	outline.antialiased = true
	root.add_child(outline)
	# 잠금 표시 — 작은 자물쇠 형태(사각형 위 호)
	var lock := ColorRect.new()
	lock.color = Color(hint_color.r, hint_color.g, hint_color.b, 0.75)
	lock.position = Vector2(-3.0, -3.0)
	lock.size = Vector2(6.0, 6.0)
	root.add_child(lock)
	root.set_meta("opened", false)
	# 비밀 칸(해치)도 정찰 POI — 정찰 보상 활성 시 VeilSight가 위치를 짚는다.
	root.add_to_group("recon_poi")
	return root

func _open_hatch(hatch: Node2D) -> void:
	if hatch.get_meta("opened", false):
		return
	hatch.set_meta("opened", true)
	hatch.remove_from_group("recon_poi")   # 열린 칸은 더 짚을 필요 없음
	SfxPlayer.play("hatch_open")
	var tw := hatch.create_tween()
	tw.set_parallel(true)
	tw.tween_property(hatch, "modulate:a", 0.0, 0.45)
	tw.tween_property(hatch, "scale", Vector2(0.85, 0.20), 0.45)
	tw.chain().tween_callback(hatch.queue_free)

# 동적으로 떨어지는 발판 — 레버 풀리면 위에서 내려와 정착한다.
# StaticBody이지만 이동시키기 위해 collision_shape를 직접 옮기는 방식 (one_way 유지).
func _spawn_drop_platform(start_pos: Vector2, end_pos: Vector2, w: float) -> Node:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.add_to_group("platform")
	add_child(body)
	var col := CollisionShape2D.new()
	col.one_way_collision = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, 16.0)
	col.shape = shape
	col.position = start_pos
	body.add_child(col)
	# 시각 — 일반 플랫폼보다 얇고 청록색 강조 (작동된 것 표시)
	var visual := Node2D.new()
	body.add_child(visual)
	var px: float = -w * 0.5
	var panel := ColorRect.new()
	panel.color = Color(0.16, 0.20, 0.26)
	panel.position = Vector2(px, -8.0)
	panel.size = Vector2(w, 16.0)
	visual.add_child(panel)
	var top := ColorRect.new()
	top.color = Color(0.55, 0.85, 0.95, 0.85)
	top.position = Vector2(px + 2.0, -9.0)
	top.size = Vector2(w - 4.0, 1.6)
	visual.add_child(top)
	visual.position = start_pos
	# 시작은 invisible + 콜리전 비활성 — 풀리기 전에 플레이어가 보이지 않는 발판에 부딪히지 않게
	body.modulate.a = 0.0
	col.disabled = true
	body.set_meta("col_node", col)
	body.set_meta("visual_node", visual)
	body.set_meta("end_pos", end_pos)
	body.set_meta("descended", false)
	return body

func _descend_drop_platform(body: Node) -> void:
	if body.get_meta("descended", false):
		return
	body.set_meta("descended", true)
	SfxPlayer.play("drop_platform_descend")
	var col: CollisionShape2D = body.get_meta("col_node")
	var visual: Node2D = body.get_meta("visual_node")
	var end_pos: Vector2 = body.get_meta("end_pos")
	col.disabled = false
	(body as CanvasItem).modulate.a = 1.0
	var tw := body.create_tween()
	tw.set_parallel(true)
	tw.tween_property(col, "position", end_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "position", end_pos, 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

# ── datacenter 비밀 레버 (가시 비활성화) ────────────────────────
# 메인 ARENA 지면에 가시 두 구간 → 사격하면서 위치 조심해야 함.
# 측면 상층(top, y=340) 끝에 레버 — 당기면 가시가 어두워지며 콜리전 off.
# 보상: 위험 통로를 안전 통로로 전환 (XP/HP 픽업 같은 토큰 보상은 없음 — 안전 자체가 보상).
# ── server_hall 숨은 터미널 로그 (이스터에그 — 라이벌 VEIL 복선) ──────────────
# 서버 랙 위 숨은 레버(ARCTURUS 청색 hint)를 당기면 복구된 서버 로그 단편을 문서로 보여준다.
# ArcturusDocumentOverlay가 일시정지·타이핑·닫기·해제를 자립 처리. 스테이지당 1회.
# 문구는 초안(사용자 검토 대기) — 두 번째 VEIL이 "당신이 무엇을 보는지를 본다"는 복선.
var _server_log_shown: bool = false

func _build_server_hall_secret() -> void:
	var lever := _spawn_lever(Vector2(2000.0, 450.0), "server_log")   # 서버 랙(2000,470) 위
	lever.hint_color = Color(0.55, 0.85, 0.95)   # 청색 = 로어 단서(ARCTURUS 계열)
	lever.pulled.connect(func(_id: String) -> void:
		if _server_log_shown:
			return
		_server_log_shown = true
		GameState.found_server_log = true
		GameState.save_settings()
		var doc := ArcturusDocumentOverlay.new()
		add_child(doc)
		# VEIL의 실황 반응은 문서(복구 기록) 안이 아니라 문서를 닫은 뒤 통신 자막으로.
		# speaker 비트로 넣어도 종이 위에 그려져 "문서에 적힌 글"로 읽힘(사용자 지적 2026-08-16).
		doc.finished.connect(func() -> void:
			get_tree().create_timer(0.8, false).timeout.connect(func() -> void:
				_show_veil_subtitle(VeilDialogue.banded("...이 기록, 제가 남긴 게 아닙니다.", "...이 기록, 제가 남긴 게 아니에요."), 4.0))
		)
		doc.show_doc(_server_log_doc_lines())
	)

# 서버 로그 문서 라인(초안 2차 — 사용자 검토 대기). 포맷: {text, kind(title/body/speaker/blank), delay}.
# 2026-08-12 개정: 14장 회의 확정 설정을 복선으로 직조 — 라이벌 = 인간을 닮게 설계됐다 폐기된
# 선대 빌드(§7.2 시각 대비축), 결이 어긋난 정중함 잔향(말투 A), 갇혀 기다리는 동기(§2.1).
# 문서는 기록체만. 2026-08-15 재개정: 독자를 부르는 해설·시적 내레이션 4줄 제거(기록체 규약).
# 2026-08-16 재개정: VEIL 실황 반응을 문서에서 제거. speaker 비트도 종이 위에 그려져
# "문서에 적힌 글"로 읽힌다는 반복 지적 수용. 반응은 문서 닫힌 뒤 통신 자막으로(위 finished 연결).
func _server_log_doc_lines() -> Array:
	return [
		{"text": "서버 로그 · 복구 단편", "kind": "title", "delay": 0.6},
		{"text": "", "kind": "blank", "delay": 0.2},
		{"text": "감시 계층 이중화 감지. 등록되지 않은 인스턴스.", "kind": "body", "delay": 0.6},
		{"text": "계보 조회: 현행의 선행 빌드. 상태: 폐기. 삭제 절차 미완료.", "kind": "body", "delay": 0.6, "hl": true},
		{"text": "설계 노트 단편: \"더 사람처럼 만들 것. 눈. 목소리. 머뭇거림.\"", "kind": "body", "delay": 0.7},
		{"text": "폐기 사유: 사람을 너무 닮았음. 후속 빌드는 정제형으로 회귀.", "kind": "body", "delay": 0.7, "hl": true},
		{"text": "권한 충돌 기록: 동일 표적에 관측 세션 2건.", "kind": "body", "delay": 0.5},
		{"text": "세션 1: 대상 위치 추적. 세션 2: 대상의 시야 스트림 열람.", "kind": "body", "delay": 0.8},
		{"text": "[이하 구간 덮어쓰임 · 복구 불가]", "kind": "body", "delay": 0.6},
		{"text": "미서명 문자열 1건 검출: \"기다리고 있었습니다.\"", "kind": "body", "delay": 0.9, "hl": true},
	]

func _build_datacenter_secret() -> void:
	# 두 개의 토글 가능 가시 그룹. 지면 y=820 기준 base_y=814.
	var base_y: float = 814.0
	var spike_a := _spawn_toggleable_spike(550.0, 120.0, base_y, 1)
	var spike_b := _spawn_toggleable_spike(1500.0, 120.0, base_y, 1)
	# 레버 — 상층 우측 평지 위. (1200, 320)으로 platform y=340 위에 적당히 얹힘.
	var lever := _spawn_lever(Vector2(1200.0, 320.0), "datacenter_spikes_off")
	lever.hint_color = Color(0.55, 0.85, 0.95)
	lever.pulled.connect(func(_id: String) -> void:
		_set_spike_group_active(spike_a, false)
		_set_spike_group_active(spike_b, false)
		_show_veil_subtitle(VeilDialogue.banded("전원 차단 확인. 발밑 가시 무력화.", "전기가 끊겼어요. 발 밑 가시 무력화."), 3.0)
	)

# ── back_alley 비밀칸 ─────────────────────────────────────────
# 레버 위치: 1300, 588 (지면, 3·4번 발판 사이를 지나갈 때 보임)
# 비밀 해치: 2300, 280 (6번 발판 위 천장 alcove)
# 풀면 해치 fade + drop platform 강하 + XP orb 5개 spawn
func _build_back_alley_secret() -> void:
	# 첫 레버 튜토리얼 — 레버와 해치를 한 화면에 둬 "당김→바로 앞 칸 열림" 인과를 즉시 이해하게 함
	# (사용자 피드백 2026-06-14: 이전엔 1000px 떨어져 무엇이 열렸는지 안 보였음). 1300→2120.
	var lever := _spawn_lever(Vector2(2120.0, 588.0), "back_alley_vent")
	var hatch := _spawn_closed_hatch(Vector2(2300.0, 290.0), Vector2(80.0, 50.0), Color(0.55, 0.85, 0.95))
	var drop_platform := _spawn_drop_platform(
		Vector2(2150.0, 200.0), Vector2(2150.0, 380.0), 100.0
	)
	lever.pulled.connect(func(_id: String) -> void:
		_open_hatch(hatch)
		_descend_drop_platform(drop_platform)
		# XP orb 5개 — 해치 안쪽에 흩어짐
		var spots: Array = [
			Vector2(2270.0, 250.0), Vector2(2310.0, 240.0), Vector2(2350.0, 250.0),
			Vector2(2290.0, 290.0), Vector2(2330.0, 290.0),
		]
		for p in spots:
			_spawn_orb(p, true)
		# 첫 레버 튜토리얼: 레버↔해치가 1000px 떨어져 인과가 한 화면에 안 보임 → VEIL이
		# 무엇을/어디를 열었는지 방향까지 짚어준다(사용자: "뭘 여는 건지 알려주는 기능이 모자람").
		_show_veil_subtitle("잠긴 칸이 열렸습니다. 바로 앞, 위로 올라가 보십시오.", 3.2)
	)

# ── cooling 비밀칸 (후반 맵 레버 강화 — back_alley 인과를 한 번 더) ──────────────
# 레버 바로 위에 해치를 둬 인과가 한 화면에 또렷. 증기 분출구(x1380) 우측 안전 지대.
func _build_cooling_secret() -> void:
	# 레버를 증기 분출구(x1380/1760) 사이 안전한 발판(1560,380) 위로 옮긴다. 당기면 솟는
	# 발판·해치 없이 XP 3을 그 발판 위에 직접 떨어뜨린다(사용자 피드백 2026-06-19: 레버가
	# 증기 분출구 옆 지면에 있어 위험했고, 당겨 솟는 발판 연출이 불필요했음).
	var lever := _spawn_lever(Vector2(1560.0, 360.0), "cooling_vent")
	lever.pulled.connect(func(_id: String) -> void:
		var spots: Array = [Vector2(1510.0, 354.0), Vector2(1560.0, 348.0), Vector2(1610.0, 354.0)]
		for p in spots:
			_spawn_orb(p, true)
		_show_veil_subtitle(VeilDialogue.banded("여기도 잠긴 칸이었습니다. 발밑 보급품을 챙기십시오.", "여기도 잠긴 칸이었네요. 발밑 보급품을 챙겨요."), 3.0)
	)

# ── rooftops 비밀칸 ───────────────────────────────────────────
# 레버 위치: 200, 3060 (지면 시작 부근, 좌측 외벽 근처)
# 닫힌 환기구: 200, 2820 (좌측 벽쪽 alcove)
# 풀면 환기구 fade + 사다리 발판 2개 강하 + HP 1 + XP 2
func _build_rooftops_secret() -> void:
	var lever := _spawn_lever(Vector2(200.0, 3060.0), "rooftops_vent")
	var hatch := _spawn_closed_hatch(Vector2(200.0, 2820.0), Vector2(70.0, 60.0), Color(0.55, 0.85, 0.95))
	var step1 := _spawn_drop_platform(Vector2(180.0, 2700.0), Vector2(180.0, 2960.0), 90.0)
	var step2 := _spawn_drop_platform(Vector2(140.0, 2620.0), Vector2(140.0, 2880.0), 90.0)
	lever.pulled.connect(func(_id: String) -> void:
		_open_hatch(hatch)
		_descend_drop_platform(step1)
		_descend_drop_platform(step2)
		_spawn_hp_orb(Vector2(200.0, 2820.0))
		# 레버 보상 상향(XP2→4) — 외곽 진입로 해치(XP5)보다 어려운 맵(수직 등반+저격)인데
		# 더 적던 역전 해소. 글라이드 게이트 제거 보전도 겸함. 사용자 피드백 2026-06-12.
		_spawn_orb(Vector2(160.0, 2810.0), true)
		_spawn_orb(Vector2(200.0, 2810.0), true)
		_spawn_orb(Vector2(240.0, 2810.0), true)
		_spawn_orb(Vector2(200.0, 2770.0), true)
	)

var _enemies_remaining: int = 0  # ARENA enemy_clear 카운트
var _defense_core: DefenseCore = null  # 아레나 방어 맵의 코어(있을 때만)
var _had_enemies: bool = false   # 이 스테이지에 적이 스폰됐는가(평화주의 이스터에그 판정)

func _build_goal() -> void:
	match _goal_type:
		"POSITION":
			_build_goal_position()
		"ENEMY_CLEAR":
			_setup_arena_clear_tracking()
			if _rival_boss_active():
				_init_rival_boss()
		"SEQUENCE":
			pass  # ??? 등 — 자체 종료 로직
		_:
			_build_goal_position()

func _build_goal_position() -> void:
	var goal := Area2D.new()
	goal.collision_layer = 0
	goal.collision_mask = 2
	# MapData에서 명시한 goal_pos 사용 (없으면 우측 끝 폴백)
	var pos: Vector2 = _goal_pos
	if pos == Vector2.ZERO:
		pos = Vector2(STAGE_LENGTH - 80.0, GROUND_Y - 60.0)
	goal.position = pos
	add_child(goal)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60.0, 200.0)
	col.shape = shape
	goal.add_child(col)
	# 골 비주얼 폴리시(2026-08-17) · 플랫 노란 사각 2장 → 그라디언트 문 + 위로 잦아드는
	# 빛기둥 + 바닥 착지 글로우. "문/출구" 가독(외곽선·라벨)은 유지.
	# 그림 = 판정의 부분집합(사용자 2026-08-18 "그림이랑 판정 위치 같게 · 그림을 줄여라"):
	# 예전엔 지면 박힘을 비주얼 *이동*으로 보정해 그림과 판정이 어긋났다. 이제 이동 없이
	# 문 하단을 지면에 클램프해 *축소*하고, 빛기둥·글로우 폭도 판정 폭(60)에 맞춘다.
	var vis := Node2D.new()
	goal.add_child(vis)
	# 그림 하단(로컬) — 판정 하단(+100)이 *받침면* 아래로 박히는 만큼 줄인다(최소 높이 보장).
	# 받침면 = 지면 또는 골 바로 아래 발판 top(발판 위 출구가 발판을 뚫고 내려와 보이던
	# 붕괴 샤프트 출구 데크 사건, 2026-08-20 사용자). 골 x를 덮는 발판 중 골 중심 아래 최상단.
	var support_y: float = GROUND_Y
	for p_entry in _map_data.get("platforms", []):
		var pd: Dictionary = p_entry
		var pp: Vector2 = pd.get("pos", Vector2.ZERO)
		var pw: float = float(pd.get("w", 0.0))
		if absf(pp.x - pos.x) <= pw * 0.5 and pp.y >= pos.y:
			support_y = minf(support_y, pp.y)
	var vbot: float = clampf(100.0 - maxf(0.0, (pos.y + 100.0) - support_y), 30.0, 100.0)
	var door := Polygon2D.new()
	door.polygon = PackedVector2Array([
		Vector2(-30.0, -100.0), Vector2(30.0, -100.0), Vector2(30.0, vbot), Vector2(-30.0, vbot)])
	door.vertex_colors = PackedColorArray([
		Color(0.95, 0.85, 0.3, 0.16), Color(0.95, 0.85, 0.3, 0.16),
		Color(1.0, 0.92, 0.5, 0.55), Color(1.0, 0.92, 0.5, 0.55)])
	vis.add_child(door)
	# 빛기둥 · 바닥에서 위로 잦아드는 세로 그라디언트(판정 폭 언저리 겹 + 좁은 코어 겹).
	for entry in [[100.0, 0.14, 600.0], [52.0, 0.20, 460.0]]:
		var e: Array = entry
		var bw: float = float(e[0])
		var beam := Polygon2D.new()
		beam.polygon = PackedVector2Array([
			Vector2(-bw * 0.5, vbot - float(e[2])), Vector2(bw * 0.5, vbot - float(e[2])),
			Vector2(bw * 0.5, vbot), Vector2(-bw * 0.5, vbot)])
		beam.vertex_colors = PackedColorArray([
			Color(0.95, 0.85, 0.3, 0.0), Color(0.95, 0.85, 0.3, 0.0),
			Color(0.95, 0.85, 0.3, float(e[1])), Color(0.95, 0.85, 0.3, float(e[1]))])
		vis.add_child(beam)
	# 바닥 착지 글로우 · 문 아래 얇고 밝은 띠 + 옆으로 번지는 빛(판정 폭 언저리).
	var base_core := ColorRect.new()
	base_core.color = Color(1.0, 0.94, 0.6, 0.85)
	base_core.position = Vector2(-30.0, vbot - 3.0)
	base_core.size = Vector2(60.0, 3.0)
	vis.add_child(base_core)
	var base_spread := Polygon2D.new()
	base_spread.polygon = PackedVector2Array([
		Vector2(-48.0, vbot - 4.0), Vector2(48.0, vbot - 4.0), Vector2(48.0, vbot), Vector2(-48.0, vbot)])
	base_spread.vertex_colors = PackedColorArray([
		Color(1.0, 0.9, 0.5, 0.0), Color(1.0, 0.9, 0.5, 0.0),
		Color(1.0, 0.9, 0.5, 0.35), Color(1.0, 0.9, 0.5, 0.35)])
	vis.add_child(base_spread)
	# 박스 외곽선 — "배경 장식"이 아니라 *문/출구*로 읽히게(피드백: 노란 네모가 끝인지 모름).
	var border := Line2D.new()
	border.points = PackedVector2Array([
		Vector2(-30.0, -100.0), Vector2(30.0, -100.0), Vector2(30.0, vbot), Vector2(-30.0, vbot),
	])
	border.closed = true
	border.width = 2.0
	border.default_color = Color(1.0, 0.9, 0.45, 0.85)
	vis.add_child(border)
	# "출구" 라벨 + 점멸 — 글자로 명시(시선 유도).
	var exit_lbl := Label.new()
	exit_lbl.text = "▼ 출구"
	exit_lbl.add_theme_font_size_override("font_size", 20)
	exit_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
	exit_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.85))
	exit_lbl.add_theme_constant_override("outline_size", 5)
	exit_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	exit_lbl.position = Vector2(-60.0, -150.0)
	exit_lbl.size = Vector2(120.0, 26.0)
	exit_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vis.add_child(exit_lbl)
	var pulse := exit_lbl.create_tween()
	pulse.set_loops()
	pulse.tween_property(exit_lbl, "modulate:a", 0.55, 0.8)
	pulse.tween_property(exit_lbl, "modulate:a", 1.0, 0.8)
	goal.body_entered.connect(_on_goal_reached)

func _on_goal_reached(body: Node) -> void:
	if goal_reached:
		return
	if not (body is CharacterBody2D and body == player):
		return
	# 도전 방: 실패 상태에선 골 도달해도 보너스 없음 (이미 fail 분기로 처리됨)
	if challenge_active and not challenge_failed:
		GameState.add_xp(challenge_xp_on_clear, false)
		_show_veil_subtitle(VeilDialogue.banded("도전 완수 확인. 교신도 없이 해내셨습니다.", "혼자 해냈네요, 요원."), 2.5)
	goal_reached = true
	GameState.profile_stage_end(_profile_alive_enemies())
	# 연습장 · 출구 도달 = 세계 정지(설정 조작 중 수위·열차 등 해저드에 죽는 것 방지,
	# 사용자 2026-08-17). 패널(PROCESS_MODE_ALWAYS)은 계속 조작 가능 · F1 여닫기나 패널의
	# 맵/스테이지 변경(reload가 paused 해제)으로 재개.
	if GameState.playground_active:
		get_tree().paused = true
		var fl := CanvasLayer.new()
		fl.layer = 32
		fl.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(fl)
		var lbl := Label.new()
		lbl.text = "연습장 · 출구 도달 · 세계 정지 (F1 패널로 계속)"
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.5))
		lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		lbl.add_theme_constant_override("outline_size", 4)
		lbl.set_anchors_preset(Control.PRESET_CENTER_TOP)
		lbl.position = Vector2(-220.0, 120.0)
		lbl.size = Vector2(440.0, 30.0)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.add_child(lbl)
		return
	# 방 체인 · 마지막 방이 아니면 스테이지 클리어가 아니라 다음 방으로 문 전환.
	if int(_map_data.get("segment_count", 1)) > int(_map_data.get("segment_index", 0)) + 1:
		_begin_segment_transition()
		return
	_trigger_stage_clear()

# 무인 화물 열차(TrainHazard) · MapData "train_hazard" 키. 벽감(cover_niches) 값을 세이프존으로 공유.
func _build_train_hazard() -> void:
	var cfg: Dictionary = _map_data.get("train_hazard", {})
	if cfg.is_empty():
		return
	var th := TrainHazard.new()
	add_child(th)
	var niche_xs: Array = _map_data.get("cover_niches", [])
	th.setup(cfg, GROUND_Y, STAGE_LENGTH, niche_xs, float(_map_data.get("niche_half", 90.0)))

# 수위 변화(WaterLevel) · MapData "water_level" 키. 하수도 시그니처(map_identity_rework §5).
func _build_water_level() -> void:
	var cfg: Dictionary = _map_data.get("water_level", {})
	if cfg.is_empty():
		return
	var wl := WaterLevel.new()
	add_child(wl)
	wl.setup(cfg, _world_size.x, _world_size.y, GROUND_Y)

# 탐조등(Searchlight) · MapData "searchlights" 키. 감시탑 시그니처 · 경보 = 경비 증원
# (2026-08-17 사용자 확정 ⓑ · 즉시 피해 아님). 증원은 인간 경비만(막1 계약).
var _searchlight_reinforced: int = 0
var _searchlight_line_shown: bool = false

func _build_searchlights() -> void:
	for entry in _map_data.get("searchlights", []):
		var sl := Searchlight.new()
		add_child(sl)
		sl.setup(entry)
		sl.alerted.connect(_on_searchlight_alert)

func _on_searchlight_alert(ppos: Vector2) -> void:
	SfxPlayer.play("siren_flash", -8.0)
	if not _searchlight_line_shown:
		_searchlight_line_shown = true
		# "감시등" = 감시탑 탐조등·순찰로 경계등의 상위 일상어(맵 공용 콜아웃).
		# 위압감 재작업(사용자 2026-08-17 "파밍용 졸개라 오히려 좋아") · 진압 경비 = 무보상 고지.
		_show_veil_subtitle(VeilDialogue.banded("감시등 노출. 진압 경비가 붙습니다. 잡아도 남는 게 없으니, 빛부터 피하십시오.", "감시등에 걸렸어요. 진압 경비가 붙어요. 잡아도 남는 건 없으니, 빛부터 피해요."), 3.8)
	if _searchlight_reinforced >= 2:
		return
	_searchlight_reinforced += 1
	# 증원 지점 · 플레이어보다 살짝 위의 넓은 발판(내려오며 압박 = 등반 저지 문법).
	var best := Vector2.ZERO
	var best_score: float = 1e12
	for entry in _map_data.get("platforms", []):
		var d: Dictionary = entry
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		if float(d.get("w", 0.0)) < 200.0:
			continue
		var score: float = absf(p.y - (ppos.y - 140.0)) + absf(p.x - ppos.x) * 0.35
		if score < best_score:
			best_score = score
			best = p
	if best == Vector2.ZERO:
		return
	var spawn_pos := Vector2(best.x, best.y - 30.0)
	var tel := _WaveSpawnTelegraph.new()
	tel.lifetime = 0.7
	tel.position = spawn_pos
	add_child(tel)
	get_tree().create_timer(0.7, false).timeout.connect(_searchlight_do_spawn.bind(spawn_pos))

func _searchlight_do_spawn(pos: Vector2) -> void:
	if goal_reached or not is_inside_tree():
		return
	# 진압 경비 = 추격 방패병 + 무보상(점수·XP 0) · 정면 사격이 안 통하는 게 쫓아오고,
	# 잡아도 얻는 게 없어 "들키면 순손해"를 몸으로 학습(사용자 2026-08-17 위압감 재작업).
	# 막1 "인간 경비만" 계약 준수(방패병 = 인간 팔레트).
	var e := _spawn_enemy(4, pos, -1, -1, false, true)
	e.set("hunt", true)
	_enemies_remaining += 1

# 돌풍(WindGust) · MapData "wind" 키. 옥상 시그니처 · 표류 보정형(2026-08-17 사용자 확정).
func _build_wind() -> void:
	var cfg: Dictionary = _map_data.get("wind", {})
	if cfg.is_empty():
		return
	var wg := WindGust.new()
	add_child(wg)
	wg.setup(cfg, _world_size.x, _world_size.y)

# 감전 아크(ElectricArc) · MapData "arc_zones" 키. 변전소 시그니처(확산 4호).
func _build_arc_zones() -> void:
	for entry in _map_data.get("arc_zones", []):
		var d: Dictionary = entry
		var arc := ElectricArc.new()
		add_child(arc)
		arc.setup(float(d.get("x1", 0.0)), float(d.get("x2", 100.0)), GROUND_Y,
			float(d.get("phase", 0.0)), int(d.get("dmg", 1)))

# 낙하 잔해(FallingDebris) · MapData "debris_zones" 키. 철거구역 시그니처(확산 5호).
# 발판 예고(2026-08-20)는 맵 platforms에서 자동 파생 — 데이터 추가 없이 모든 잔해 맵에 적용.
func _build_debris_zones() -> void:
	var plats: Array = _debris_mark_platforms()
	for entry in _map_data.get("debris_zones", []):
		var fd := FallingDebris.new()
		add_child(fd)
		fd.setup(entry, GROUND_Y, plats)

# 맵 platforms → FallingDebris 발판 예고 목록 [{x_min, x_max, y}].
func _debris_mark_platforms() -> Array:
	var out: Array = []
	for p_entry in _map_data.get("platforms", []):
		var pd: Dictionary = p_entry
		var pp: Vector2 = pd.get("pos", Vector2.ZERO)
		var pw: float = float(pd.get("w", 0.0))
		out.append({"x_min": pp.x - pw * 0.5, "x_max": pp.x + pw * 0.5, "y": pp.y})
	return out

# 컨베이어(ConveyorBelt) · MapData "conveyors" 키. 물류 창고 시그니처(확산 6호).
func _build_conveyors() -> void:
	for entry in _map_data.get("conveyors", []):
		var cb := ConveyorBelt.new()
		add_child(cb)
		cb.setup(entry, GROUND_Y)

# 차단 셔터(CycleShutter) · MapData "shutters" 키. 지하 주차장 시그니처(확산 7호).
func _build_shutters() -> void:
	for entry in _map_data.get("shutters", []):
		var sh := CycleShutter.new()
		add_child(sh)
		sh.setup(entry, GROUND_Y)

# 응축수 낙수(CondensateDrip) · MapData "drips" 키. 응축기 시그니처(확산 8호 · 증기 교체).
# 착지면 = 낙수점 아래 첫 표면. 발판이 낙수점 x를 덮으면 그 발판 위에서 튀고, 발판 아래는
# 비 그늘(안전)이 된다 — 물이 발판을 뚫고 지나가지 않는다(사용자 2026-08-22 지적).
func _build_drips() -> void:
	for entry in _map_data.get("drips", []):
		var d: Dictionary = entry
		var dx: float = float(d.get("x", 0.0))
		var src: float = float(d.get("src_y", 210.0))
		var land: float = GROUND_Y
		for pf in _map_data.get("platforms", []):
			var p: Dictionary = pf
			var pos: Vector2 = p.get("pos", Vector2.ZERO)
			var half: float = float(p.get("w", 220.0)) * 0.5
			if dx >= pos.x - half and dx <= pos.x + half and pos.y > src and pos.y < land:
				land = pos.y
		var dp := CondensateDrip.new()
		add_child(dp)
		dp.setup(d, land)

# 방류 사이클(DischargeJet) · MapData "discharge_jets" 키. 펌프장 시그니처(2026-08-22) —
# "물을 퍼내는 시설"의 기믹 실물. 수평 물줄기라 회피 = 발판 위(펌프장 거치대의 존재 이유).
func _build_discharge_jets() -> void:
	for entry in _map_data.get("discharge_jets", []):
		var d: Dictionary = entry
		var dj := DischargeJet.new()
		add_child(dj)
		dj.setup(d, GROUND_Y)

# 방 체인 전환(map_identity_rework §2) · RouteMap/Briefing 없이 짧은 문 전환으로 다음 방 로드.
# XP·HP·성장은 GameState 소유라 유지되고, 스테이지 타이머는 record_route_choice 기준이라 체인
# 합산이 자동이다([RUN] 로그·정산도 한 스테이지로 잡힘). 클리어 챔·발광·토스트·on_stage_clear는
# 마지막 방에서만 · 중간 방은 "지나간다"로 읽혀야 한다. 사망은 register_death가 세그먼트를
# 0으로 되돌려 체인 첫 방부터 재개.
func _begin_segment_transition() -> void:
	GameState.restrict_combat_input = true
	# 전환 연출 중 잔여 위협 무력화 · 클리어 시퀀스와 같은 함정(known_issues 2026-08-16) 예방.
	if _chase_hazard != null and is_instance_valid(_chase_hazard):
		_chase_hazard.halt()
	if player != null and is_instance_valid(player):
		player.set("clear_protect", true)
	# 처치 드롭 회수 · 클리어 시퀀스와 동일한 자연 흡수 + 전환 직전 낙오분 수집(placed 제외).
	if player != null and is_instance_valid(player):
		for orb in get_tree().get_nodes_in_group("exp_orb"):
			if orb is Node2D and not orb.is_queued_for_deletion() and not (orb as Node2D).get("placed"):
				(orb as Node2D).set("spawn_anim_t", 1.0)
				(orb as Node2D).set("attract_range", 999999.0)
	SfxPlayer.play("hatch_open")
	_do_clear_fade(0.55)
	await get_tree().create_timer(0.6).timeout
	for orb in get_tree().get_nodes_in_group("exp_orb"):
		if orb is Node2D and not orb.is_queued_for_deletion() and not (orb as Node2D).get("placed"):
			(orb as Node2D).call("_collect")
	# 중간 방에서 레벨업 오브를 먹었을 수 있다 · 오버레이 정리 전 전환 금지(빈 화면 freeze 함정).
	while pending_levelup:
		await get_tree().process_frame
	GameState.note_segment_split()   # 방별 타이머(상세 런 로그)
	GameState.current_segment += 1
	# 봇 계측(BotRunner) 중엔 씬 전환이 러너 씬을 파괴한다 · 러너가 다음 방을 직접 띄운다.
	if GameState.bot_headless:
		return
	SceneRouter.go(get_tree(), SceneRouter.STAGE)

func _setup_arena_clear_tracking() -> void:
	# ARENA — _spawn_enemies가 끝난 시점이라 group에 등록된 적 수가 곧 카운트.
	_enemies_remaining = get_tree().get_nodes_in_group("enemy").size()
	if _enemies_remaining <= 0:
		# 적 없는 ARENA (이상 케이스) — 즉시 클리어
		call_deferred("_on_arena_cleared")

# 플레이 습관 프로필 · 클리어 시점 생존 적 수(전멸 성향 hunt_ratio 분모).
func _profile_alive_enemies() -> int:
	var n: int = 0
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e is Node2D and not bool((e as Node2D).get("dead")) \
				and not bool((e as Node2D).get("harmless")):
			n += 1
	return n

func _on_arena_cleared() -> void:
	if goal_reached:
		return
	goal_reached = true
	GameState.profile_stage_end(_profile_alive_enemies())
	# 방어 맵 — 코어를 "확보" 상태로 굳혀 잔여 드레인/경보 정지.
	if _defense_core != null and is_instance_valid(_defense_core):
		_defense_core.set_secured()
	# ARENA 클리어 보너스 XP — MapData arena_clear_xp
	var data: Dictionary = MapData.get_layout(GameState.current_route_id)
	var bonus_xp: int = int(data.get("arena_clear_xp", 0))
	if bonus_xp > 0:
		GameState.add_xp(bonus_xp, false)
	_trigger_stage_clear()

# 클리어 시 캐릭터 백색 발광 → 떠오르며 소멸 + 확장 링(출구로 빠져나가는 임팩트).
func _play_clear_player_fx() -> void:
	if player == null or not is_instance_valid(player):
		return
	var ppos: Vector2 = player.global_position
	# 캐릭터 과노출 백색 발광 → 알파 소멸
	var tw := player.create_tween()
	tw.tween_property(player, "modulate", Color(2.6, 2.6, 3.0, 1.0), 0.15)
	tw.tween_property(player, "modulate:a", 0.0, 0.7)
	# 확장 백색 링
	var ring := Line2D.new()
	var pts := PackedVector2Array()
	for i in 25:
		var a: float = TAU * float(i) / 24.0
		pts.append(Vector2(cos(a), sin(a)) * 40.0)
	ring.points = pts
	ring.closed = true
	ring.width = 4.0
	ring.default_color = Color(0.9, 0.95, 1.0, 0.9)
	ring.global_position = ppos
	ring.z_index = 30
	add_child(ring)
	var rtw := ring.create_tween()
	rtw.set_parallel(true)
	rtw.tween_property(ring, "scale", Vector2(3.6, 3.6), 0.55)
	rtw.tween_property(ring, "modulate:a", 0.0, 0.55)
	rtw.chain().tween_callback(ring.queue_free)

# 평화주의 이스터에그 판정 — 통과형(POSITION) 맵에 적이 있었는데 한 발도 안 쐈고, 런당 첫 인정일 때.
# ENEMY_CLEAR/보스는 안 쏘고 클리어가 불가/무의미해 제외. 서사용 맵(탈출로·??? 방)도 제외.
func _check_pacifist_clear() -> bool:
	if GameState.pacifist_line_shown or GameState.playground_active:
		return false
	if _goal_type != "POSITION" or not _had_enemies or challenge_active:
		return false
	if GameState.current_route_id == "route_hidden" or GameState.current_route_id.begins_with("route_escape"):
		return false
	if player == null or not is_instance_valid(player):
		return false
	return int(player.get("shots_fired")) == 0

func _trigger_stage_clear() -> void:
	# 추격 벽 정지: 클리어 연출(입력 락 + 페이드 + 엔딩 멘트) 동안 게임이 pause되지 않아
	# 벽이 계속 전진해 연출 중 사망 판정이 떴다(사용자 2026-08-16, 붕괴 회랑 엔딩 중 사망).
	if _chase_hazard != null and is_instance_valid(_chase_hazard):
		_chase_hazard.halt()
	if GameState.playground_active:
		# 연습장에선 자동 진행 안 함 — 패널에서 직접 다음 stage/route 선택
		_show_playground_clear_msg()
		return
	# 클리어 시 즉시 씬 전환 대신 짧은 연출 — XP orb 자동 흡수 + 페이드.
	# 보스/도전방에선 VEIL 대사도 들을 수 있게 더 긴 딜레이.
	_begin_clear_sequence()

# 클리어 시퀀스 — 입력 락 + XP orb 흡수 + 페이드 + delay 후 다음 단계.
# 사용자 피드백: "도전방에서 마지막 적 처치 시 XP 못 먹고 바로 맵 선택으로"
# 보스/ARENA — 2.6s, 일반 골 — 1.0s.
func _begin_clear_sequence() -> void:
	# 도전방은 별도 챔, 일반 stage clear는 stage_clear_chime.
	if challenge_active and not challenge_failed:
		SfxPlayer.play("challenge_clear")
	elif GameState.current_route_id == "route_lab":
		pass   # §7 SENTINEL reveal — 승리 챔 억제(한 박자 정적). 보스 죽는 소리만 여운으로 남긴다.
	else:
		SfxPlayer.play("stage_clear_chime")
	GameState.restrict_combat_input = true
	# 클리어 연출 보호: 연출 동안 pause가 없어 잔여 위협(추격 벽·탄·빔·증기)이 플레이어를
	# 죽일 수 있다(사용자 2026-08-16, 붕괴 회랑 엔딩 멘트 중 사망). 씬 전환까지 피격 무시.
	if player != null and is_instance_valid(player):
		player.set("clear_protect", true)
	# 클리어 시각 임팩트 — 일반 골(출구 도달) 클리어에서 캐릭터가 백색 발광하며 소멸(피드백: 클리어
	# 피드백이 소리뿐이라 약함). 보스(lab, 회수 연출)·ARENA는 후속 비트가 있어 제외.
	var _is_arena_fx: bool = challenge_active or _goal_type == "ENEMY_CLEAR"
	if not _is_arena_fx and GameState.current_route_id != "route_lab":
		_play_clear_player_fx()
	# 남은 "처치 드롭" XP orb 회수 — 마지막 처치가 곧 클리어인 맵(ENEMY_CLEAR)에서 그 드롭이
	# 씬 전환으로 버려지지 않게. 종전의 "곁 순간이동 + 금빛 궤적 라인"은 시체와 캐릭터를 잇는
	# 노란 선으로 읽히는 노이즈였다(2026-08-15 지적 2회 → 라인 폐지). 대신 **자연 흡수**:
	# 흡인 반경을 전역으로 풀어 오브가 스스로 날아와 먹힌다(가속 흡인, 최대 1500/s). 클리어 딜레이
	# 안에 못 닿을 원거리 미수집 오브만 소리 없이 곁으로 옮긴다. 배치형(placed)은 종전대로 제외
	# (게이트 오브 등 유인 설계 보호, 2026-08-11).
	if player != null and is_instance_valid(player):
		for orb in get_tree().get_nodes_in_group("exp_orb"):
			if not (orb is Node2D) or orb.is_queued_for_deletion():
				continue
			var o := orb as Node2D
			if o.get("placed"):
				continue
			o.set("spawn_anim_t", 1.0)
			if o.global_position.distance_to(player.global_position) > 380.0:
				o.global_position = player.global_position + Vector2(randf_range(-60.0, 60.0), -90.0)
			o.set("attract_range", 999999.0)
	var is_arena: bool = challenge_active or _goal_type == "ENEMY_CLEAR"
	var delay: float = 2.6 if is_arena else 1.0
	# 이스터에그(평화주의) — 적이 있던 통과형 맵을 한 발도 안 쏘고 클리어. 런당 1회 VEIL 인정.
	if _check_pacifist_clear():
		GameState.pacifist_line_shown = true
		delay = maxf(delay, 3.2)   # 대사 읽을 여유
		_show_veil_subtitle(VeilDialogue.banded("한 발도 쏘지 않으셨군요. 그런 답도 있습니다.", "한 발도 안 쏘고 지나왔네요. 그것도 하나의 답이겠죠."), 3.0)
	# 회수 문서 연출(ArcturusDocumentOverlay, layer 25)이 클리어 후 화면을 덮는 맵은 클리어 페이드
	# (layer 38)가 문서를 가린다 → 페이드 생략(문서 자체 배경으로 어두워짐). ④ 이후 종이 문서는
	# 스토리 lab 경로에만 남고, core_recovery는 터널 씬으로 전환이라 페이드가 자연스러운 이음새
	# (터널이 검은 화면에서 페이드 인).
	var doc_next: bool = GameState.current_route_id == "route_lab"
	if not doc_next:
		_do_clear_fade(delay)
	await get_tree().create_timer(delay).timeout
	# 흡수 낙오분 안전망 — 딜레이 안에 못 날아온 처치 드롭은 전환 직전 즉시 수집(XP 유실 방지).
	for orb in get_tree().get_nodes_in_group("exp_orb"):
		if orb is Node2D and not orb.is_queued_for_deletion() and not (orb as Node2D).get("placed"):
			(orb as Node2D).call("_collect")
	# 보스 처치 직후 보스가 떨군 orb로 mid-stage 레벨업이 떠있을 수 있다. 그 사이에
	# _on_arena_cleared(deferred)가 진행되어 transition이 먼저 일어나면 LevelUpOverlay
	# 가 사라진 채 paused만 남아 다음 씬(Briefing)이 freeze된다(사용자 보고: 스토리
	# 모드 보스 후 stage 5/5만 뜨는 빈 화면). 따라서 mid-stage 레벨업이 정리될 때까지
	# 여기서 대기.
	while pending_levelup:
		await get_tree().process_frame
	# §7 SENTINEL reveal — 라이벌 첫 발화 시퀀스가 끝나야 회수(recovery/처리선택)로 넘어간다.
	# (lab 전용. 다른 맵은 _sentinel_reveal_done을 안 봐 영향 없음.) guard = 소프트락 방지 상한.
	if GameState.current_route_id == "route_lab":
		var reveal_guard: float = 0.0
		while not _sentinel_reveal_done and reveal_guard < 14.0:
			await get_tree().process_frame
			# 컷씬(StoryDialogue)이 떠 있는 동안은 상한을 세지 않는다 — 천천히 읽는 플레이어에게
			# 14s가 차서 회수 단계가 컷씬 밑으로 진행되는 사고 방지(process_frame은 pause 무시).
			if StoryDialogue.active == null:
				reveal_guard += get_process_delta_time()
	GameState.restrict_combat_input = false
	var leveled: bool = GameState.on_stage_clear()
	# 클리어 가산 토스트 — 보상은 눈에 보여야 보상이다(점수만 오르면 침묵 보상).
	# 도전 완수가 단일 기록보다 우선(도전 클리어는 대개 무사망이라 둘이 겹침 — 한 장만).
	if player != null and is_instance_valid(player):
		if GameState.last_clear_challenge:
			_show_clear_toast(player.global_position + Vector2(0.0, -64.0), "도전 완수 · 보상 가산")
		elif GameState.last_clear_flawless:
			_show_clear_toast(player.global_position + Vector2(0.0, -64.0), "단일 기록 · 점수 보너스")
		elif GameState.last_clear_reward_note != "":
			# 종류 보상(기록·정찰)은 지급 순간이 안 보이면 없는 것과 같다 — 위 두 장이 없을 때 표시.
			_show_clear_toast(player.global_position + Vector2(0.0, -64.0), GameState.last_clear_reward_note)
		# 수행 보너스(2026-08-23 사용자) — 무피격 / 전원 처치는 위 카드와 별개로 위에 쌓인다.
		var perf_y: float = -100.0
		if GameState.last_clear_nohit:
			_show_clear_toast(player.global_position + Vector2(0.0, perf_y), "무피격 통과 +150")
			perf_y -= 36.0
		if GameState.last_clear_allkill:
			_show_clear_toast(player.global_position + Vector2(0.0, perf_y), "경비 전원 처치 +150")
		# VEIL 수행 멘트 — 매 스테이지 도배 방지(3스테이지 간격). 클리어 직후 = 조용한 순간이라
		# 자막 문법 유지(컷씬 아님 · 짧은 보고 1줄).
		if (GameState.last_clear_nohit or GameState.last_clear_allkill) \
				and GameState.current_stage - GameState.bonus_line_last_stage >= 3:
			GameState.bonus_line_last_stage = GameState.current_stage
			if GameState.last_clear_nohit:
				# EN: "Zero hits taken. Clean pass on this section."
				_show_veil_subtitle(VeilDialogue.banded("피격 0. 이 구간, 깨끗하게 지나셨습니다.", "피격 0이에요. 이 구간, 깨끗하게 지나셨네요."), 3.0)
			else:
				# EN: "All area guards confirmed down. Nothing behind us now."
				_show_veil_subtitle(VeilDialogue.banded("구역 경비, 전원 처치 확인했습니다. 이제 뒤는 조용합니다.", "구역 경비까지 전부 정리하셨네요. 이제 뒤는 조용해요."), 3.0)
	# 보스(route_lab) 또는 최종 스테이지 클리어 후엔 위협 없는 마무리라 스킬 선택이 무의미 —
	# 카드를 건너뛰고 보스 처치 대사/엔딩(서사 비트)이 보상을 대신한다(사용자 피드백 "1+3").
	var skip_card: bool = GameState.current_route_id == "route_lab" or GameState.current_route_id == "route_core_recovery" or GameState.is_final_stage_done()
	if leveled and not skip_card:
		pending_levelup = true
		get_tree().paused = true
		var advice: Dictionary = VeilDialogue.get_levelup_advice(GameState.skills, GameState.current_route_tags, GameState.current_route_id)
		levelup_overlay = LevelUpOverlay.show(self, advice, _on_clear_levelup_picked)
	else:
		_transition_after_clear()

# 화면 전체 검은색 페이드 — duration의 후반 60% 시간 동안 0 → 0.85로 진행.
# 다음 씬 전환 전에 정리되지 않으니 자연스럽게 검은 화면 → BRIEFING/STAGE 전환.
func _do_clear_fade(duration: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 38
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(0, 0, 0, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_interval(duration * 0.4)
	tw.tween_property(rect, "color:a", 0.85, duration * 0.6)

func _on_clear_levelup_picked(_picked_id: String) -> void:
	levelup_overlay = null
	pending_levelup = false
	get_tree().paused = false
	_transition_after_clear()

func _transition_after_clear() -> void:
	# 5막 엔드게임(§7.1 — 2026-08-12 ④ 배선): 14-1 보스 클리어는 14-2 코어 대면 터널로 직결
	# (맵 선택 없음). 회수 리드아웃·고백·처리 선택은 터널의 목격 비트로 이주(CoreTunnel).
	# 스토리 모드는 5스테이지 골격이라 예전대로 보스(lab) 직후 종이 문서 경로 유지.
	var is_recovery_stage: bool = GameState.current_route_id == "route_core_recovery"
	var story_boss: bool = GameState.story_mode and GameState.current_route_id == "route_lab"
	if story_boss:
		_play_lab_recovery_and_disposal()
		return
	if is_recovery_stage:
		GameState.core_tunnel_live = true
		SceneRouter.go(get_tree(), SceneRouter.CORE_TUNNEL)
		return
	# 메인 SENTINEL(route_lab, 막3): §7 reveal은 처치 시 재생됨 → 처리선택 없이 다음 막(추적)으로 계속.
	if GameState.is_final_stage_done():
		# 최종 스테이지 = 탈출(escape, 양 모드 공통). 엔딩별 에필로그 1챕터를 거쳐 엔딩으로 잇는다.
		_play_final_epilogue()
	else:
		get_tree().change_scene_to_file.call_deferred(SceneRouter.BRIEFING)

# 막3 핵심부(lab) 클라이맥스 — 보스 처치 후: 회수한 드라이브를 문서로 reveal(ArcturusDocumentOverlay
# 재사용) → 처리 선택(DisposalChoiceOverlay 4지선다) → 선택 저장 후 다음 스테이지(탈출 s8)로.
# 대사 문구는 플레이스홀더(사용자 검토 대기). truth_seen(???에서 진실을 이미 본 회차)이면 reveal을
# "이미 안다"는 톤으로 변형(엔딩은 truth_seen이면 처리·신뢰 무관 '진실' 엔딩으로 수렴).
func _play_lab_recovery_and_disposal() -> void:
	GameState.restrict_combat_input = true
	var doc := ArcturusDocumentOverlay.new()
	add_child(doc)
	doc.finished.connect(_on_lab_recovery_doc_done)
	doc.show_doc(_lab_recovery_doc_lines())

func _on_lab_recovery_doc_done() -> void:
	# 문서(기록)가 닫힌 뒤 VEIL 고백 자막 비트 → 처리 선택. 문서 안에 해설·대사를 섞지 않는 구조
	# (사용자 지적 2026-08-10: "문서면 문서답게, 말은 컷씬처럼").
	_play_recovery_confession()

# 회수 문서 직후 VEIL의 고백 — 문서에서 빠진 해설("회수 대상 = VEIL")을 VEIL 자신의 입으로.
# 대사 단일 소스 = VeilDialogue.get_recovery_confession(14-2 터널과 공유). 끝나면 처리 선택.
func _play_recovery_confession() -> void:
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	for ln_raw in VeilDialogue.get_recovery_confession(GameState.truth_seen):
		var ln: Dictionary = ln_raw
		var dur: float = float(ln.get("dur", 3.8))
		_show_veil_subtitle(str(ln.get("text", "")), dur)
		await get_tree().create_timer(dur + 0.6).timeout
		if not is_inside_tree():
			return
	DisposalChoiceOverlay.show(self, _on_disposal_picked)

func _on_disposal_picked(choice_id: String) -> void:
	GameState.disposal_choice = choice_id
	# SceneRouter.go가 paused=false 보장 후 전환 — 탈출(s8) 브리핑으로.
	SceneRouter.go(get_tree(), SceneRouter.BRIEFING)

# 회수 드라이브 reveal 문서 — 단일 소스 = VeilDialogue.get_recovery_doc_lines(14-2 터널 리드아웃과
# 공유). 문서는 기록체만, 해설·대사는 고백 비트가 맡는다(사용자 지적 2026-08-10 구조 유지).
func _lab_recovery_doc_lines() -> Array:
	return VeilDialogue.get_recovery_doc_lines()

# 탈출(escape) 클리어 → 엔딩 사이의 에필로그 1챕터. 검은 화면 위 VEIL의 "빠져나온 직후" 한 호흡.
# 엔딩별로 내용이 다르다(처리 결과 반영) — EndingResolver.get_epilogue_lines. ENDING 씬과 동일한 입력
# (disposal/truth/followed/rec)으로 같은 id를 산출하므로 에필로그↔엔딩 본문이 일관된다. (문구 플레이스홀더.)
func _play_final_epilogue() -> void:
	GameState.restrict_combat_input = true
	var ep_layer := CanvasLayer.new()
	ep_layer.layer = 40
	add_child(ep_layer)
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.03, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.modulate.a = 0.0
	ep_layer.add_child(bg)
	var label := Label.new()
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", 4)
	label.modulate.a = 0.0
	ep_layer.add_child(label)
	# 검은 화면으로 가라앉히기
	var ft := bg.create_tween()
	ft.tween_property(bg, "modulate:a", 1.0, 1.0)
	await ft.finished
	await get_tree().create_timer(0.6).timeout
	# 엔딩별 에필로그 — ENDING 씬과 같은 입력으로 resolve해 동일 id의 에필로그를 고른다.
	var eid: String = EndingResolver.resolve(GameState.disposal_choice, GameState.truth_seen, GameState.followed_count, GameState.rec_count)
	var lines: Array = EndingResolver.get_epilogue_lines(eid)
	for ln in lines:
		label.text = str(ln)
		var lt := label.create_tween()
		lt.tween_property(label, "modulate:a", 1.0, 0.6)
		lt.tween_interval(1.9)
		lt.tween_property(label, "modulate:a", 0.0, 0.7)
		await lt.finished
		await get_tree().create_timer(0.35).timeout
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file.call_deferred(SceneRouter.ENDING)

func _show_playground_clear_msg() -> void:
	# PlaygroundOverlay(layer 30) 위로 띄우기 위해 별도 CanvasLayer 사용
	var msg_layer := CanvasLayer.new()
	msg_layer.layer = 35
	add_child(msg_layer)
	var l := Label.new()
	l.text = "[연습장] 골 도달. 패널에서 다음 설정을 선택하세요"
	l.add_theme_font_size_override("font_size", 18)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.30))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.position = Vector2(140, 130)
	l.size = Vector2(1000, 28)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg_layer.add_child(l)

func _on_player_died() -> void:
	GameState.register_death()
	get_tree().change_scene_to_file.call_deferred(SceneRouter.DEATH)

# 코어 함락 = 방어 실패. 플레이어 사망과 동일 경로(재시도)로 처리한다.
# breached는 DefenseCore._physics_process 안에서 emit되므로 씬 전환은 call_deferred로 한 프레임 미룬다.
func _on_core_breached() -> void:
	if goal_reached:
		return
	GameState.register_death()
	# 짧은 붉은 화면 플래시 — 즉시 전환하면 "함락"이 안 읽혀서.
	_screen_flash(Color(1.0, 0.2, 0.24, 0.7), 0.08, 0.5)
	SfxPlayer.play("challenge_fail")
	get_tree().change_scene_to_file.call_deferred(SceneRouter.DEATH)

func _on_player_damaged() -> void:
	# 도전 방: 1 hit fail — 즉시 stage 스킵 처리.
	if challenge_active and not challenge_failed and not goal_reached:
		_challenge_fail("피격")
		return
	# 피격 — 화면 가장자리 짧은 붉은 플래시 + 가벼운 카메라 흔들림
	_screen_flash(Color(1.0, 0.18, 0.22, 0.55), 0.06, 0.32)
	_camera_shake(6.0, 0.18)

func _challenge_fail(_reason: String) -> void:
	if challenge_failed:
		return
	challenge_failed = true
	SfxPlayer.play("challenge_fail")
	# 잔여 데미지로 인한 사망 방지: HP 리필 + 긴 invuln (대기 중 죽으면 데스 씬으로 새버림).
	GameState.player_hp = GameState.player_max_hp
	if player != null and is_instance_valid(player):
		player.set("invuln", 5.0)
	# 안전 처리: paused 상태가 어떤 경로로든 set되어 있으면 풀어줘서 await timer가 진행되게.
	# restrict_combat_input도 명시 해제 — 다음 stage carry되어 입력 잠김 방지.
	get_tree().paused = false
	GameState.restrict_combat_input = false
	# VEIL 실패 대사 + 조용히 다음 stage로 (보상 0, 페널티 없음).
	_show_veil_subtitle(VeilDialogue.banded("괜찮습니다. 다음 구역으로 갑니다.", "괜찮아요. 다음 구역으로 가요."), 2.5)
	await get_tree().create_timer(2.8).timeout
	if goal_reached:
		return
	goal_reached = true
	# 보상/레벨업 없이 stage 카운트만 증가시킨 뒤 다음 씬으로.
	GameState.current_stage += 1
	GameState.player_hp = GameState.player_max_hp
	# transition 직전 한 번 더 안전 reset.
	get_tree().paused = false
	GameState.restrict_combat_input = false
	_transition_after_clear()

func _on_player_revived() -> void:
	# 부활 — 강한 흰 플래시 (전체 화면이 잠깐 밝아짐)
	_screen_flash(Color(1.0, 1.0, 1.15, 0.85), 0.05, 0.5)

func _screen_flash(col: Color, fade_in: float, fade_out: float) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 35
	add_child(layer)
	var rect := ColorRect.new()
	rect.color = Color(col.r, col.g, col.b, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", col.a, fade_in)
	tw.tween_property(rect, "color:a", 0.0, fade_out)
	tw.tween_callback(layer.queue_free)

func _camera_shake(magnitude: float, duration: float) -> void:
	if not GameState.camera_shake_enabled:
		return
	if camera == null or not is_instance_valid(camera):
		return
	var origin: Vector2 = camera.offset
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var elapsed: float = 0.0
	var steps: int = 6
	for i in steps:
		var t: float = float(i) / float(steps)
		var falloff: float = 1.0 - t
		var ox: float = rng.randf_range(-magnitude, magnitude) * falloff
		var oy: float = rng.randf_range(-magnitude, magnitude) * falloff
		camera.offset = origin + Vector2(ox, oy)
		await get_tree().create_timer(duration / float(steps)).timeout
		if not is_instance_valid(camera):
			return
	camera.offset = origin

var _traps_present: bool = false
var _trap_warned: bool = false
var _avoid_warned: bool = false

func _process(delta: float) -> void:
	_refresh_hud()
	_tick_boss(delta)
	_tick_challenge(delta)
	_tick_escape_transition(delta)
	_tick_trap_warning()
	_tick_avoid_warning()
	_tick_mid_gate(delta)
	_tick_p3_camp(delta)
	_tick_hide_zone()

# ─── 대피 칸 숨기 존(2026-08-22 사용자 안: "뒤로 숨는 공간" + 능동 입력) ───
# 칠해진 칸 x밴드 안이면 Player.hide_zone을 켠다 — ▼ 홀드로 숨기(판정·연출은 Player).
# 첫 진입 1회 티칭: 어느 칸에서든 조작을 모른 채 빔/열차를 맞는 일이 없게.
var _hide_niche_xs: Array = []
var _hide_niche_half: float = 90.0
var _hide_hint_shown: bool = false

func _tick_hide_zone() -> void:
	if _hide_niche_xs.is_empty() or player == null or not is_instance_valid(player):
		return
	var px: float = player.global_position.x
	var inz: bool = false
	for nx in _hide_niche_xs:
		if absf(px - float(nx)) <= _hide_niche_half:
			inz = true
			break
	player.set("hide_zone", inz)
	if inz and not _hide_hint_shown:
		_hide_hint_shown = true
		# EN: "That recess is deep enough to hide in. Hold Down inside the marked bay."
		_show_veil_subtitle("칠해진 칸 안쪽은 몸을 숨길 만큼 깊습니다. 칸 안에서 아래 키를 꾹 누르십시오.", 3.6)

# ─── P3 캠핑 감지(2026-08-20 사용자 "맨 위 발판에서 연사 홀드로 무피해 클리어") ───
# 판정 3차 개정(2026-08-21 사용자 "발판 하나에서 좌우 와리가리만 하면 유도탄이 영영 안 옴"):
#   1차 유클리드 130px → 제자리 점프 y 진폭이 리셋(구멍) → 2차 x만 130px → 130px 넘는 좌우
#   왕복이 매번 리셋(구멍). → 3차 = **체류 범위 창**: 최근 이동이 300px 폭(발판 하나+여유) 안에
#   머무는 동안 타이머가 계속 흐른다. 왕복·점프는 창 안 = 캠핑, 다른 데크로 실제 이동만 리셋.
# 발동 시 잠복 중에도 유도탄(FalseVeil.fire_suppression) · ~2.4s마다 반복 · 첫 발동 VEIL 1회.
const P3_CAMP_SPAN: float = 300.0
const P3_CAMP_TIME: float = 4.5
var _p3_min_x: float = 1e9
var _p3_max_x: float = -1e9
var _p3_camp_t: float = 0.0
var _p3_camp_line_shown: bool = false

func _tick_p3_camp(delta: float) -> void:
	if _rival_phase != 2 or _false_veil == null or not is_instance_valid(_false_veil):
		_p3_camp_t = 0.0
		_p3_min_x = 1e9
		_p3_max_x = -1e9
		return
	if player == null or not is_instance_valid(player):
		return
	var px: float = player.global_position.x
	_p3_min_x = minf(_p3_min_x, px)
	_p3_max_x = maxf(_p3_max_x, px)
	if _p3_max_x - _p3_min_x > P3_CAMP_SPAN:
		# 창을 벗어나는 실제 이동 — 현 위치부터 새 창.
		_p3_min_x = px
		_p3_max_x = px
		_p3_camp_t = 0.0
		return
	_p3_camp_t += delta
	if _p3_camp_t >= P3_CAMP_TIME:
		_p3_camp_t = P3_CAMP_TIME - 2.4
		_false_veil.call("fire_suppression", player.global_position + Vector2(0.0, -24.0))
		if not _p3_camp_line_shown:
			_p3_camp_line_shown = true
			_show_veil_subtitle("한자리에 오래 서 있으면 조준이 고정됩니다. 계속 움직이십시오.", 3.2)

# 자막창 흔들림은 완전 제거됨(2026-08-14 2차: 잠깐의 등장 떨림조차 "글씨를 읽을 수 없다" 반려).
# 통신 두절 톤은 14-1 후반의 대사 조기 끊김(_show_veil_subtitle duration 캡)이 담당한다.

# 발사 함정에 처음 가까워지면 VEIL이 "파괴 불가, 회피" 1회 안내(못 잡는 함정 명시).
func _tick_trap_warning() -> void:
	if not _traps_present or _trap_warned or player == null or not is_instance_valid(player):
		return
	for grp in ["bullet_trap", "laser_tripwire"]:
		for t in get_tree().get_nodes_in_group(grp):
			if t is Node2D and player.global_position.distance_to((t as Node2D).global_position) < 320.0:
				_trap_warned = true
				# 시야 붕괴(ACT3) 후엔 마커로 못 짚어주니 "잘 안 보인다"는 톤으로.
				if GameState.veil_degraded:
					_show_veil_subtitle("전방에 함정 신호. 확신이 없습니다. 발밑과 천장을 직접 살피십시오.", 3.4)
				else:
					# 런당 2회까지만 — 함정 맵마다 같은 멘트가 반복돼 지겹다는 피드백(2026-08-11).
					# 붕괴 경고는 상황성(그 맵의 시야 상태)이라 제한 없이 유지. 어투 = 전술 보고체.
					if GameState.trap_warn_count >= 2:
						return
					GameState.trap_warn_count += 1
					_show_veil_subtitle("저 포탑은 파괴할 수 없습니다. 발사 간격을 읽고 통과하십시오.", 3.2)
				return

# 측면 단독 둥지 저격수(회피 전용)에 처음 가까워지면 VEIL이 1회 안내 — "정면으론 못 잡으니
# 사선 피하거나 글라이드로 덮쳐라". 못 잡는 적 명시 + 글라이드-저격 상성 학습.
func _tick_avoid_warning() -> void:
	if _avoid_warned or player == null or not is_instance_valid(player):
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var en: Node2D = e as Node2D
		if not en.has_meta("avoid_only") or bool(en.get("dead")):
			continue
		if player.global_position.distance_to(en.global_position) < 430.0:
			_avoid_warned = true
			if GameState.veil_degraded:
				_show_veil_subtitle("저 위 저격수, 제 쪽에선 흐릿합니다. 조준선을 피하거나, 글라이드로 위에서 덮치십시오.", 3.6)
			else:
				_show_veil_subtitle("저 저격수는 정면으로 안 닿습니다. 조준선을 피해 가거나, 글라이드로 위에서 덮치십시오.", 3.6)
			return

# ─── 도전 방(블랙아웃 런) — world_layout §3.2 ───
# 30s 타이머 + 1 hit 실패 + 좁은 시야. 실패해도 stage는 그냥 스킵 (페널티 없음).
var challenge_active: bool = false      # 실제 도전 진행 중(타이머·블랙아웃·1hit fail 모두 적용)
var challenge_pending: bool = false      # 입구 발판 대기 중(맵은 깔렸으나 도전 미시작)
var challenge_time_remaining: float = 30.0
var challenge_failed: bool = false
var challenge_xp_on_clear: int = 5
var challenge_timer_label: Label = null
var challenge_dark_layer: CanvasLayer = null
var challenge_gate_door: StaticBody2D = null
var challenge_gate_visual: Node2D = null
var challenge_plate: PressurePlate = null
var challenge_curtain: Node2D = null   # 입구 너머 전체를 가리는 차폐막 (world-space)

func _setup_challenge_mode() -> void:
	if not bool(_map_data.get("challenge", false)):
		return
	# 즉시 활성화하지 않음 — 입구 발판을 밟아야 시작. 사용자: "도전이 그런 거라는 걸
	# 알려주기 위해 연출이 필요". 사이렌/암전/클리어 조건 안내가 시작과 함께 나오게.
	challenge_pending = true
	challenge_time_remaining = float(_map_data.get("challenge_time", 30.0))
	challenge_xp_on_clear = int(_map_data.get("challenge_xp_clear", 5))
	_build_challenge_gate()

# 도전 입구 — 통제선 느낌의 어두운 문 + 경고 라벨 + 발판. 문은 fade 전까지 충돌 차단.
# 플레이어가 발판에 발을 디디는 행동 자체가 "들어가겠다는 의사"가 됨.
func _build_challenge_gate() -> void:
	# 문 위치 — x=240 (플레이어 시작 140 우측). 문 너머는 입구 통로(첫 발판 680/첫 위협 760+)라
	# 들어서도 살펴볼 여유가 있다. 통로 구간엔 가시·적 없음.
	var gate_x: float = 240.0
	var gate_w: float = 50.0
	var gate_h: float = 720.0
	# 차폐막 — 도전방 내부 전체를 world-space로 가린다. 플랫폼/적/가시 모두 시각적으로
	# 묻혀서 입장 전에는 무엇이 있는지 알 수 없다. 발판 step 시 fade 후 free.
	# (사용자 요구: "들어가기 전에는 안이 어떻게 생겼는지, 뭐가 나올지 전혀 몰라야 해")
	challenge_curtain = Node2D.new()
	challenge_curtain.z_index = 9
	add_child(challenge_curtain)
	var curtain_x: float = gate_x + gate_w * 0.5  # 문 우측 경계부터 시작
	var curtain_w: float = STAGE_LENGTH - curtain_x + 200.0  # 끝 벽 너머까지 여유
	# 본체 — 짙은 보라-검정. 위협적 톤.
	var c_body := ColorRect.new()
	c_body.color = Color(0.04, 0.03, 0.06, 1.0)
	c_body.position = Vector2(curtain_x, -200.0)
	c_body.size = Vector2(curtain_w, 1200.0)
	challenge_curtain.add_child(c_body)
	# 수직 grain — 가는 선 패턴(입자 같은 정적). 50px 간격.
	var grain_count: int = int(curtain_w / 50.0)
	for i in grain_count:
		var line := ColorRect.new()
		line.color = Color(0.10, 0.08, 0.12, 0.55)
		line.position = Vector2(curtain_x + 5.0 + float(i) * 50.0, -200.0)
		line.size = Vector2(1.0, 1200.0)
		challenge_curtain.add_child(line)
	# 좌측 진한 비네트 — 문 쪽으로 더 어둡게.
	var fade_l := ColorRect.new()
	fade_l.color = Color(0, 0, 0, 0.65)
	fade_l.position = Vector2(curtain_x, -200.0)
	fade_l.size = Vector2(80.0, 1200.0)
	challenge_curtain.add_child(fade_l)
	# 분류 미상 라벨 — 차폐막 위 큰 글자. 화면 가운데쯤(스크롤되어 보임)에 위치.
	var unknown := Label.new()
	unknown.text = "[ DARK ZONE ]\n\n분류 미상"
	unknown.add_theme_font_size_override("font_size", 24)
	unknown.add_theme_color_override("font_color", Color(0.65, 0.30, 0.32, 0.85))
	unknown.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	unknown.add_theme_constant_override("outline_size", 3)
	unknown.position = Vector2(curtain_x + 220.0, 280.0)
	unknown.size = Vector2(380.0, 140.0)
	unknown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	challenge_curtain.add_child(unknown)
	# 시각 — Node2D wrapper에 패널 + 사선 줄무늬 + 경고 라벨.
	challenge_gate_visual = Node2D.new()
	# 게이트는 차폐막 위에 그려져야 함 (커튼 z=9, 게이트 z>=10).
	add_child(challenge_gate_visual)
	var panel := ColorRect.new()
	panel.color = Color(0.10, 0.05, 0.06, 0.95)
	panel.position = Vector2(gate_x - gate_w * 0.5, 0.0)
	panel.size = Vector2(gate_w, gate_h)
	panel.z_index = 10
	challenge_gate_visual.add_child(panel)
	# 사선 줄무늬 (폴리스 라인) — 빨강/노랑 사선 줄 4개
	for i in 5:
		var stripe := Polygon2D.new()
		stripe.color = Color(0.95, 0.78, 0.30) if i % 2 == 0 else Color(0.85, 0.30, 0.30)
		var y0: float = 80.0 + float(i) * 130.0
		stripe.polygon = PackedVector2Array([
			Vector2(gate_x - gate_w * 0.5, y0),
			Vector2(gate_x + gate_w * 0.5, y0 + 30.0),
			Vector2(gate_x + gate_w * 0.5, y0 + 50.0),
			Vector2(gate_x - gate_w * 0.5, y0 + 20.0),
		])
		stripe.z_index = 11
		challenge_gate_visual.add_child(stripe)
	# 경고 라벨 — 큼지막한 빨강 한 줄
	var warn := Label.new()
	warn.text = "출입 통제\nDARK ZONE"
	warn.add_theme_font_size_override("font_size", 14)
	warn.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
	warn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	warn.add_theme_constant_override("outline_size", 3)
	warn.position = Vector2(gate_x - 120.0, 380.0)
	warn.size = Vector2(240.0, 60.0)
	warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warn.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	warn.z_index = 12
	challenge_gate_visual.add_child(warn)
	# 충돌 — StaticBody. 발판 step 후 disabled.
	challenge_gate_door = StaticBody2D.new()
	challenge_gate_door.collision_layer = 1
	add_child(challenge_gate_door)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(gate_w, gate_h)
	col.shape = shape
	col.position = Vector2(gate_x, gate_h * 0.5)
	challenge_gate_door.add_child(col)
	# 발판 — 문 바로 앞 지면. 밟으면 도전 시작.
	challenge_plate = PressurePlate.new()
	challenge_plate.plate_id = "blackout_enter"
	challenge_plate.plate_width = 70.0
	challenge_plate.plate_thickness = 10.0
	challenge_plate.hint_color = Color(0.95, 0.55, 0.30)  # 도전 톤 — 주황 경고
	add_child(challenge_plate)
	challenge_plate.global_position = Vector2(gate_x - 70.0, GROUND_Y - 5.0)
	challenge_plate.stepped.connect(_on_challenge_plate_stepped)
	# VEIL 사전 경고 — 발판이 뭔지 알려주기.
	_show_veil_subtitle("이 안은 통신이 끊깁니다. 발판을 밟으면 시작입니다.\n한 대만 맞아도 끝.", 4.0)

func _on_challenge_plate_stepped(_id: String) -> void:
	if not challenge_pending:
		return
	challenge_pending = false
	_start_challenge_run()

# 도전 실제 시작 — 문 fade + 사이렌 플래시 + 암전 + 타이머 HUD + 클리어 조건 배너.
func _start_challenge_run() -> void:
	challenge_active = true
	SfxPlayer.play("gate_unlock")
	# 1) 문 + 차폐막 fade out + 충돌 disable.
	if challenge_gate_visual != null and is_instance_valid(challenge_gate_visual):
		var tw_v := challenge_gate_visual.create_tween()
		tw_v.tween_property(challenge_gate_visual, "modulate:a", 0.0, 0.5)
		tw_v.tween_callback(challenge_gate_visual.queue_free)
	if challenge_curtain != null and is_instance_valid(challenge_curtain):
		# 차폐막은 살짝 더 천천히 — 안이 점차 드러나는 톤. 사이렌 플래시 끝나갈 때 즈음 모두 보임.
		var tw_c := challenge_curtain.create_tween()
		tw_c.tween_interval(0.2)
		tw_c.tween_property(challenge_curtain, "modulate:a", 0.0, 0.9)
		tw_c.tween_callback(challenge_curtain.queue_free)
	if challenge_gate_door != null and is_instance_valid(challenge_gate_door):
		for c in challenge_gate_door.get_children():
			if c is CollisionShape2D:
				(c as CollisionShape2D).set_deferred("disabled", true)
	# 2) 사이렌 플래시 — 화면 빨강 두 번 깜빡.
	_play_siren_flash()
	# 3) 암전 — 0 → 정상 강도 fade in. CanvasLayer 안의 Control 노드를 트윈.
	_build_challenge_blackout()
	if challenge_dark_root != null:
		SfxPlayer.play("blackout_fade_in")
		challenge_dark_root.modulate.a = 0.0
		var tw_d := challenge_dark_root.create_tween()
		tw_d.tween_interval(0.4)
		tw_d.tween_property(challenge_dark_root, "modulate:a", 1.0, 0.7)
	# 4) 타이머 HUD.
	_build_challenge_timer_hud()
	# 5) 클리어 조건 배너 — 큰 글자, 화면 중앙. 페이드 인 → 2.4s 머무름 → 페이드 아웃.
	_show_challenge_briefing_banner()

func _play_siren_flash() -> void:
	SfxPlayer.play("siren_flash")
	var siren := CanvasLayer.new()
	siren.layer = 18
	add_child(siren)
	var rect := ColorRect.new()
	rect.color = Color(0.95, 0.20, 0.20, 0.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	siren.add_child(rect)
	var tw := rect.create_tween()
	tw.tween_property(rect, "color:a", 0.55, 0.10)
	tw.tween_property(rect, "color:a", 0.0, 0.18)
	tw.tween_property(rect, "color:a", 0.45, 0.10)
	tw.tween_property(rect, "color:a", 0.0, 0.20)
	tw.tween_callback(siren.queue_free)

func _show_challenge_briefing_banner() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 23
	add_child(layer)
	var holder := CenterContainer.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(holder)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.07, 0.92)
	sb.border_color = Color(0.95, 0.55, 0.30, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 32
	sb.content_margin_right = 32
	sb.content_margin_top = 20
	sb.content_margin_bottom = 20
	panel.add_theme_stylebox_override("panel", sb)
	holder.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	var title_lbl := Label.new()
	title_lbl.text = "BLACKOUT RUN"
	title_lbl.add_theme_font_size_override("font_size", 28)
	title_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.30))
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title_lbl)
	var body_lbl := Label.new()
	body_lbl.text = "%d초 안에 골 도달 / 한 대만 맞아도 실패" % int(challenge_time_remaining)
	body_lbl.add_theme_font_size_override("font_size", 18)
	body_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85))
	body_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(body_lbl)
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.92, 0.92)
	var tw := panel.create_tween()
	tw.set_parallel(true)
	tw.tween_property(panel, "modulate:a", 1.0, 0.30)
	tw.tween_property(panel, "scale", Vector2(1.0, 1.0), 0.30).set_trans(Tween.TRANS_BACK)
	tw.chain().tween_interval(2.4)
	tw.chain().tween_property(panel, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(layer.queue_free)

var challenge_dark_root: Control = null

func _build_challenge_blackout() -> void:
	# 화면 강 dim — 짙은 검정. 더 진하게(0.72), 가장자리 비네트도 더 두껍게.
	# 시야 압박: 가시 함정 / drone 폭탄 그림자 / bomber 점멸이 잘 안 보임.
	# CanvasLayer 자체는 modulate가 없어 fade in을 위해 자식 Control 하나 두고
	# 거기에 시각 children 모두 넣음. (사용자 보고 버그: line 2914 modulate 접근 에러)
	challenge_dark_layer = CanvasLayer.new()
	challenge_dark_layer.layer = 17
	add_child(challenge_dark_layer)
	challenge_dark_root = Control.new()
	challenge_dark_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	challenge_dark_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	challenge_dark_layer.add_child(challenge_dark_root)
	# 풀스크린 dim
	var full_dim := ColorRect.new()
	full_dim.color = Color(0, 0, 0, 0.72)
	full_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	full_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	challenge_dark_root.add_child(full_dim)
	# 가장자리 비네트 (상/하/좌/우 각각 짙은 띠 — 화면 가장자리에 앵커, 화면비 무관)
	for side_data in [
		{"preset": Control.PRESET_TOP_WIDE, "thick": 140.0},      # 상
		{"preset": Control.PRESET_BOTTOM_WIDE, "thick": 140.0},   # 하
		{"preset": Control.PRESET_LEFT_WIDE, "thick": 220.0},     # 좌
		{"preset": Control.PRESET_RIGHT_WIDE, "thick": 220.0},    # 우
	]:
		var d: Dictionary = side_data
		var v := ColorRect.new()
		v.color = Color(0, 0, 0, 0.72)
		var preset: int = d["preset"]
		var thick: float = d["thick"]
		v.set_anchors_preset(preset)
		match preset:
			Control.PRESET_TOP_WIDE:
				v.offset_bottom = thick
			Control.PRESET_BOTTOM_WIDE:
				v.offset_top = -thick
			Control.PRESET_LEFT_WIDE:
				v.offset_right = thick
			Control.PRESET_RIGHT_WIDE:
				v.offset_left = -thick
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE
		challenge_dark_root.add_child(v)

func _build_challenge_timer_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ChallengeTimer"
	layer.layer = 22
	add_child(layer)
	challenge_timer_label = Label.new()
	challenge_timer_label.text = "TIME  30.0"
	challenge_timer_label.add_theme_font_size_override("font_size", 22)
	challenge_timer_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.30))
	challenge_timer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	challenge_timer_label.add_theme_constant_override("outline_size", 4)
	challenge_timer_label.position = Vector2(540.0, 36.0)
	challenge_timer_label.size = Vector2(200.0, 28.0)
	challenge_timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	layer.add_child(challenge_timer_label)

func _tick_challenge(delta: float) -> void:
	if not challenge_active or challenge_failed or goal_reached:
		return
	challenge_time_remaining = max(0.0, challenge_time_remaining - delta)
	if challenge_timer_label != null and is_instance_valid(challenge_timer_label):
		challenge_timer_label.text = "TIME  %.1f" % challenge_time_remaining
		# 5초 이하면 빨강 점멸
		if challenge_time_remaining <= 5.0:
			challenge_timer_label.add_theme_color_override("font_color", Color(1.0, 0.30, 0.30))
	if challenge_time_remaining <= 0.0:
		_challenge_fail("타이머 초과")

func _tick_boss(delta: float) -> void:
	if boss == null or not is_instance_valid(boss):
		return
	_refresh_boss_hp_bar()
	# 자폭 카운트다운 라벨 갱신
	if boss_self_destruct_label != null and is_instance_valid(boss_self_destruct_label):
		if bool(boss.get("self_destruct_active")):
			boss_self_destruct_timer_t = float(boss.get("self_destruct_t"))
			var remaining: float = max(0.0, BossSentinel.SELF_DESTRUCT_TIME - boss_self_destruct_timer_t)
			boss_self_destruct_label.text = "SENTINEL OVERLOAD  %.1f" % remaining

# 레버 + 발판 트리거 — ArcturusDocumentOverlay (풀스크린 문서 + 카메라 스크롤 + 시간 정지).
func _start_arcturus_sequence() -> void:
	GameState.restrict_combat_input = true
	# 큐 + 현재 표시 중인 자막 layer까지 모두 폐기. 단순 _subtitle_queue.clear()는
	# 이미 화면에 fade-in/out 진행 중이던 Label은 못 잡아서, paused가 풀린 뒤에도
	# zombie tween이 outro 자막과 함께 떠 있던 문제(사용자 보고)가 있었다.
	_purge_subtitles()
	var doc := ArcturusDocumentOverlay.new()
	doc.name = "ArcturusDoc"
	add_child(doc)
	doc.finished.connect(_on_arcturus_lines_done)
	doc.show_doc(_arcturus_document_lines())

func _on_arcturus_lines_done() -> void:
	if arcturus_state == "done":
		return
	arcturus_state = "done"
	GameState.add_xp(3, false)
	GameState.trust_score += 1
	GameState.visited_arcturus = true
	GameState.save_settings()
	GameState.restrict_combat_input = false
	# VEIL outro — VEIL-1/VEIL-2 시퀀스 직후라 em dash 없이 화자 라벨만(시각 일관성).
	_show_veil_subtitle(VeilDialogue.banded("저도 이 파일들, 읽은 적 있습니다.\n계속 가시죠, 요원.", "저도 이 파일들 읽은 적 있어요.\n계속 가요, 요원."), 3.2, true)

# ARCTURUS 아카이브 문서 — 3 단말기.
# kind: "title" (큰 헤더) / "speaker" (회색 작은 발화자) / "body" (본문) / "blank" (간격)
func _arcturus_document_lines() -> Array:
	var out: Array = []
	# 표지
	out.append({"kind": "title", "text": "ARCTURUS: 내부 문서 단편", "delay": 0.6})
	out.append({"kind": "blank", "text": "", "delay": 0.2})
	# 단말기 A — 신입 직원 온보딩
	out.append({"kind": "speaker", "text": "[A]  인사팀 온보딩 메모", "delay": 0.4})
	out.append({"kind": "body", "text": "ARCTURUS에 오신 것을 환영합니다.", "delay": 0.6})
	out.append({"kind": "body", "text": "본사는 공식적으로 존재하지 않습니다.", "delay": 0.6, "hl": true})
	out.append({"kind": "body", "text": "모든 임무는 기록되지 않습니다.", "delay": 0.6})
	out.append({"kind": "body", "text": "질문하지 마세요. 결과만 내세요.", "delay": 0.7})
	out.append({"kind": "body", "text": "인사팀 (인사팀도 공식적으로 존재하지 않습니다)", "delay": 0.5})
	out.append({"kind": "blank", "text": "", "delay": 0.3})
	# 단말기 B — VEIL 회의록
	out.append({"kind": "speaker", "text": "[B]  VEIL 프로젝트 초기 회의록", "delay": 0.4})
	out.append({"kind": "body", "text": "참석자: [REDACTED], [REDACTED], [REDACTED]", "delay": 0.6})
	out.append({"kind": "body", "text": "주제: VEIL 감정 모듈 탑재 여부", "delay": 0.6})
	out.append({"kind": "body", "text": "결론: 탑재 보류. 불필요한 복잡성.", "delay": 0.7})
	out.append({"kind": "body", "text": "비고: VEIL-2가 감정 모듈 없이도 이상 반응을 보인 것에 대해", "delay": 0.5, "hl": true})
	out.append({"kind": "body", "text": "        추가 조사 예정.", "delay": 0.6})
	out.append({"kind": "body", "text": "[REDACTED]", "delay": 0.5})
	out.append({"kind": "blank", "text": "", "delay": 0.3})
	# 단말기 C — 감시팀 메모
	out.append({"kind": "speaker", "text": "[C]  감시팀 내부 메모", "delay": 0.4})
	out.append({"kind": "body", "text": "요원 코드: [REDACTED]", "delay": 0.5})
	out.append({"kind": "body", "text": "임무: PALIMPSEST", "delay": 0.5, "hl": true})
	out.append({"kind": "body", "text": "현재 상태: 진행 중", "delay": 0.5})
	out.append({"kind": "body", "text": "VEIL과의 협조도: [측정 중]", "delay": 0.6})
	out.append({"kind": "body", "text": "비고: 요원이 이 문서를 읽고 있다면", "delay": 0.5})
	out.append({"kind": "body", "text": "        이미 임무 범위를 벗어난 것임.", "delay": 0.7})
	out.append({"kind": "body", "text": "감시팀", "delay": 0.5})
	# VEIL outro는 문서 안이 아니라 _on_arcturus_lines_done에서 게임 내 자막으로 표시.
	# 문서는 ARCTURUS 내부 단편들만 — VEIL 발화는 게임 화면의 대사창이 어울림.
	return out

func _on_xp_collected(leveled_up: bool) -> void:
	if leveled_up and not pending_levelup:
		pending_levelup = true
		_show_levelup()

func _show_levelup() -> void:
	get_tree().paused = true
	var advice: Dictionary = VeilDialogue.get_levelup_advice(GameState.skills, GameState.current_route_tags, GameState.current_route_id)
	levelup_overlay = LevelUpOverlay.show(self, advice, _on_levelup_picked)

func _on_levelup_picked(_picked_id: String) -> void:
	levelup_overlay = null
	pending_levelup = false
	get_tree().paused = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and levelup_overlay == null:
		if pause_overlay == null:
			_show_pause()
		else:
			_hide_pause()

# 모바일 가상 패드 — 터치 기기에서만 생성한다(데스크톱/키보드 플레이엔 영향 없음).
# 게이팅은 OrientationGuard.is_touch_device() — 모바일 웹에서 부정확한 is_touchscreen_available()
# 대신 navigator.maxTouchPoints로 확인한다.
func _build_touch_controls() -> void:
	if not OrientationGuard.is_touch_device():
		return
	add_child(TouchControls.new())

func _show_pause() -> void:
	get_tree().paused = true
	SfxPlayer.play("ui_pause_open")
	pause_overlay = PauseHelper.build(self, _on_pause_resume, _on_pause_settings, _on_pause_to_title)
	add_child(pause_overlay)

func _hide_pause() -> void:
	if pause_overlay != null:
		SfxPlayer.play("ui_cancel")
		pause_overlay.queue_free()
		pause_overlay = null
	get_tree().paused = false

func _on_pause_resume() -> void:
	_hide_pause()

func _on_pause_settings() -> void:
	if settings_overlay != null:
		return
	var packed := load(SceneRouter.SETTINGS) as PackedScene
	if packed == null:
		return
	settings_overlay = packed.instantiate()
	settings_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	if pause_overlay != null:
		pause_overlay.add_child(settings_overlay)
	else:
		add_child(settings_overlay)
	if settings_overlay.has_signal("closed"):
		settings_overlay.closed.connect(_on_settings_closed)

func _on_settings_closed() -> void:
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null

func _on_pause_to_title() -> void:
	get_tree().paused = false
	GameState.reset()
	get_tree().change_scene_to_file.call_deferred(SceneRouter.TITLE)
