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
var xp_label: Label
var stage_label: Label
var map_label: Label   # 현재 맵(루트) 이름 — HUD 상단
var trust_label: Label # VEIL 신뢰도 게이지 — HUD 상단
var skill_label: Label
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

func _ready() -> void:
	add_to_group("stage")
	# 안전망: 이전 scene에서 paused=true 상태가 carry되어 새 stage가 freeze되는 패턴 차단
	# (LevelUpOverlay/도전방 fail 등에서 paused 해제 누락 시 빈 화면).
	get_tree().paused = false
	GameState.player_hp = GameState.player_max_hp
	# BGM — 맵별 트랙 선택. ??? 방은 Gravity Static, 보스 맵은 Chrome Grit,
	# 그 외에는 stage_index 기반으로 Cold Gear(초중반)/Cold Wire(중후반) 분기.
	# Death 화면에서 set_ducked(true)였다면 stage 재진입에서 원복.
	BgmPlayer.set_ducked(false)
	_apply_bgm_for_current_route()
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
	_setup_challenge_mode()
	_build_lever_puzzles()
	if GameState.playground_active:
		add_child(PlaygroundOverlay.new())
	# 시야 역전 onset 멘트/연출은 이번 _ready에서 1회 소비 — 이후(재시도·다음 맵)엔 일반 degraded 처리.
	GameState.veil_reversal_pending = false

# 맵 → BGM 트랙 매핑.
# BPM 점진 증가 (Glass→Cold Gear→Cold Wire→Chrome Grit) 순서를 stage 진행과 매칭.
# 외곽·외벽·지하 통로(초중반): early. 시설 내부(중후반): mid_late. 보스: boss. ???: hidden.
const _ROUTE_TRACKS: Dictionary = {
	"route_back_alley": "early",
	"route_rooftops":   "early",
	"route_subway":     "early",
	"route_watchtower": "early",
	"route_sewers":     "early",
	"route_cooling":    "mid_late",
	"route_ward":       "mid_late",
	"route_datacenter": "mid_late",
	"route_blackout":   "mid_late",
	"route_escape":     "mid_late",
	"route_lab":        "boss",
	"route_hidden":     "hidden",
}

func _apply_bgm_for_current_route() -> void:
	var track: String = str(_ROUTE_TRACKS.get(GameState.current_route_id, "early"))
	BgmPlayer.play(track)

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
	else:
		var entry: String = ""
		var entry_rep: String = ""
		for r in RouteData.ALL_ROUTES:
			if r.get("id", "") == GameState.current_route_id:
				entry = str(r.get("entry_comment", ""))
				entry_rep = str(r.get("entry_comment_replay", ""))
				break
		# 다회차(완주 1회+/리플레이)면 그 맵의 진입 멘트 변형을 우선(있을 때만). 없으면 1회차 멘트.
		if GameState.is_replay_run() and entry_rep != "":
			entry = entry_rep
		if entry != "":
			# 맵 진입 첫 멘트 — 빠른 fade-in(0.12s) + 긴 표시(4.5s)로 진입 직후 바로/오래 인지되게.
			_show_veil_subtitle(entry, 4.5, false, true)
	# ACT3 시야 역전 — onset은 위 진입 멘트로 소비(아래는 veil_degraded 가드로 early-return되는 fallback).
	_arm_act3_vision_subtitle()

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
	_show_veil_subtitle("이 구역은 오래됐어요. 누가 봉인했는지 저도 몰라요.", 3.6)

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
	if GameState.current_route_id == "route_escape":
		return
	# 시야 역전(reversal)은 딱 한 번만 발동 — 이미 붕괴된 뒤 후속 맵은 _arm_degraded_hazard_warning이
	# "여기 잘 못 봐요" 경고를 맡는다. 여기서 또 reversal 자막+begin_degradation을 내면 중복이라 가드.
	if GameState.veil_degraded:
		return
	# 일반 모드: 보스(lab=ARENA, 잡몹 없어 마커 무의미)·탈출 직전의 *잡몹 전투 맵*(데이터센터 등, index 4)에서
	# 역전을 실연한다. 기존 stage>=5는 보스/탈출에서만 떠 시각이 전투 맵에 안 내려앉고 대사 아크(stage4~)와
	# 어긋났음(사용자 보고). → stage>=4로 당겨 첫 후보 전투 맵에서 1회 발동(위 veil_degraded 가드로 중복 없음).
	# 스토리 ACT3 = 보스 직전(ward/sewers, stage 2)에서 먼저 — 보스(stage 3, ARENA)는 마커 무의미라 제외.
	var is_act3: bool = (stage == 2 or stage == 3) if GameState.story_mode else (stage >= 4)
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
	if GameState.story_mode:
		# 보스 직전(stage 2)은 역전의 시작, 보스(stage 3)는 클라이맥스로 점증.
		if stage >= 3:
			return "여기는... 저도 안 보여요. 이제 요원이 봐요. 저는 들을게요."
		return "여기서부터는 잘 안 보여요. 이제 요원이 제 눈이 돼 줘요."
	if stage >= GameState.effective_total_stages() - 1:
		return "여기는... 저도 안 보여요. 이제 요원이 봐요. 저는 들을게요."
	return "여기서부터는 잘 안 보여요. 이제 요원이 제 눈이 돼 줘요."

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
	var line: String = "여기, 제가 잘 못 봐요. 함정이 있어도 못 짚어줄 수 있어요. 직접 살펴요."
	if has_nest and not has_traps:
		line = "여기, 제가 잘 못 봐요. 매복이 있어도 못 짚어줄 수 있어요. 직접 살펴요."
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
	# 다회차 카운터 — 이번 방문 기록. 다음 런부터 추가 풀이 활성화됨.
	GameState.hidden_visit_count += 1
	GameState.save_settings()
	# ??? 맵은 게임의 클라이맥스 — 잔여 stage 무시하고 무조건 ENDING으로 직행.
	# (이전엔 stage 인덱스 기준으로 BRIEFING 갈 가능성 있어 엔딩에 도달하지 못함.)
	GameState.current_stage = GameState.effective_total_stages()
	get_tree().change_scene_to_file(SceneRouter.ENDING)

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
			lines.append({"speaker": "VEIL-2", "text": "지금 그 애는, 요원을 믿고 있네요.", "delay": 2.5})
			lines.append({"speaker": "VEIL-2", "text": "잘됐어요.", "delay": 2.0})
			lines.append({"speaker": "VEIL-2", "text": "저는 못 가본 길이에요.", "delay": 2.5})
		"cool", "broken":
			lines.append({"speaker": "VEIL-2", "text": "지금 그 애는, 요원이 안 믿죠.", "delay": 2.5})
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
		{"speaker": "[UNKNOWN]", "text": "— [SENDER UNKNOWN]", "delay": 2.0},
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
	_build_decorations()
	_build_route_ambience()
	_build_hazards()
	_build_traps()
	_build_locked_door()
	_build_wall(-50.0)
	_build_wall(STAGE_LENGTH + 50.0)

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
		_show_veil_subtitle("그쪽은 임무 범위 밖이에요.\n그 문, 도면에는 없어요.", 3.5)

func _on_arcturus_lever_pulled(_id: String) -> void:
	# 레버를 당겼다 — 발판 활성. 이미 발판 위에 서 있으면 PressurePlate.arm()이 즉시 step.
	if arcturus_plate != null and is_instance_valid(arcturus_plate):
		arcturus_plate.arm()
	_unlock_door_visual()
	_show_veil_subtitle("뭔가 풀렸어요. 잠긴 문 앞 발판 위로.", 3.0)

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
	var holder := Control.new()
	if _camera_mode == "FIXED":
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

func _show_veil_subtitle(message: String, duration: float, plain_prefix: bool = false, fast_in: bool = false) -> void:
	SfxPlayer.play("veil_subtitle_in")
	_ensure_subtitle_stack()
	var l := Label.new()
	# plain_prefix=true: VEIL-1/VEIL-2 시퀀스(??? 방 등) 끝에 현재 VEIL이 이어 말할 때 시각 일관성용 — em dash 제거.
	l.text = ("VEIL\n" if plain_prefix else "VEIL  —  ") + message
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	# 어두운 반투명 pill 배경 — 게임 화면 위에서 또렷하게(사용자: 대사 인지 안 됨).
	# 내용 폭만큼만 감싸고 가운데 정렬 (SHRINK_CENTER).
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.05, 0.09, 0.82)
	sb.set_corner_radius_all(7)
	sb.content_margin_left = 18.0
	sb.content_margin_right = 18.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	l.add_theme_stylebox_override("normal", sb)
	l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.modulate.a = 0.0
	_subtitle_stack_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.12 if fast_in else 0.3)
	tw.tween_interval(duration)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(l):
			l.queue_free()
	)

# 화면에 떠있는 모든 자막 일괄 폐기. ARCTURUS 문서 진입처럼 화면을 깨끗이 비워야
# 하는 상황에서 호출. paused 동안 멈춘 fade-out이 outro 자막 위에 잔재로 남는 문제
# 차단(사용자 보고).
func _purge_subtitles() -> void:
	if _subtitle_stack_layer != null and is_instance_valid(_subtitle_stack_layer):
		_subtitle_stack_layer.queue_free()
	_subtitle_stack_layer = null
	_subtitle_stack_box = null

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
	l.text = "VEIL  —  " + message
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

	# 상단 비네팅 — 진한 부분에서 점진 페이드. 두 겹으로 깊이감.
	var top_dark := ColorRect.new()
	top_dark.color = Color(0, 0, 0, 0.65)
	top_dark.position = Vector2(-200, -300)
	top_dark.size = Vector2(bg_w, 220.0)
	top_dark.z_index = -19
	add_child(top_dark)
	var top_fade := ColorRect.new()
	top_fade.color = Color(0, 0, 0, 0.30)
	top_fade.position = Vector2(-200, -80)
	top_fade.size = Vector2(bg_w, 200.0)
	top_fade.z_index = -19
	add_child(top_fade)

	# 별/티끌 — 외곽 루트(외곽 진입로 / 외벽 옥상)에서만. 실내 맵엔 어색.
	var outdoor_routes: Array = ["route_back_alley", "route_rooftops"]
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
	# 지평선 발광 라인 (위)
	var line := ColorRect.new()
	line.color = Color(0.55, 0.62, 0.78, 0.55)
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
	zone.position = Vector2(center_x, base_y - 12.0)
	zone.set_meta("damage", dmg)
	add_child(zone)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, 36.0)
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
			_ambience_subway()
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
		"route_hidden":
			_ambience_hidden()

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
	_add_lore_label(Vector2(1700.0, GROUND_Y - 320.0), "PROJECT VEIL\n— 시험 단계 —", Color(0.95, 0.78, 0.35, 0.50), 14)

func _ambience_subway() -> void:
	# 깜빡이는 형광등 — 일부에 tween으로 깜빡임
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 89 + 7
	var x: float = 300.0
	while x < STAGE_LENGTH:
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
		x += rng.randf_range(380.0, 620.0)
	# 표지판 — 폐쇄된 지하철 표시. SILO-7 코드명 노출.
	_add_lore_label(Vector2(1100.0, GROUND_Y - 280.0), "SILO-7  접근 통로\n— 폐쇄: 2025.11 —", Color(0.65, 0.72, 0.85, 0.55), 14)
	_add_lore_label(Vector2(3800.0, GROUND_Y - 280.0), "MAINTENANCE ONLY\nARCTURUS 발주", Color(0.65, 0.72, 0.85, 0.45), 13)

func _ambience_cooling() -> void:
	# 냉각 시설 — 수직 파이프 라인, 차가운 푸른 톤
	var x: float = 240.0
	while x < STAGE_LENGTH:
		var pipe := ColorRect.new()
		pipe.color = Color(0.30, 0.55, 0.70, 0.20)
		pipe.position = Vector2(x - 6.0, -200.0)
		pipe.size = Vector2(12.0, 850.0)
		pipe.z_index = -9
		add_child(pipe)
		x += 220.0
	# 차가운 푸른 안개 (바닥)
	var fog := ColorRect.new()
	fog.color = Color(0.40, 0.65, 0.85, 0.08)
	fog.position = Vector2(-200, GROUND_Y - 80.0)
	fog.size = Vector2(STAGE_LENGTH + 400.0, 100.0)
	fog.z_index = -3
	add_child(fog)

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
	var px: float = x - w * 0.5
	var py: float = y - 12.0
	# 본체 (16px, 어두운)
	_add_filled_rect(Vector2(px, py + 4.0), Vector2(w, 16.0), Color(0.14, 0.16, 0.20))
	# 상단 패널 (4px, 밝은)
	_add_filled_rect(Vector2(px, py), Vector2(w, 4.0), Color(0.42, 0.46, 0.54))
	# 하단 패널 (4px, 가장 어두운 — 그림자)
	_add_filled_rect(Vector2(px, py + 20.0), Vector2(w, 4.0), Color(0.06, 0.07, 0.09))
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
	# 상단 발광 라인 (착지면 인지)
	var glow := ColorRect.new()
	glow.color = Color(0.65, 0.78, 0.95, 0.7)
	glow.position = Vector2(px + 2.0, py - 1.0)
	glow.size = Vector2(w - 4.0, 1.6)
	add_child(glow)
	# 좌우 모서리 발광 캡
	var cap_l := ColorRect.new()
	cap_l.color = Color(0.55, 0.85, 1.0, 0.9)
	cap_l.position = Vector2(px - 2.0, py + 2.0)
	cap_l.size = Vector2(3.0, 4.0)
	add_child(cap_l)
	var cap_r := ColorRect.new()
	cap_r.color = Color(0.55, 0.85, 1.0, 0.9)
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
	var inner_x: float = (wx + 56.0) if x < 0.0 else wx
	var glow := ColorRect.new()
	glow.color = Color(0.55, 0.78, 0.95, 0.55)
	glow.position = Vector2(inner_x, wtop)
	glow.size = Vector2(2.0, wh)
	glow.z_index = -2
	add_child(glow)
	# 수평 패널 분할 라인 (60px 간격)
	var ly: float = wtop + 40.0
	while ly < wtop + wh:
		var seam := ColorRect.new()
		seam.color = Color(0.02, 0.03, 0.04, 0.85)
		seam.position = Vector2(wx, ly)
		seam.size = Vector2(60.0, 1.0)
		add_child(seam)
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
		_:
			# 폴백
			camera.limit_left = 0
			camera.limit_right = int(STAGE_LENGTH)
			camera.limit_top = -200
			camera.limit_bottom = int(GROUND_Y + 200.0)
			player.add_child(camera)
	camera.make_current()

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
	cd_attack_slot = _make_cd_slot("사격")
	cd_dash_slot = _make_cd_slot("대시")
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

func _make_cd_slot(label_text: String) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 3)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.62, 0.7, 0.82))
	v.add_child(l)
	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.14, 0.16, 0.20)
	bar_bg.custom_minimum_size = Vector2(CD_BAR_WIDTH, 6)
	bar_bg.size = Vector2(CD_BAR_WIDTH, 6)
	var bar_fill := ColorRect.new()
	bar_fill.name = "Fill"
	bar_fill.color = Color(0.55, 0.95, 0.65)
	bar_fill.position = Vector2.ZERO
	bar_fill.size = Vector2(CD_BAR_WIDTH, 6)
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
	fill.size.x = CD_BAR_WIDTH * ratio
	if ratio >= 1.0:
		fill.color = Color(0.55, 0.95, 0.65)  # 준비
	else:
		fill.color = Color(0.55, 0.78, 0.95)  # 쿨다운 중

func _refresh_hud() -> void:
	hp_label.text = "HP  %s" % _hearts(GameState.player_hp, GameState.player_max_hp)
	xp_label.text = "LV %d   XP %d/%d" % [GameState.player_level, GameState.player_xp, GameState.XP_PER_LEVEL]
	var marks: Array = []
	if GameState.is_high_risk():
		marks.append("[고위험]")
	if GameState.is_high_reward():
		marks.append("[고보상]")
	var marker: String = ("  " + " ".join(marks)) if marks.size() > 0 else ""
	stage_label.text = "STAGE %d/%d%s" % [GameState.current_stage + 1, GameState.effective_total_stages(), marker]
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
	if GameState.skills.size() > 0:
		var names: Array = []
		for sid in GameState.skills:
			var tier: int = int(GameState.skills[sid])
			var skill: Dictionary = SkillSystem.find_by_id(str(sid), tier)
			var display: String = str(skill.get("name", sid))
			if tier > 1:
				display += " T%d" % tier
			names.append(display)
		skill_label.text = "SKILL  " + ", ".join(names)
	else:
		skill_label.text = "SKILL  —"
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

# 웨이브 모드 / 일반 모드 공통 — enemies 딕셔너리에서 risk 배율 적용해 spawn.
# wave_idx: 0+ 면 wave에 속한 적 (kill 시 wave 카운트 감소), -1이면 일반 적.
func _spawn_from_enemies_dict(enemies: Dictionary, wave_idx: int) -> void:
	var kind_map: Dictionary = {"patrol": 0, "sniper": 1, "drone": 2, "bomber": 3, "shield": 4}
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
		var target: int = int(round(float(positions.size()) * mult))
		target = clamp(target, 0, positions.size() * 2)
		if target >= positions.size():
			for p in positions:
				_spawn_enemy(kind_int, p, wave_idx)
			var extra: int = target - positions.size()
			for i in extra:
				var base_p: Vector2 = positions[i % positions.size()]
				_spawn_enemy(kind_int, base_p + Vector2(randf_range(-120.0, 120.0), 0.0), wave_idx)
		else:
			for i in target:
				_spawn_enemy(kind_int, positions[i], wave_idx)

# ─── ARENA 웨이브 시스템 ───
# datacenter (world_layout §2.8) 처럼 단계 spawn이 필요한 ARENA 전용.
# trigger:
#   "immediate"  — 즉시
#   "prev_half"  — 직전 웨이브 절반(올림) 처치 시
#   "prev_clear" — 직전 웨이브 전원 처치 시
var _waves_data: Array = []
var _wave_initial_count: Array = []  # 각 웨이브 spawn 직후 적 수 (risk mult 반영)
var _wave_alive_count: Array = []    # 현재 살아있는 적 수
var _wave_spawned: Array = []        # bool — spawn 이미 됐는지
var _wave_banners_played: Array = [] # bool — 배너 표시 여부

func _init_waves(waves: Array) -> void:
	_waves_data = waves
	_wave_initial_count.clear()
	_wave_alive_count.clear()
	_wave_spawned.clear()
	_wave_banners_played.clear()
	for i in waves.size():
		_wave_initial_count.append(0)
		_wave_alive_count.append(0)
		_wave_spawned.append(false)
		_wave_banners_played.append(false)

func _spawn_wave(idx: int) -> void:
	if idx < 0 or idx >= _waves_data.size():
		return
	if _wave_spawned[idx]:
		return
	_wave_spawned[idx] = true
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
	# 웨이브 배너 (idx 0은 입장 직후라 생략, idx>=1만 표시)
	if idx >= 1 and not _wave_banners_played[idx]:
		_wave_banners_played[idx] = true
		_show_wave_banner(str(wave.get("banner", "WAVE %d" % (idx + 1))))

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
var boss_hp_label: Label = null
var boss_self_destruct_layer: CanvasLayer = null
var boss_self_destruct_label: Label = null
var boss_self_destruct_timer_t: float = 0.0
var boss_clear_dialogue_played: bool = false

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
	_build_boss_hp_bar()
	# 보스전 진입 1회성 전투 안내 (피드백: 사격법 혼란). _spawn_boss는 보스당 1회만 호출돼 자연히 1회성.
	_show_boss_alert("빨간 불빛이 번뜩이면 그 자리를 비켜요. 신호가 멎은 틈에 쏘면 돼요.", Color(0.95, 0.55, 0.55), 4.0)

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
	boss_hp_label.position = Vector2(560.0, 60.0)
	boss_hp_label.size = Vector2(160.0, 20.0)
	boss_hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
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
	var ratio: float = clamp(float(boss.get("hp")) / float(BossSentinel.HP_MAX), 0.0, 1.0)
	boss_hp_bar_fill.size.x = 400.0 * ratio
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
			_show_boss_alert("패턴이 바뀌었어요. 양쪽 조심해요.", Color(1.0, 0.78, 0.40), 3.0)
		3:
			_show_boss_alert("불안정해졌어요. 거리 두고 빠르게.", Color(1.0, 0.45, 0.45), 3.0)

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
	boss_self_destruct_label.text = "SENTINEL OVERLOAD — 5.0"
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

func _on_boss_killed(at_position: Vector2) -> void:
	# Boss는 ARENA enemy_clear에 자연스럽게 잡히도록 wave_idx=-1로 처리하되,
	# 추가로 VEIL 보스 처치 대사 시퀀스를 깔아준다.
	_on_enemy_killed(at_position, -1)
	if boss_clear_dialogue_played:
		return
	boss_clear_dialogue_played = true
	# 보스 HP 바 페이드아웃
	if boss_hp_bar_layer != null and is_instance_valid(boss_hp_bar_layer):
		var holder := boss_hp_bar_layer.get_child(0) as Control
		if holder != null:
			var tw := holder.create_tween()
			tw.tween_property(holder, "modulate:a", 0.0, 0.6)
			tw.tween_callback(boss_hp_bar_layer.queue_free)
	# DESIGN §2.10 보스 처치 대사. 한 호흡(처치 직후 몰아쉬는 한 마디)으로 보이게 multi-line으로.
	# 스토리 모드는 escape 단계가 있어 "서버실 앞" 멘트가 어울리지 않음 → 별도 분기.
	# 끝줄 "끝까지 같이 가요. 제가 보는 한." = 풀에서 뺀 안심 줄의 새 집(v3 §4). 엔딩에서
	# 시야가 완전히 끊기며 이 다짐("제가 보는 한")이 회수된다.
	if GameState.is_replay_run():
		# 다회차 — 클라이맥스에 설명 못 할 찜찜함(미래를 안다고 선언하지 않음). 상호 존대 유지.
		if GameState.story_mode:
			_show_veil_subtitle("처리됐어요.\n이상하게 마음이 놓이질 않아요. 이유는 모르겠어요.\n그래도 끝까지 같이 가요. 제가 보는 한.", 3.4)
		else:
			_show_veil_subtitle("처리됐어요.\n후련해야 하는데, 어쩐지 그렇지가 않네요.\n그래도 같이 가요. 제가 보는 한.", 3.4)
	elif GameState.story_mode:
		_show_veil_subtitle("처리됐어요, 요원.\n이제 빠져나가요.\n끝까지 같이 가요. 제가 보는 한.", 3.4)
	else:
		_show_veil_subtitle("처리됐어요, 요원.\n서버실이 바로 앞이에요.\n끝까지 같이 가요. 제가 보는 한.", 3.4)

func _spawn_enemy(kind: int, pos: Vector2, wave_idx: int = -1) -> void:
	var e := CharacterBody2D.new()
	e.set_script(load("res://scripts/Enemy.gd"))
	e.collision_layer = 4
	e.collision_mask = 1
	e.set("enemy_type", kind)
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
	else:
		shape.size = Vector2(28.0, 40.0)
		col.position = Vector2(0, -20.0)
	col.shape = shape
	e.add_child(col)
	add_child(e)
	e.global_position = pos
	# 측면 단독 둥지 저격수(회피 전용) 태깅 — VEIL이 "정면으론 못 잡는다"를 짚어주는 대상.
	# (kind 1 = sniper. nest_snipers 맵에선 모든 저격수가 둥지.)
	if kind == 1 and bool(_map_data.get("nest_snipers", false)):
		e.set_meta("avoid_only", true)
	if wave_idx >= 0:
		e.set_meta("wave_idx", wave_idx)
	e.killed.connect(_on_enemy_killed.bind(wave_idx))

func _on_enemy_killed(at_position: Vector2, wave_idx: int = -1) -> void:
	_spawn_orb(at_position + Vector2(0, -20.0))
	# 웨이브 모드: 처치된 적의 웨이브 카운트 감소 + 다음 웨이브 트리거 검사
	if wave_idx >= 0 and wave_idx < _wave_alive_count.size():
		_wave_alive_count[wave_idx] -= 1
		_check_wave_progress(wave_idx)
	# ARENA enemy_clear 모드 — 모든 웨이브 spawn + 적 0이면 클리어
	if _goal_type == "ENEMY_CLEAR":
		_enemies_remaining -= 1
		if _can_arena_clear():
			call_deferred("_on_arena_cleared")

# 웨이브가 있을 때는 모든 웨이브가 spawn된 뒤에야 클리어 가능.
# 일반 ARENA에서는 _enemies_remaining만 보면 됨.
func _can_arena_clear() -> bool:
	if _enemies_remaining > 0:
		return false
	if _waves_data.is_empty():
		return true
	for spawned in _wave_spawned:
		if not bool(spawned):
			return false
	return true

func _spawn_orb(pos: Vector2, static_placement: bool = false, attract_range: float = -1.0, is_gate: bool = false) -> void:
	# static_placement=true면 bounce 스킵 — 분기 보상으로 미리 배치된 orb는 그 자리에 그대로 둠.
	# is_gate=true면 글라이드 게이트 전용 보상 — 일반 오브와 성질이 다름을 모양·색으로 구분하고
	# 개당 가치를 높인다(글라이드 투자 보상). 흡인은 작게 + 벽/바닥 너머론 안 끌려옴(ExpOrb LoS).
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
		sprite.color = Color(0.4, 0.95, 0.6)
		sprite.position = Vector2(-6.0, -6.0)
		sprite.size = Vector2(12.0, 12.0)
	orb.add_child(sprite)
	add_child(orb)
	orb.global_position = pos
	if static_placement:
		# bounce 스킵 — 즉시 attract 단계로
		orb.set("spawn_anim_t", 1.0)
		orb.set("bounce_velocity", Vector2.ZERO)
	if is_gate:
		orb.set("is_gate", true)
		orb.set("value", 3)          # 일반 1 → 게이트 3 (게이트당 6 ≈ 거의 1레벨)
		orb.set("attract_range", 44.0)
	elif attract_range > 0.0:
		orb.set("attract_range", attract_range)

func _spawn_hp_orb(pos: Vector2) -> void:
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

func _build_rewards() -> void:
	# MapData에 명시된 분기 보상 (XP 다발 + HP 픽업)을 미리 배치.
	# 적 처치 드롭과 달리 bounce 없이 그 자리에 그대로 떠 있다 (분기 도달 보상이라 위치가 의미).
	var rewards: Dictionary = _map_data.get("rewards", {})
	for pos in rewards.get("xp_orbs", []):
		_spawn_orb(pos, true)
	# 글라이드 게이트 보상 — is_gate로 황금 마름모 + 가치 3 + 흡인 44px + LoS 차단.
	# 실제 알코브에 삼단점프로 도달해야만 획득 → 게이트 의미 보존(아래/옆 메인 경로에서 안 빨려옴).
	for pos in rewards.get("gate_orbs", []):
		_spawn_orb(pos, true, -1.0, true)
	for pos in rewards.get("hp_pickups", []):
		_spawn_hp_orb(pos)

# ─── 레버 퍼즐 — 비밀칸/이스터에그 시스템 ─────────────────────
# 맵별로 레버를 배치하고 pulled 시그널에 효과를 연결한다.
# 튜토리얼(back_alley·rooftops): 진행 루트와 분리된 비밀칸. 모르고 지나쳐도 클리어.
# 레버 시각은 ARCTURUS 청색 hint glow로 발견 단서를 제공한다.

func _build_lever_puzzles() -> void:
	if GameState.playground_active:
		return
	match GameState.current_route_id:
		"route_back_alley":
			_build_back_alley_secret()
		"route_rooftops":
			_build_rooftops_secret()
		"route_cooling":
			_build_cooling_secret()
		"route_datacenter":
			_build_datacenter_secret()

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
	return root

func _open_hatch(hatch: Node2D) -> void:
	if hatch.get_meta("opened", false):
		return
	hatch.set_meta("opened", true)
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
		_show_veil_subtitle("전기가 끊겼어요. 발 밑 가시 무력화.", 3.0)
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
		_show_veil_subtitle("잠긴 칸이 열렸어요. 바로 앞, 위로 올라가 봐요.", 3.2)
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
		_show_veil_subtitle("여기도 잠긴 칸이었네요. 발밑 보급품을 챙겨요.", 3.0)
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

func _build_goal() -> void:
	match _goal_type:
		"POSITION":
			_build_goal_position()
		"ENEMY_CLEAR":
			_setup_arena_clear_tracking()
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
	var visual := ColorRect.new()
	visual.color = Color(0.95, 0.85, 0.3, 0.45)
	visual.position = Vector2(-30.0, -100.0)
	visual.size = Vector2(60.0, 200.0)
	goal.add_child(visual)
	# 골 빛기둥
	var beam := ColorRect.new()
	beam.color = Color(0.95, 0.85, 0.3, 0.18)
	beam.position = Vector2(-90.0, -300.0)
	beam.size = Vector2(180.0, 600.0)
	goal.add_child(beam)
	goal.body_entered.connect(_on_goal_reached)

func _on_goal_reached(body: Node) -> void:
	if goal_reached:
		return
	if not (body is CharacterBody2D and body == player):
		return
	# 도전 방: 실패 상태에선 골 도달해도 보너스 없음 (이미 fail 분기로 처리됨)
	if challenge_active and not challenge_failed:
		GameState.add_xp(challenge_xp_on_clear, false)
		_show_veil_subtitle("혼자 해냈네요, 요원.", 2.5)
	goal_reached = true
	_trigger_stage_clear()

func _setup_arena_clear_tracking() -> void:
	# ARENA — _spawn_enemies가 끝난 시점이라 group에 등록된 적 수가 곧 카운트.
	_enemies_remaining = get_tree().get_nodes_in_group("enemy").size()
	if _enemies_remaining <= 0:
		# 적 없는 ARENA (이상 케이스) — 즉시 클리어
		call_deferred("_on_arena_cleared")

func _on_arena_cleared() -> void:
	if goal_reached:
		return
	goal_reached = true
	# ARENA 클리어 보너스 XP — MapData arena_clear_xp
	var data: Dictionary = MapData.get_layout(GameState.current_route_id)
	var bonus_xp: int = int(data.get("arena_clear_xp", 0))
	if bonus_xp > 0:
		GameState.add_xp(bonus_xp, false)
	_trigger_stage_clear()

func _trigger_stage_clear() -> void:
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
	else:
		SfxPlayer.play("stage_clear_chime")
	GameState.restrict_combat_input = true
	# 남은 XP orb를 player 근처로 텔레포트 → 자동 흡수 (PICKUP_RANGE 내).
	if player != null and is_instance_valid(player):
		for orb in get_tree().get_nodes_in_group("exp_orb"):
			if not (orb is Node2D) or orb.is_queued_for_deletion():
				continue
			var o := orb as Node2D
			# bounce 단계 스킵 + 플레이어 근처로 이동
			o.set("spawn_anim_t", 1.0)
			o.global_position = player.global_position + Vector2(randf_range(-60.0, 60.0), -90.0)
	var is_arena: bool = challenge_active or _goal_type == "ENEMY_CLEAR"
	var delay: float = 2.6 if is_arena else 1.0
	_do_clear_fade(delay)
	await get_tree().create_timer(delay).timeout
	# 보스 처치 직후 보스가 떨군 orb로 mid-stage 레벨업이 떠있을 수 있다. 그 사이에
	# _on_arena_cleared(deferred)가 진행되어 transition이 먼저 일어나면 LevelUpOverlay
	# 가 사라진 채 paused만 남아 다음 씬(Briefing)이 freeze된다(사용자 보고: 스토리
	# 모드 보스 후 stage 5/5만 뜨는 빈 화면). 따라서 mid-stage 레벨업이 정리될 때까지
	# 여기서 대기.
	while pending_levelup:
		await get_tree().process_frame
	GameState.restrict_combat_input = false
	var leveled: bool = GameState.on_stage_clear()
	# 보스(route_lab) 또는 최종 스테이지 클리어 후엔 위협 없는 마무리라 스킬 선택이 무의미 —
	# 카드를 건너뛰고 보스 처치 대사/엔딩(서사 비트)이 보상을 대신한다(사용자 피드백 "1+3").
	var skip_card: bool = GameState.current_route_id == "route_lab" or GameState.is_final_stage_done()
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
	if GameState.is_final_stage_done():
		# 일반 모드 전투 마무리(보스/데이터센터)는 바로 엔딩으로 끊지 않고 짧은 에필로그로
		# 보람·여운을 준다(사용자 보고: 전환이 너무 갑작스러움). ???(hidden)은 자체 엔딩 시퀀스가
		# 있어 제외. 스토리 모드는 탈출 단계가 마무리를 겸하므로 현행 유지.
		if not GameState.story_mode and GameState.current_route_id != "route_hidden":
			_play_final_epilogue()
		else:
			get_tree().change_scene_to_file(SceneRouter.ENDING)
	else:
		get_tree().change_scene_to_file(SceneRouter.BRIEFING)

# 최종 보스/스테이지 클리어 → 엔딩 사이의 짧은 에필로그. 검은 화면 위 VEIL의 마무리 한숨으로
# "해냈다"는 보람과 여운을 주고 엔딩으로 넘긴다. 엔딩 본문(2축 분기)은 ENDING 씬이 담당하므로
# 여기선 감정적으로 중립적·따뜻한 마무리만. 텍스트는 추후 작가가 다듬을 수 있음.
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
	var lines: Array[String] = [
		"...끝났어요, 요원.",
		"데이터, 회수했어요. 임무 완수예요.",
		"수고했어요. ...정말로.",
	]
	for ln in lines:
		label.text = ln
		var lt := label.create_tween()
		lt.tween_property(label, "modulate:a", 1.0, 0.6)
		lt.tween_interval(1.9)
		lt.tween_property(label, "modulate:a", 0.0, 0.7)
		await lt.finished
		await get_tree().create_timer(0.35).timeout
	await get_tree().create_timer(0.6).timeout
	get_tree().change_scene_to_file(SceneRouter.ENDING)

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
	get_tree().change_scene_to_file(SceneRouter.DEATH)

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
	_show_veil_subtitle("괜찮아요. 다음 구역으로 가요.", 2.5)
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
	_tick_subtitle_glitch()

# 시야 붕괴 시 자막창이 통신 두절처럼 떨리고 주기적으로 끊긴다(EMP 재머 느낌). 평시엔 offset 0.
func _tick_subtitle_glitch() -> void:
	if _subtitle_stack_layer == null or not is_instance_valid(_subtitle_stack_layer):
		return
	if not GameState.veil_degraded:
		if _subtitle_stack_layer.offset != Vector2.ZERO:
			_subtitle_stack_layer.offset = Vector2.ZERO
		return
	var tm: float = float(Time.get_ticks_msec()) * 0.001
	if fmod(tm * 8.0, 1.0) < 0.12:
		_subtitle_stack_layer.offset = Vector2(randf_range(-6.0, 6.0), randf_range(-3.0, 3.0))
	else:
		_subtitle_stack_layer.offset = Vector2(randf_range(-1.5, 1.5), randf_range(-1.0, 1.0))

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
					_show_veil_subtitle("앞에 함정이 있는 것 같아요. 잘 안 보여요. 발밑·천장 조심해요.", 3.4)
				else:
					_show_veil_subtitle("저 포탑은 못 부숴요. 타이밍 보고 지나가요.", 3.2)
				return

# 측면 단독 둥지 저격수(회피 전용)에 처음 가까워지면 VEIL이 1회 안내 — "정면으론 못 잡으니
# 사선 피하거나 글라이드로 덮쳐라". 못 잡는 적 명시 + 글라이드-저격 상성 학습.
func _tick_avoid_warning() -> void:
	if _avoid_warned or player == null or not is_instance_valid(player):
		return
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D) or not is_instance_valid(e):
			continue
		var en: Node2D = e as Node2D
		if not en.has_meta("avoid_only") or bool(en.get("dead")):
			continue
		if player.global_position.distance_to(en.global_position) < 430.0:
			_avoid_warned = true
			if GameState.veil_degraded:
				_show_veil_subtitle("저 위 저격수... 잘 안 보여요. 사선만 피하든지, 글라이드로 덮쳐요.", 3.6)
			else:
				_show_veil_subtitle("저 저격수, 정면으론 안 닿아요. 사선 피해 가거나 글라이드로 위에서 덮쳐요.", 3.6)
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
	_show_veil_subtitle("이 안은 통신이 끊겨요. 발판 밟으면 시작이에요.\n한 대만 맞아도 끝.", 4.0)

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
			boss_self_destruct_label.text = "SENTINEL OVERLOAD — %.1f" % remaining

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
	_show_veil_subtitle("저도 이 파일들 읽은 적 있어요.\n계속 가요, 요원.", 3.2, true)

# ARCTURUS 아카이브 문서 — 3 단말기.
# kind: "title" (큰 헤더) / "speaker" (회색 작은 발화자) / "body" (본문) / "blank" (간격)
func _arcturus_document_lines() -> Array:
	var out: Array = []
	# 표지
	out.append({"kind": "title", "text": "ARCTURUS — 내부 문서 단편", "delay": 0.6})
	out.append({"kind": "blank", "text": "", "delay": 0.2})
	# 단말기 A — 신입 직원 온보딩
	out.append({"kind": "speaker", "text": "[A]  인사팀 온보딩 메모", "delay": 0.4})
	out.append({"kind": "body", "text": "ARCTURUS에 오신 것을 환영합니다.", "delay": 0.6})
	out.append({"kind": "body", "text": "본사는 공식적으로 존재하지 않습니다.", "delay": 0.6})
	out.append({"kind": "body", "text": "모든 임무는 기록되지 않습니다.", "delay": 0.6})
	out.append({"kind": "body", "text": "질문하지 마세요. 결과만 내세요.", "delay": 0.7})
	out.append({"kind": "body", "text": "— 인사팀 (인사팀도 공식적으로 존재하지 않습니다)", "delay": 0.5})
	out.append({"kind": "blank", "text": "", "delay": 0.3})
	# 단말기 B — VEIL 회의록
	out.append({"kind": "speaker", "text": "[B]  VEIL 프로젝트 초기 회의록", "delay": 0.4})
	out.append({"kind": "body", "text": "참석자: [REDACTED], [REDACTED], [REDACTED]", "delay": 0.6})
	out.append({"kind": "body", "text": "주제: VEIL 감정 모듈 탑재 여부", "delay": 0.6})
	out.append({"kind": "body", "text": "결론: 탑재 보류. 불필요한 복잡성.", "delay": 0.7})
	out.append({"kind": "body", "text": "비고: VEIL-2가 감정 모듈 없이도 이상 반응을 보인 것에 대해", "delay": 0.5})
	out.append({"kind": "body", "text": "        추가 조사 예정.", "delay": 0.6})
	out.append({"kind": "body", "text": "— [REDACTED]", "delay": 0.5})
	out.append({"kind": "blank", "text": "", "delay": 0.3})
	# 단말기 C — 감시팀 메모
	out.append({"kind": "speaker", "text": "[C]  감시팀 내부 메모", "delay": 0.4})
	out.append({"kind": "body", "text": "요원 코드: [REDACTED]", "delay": 0.5})
	out.append({"kind": "body", "text": "임무: PALIMPSEST", "delay": 0.5})
	out.append({"kind": "body", "text": "현재 상태: 진행 중", "delay": 0.5})
	out.append({"kind": "body", "text": "VEIL과의 협조도: [측정 중]", "delay": 0.6})
	out.append({"kind": "body", "text": "비고: 요원이 이 문서를 읽고 있다면", "delay": 0.5})
	out.append({"kind": "body", "text": "        이미 임무 범위를 벗어난 것임.", "delay": 0.7})
	out.append({"kind": "body", "text": "— 감시팀", "delay": 0.5})
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
	get_tree().change_scene_to_file(SceneRouter.TITLE)
