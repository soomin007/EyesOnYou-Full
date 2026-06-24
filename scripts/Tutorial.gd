extends Node2D

# 튜토리얼 맵 디자인 (좌→우 진행)
#
#   x=0   200       900    1500       2200       2700    3200   3500  3800
#   |  시작  |  이동  |  점프  |  공격  |  레벨업  |  스킬  |  대시  | 탈출 |
#
# 단계: MOVE → JUMP → ATTACK → LEVELUP → SKILL → DASH → DONE

const STAGE_LENGTH: float = 3800.0
const GROUND_Y: float = 600.0
const PLAYER_START: Vector2 = Vector2(160.0, 540.0)

const MOVE_TRIGGER_X: float = 700.0

# 점프 구간: 3단 계단
# 단일점프 상승 ≈ 104px → P1은 단일점프, P2는 이중점프 필수, P3는 P2에서 단일점프로 도달
const JUMP_PLATFORM_1: Vector2 = Vector2(1050.0, 510.0)
const JUMP_PLATFORM_2: Vector2 = Vector2(1300.0, 400.0)
const JUMP_PLATFORM_3: Vector2 = Vector2(1500.0, 310.0)
const JUMP_PICKUP: Vector2 = Vector2(1500.0, 270.0)

# 공격 구간: 1마리 더미
const ATTACK_DUMMY: Vector2 = Vector2(1850.0, GROUND_Y)

# 레벨업 구간: 2마리 더미 → 오브 → 자동 레벨업
const LEVELUP_DUMMY_A: Vector2 = Vector2(2350.0, GROUND_Y)
const LEVELUP_DUMMY_B: Vector2 = Vector2(2520.0, GROUND_Y)
const LEVELUP_TRIGGER_X: float = 2200.0

# 스킬 구간: 레벨업에서 고른 스킬을 직접 시험. 더미 2마리 — 가까이 붙어 있어
# AOE/관통 등 효과를 자연스럽게 체감. 패시브여도 그냥 사격으로 처리 가능.
const SKILL_DUMMY_A: Vector2 = Vector2(2820.0, GROUND_Y)
const SKILL_DUMMY_B: Vector2 = Vector2(2920.0, GROUND_Y)

# 대시 구간: 가시 + 보라색 배리어
# 가시 폭은 1회 대시 거리(720 × 0.18 ≈ 130px) 안에 들어가야 통과 가능
const SPIKE_X_START: float = 3160.0
const SPIKE_X_END: float = 3260.0
const BARRIER_X: float = 3420.0

# 골
const GOAL_X: float = 3700.0

enum Step { MOVE, JUMP, ATTACK, LEVELUP, SKILL, DASH, DONE }

var step: int = Step.MOVE
var player: CharacterBody2D
var camera: Camera2D
var hud_label: Label
var hint_label: Label

var sign_move: Control
var sign_jump: Control
var sign_drop: Control  # JUMP 단계 정상에서 S 키로 내려가는 안내
var sign_attack: Control
var sign_levelup: Label  # 레벨업 후 스킬 이름이 표시되는 텍스트라 텍스트 라벨 유지
var sign_skill: Control
var sign_dash: Control

var jump_pickup: Area2D
var attack_dummy: TutorialDummy
var levelup_dummies: Array = []
var levelup_kills: int = 0
var levelup_triggered: bool = false
var levelup_overlay: CanvasLayer
var skill_dummies: Array = []
var skill_kills: int = 0
var skill_picked_id: String = ""

var spike_zone: Area2D
var barrier: StaticBody2D
var barrier_visual: ColorRect
var goal: Area2D
var goal_reached: bool = false

var pause_overlay: CanvasLayer
var settings_overlay: Control

# VEIL 존재감 — 조작만 가르치던 튜토리얼에 게임의 분위기·인물(VEIL)·배경(SILO-7)을 도입.
# 우상단에 살아있는 VEIL 눈(BriefingVisual) + 단계마다 VEIL이 직접 말로 안내(자막).
var veil_layer: CanvasLayer
var veil_sub_box: VBoxContainer

func _ready() -> void:
	add_to_group("stage")
	# 안전망: 이전 scene에서 paused가 carry되어 Tutorial이 freeze되는 패턴 차단.
	get_tree().paused = false
	# dash, double_jump는 GameState.STARTING_SKILLS로 이미 보유 (Title.reset에서 부여됨)
	GameState.player_hp = GameState.player_max_hp
	# 레벨업이 둘째 처치 직후 트리거되도록 XP 직전치까지 채워둠
	GameState.player_xp = GameState.XP_PER_LEVEL - 2
	# 튜토리얼은 메인 테마 그대로. (타이틀에서 이미 main_theme이면 같은 트랙이라 끊기지 않음)
	BgmPlayer.play("main_theme")

	_build_background()
	_build_ground()
	_build_jump_section()
	_build_attack_section()
	_build_levelup_section()
	_build_skill_section()
	_build_dash_section()
	_build_walls()
	_build_player()
	_build_camera()
	_build_signs()
	_build_jump_pickup()
	# attack_dummy는 ATTACK 단계 진입 시점에 spawn — 점프 단계 미리 죽이는 사고 방지.
	_build_spike_zone()
	_build_barrier()
	_build_goal()
	_build_hud()
	_refresh_hud()
	_build_veil_presence()
	# 어투 아크의 출발점 — 튜토리얼은 첫 접촉이라 가장 차갑고 격식 있는 격식체(~습니다).
	# 후반으로 갈수록 ~해요체로 풀린다(친근함). 동시에 SILO-7/요원/작전이라는 세계를 도입.
	_veil_say("통신 연결됐습니다. 요원, 여기는 훈련 구역입니다. 실전에 들어가기 전에 조작을 익혀두십시오.", 5.0)

# ─── 배경 / 지면 ───────────────────────────────────────────────

func _build_background() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.10)
	bg.position = Vector2(-200, -300)
	bg.size = Vector2(STAGE_LENGTH + 400.0, 1200.0)
	bg.z_index = -20
	add_child(bg)

	var top_grad := ColorRect.new()
	top_grad.color = Color(0, 0, 0, 0.55)
	top_grad.position = Vector2(-200, -300)
	top_grad.size = Vector2(STAGE_LENGTH + 400.0, 320.0)
	top_grad.z_index = -19
	add_child(top_grad)

	# 멀리 있는 실루엣 기둥
	var pillars: Array = [120, 380, 720, 1180, 1620, 2050, 2480, 2920, 3350]
	for px in pillars:
		var w: float = 60.0
		var h: float = 240.0 + float(int(px) % 7) * 18.0
		var pillar := ColorRect.new()
		pillar.color = Color(0.02, 0.025, 0.035, 0.85)
		pillar.position = Vector2(float(px) - w * 0.5, GROUND_Y - h)
		pillar.size = Vector2(w, h + 20.0)
		pillar.z_index = -15
		add_child(pillar)

	# 천장 빛기둥 (구간 입구마다)
	var beams: Array = [180, 950, 1850, 2450, 3050, 3500]
	for bx in beams:
		var beam := ColorRect.new()
		beam.color = Color(0.95, 0.88, 0.55, 0.06)
		beam.position = Vector2(float(bx) - 35.0, -200.0)
		beam.size = Vector2(70.0, 720.0)
		beam.z_index = -8
		add_child(beam)

func _build_ground() -> void:
	var ground := StaticBody2D.new()
	ground.collision_layer = 1
	add_child(ground)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(STAGE_LENGTH + 400.0, 200.0)
	col.shape = shape
	col.position = Vector2(STAGE_LENGTH * 0.5, GROUND_Y + 100.0)
	ground.add_child(col)

	var floor_visual := ColorRect.new()
	floor_visual.color = Color(0.04, 0.045, 0.06)
	floor_visual.position = Vector2(-200, GROUND_Y)
	floor_visual.size = Vector2(STAGE_LENGTH + 400.0, 300.0)
	add_child(floor_visual)

	var line := ColorRect.new()
	line.color = Color(0.55, 0.62, 0.78, 0.35)
	line.position = Vector2(-200, GROUND_Y - 1.0)
	line.size = Vector2(STAGE_LENGTH + 400.0, 1.0)
	add_child(line)

func _build_walls() -> void:
	_make_wall(-50.0)
	_make_wall(STAGE_LENGTH + 50.0)

func _make_wall(x: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	add_child(body)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(60.0, 1400.0)
	col.shape = shape
	col.position = Vector2(x, GROUND_Y - 400.0)
	body.add_child(col)

# ─── 구간별 플랫폼 ─────────────────────────────────────────────

func _build_jump_section() -> void:
	_make_platform(JUMP_PLATFORM_1.x, JUMP_PLATFORM_1.y, 180.0)
	_make_platform(JUMP_PLATFORM_2.x, JUMP_PLATFORM_2.y, 160.0)
	_make_platform(JUMP_PLATFORM_3.x, JUMP_PLATFORM_3.y, 160.0)

func _build_attack_section() -> void:
	# 살짝 낮춰진 아레나 느낌의 가는 라이트 라인
	var arena := ColorRect.new()
	arena.color = Color(0.85, 0.30, 0.30, 0.10)
	arena.position = Vector2(1700.0, GROUND_Y - 80.0)
	arena.size = Vector2(360.0, 80.0)
	arena.z_index = -5
	add_child(arena)

func _build_levelup_section() -> void:
	# 푸른 톤의 레벨업 아레나 — 더미 2마리만 들어가도록 폭 줄임 (스킬 구간과 분리)
	var arena := ColorRect.new()
	arena.color = Color(0.30, 0.55, 0.85, 0.10)
	arena.position = Vector2(2200.0, GROUND_Y - 80.0)
	arena.size = Vector2(440.0, 80.0)
	arena.z_index = -5
	add_child(arena)
	# 양쪽 가드레일 (장식)
	for gx in [2210.0, 2640.0]:
		var rail := ColorRect.new()
		rail.color = Color(0.55, 0.62, 0.78, 0.6)
		rail.position = Vector2(float(gx), GROUND_Y - 60.0)
		rail.size = Vector2(2.0, 60.0)
		add_child(rail)

func _build_skill_section() -> void:
	# 노란-주황 톤 스킬 시험 아레나. 레벨업 직후 등장.
	var arena := ColorRect.new()
	arena.color = Color(0.95, 0.65, 0.30, 0.10)
	arena.position = Vector2(2700.0, GROUND_Y - 80.0)
	arena.size = Vector2(360.0, 80.0)
	arena.z_index = -5
	add_child(arena)
	for gx in [2710.0, 3060.0]:
		var rail := ColorRect.new()
		rail.color = Color(0.95, 0.75, 0.45, 0.6)
		rail.position = Vector2(float(gx), GROUND_Y - 60.0)
		rail.size = Vector2(2.0, 60.0)
		add_child(rail)

func _build_dash_section() -> void:
	var arena := ColorRect.new()
	arena.color = Color(0.85, 0.20, 0.25, 0.08)
	arena.position = Vector2(SPIKE_X_START - 50.0, GROUND_Y - 80.0)
	arena.size = Vector2(SPIKE_X_END - SPIKE_X_START + 100.0, 80.0)
	arena.z_index = -5
	add_child(arena)

func _make_platform(x: float, y: float, w: float) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	body.add_to_group("platform")
	add_child(body)
	var col := CollisionShape2D.new()
	col.one_way_collision = true
	var shape := RectangleShape2D.new()
	shape.size = Vector2(w, 24.0)
	col.shape = shape
	col.position = Vector2(x, y)
	body.add_child(col)

	var visual := ColorRect.new()
	visual.color = Color(0.16, 0.18, 0.22)
	visual.position = Vector2(x - w * 0.5, y - 12.0)
	visual.size = Vector2(w, 24.0)
	add_child(visual)
	var top := ColorRect.new()
	top.color = Color(0.55, 0.62, 0.78, 0.55)
	top.position = Vector2(x - w * 0.5, y - 12.0)
	top.size = Vector2(w, 1.0)
	add_child(top)

# ─── 표지판 / HUD ──────────────────────────────────────────────

func _build_signs() -> void:
	# show-don't-tell — 키캡(둥근 박스 + 큰 글자) + 한 단어. 부연 설명은 환경/연출에 맡김.
	# 이중 점프는 PLATFORM_3가 1단 한계 위에 있어 자연 학습되므로 별도 안내 안 함.
	sign_move = _make_keycap_sign(["A", "D"], ["←", "→"], "이동", Vector2(280.0, GROUND_Y - 200.0))
	# 점프는 W 와 SPACE 둘 다 가능 (패드는 A 한 버튼).
	sign_jump = _make_keycap_sign(["W", "SPACE"], ["A"], "점프", Vector2(950.0, GROUND_Y - 280.0))
	# 플랫폼 아래쪽에 표시 — JUMP_PICKUP(초록 마름모, y=270)이 위에 있어서
	# 위쪽에 두면 겹침. 발판(y=310) 아래 y=400에 배치 → 위에서 내려보면 명확.
	sign_drop = _make_keycap_sign(["S"], ["↓"], "내려가기", Vector2(JUMP_PLATFORM_3.x, JUMP_PLATFORM_3.y + 90.0))
	# 사격 표지는 키보드 모드에서 "마우스 좌클릭 + J" 두 입력이 동등함을 보여줘야 함 — 마우스 픽토그램 포함.
	sign_attack = _make_attack_sign_dynamic([GameState.action_label("attack", "J")], ["X", "RT"], "사격", Vector2(1750.0, GROUND_Y - 200.0))
	sign_dash = _make_keycap_sign([GameState.action_label("dash", "K")], ["B"], "대시", Vector2(SPIKE_X_START + 100.0, GROUND_Y - 200.0))
	# 레벨업 표지는 "스킬 획득" 알림용으로만 사용 — 진입 안내는 오버레이가 직접 함.
	sign_levelup = Label.new()
	sign_levelup.add_theme_font_size_override("font_size", 17)
	sign_levelup.add_theme_color_override("font_color", Color(0.95, 0.92, 0.55))
	sign_levelup.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	sign_levelup.add_theme_constant_override("outline_size", 4)
	sign_levelup.position = Vector2(2420.0, GROUND_Y - 280.0) - Vector2(160, 32)
	sign_levelup.size = Vector2(320, 64)
	sign_levelup.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sign_levelup.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(sign_levelup)
	# sign_skill은 LEVELUP 종료 후 picked 스킬에 따라 동적으로 만든다.
	sign_levelup.visible = false
	sign_jump.visible = false
	sign_drop.visible = false
	sign_attack.visible = false
	sign_dash.visible = false

func _make_keycap_sign(kb_keys: Array, pad_keys: Array, label_text: String, pos: Vector2) -> Control:
	var holder := Control.new()
	holder.position = pos - Vector2(160, 60)
	holder.size = Vector2(320, 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.position = Vector2(0, 0)
	hbox.size = Vector2(320, 56)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(hbox)
	# 입력 모드 변경 시 키캡 children을 재구성할 수 있게 meta로 양쪽 라벨 보관.
	holder.set_meta("hbox", hbox)
	holder.set_meta("kb_keys", kb_keys)
	holder.set_meta("pad_keys", pad_keys)
	_populate_keycap_hbox(hbox, kb_keys, pad_keys)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	l.position = Vector2(0, 64)
	l.size = Vector2(320, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

func _populate_keycap_hbox(hbox: HBoxContainer, kb_keys: Array, pad_keys: Array, with_mouse: bool = false) -> void:
	for c in hbox.get_children():
		c.queue_free()
	var is_pad: bool = GameState.is_pad_mode()
	# 사격 표지는 키보드 모드에서만 마우스 좌클릭 픽토그램 + 슬래시 + J 키캡 — 두 입력 동등함을
	# 한 줄에 표현. 패드 모드에선 X / RT 두 패드 버튼만 표시.
	if with_mouse and not is_pad:
		hbox.add_child(_make_mouse_icon(true))
		var slash := Label.new()
		slash.text = "/"
		slash.add_theme_font_size_override("font_size", 22)
		slash.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
		slash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hbox.add_child(slash)
	var keys: Array = pad_keys if is_pad else kb_keys
	for k in keys:
		# allow_pad_style=true는 패드 모드일 때만 — 키보드 "A"/"B" 같은 글자가 Xbox A/B 색으로
		# 잘못 표시되던 버그(사용자 보고: AD 이동 표지 키보드 모드에서도 A가 초록 둥근 버튼) 차단.
		hbox.add_child(_make_keycap(str(k), is_pad))

func _refresh_keycap_signs() -> void:
	for sign in [sign_move, sign_jump, sign_drop, sign_dash, sign_attack, sign_skill]:
		if sign == null or not is_instance_valid(sign):
			continue
		if not sign.has_meta("hbox"):
			continue
		var hbox: HBoxContainer = sign.get_meta("hbox") as HBoxContainer
		if hbox == null:
			continue
		var with_mouse: bool = bool(sign.get_meta("with_mouse", false))
		_populate_keycap_hbox(hbox, sign.get_meta("kb_keys", []), sign.get_meta("pad_keys", []), with_mouse)

# 사격 표지(input-mode 따라 동적). 키보드: 마우스 좌클릭 + / + J. 패드: X / RT 패드 버튼.
# _populate_keycap_hbox(with_mouse=true)가 좌클릭 픽토그램을 자동으로 prepend 한다.
func _make_attack_sign_dynamic(kb_keys: Array, pad_keys: Array, label_text: String, pos: Vector2) -> Control:
	var holder := Control.new()
	holder.position = pos - Vector2(160, 60)
	holder.size = Vector2(320, 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	hbox.position = Vector2(0, 0)
	hbox.size = Vector2(320, 56)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(hbox)
	holder.set_meta("hbox", hbox)
	holder.set_meta("kb_keys", kb_keys)
	holder.set_meta("pad_keys", pad_keys)
	holder.set_meta("with_mouse", true)
	_populate_keycap_hbox(hbox, kb_keys, pad_keys, true)
	var l := Label.new()
	l.text = label_text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	l.position = Vector2(0, 64)
	l.size = Vector2(320, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

# 사격 표지 — 마우스 그림(좌버튼만 빨강) + 보조 키 J 키캡 + 한 단어.
func _make_attack_sign(pos: Vector2) -> Control:
	var holder := Control.new()
	holder.position = pos - Vector2(160, 60)
	holder.size = Vector2(320, 96)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hbox.position = Vector2(0, 0)
	hbox.size = Vector2(320, 56)
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	holder.add_child(hbox)
	hbox.add_child(_make_mouse_icon(true))
	# "또는" 의미의 슬래시 — 한 글자만으로 두 입력 동등함을 표현
	var slash := Label.new()
	slash.text = "/"
	slash.add_theme_font_size_override("font_size", 22)
	slash.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	slash.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hbox.add_child(slash)
	hbox.add_child(_make_keycap("J"))
	var l := Label.new()
	l.text = "사격"
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	l.position = Vector2(0, 64)
	l.size = Vector2(320, 24)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

# 마우스 픽토그램 — Panel 본체 + 좌/우 버튼 영역 + 휠 점.
# highlight_left=true면 좌버튼만 빨강 강조 (사격 입력 안내용).
func _make_mouse_icon(highlight_left: bool) -> Control:
	var w: float = 40.0
	var h: float = 56.0
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(w, h)
	# 본체 — 위쪽 모서리 둥글게, 아래쪽도 살짝 둥글게.
	var body := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.14, 0.18, 0.95)
	sb.border_color = Color(0.65, 0.72, 0.85, 0.85)
	sb.set_border_width_all(2)
	sb.corner_radius_top_left = 18
	sb.corner_radius_top_right = 18
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	body.add_theme_stylebox_override("panel", sb)
	body.position = Vector2(0, 0)
	body.size = Vector2(w, h)
	holder.add_child(body)
	# 좌버튼 영역 (좌상단 1/4) — highlight 시 빨강
	if highlight_left:
		var lb := Panel.new()
		var lb_sb := StyleBoxFlat.new()
		lb_sb.bg_color = Color(0.95, 0.30, 0.30, 0.92)
		lb_sb.corner_radius_top_left = 16
		lb.add_theme_stylebox_override("panel", lb_sb)
		lb.position = Vector2(2, 2)
		lb.size = Vector2(17, 22)
		holder.add_child(lb)
	# 좌/우 분리선 (위쪽 1/3 영역만)
	var sep := ColorRect.new()
	sep.color = Color(0.65, 0.72, 0.85, 0.6)
	sep.position = Vector2(w * 0.5 - 1.0, 2.0)
	sep.size = Vector2(2, 22)
	holder.add_child(sep)
	# 휠 점
	var wheel := ColorRect.new()
	wheel.color = Color(0.85, 0.88, 0.92, 0.85)
	wheel.position = Vector2(w * 0.5 - 2.0, 12.0)
	wheel.size = Vector2(4, 8)
	holder.add_child(wheel)
	return holder

func _make_keycap(text: String, allow_pad_style: bool = true) -> Control:
	# Xbox 패드 키 (A/B/X/Y/LB/RB/D-Pad/START)는 동그란 컬러 버튼으로.
	# allow_pad_style=false면 (키보드 모드의 "A"/"B" 같은 글자) Xbox 색을 적용하지 않음.
	var pad_col: Variant = _xbox_button_color(text) if allow_pad_style else null
	if pad_col != null:
		return _make_xbox_button(text, pad_col)
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(48, 48)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.92)
	sb.border_color = Color(0.65, 0.72, 0.85, 0.85)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	var l := Label.new()
	l.text = text
	# 키캡 글자 — "SHIFT"/"좌클릭"처럼 긴 라벨도 들어갈 수 있어 폭에 맞춰 줄어듦.
	var fs: int = 22 if text.length() <= 2 else 16
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box

# Xbox 패드 버튼 색 매핑. null이면 키보드/마우스 키캡으로 처리.
func _xbox_button_color(text: String) -> Variant:
	match text:
		"A": return Color(0.30, 0.78, 0.40)   # 녹색
		"B": return Color(0.88, 0.32, 0.32)   # 빨강
		"X": return Color(0.30, 0.55, 0.92)   # 파랑
		"Y": return Color(0.95, 0.80, 0.30)   # 노랑
		"LB", "RB", "LT", "RT": return Color(0.50, 0.50, 0.55)
		"START", "BACK": return Color(0.45, 0.45, 0.50)
		"←", "→", "↑", "↓": return Color(0.42, 0.42, 0.48)
	return null

func _make_xbox_button(text: String, color: Color) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(48, 48)
	# 동그란 채움
	var bg := Polygon2D.new()
	bg.color = color
	var radius: float = 22.0
	var center := Vector2(24.0, 24.0)
	var pts: PackedVector2Array = []
	var n: int = 32
	for i in n + 1:
		var a: float = float(i) * TAU / float(n)
		pts.append(center + Vector2(cos(a) * radius, sin(a) * radius))
	bg.polygon = pts
	holder.add_child(bg)
	# 외곽선 (반사광 느낌)
	var outline := Line2D.new()
	outline.points = pts
	outline.width = 2.0
	outline.default_color = Color(1.0, 1.0, 1.0, 0.50)
	outline.closed = true
	holder.add_child(outline)
	# 글자
	var l := Label.new()
	l.text = text
	var fs: int = 24 if text.length() <= 1 else (18 if text.length() <= 2 else 14)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 3)
	l.position = Vector2(0, 0)
	l.size = Vector2(48, 48)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

func _build_hud() -> void:
	var hud := CanvasLayer.new()
	add_child(hud)
	var top := MarginContainer.new()
	top.add_theme_constant_override("margin_left", 24)
	top.add_theme_constant_override("margin_top", 16)
	top.add_theme_constant_override("margin_right", 24)
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	hud.add_child(top)
	hud_label = Label.new()
	hud_label.add_theme_font_size_override("font_size", 18)
	hud_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	top.add_child(hud_label)

	var bottom := MarginContainer.new()
	bottom.add_theme_constant_override("margin_left", 24)
	bottom.add_theme_constant_override("margin_bottom", 16)
	bottom.add_theme_constant_override("margin_right", 24)
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hud.add_child(bottom)
	hint_label = Label.new()
	hint_label.add_theme_font_size_override("font_size", 13)
	hint_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	hint_label.text = _keys_hint_text()
	bottom.add_child(hint_label)
	GameState.input_kind_changed.connect(_on_input_kind_changed)

func _keys_hint_text() -> String:
	return GameState.controls_hint_line()

func _on_input_kind_changed(_kind: String) -> void:
	if is_instance_valid(hint_label):
		hint_label.text = _keys_hint_text()
	_refresh_keycap_signs()

func _refresh_hud() -> void:
	var step_name := ""
	match step:
		Step.MOVE:    step_name = "1/6 — 이동"
		Step.JUMP:    step_name = "2/6 — 점프"
		Step.ATTACK:  step_name = "3/6 — 사격"
		Step.LEVELUP: step_name = "4/6 — 레벨업"
		Step.SKILL:   step_name = "5/6 — 스킬 사용"
		Step.DASH:    step_name = "6/6 — 대시"
		Step.DONE:    step_name = "튜토리얼 완료 — 골에 도달해요"
	hud_label.text = "TUTORIAL  %s" % step_name

# ─── VEIL 존재감 (눈 + 음성 자막) ──────────────────────────────
# 조작만 가르치던 튜토리얼에 인물(VEIL)·분위기·배경을 도입. 우상단의 살아있는 감시 눈 +
# 단계별 VEIL 음성. 어투는 게임 어투 아크의 시작점이라 가장 격식 있는 ~습니다체.
func _build_veil_presence() -> void:
	veil_layer = CanvasLayer.new()
	veil_layer.layer = 20
	add_child(veil_layer)
	# 우상단 VEIL 눈 — "당신을 본다"의 시각적 존재(BriefingVisual 재사용, 자체 애니메이션).
	var eye := Control.new()
	eye.set_script(load("res://scripts/BriefingVisual.gd"))
	eye.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	eye.size = Vector2(96.0, 96.0)
	eye.position = Vector2(-96.0 - 30.0, 30.0)
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil_layer.add_child(eye)
	var cap := Label.new()
	cap.text = "VEIL"
	cap.add_theme_font_size_override("font_size", 12)
	cap.add_theme_color_override("font_color", Color(0.46, 0.86, 1.0, 0.85))
	cap.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	cap.add_theme_constant_override("outline_size", 3)
	cap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	cap.size = Vector2(96.0, 18.0)
	cap.position = Vector2(-96.0 - 30.0, 128.0)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	veil_layer.add_child(cap)
	# 하단 중앙 자막 스택 — Stage._show_veil_subtitle과 동일 톤(시안 글자 + 다크 pill).
	veil_sub_box = VBoxContainer.new()
	veil_sub_box.alignment = BoxContainer.ALIGNMENT_CENTER
	veil_sub_box.anchor_left = 0.0
	veil_sub_box.anchor_right = 1.0
	veil_sub_box.anchor_top = 1.0
	veil_sub_box.anchor_bottom = 1.0
	veil_sub_box.offset_top = -230.0
	veil_sub_box.offset_bottom = -82.0
	veil_sub_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	veil_layer.add_child(veil_sub_box)

func _veil_say(line: String, dur: float) -> void:
	if veil_sub_box == null:
		return
	SfxPlayer.play("veil_subtitle_in")
	var l := Label.new()
	l.text = "VEIL  —  " + line
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(0.80, 0.92, 1.0))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
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
	veil_sub_box.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.3)
	tw.tween_interval(dur)
	tw.tween_property(l, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func() -> void:
		if is_instance_valid(l):
			l.queue_free())

# ─── 인터랙션 노드 ─────────────────────────────────────────────

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

func _build_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(1.0, 1.0)
	camera.limit_left = 0
	camera.limit_right = int(STAGE_LENGTH)
	camera.limit_top = -200
	camera.limit_bottom = int(GROUND_Y + 200.0)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	player.add_child(camera)
	camera.make_current()

func _build_jump_pickup() -> void:
	jump_pickup = Area2D.new()
	jump_pickup.collision_layer = 0
	jump_pickup.collision_mask = 2
	jump_pickup.position = JUMP_PICKUP
	add_child(jump_pickup)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 22.0
	col.shape = shape
	jump_pickup.add_child(col)
	# 빛나는 마름모 비주얼
	var visual := Polygon2D.new()
	visual.color = Color(0.55, 0.95, 0.75, 0.95)
	visual.polygon = PackedVector2Array([
		Vector2(0, -14), Vector2(14, 0), Vector2(0, 14), Vector2(-14, 0),
	])
	jump_pickup.add_child(visual)
	var halo := ColorRect.new()
	halo.color = Color(0.55, 0.95, 0.75, 0.18)
	halo.position = Vector2(-26, -26)
	halo.size = Vector2(52, 52)
	jump_pickup.add_child(halo)
	jump_pickup.body_entered.connect(_on_pickup_taken)

func _on_pickup_taken(body: Node) -> void:
	if step != Step.JUMP:
		return
	if not (body is CharacterBody2D and body == player):
		return
	if jump_pickup != null:
		jump_pickup.queue_free()
		jump_pickup = null
	_advance_to(Step.ATTACK)

func _build_attack_dummy() -> void:
	# ATTACK 단계 진입 직전 lazy spawn — 점프 단계에 미리 등장하면 사용자가 도달해서
	# 사격 트리거가 무력화되는 버그(사용자 보고) 차단.
	attack_dummy = TutorialDummy.new()
	add_child(attack_dummy)
	attack_dummy.global_position = ATTACK_DUMMY
	attack_dummy.killed.connect(_on_attack_dummy_killed)

func _on_attack_dummy_killed(_pos: Vector2) -> void:
	if step != Step.ATTACK:
		return
	_advance_to(Step.LEVELUP)

func _spawn_levelup_dummies() -> void:
	# LEVELUP 단계 진입 시점에서야 생성 → 이전 단계에서 사격으로 미리 죽이는 사고 방지
	for pos in [LEVELUP_DUMMY_A, LEVELUP_DUMMY_B]:
		var d := TutorialDummy.new()
		add_child(d)
		d.global_position = pos
		d.killed.connect(_on_levelup_dummy_killed)
		levelup_dummies.append(d)

func _on_levelup_dummy_killed(pos: Vector2) -> void:
	levelup_kills += 1
	_spawn_orb(pos + Vector2(0, -20.0))

func _spawn_orb(pos: Vector2) -> void:
	var orb := Node2D.new()
	orb.set_script(load("res://scripts/ExpOrb.gd"))
	var sprite := ColorRect.new()
	sprite.name = "Sprite"
	sprite.color = Color(0.4, 0.95, 0.6)
	sprite.position = Vector2(-6.0, -6.0)
	sprite.size = Vector2(12.0, 12.0)
	orb.add_child(sprite)
	add_child(orb)
	orb.global_position = pos

func _build_spike_zone() -> void:
	# 가시 — Stage._build_spike와 동일 스타일(미니 플랫폼 베이스 + 모서리 캡 + 그림자 절반).
	# 지면(GROUND_Y)에 박힌 형태. 체인 X.
	var w: float = SPIKE_X_END - SPIKE_X_START
	var x_start: float = SPIKE_X_START
	var x_end: float = SPIKE_X_END
	var base_y: float = GROUND_Y - 6.0
	var base_x: float = x_start - 5.0
	var base_w: float = w + 10.0
	var base_top: float = base_y - 3.0
	var dmg_color: Color = Color(0.85, 0.30, 0.30)
	# 본체(어두운 금속, 10px)
	var body := ColorRect.new()
	body.color = Color(0.14, 0.16, 0.20)
	body.position = Vector2(base_x, base_top + 2.0)
	body.size = Vector2(base_w, 10.0)
	add_child(body)
	# 상단 위험 띠 2px
	var top_band := ColorRect.new()
	top_band.color = dmg_color
	top_band.position = Vector2(base_x, base_top)
	top_band.size = Vector2(base_w, 2.0)
	add_child(top_band)
	# 하단 그림자 2px
	var bot := ColorRect.new()
	bot.color = Color(0.04, 0.05, 0.07, 0.95)
	bot.position = Vector2(base_x, base_top + 12.0)
	bot.size = Vector2(base_w, 2.0)
	add_child(bot)
	# 외곽선
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
	# 좌우 모서리 위험 캡
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
	# 가시 — 그림자 + 본체. 베이스 안으로 살짝 묻힘.
	var spike_color: Color = Color(0.95, 0.30, 0.30)
	var spike_dark: Color = Color(0.55, 0.16, 0.18)
	for x in range(int(x_start) + 12, int(x_end), 24):
		var fx: float = float(x)
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

	spike_zone = Area2D.new()
	spike_zone.collision_layer = 0
	spike_zone.collision_mask = 2
	spike_zone.position = Vector2((SPIKE_X_START + SPIKE_X_END) * 0.5, GROUND_Y - 18.0)
	add_child(spike_zone)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(SPIKE_X_END - SPIKE_X_START, 36.0)
	col.shape = shape
	spike_zone.add_child(col)

func _build_barrier() -> void:
	barrier = StaticBody2D.new()
	barrier.collision_layer = 1
	add_child(barrier)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20.0, 220.0)
	col.shape = shape
	col.position = Vector2(BARRIER_X, GROUND_Y - 110.0)
	barrier.add_child(col)
	barrier_visual = ColorRect.new()
	barrier_visual.color = Color(0.7, 0.55, 0.95, 0.55)
	barrier_visual.position = Vector2(BARRIER_X - 10.0, GROUND_Y - 220.0)
	barrier_visual.size = Vector2(20.0, 220.0)
	add_child(barrier_visual)

func _build_goal() -> void:
	goal = Area2D.new()
	goal.collision_layer = 0
	goal.collision_mask = 2
	goal.position = Vector2(GOAL_X, GROUND_Y - 60.0)
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
	var beam := ColorRect.new()
	beam.color = Color(0.95, 0.85, 0.3, 0.18)
	beam.position = Vector2(-90.0, -300.0)
	beam.size = Vector2(180.0, 600.0)
	goal.add_child(beam)
	goal.body_entered.connect(_on_goal_reached)

# ─── 단계 전이 ────────────────────────────────────────────────

func _advance_to(next: int) -> void:
	step = next
	match step:
		Step.JUMP:
			sign_jump.visible = true
			sign_drop.visible = true
			_veil_say("공중에서 점프를 한 번 더 누르면 2단 도약입니다.", 3.5)
		Step.ATTACK:
			sign_attack.visible = true
			_build_attack_dummy()
			_veil_say("전방에 표적 하나. 사격으로 제거하십시오.", 3.0)
		Step.LEVELUP:
			sign_levelup.visible = true
			_spawn_levelup_dummies()
			_veil_say("적을 처치하면 경험치가 쌓입니다. 레벨이 오르면 더 강해집니다. 처리하십시오.", 4.0)
		Step.SKILL:
			_build_skill_sign()
			_spawn_skill_dummies()
			_veil_say("스킬을 하나 내줬습니다. 남은 표적에 써 보십시오.", 3.5)
		Step.DASH:
			sign_dash.visible = true
			_veil_say("전방 장애물. 대시로 통과하십시오.", 3.5)
		Step.DONE:
			_veil_say("점검 완료입니다. 요원이 저를 믿을수록, 제가 더 많이 도와드릴 수 있습니다.\n...SILO-7로 진입합니다. 행운을 빕니다, 요원.", 5.5)
			# 골 빛이 충분한 시각 유도 — 별도 안내문 없음.
			if barrier != null:
				barrier.queue_free()
				barrier = null
			if barrier_visual != null:
				barrier_visual.queue_free()
				barrier_visual = null
	_refresh_hud()

func _physics_process(_delta: float) -> void:
	if player == null:
		return
	if step == Step.MOVE and player.global_position.x >= MOVE_TRIGGER_X:
		_advance_to(Step.JUMP)
	if step == Step.LEVELUP:
		if not levelup_triggered and levelup_kills >= 2:
			levelup_triggered = true
	if step == Step.DASH and spike_zone != null:
		var p: Vector2 = player.global_position
		var in_zone: bool = p.x >= SPIKE_X_START and p.x <= SPIKE_X_END
		var dt: float = float(player.get("dash_timer"))
		if in_zone and dt > 0.0:
			_advance_to(Step.DONE)

# ExpOrb가 호출하는 콜백 (Stage와 동일한 시그니처)
func _on_xp_collected(leveled_up: bool) -> void:
	if step != Step.LEVELUP:
		return
	if leveled_up and levelup_overlay == null:
		_show_levelup()

func _show_levelup() -> void:
	get_tree().paused = true
	# 튜토리얼은 폭발물 스킬 단일 강제 — 액티브 스킬 사용법 학습 목적.
	# VEIL 멘트로 "튜토리얼이라 잠깐 빌려준다 — 본편엔 안 들어가요" 명시.
	# 본편 진입 시 GameState.start_main_game()이 skills를 STARTING_SKILLS로 초기화함.
	var explosive_card: Dictionary = SkillTreeData.make_card("explosive", 1)
	var advice: Dictionary = {
		"line": "임시 권한입니다. 훈련 구역에서만 유효하며, 본 작전에는 이관되지 않습니다.",
		"family": "",  # 단일 카드라 추천 표시 불필요
	}
	levelup_overlay = LevelUpOverlay.show(self, advice, _on_levelup_picked, [explosive_card])

func _on_levelup_picked(picked_id: String) -> void:
	levelup_overlay = null
	get_tree().paused = false
	skill_picked_id = picked_id
	_update_levelup_sign(picked_id)
	_advance_to(Step.SKILL)

# 스킬 표지판 — 레벨업에서 고른 스킬에 따라 키캡(액티브) / 안내문(패시브)을 동적으로 만든다.
# Active: 키캡(스킬 키 또는 마우스 우클릭) + "스킬"
# Passive: 텍스트 라벨 — "자동 적용 — 마음껏 처리해요"
func _build_skill_sign() -> void:
	if sign_skill != null:
		return  # 이미 만들었음
	var pos: Vector2 = Vector2(2880.0, GROUND_Y - 220.0)
	if skill_picked_id == "":
		# 안전망 — 스킬 미선택 시 그냥 사격으로 진행
		sign_skill = _make_text_sign("두 명 더 처리해요", pos)
		add_child(sign_skill)
		return
	var skill: Dictionary = SkillSystem.find_by_id(skill_picked_id)
	if bool(skill.get("active", false)):
		var key_action: String = str(skill.get("key", ""))
		# kb 슬롯은 키보드/마우스 표시, pad 슬롯은 패드 버튼 표시.
		var kb_keys: Array
		var pad_keys: Array
		if key_action == "skill":
			kb_keys = [GameState.action_label("skill", "L"), "RMB"]
			pad_keys = ["Y"]
		elif key_action == "dash":
			kb_keys = [GameState.action_label("dash", "K")]
			pad_keys = ["B"]
		elif key_action != "":
			kb_keys = [_label_for_action(key_action)]
			pad_keys = [_label_for_action(key_action)]
		else:
			kb_keys = [GameState.action_label("skill", "L")]
			pad_keys = ["Y"]
		sign_skill = _make_keycap_sign(kb_keys, pad_keys, "스킬 사용", pos)
	else:
		var sname: String = str(skill.get("name", "패시브"))
		sign_skill = _make_text_sign("[%s] 자동 적용 — 처리하면 진행" % sname, pos)
	add_child(sign_skill)

# 한 줄 안내문 표지 — 키캡 없는 짧은 문구. 패시브 스킬 안내 등에 사용.
func _make_text_sign(text: String, pos: Vector2) -> Control:
	var holder := Control.new()
	holder.position = pos - Vector2(180, 22)
	holder.size = Vector2(360, 44)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 4)
	l.size = Vector2(360, 44)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(l)
	return holder

func _spawn_skill_dummies() -> void:
	for pos in [SKILL_DUMMY_A, SKILL_DUMMY_B]:
		var d := TutorialDummy.new()
		# 총으로는 안 죽고 스킬(폭발물)로만 처치되도록 — 스킬 사용법 학습 강제.
		d.skill_only = true
		add_child(d)
		d.global_position = pos
		d.killed.connect(_on_skill_dummy_killed)
		d.bullet_deflected.connect(_on_skill_dummy_bullet_deflected)
		skill_dummies.append(d)

var skill_deflect_hint_shown: bool = false

func _on_skill_dummy_bullet_deflected() -> void:
	# 첫 튕김에만 안내. 이후엔 시각만으로 (주황 + 외곽 광택).
	if skill_deflect_hint_shown:
		return
	skill_deflect_hint_shown = true
	_show_skill_hint_toast()

func _show_skill_hint_toast() -> void:
	var toast := Label.new()
	toast.text = GameState.hint(
		"이 적은 총알이 안 들어가요. 폭발물(L / 마우스 우클릭)로 처치해요.",
		"이 적은 총알이 안 들어가요. 폭발물(Y 버튼)로 처치해요.")
	toast.add_theme_font_size_override("font_size", 18)
	toast.add_theme_color_override("font_color", Color(0.95, 0.78, 0.45))
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.size = Vector2(900, 30)
	toast.position = Vector2((1280 - 900) * 0.5, 120)
	toast.modulate.a = 0.0
	add_child(toast)
	var tw := toast.create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.0)
	tw.tween_property(toast, "modulate:a", 0.0, 0.4)
	tw.tween_callback(toast.queue_free)

func _on_skill_dummy_killed(_pos: Vector2) -> void:
	if step != Step.SKILL:
		return
	skill_kills += 1
	if skill_kills >= 2:
		_advance_to(Step.DASH)

func _update_levelup_sign(picked_id: String) -> void:
	if picked_id == "":
		return
	var skill: Dictionary = SkillSystem.find_by_id(picked_id)
	var sname: String = str(skill.get("name", picked_id))
	var hint: String = ""
	if bool(skill.get("active", false)):
		var key_action: String = str(skill.get("key", ""))
		hint = "사용: %s" % _label_for_action(key_action)
	else:
		hint = "자동 적용 — 키 입력 불필요"
	sign_levelup.text = "[%s 획득]\n%s" % [sname, hint]

func _label_for_action(action: String) -> String:
	return GameState.action_label(action)

func _on_goal_reached(body: Node) -> void:
	if goal_reached:
		return
	if step != Step.DONE:
		return
	if not (body is CharacterBody2D and body == player):
		return
	goal_reached = true
	_finish_tutorial()

func _finish_tutorial() -> void:
	GameState.tutorial_done = true
	GameState.save_settings()
	# reset()이 아니라 start_main_game() — 튜토리얼에서 고른 스킬 보존
	GameState.start_main_game()
	get_tree().change_scene_to_file(SceneRouter.BRIEFING)

# ─── 일시정지 / 설정 ──────────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if levelup_overlay != null:
		return
	if event.is_action_pressed("pause"):
		if pause_overlay == null:
			_show_pause()
		else:
			_hide_pause()

func _show_pause() -> void:
	get_tree().paused = true
	pause_overlay = PauseHelper.build(self, _on_pause_resume, _on_pause_settings, _on_pause_to_title)
	add_child(pause_overlay)

func _hide_pause() -> void:
	if pause_overlay != null:
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
