class_name CoreTunnel
extends Control

# 14-2 코어 대면 — 2.5D 유사 1인칭 터널 프로토타입 (rival_veil_concept §7.1, 2026-08-12 회의 확정).
# 캄캄한 복도를 전방(↑/W)으로 걸으면 천장 전등이 하나씩 텅…텅…텅 순차 점등하고,
# 복도 끝에서 코어(드라이브·라이벌의 몸)가 서서히 드러난다. 목격 순간 = 처리 선택의 새 집.
#
# 구조: 비트 컨트롤러(이 노드 — 상태·진행·사운드)와 렌더러(_TunnelView — 원근 투영 _draw)를
# 분리한다. 손맛이 안 나오면 렌더러만 소실점 2D로 교체 가능(회의 결정: 비트는 렌더러와 분리).
# 진입: 연습장 패널(PlaygroundOverlay) 프로토 버튼. 실런 배선(14-1 클리어 → 문)은 다음 단계.
# BGM: 무음 + 환경음(발소리·점등·목격 스팅)만 — 14-2 확정 사양. 현재 SFX는 기존 자산 대타.

# ── 터널 치수 / 비트 좌표 (z = 전방 거리, 월드 단위) ─────────────────────────
# 2026-08-12 실플레이: 목격 지점 4040→3240 단축("생각보다 조금 길다"), 전등 7→6개.
const TUNNEL_LEN: float = 3900.0        # 끝 벽(캡)까지
const CORE_Z: float = 3660.0            # 코어 위치
const WITNESS_Z: float = 3240.0         # 이 지점 도달 = 목격 비트(강제 정지)
const WALK_SPEED: float = 200.0         # 전진 속도 — 긴장 걸음(인게임 240보다 느리게)
const BACK_SPEED: float = 130.0

const LIGHT_ZS: Array[float] = [500.0, 1000.0, 1500.0, 2000.0, 2500.0, 3000.0]
const LIGHT_AHEAD: float = 820.0        # 이만큼 앞의 전등이 켜진다 — 항상 한 걸음 앞을 비춤
const LIGHT_CASCADE_GAP: float = 0.5    # 연속 점등 최소 간격 — 빨리 걸어도 텅…텅…텅 리듬 유지
const LIGHT_RANGE: float = 470.0        # 전등 하나가 비추는 z 반경

# ── 상태 (렌더러가 읽는다) ──────────────────────────────────────────────────
var player_z: float = 0.0
var view_bob: Vector2 = Vector2.ZERO    # 헤드밥 — 렌더러 투영 중심 오프셋
var debug_auto_walk: bool = false       # 검증 하니스용 — 전진 키 홀드와 동일

var _phase: String = "fade_in"          # fade_in / walk / witness / done
var _fade_alpha: float = 1.0
var _elapsed: float = 0.0
var _speed: float = 0.0                 # 관성 있는 현재 속도(+전방)
var _bob_phase: float = 0.0
var _last_step_cycle: int = 0
var _light_states: Array = []           # [{on: bool, t: float}] — t = 점등 후 경과
var _lights_on: int = 0
var _last_light_time: float = -10.0
var _clunk_kick: float = 0.0            # 점등 순간 시야가 살짝 내려앉는 충격
var _witness_t: float = 0.0
var _touch_forward: bool = false
var _touch_back: bool = false
var _view: Control = null
var _hint_label: Label = null
var _end_panel: PanelContainer = null

func _ready() -> void:
	# 진입 안전판 — 직전 화면(연습장 등)의 paused 누수 차단(SceneRouter.go와 동일 규약).
	get_tree().paused = false
	GameState.restrict_combat_input = false
	BgmPlayer.stop()
	for i in LIGHT_ZS.size():
		_light_states.append({"on": false, "t": 0.0})
	var view := _TunnelView.new()
	view.t = self
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(view)
	_view = view
	_hint_label = Label.new()
	_hint_label.text = "↑ / W  전진"
	_hint_label.add_theme_font_size_override("font_size", 15)
	_hint_label.add_theme_color_override("font_color", Color(0.72, 0.78, 0.85))
	_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint_label.add_theme_constant_override("outline_size", 4)
	_hint_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint_label.position = Vector2(-40, -90)
	_hint_label.modulate.a = 0.0
	add_child(_hint_label)

func _process(delta: float) -> void:
	_elapsed += delta
	_clunk_kick = maxf(0.0, _clunk_kick - delta * 3.2)
	for i in _light_states.size():
		var st: Dictionary = _light_states[i]
		if bool(st.get("on", false)):
			st["t"] = float(st.get("t", 0.0)) + delta
	match _phase:
		"fade_in":
			_fade_alpha = maxf(0.0, _fade_alpha - delta / 1.4)
			if _fade_alpha <= 0.0:
				_phase = "walk"
		"walk":
			_update_walk(delta)
			_update_lights()
			if player_z >= WITNESS_Z:
				_begin_witness()
		"witness":
			_speed = lerpf(_speed, 0.0, minf(1.0, delta * 5.0))
			player_z = minf(WITNESS_Z, player_z + _speed * delta)
			_witness_t += delta
			if _witness_t >= 2.6:
				_phase = "done"
				_show_end_panel()
		"done":
			_witness_t += delta
	_update_bob(delta)
	_update_hint(delta)
	if _view != null:
		_view.queue_redraw()

# ── 걷기 ────────────────────────────────────────────────────────────────────
# 전진 = ↑/W — 화면은 전방(깊이)으로 가는데 →키는 어색하다는 실플레이 피드백(2026-08-12).
# ←/→도 계속 허용(수평 이동 근육기억 폴백). 물리 키 직접 판정이라 리매핑과 무관.
func _forward_held() -> bool:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		return true
	return Input.is_action_pressed("move_right")

func _back_held() -> bool:
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		return true
	return Input.is_action_pressed("move_left")

func _update_walk(delta: float) -> void:
	var forward: bool = _forward_held() or _touch_forward or debug_auto_walk
	var back: bool = (_back_held() or _touch_back) and not forward
	var target: float = 0.0
	if forward:
		target = WALK_SPEED
	elif back:
		target = -BACK_SPEED
	# 관성 — 출발은 무겁게, 정지는 조금 빠르게(발을 멈추는 느낌).
	var accel: float = 3.4 if absf(target) > 0.0 else 6.0
	_speed = lerpf(_speed, target, minf(1.0, delta * accel))
	player_z = clampf(player_z + _speed * delta, 0.0, WITNESS_Z)

func _update_bob(delta: float) -> void:
	var amp: float = clampf(absf(_speed) / WALK_SPEED, 0.0, 1.0)
	if amp > 0.03:
		_bob_phase += delta * 6.2 * amp
		var cycle: int = int(_bob_phase / PI)
		if cycle != _last_step_cycle:
			_last_step_cycle = cycle
			if _phase == "walk" or _phase == "witness":
				# 빈 복도라 발소리가 존재감을 가져야 함 — 실플레이 "살짝만 크게"(2026-08-12) 반영 +3dB.
				SfxPlayer.play("player_step", 1.0)
	view_bob = Vector2(
		sin(_bob_phase) * 4.0 * amp,
		-absf(sin(_bob_phase)) * 5.5 * amp + _clunk_kick * 7.0)

# ── 순차 점등 — 진행이 이끈다 ───────────────────────────────────────────────
func _update_lights() -> void:
	for i in _light_states.size():
		var st: Dictionary = _light_states[i]
		if bool(st.get("on", false)):
			continue
		# 순서 강제 + 진행 트리거 + 최소 간격(cascade) — 셋 다 만족해야 점등.
		if i > 0:
			var prev: Dictionary = _light_states[i - 1]
			if not bool(prev.get("on", false)):
				break
		if player_z + LIGHT_AHEAD < LIGHT_ZS[i]:
			break
		if _elapsed - _last_light_time < LIGHT_CASCADE_GAP:
			break
		st["on"] = true
		st["t"] = 0.0
		_last_light_time = _elapsed
		_lights_on += 1
		_clunk_kick = 1.0
		# "텅" — 문 열림(hatch_open) 대타가 어색하다는 피드백(2026-08-12)으로 자체 제작
		# light_clunk(착지음 피치다운+홀 에코)로 교체.
		SfxPlayer.play("light_clunk", 2.0)
		break

# 전등 밝기(0~1) — 점등 직후 플리커 → 안정 후 미세한 형광등 떨림. 목격 비트에선 세계가
# 뒤로 물러나도록 감광(코어만 남는다). 렌더러가 매 프레임 호출(결정적 — randf 금지).
func lamp_intensity(idx: int) -> float:
	var st: Dictionary = _light_states[idx]
	if not bool(st.get("on", false)):
		return 0.0
	var tt: float = float(st.get("t", 0.0))
	var settle: float = 0.92 + 0.08 * sin(_elapsed * 2.3 + float(idx) * 1.7)
	var v: float = settle
	if tt < 0.45:
		var strobe: float = 1.0 if fmod(tt * 21.0 + float(idx) * 0.63, 1.0) > 0.38 else 0.12
		v = lerpf(strobe, settle, tt / 0.45)
	if _phase == "witness" or _phase == "done":
		v *= 1.0 - 0.45 * clampf(_witness_t / 2.0, 0.0, 1.0)
	return v

# z 지점의 전등 조도 합(무채색 성분). 렌더러 세그먼트 셰이딩용.
func light_at(z: float) -> float:
	var total: float = 0.0
	for i in LIGHT_ZS.size():
		var li: float = lamp_intensity(i)
		if li <= 0.0:
			continue
		total += li * maxf(0.0, 1.0 - absf(z - LIGHT_ZS[i]) / LIGHT_RANGE)
	return total

# 코어 가시성(0~1) — 접근할수록 드러나고, 목격 비트에서 마저 밝아진다.
# 램프는 목격 지점(WITNESS_Z)에서 1.0에 닿도록 터널 길이와 함께 조정할 것.
func core_vis() -> float:
	var v: float = clampf((player_z - 2100.0) / 1100.0, 0.0, 1.0)
	if _phase == "witness" or _phase == "done":
		v = minf(1.0, v + _witness_t * 0.25)
	return v

# z 지점의 코어 광(바이올렛·시안 성분).
func core_light_at(z: float) -> float:
	return core_vis() * maxf(0.0, 1.0 - absf(z - CORE_Z) / 1000.0)

# 목격 비트의 진행(0~1) — 렌더러 줌(초점거리) 보간용.
func witness_progress() -> float:
	if _phase == "witness" or _phase == "done":
		return clampf(_witness_t / 2.2, 0.0, 1.0)
	return 0.0

func current_focal() -> float:
	var w: float = witness_progress()
	return 620.0 + 150.0 * (w * w * (3.0 - 2.0 * w))   # smoothstep — 코어로 서서히 밀착

func fade_alpha() -> float:
	return _fade_alpha

# ── 목격 비트 ───────────────────────────────────────────────────────────────
func _begin_witness() -> void:
	_phase = "witness"
	_witness_t = 0.0
	SfxPlayer.play("arcturus_enter", -2.0)

func _update_hint(delta: float) -> void:
	if _hint_label == null:
		return
	# 걷기 전 4초 이상 머뭇거리면 조작 힌트 페이드 인 — 움직이면 사라짐.
	var want: bool = _phase == "walk" and player_z < 80.0 and _elapsed > 4.0 and absf(_speed) < 20.0
	var goal: float = 0.85 if want else 0.0
	_hint_label.modulate.a = lerpf(_hint_label.modulate.a, goal, minf(1.0, delta * 3.0))

# ── 프로토 종료 패널 — 본편에선 이 순간 처리 선택(DisposalChoiceOverlay)이 등장 ──
func _show_end_panel() -> void:
	if _end_panel != null:
		return
	_end_panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.92)
	style.border_color = Color(0.55, 0.45, 0.75, 0.6)
	style.set_border_width_all(1)
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	_end_panel.add_theme_stylebox_override("panel", style)
	_end_panel.set_anchors_preset(Control.PRESET_CENTER)
	_end_panel.position = Vector2(-230, 60)
	add_child(_end_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.custom_minimum_size = Vector2(460, 0)
	_end_panel.add_child(v)
	var title := Label.new()
	title.text = "14-2 프로토 종료 지점"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", Color(0.85, 0.75, 0.98))
	v.add_child(title)
	var desc := Label.new()
	desc.text = "본편에서는 코어를 목격하는 이 순간, 처리 선택이 등장합니다."
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.80, 0.83, 0.88))
	v.add_child(desc)
	var preview_btn := Button.new()
	preview_btn.text = "처리 선택 미리보기"
	preview_btn.pressed.connect(_on_preview_choice)
	v.add_child(preview_btn)
	var again_btn := Button.new()
	again_btn.text = "다시 걷기"
	again_btn.pressed.connect(_restart)
	v.add_child(again_btn)
	var exit_btn := Button.new()
	exit_btn.text = "타이틀로"
	exit_btn.pressed.connect(_exit_to_title)
	v.add_child(exit_btn)
	GameState.arm_focus_with_delay(_end_panel, preview_btn, 0.6)

func _on_preview_choice() -> void:
	# 목격 → 선택의 이음새 체감용. 프로토라 선택 결과는 저장하지 않는다(실런 오염 방지).
	if _end_panel != null:
		_end_panel.visible = false
	DisposalChoiceOverlay.show(self, _on_proto_choice_picked)

func _on_proto_choice_picked(_choice_id: String) -> void:
	if _end_panel != null:
		_end_panel.visible = true

func _restart() -> void:
	player_z = 0.0
	_speed = 0.0
	_bob_phase = 0.0
	_last_step_cycle = 0
	_lights_on = 0
	_last_light_time = -10.0
	_elapsed = 0.0
	_witness_t = 0.0
	_clunk_kick = 0.0
	_phase = "fade_in"
	_fade_alpha = 1.0
	for i in _light_states.size():
		var st: Dictionary = _light_states[i]
		st["on"] = false
		st["t"] = 0.0
	if _end_panel != null:
		_end_panel.queue_free()
		_end_panel = null

func _exit_to_title() -> void:
	GameState.reset()
	SceneRouter.go(get_tree(), SceneRouter.TITLE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and (key.keycode == KEY_ESCAPE or key.keycode == KEY_P):
			_exit_to_title()

func _input(event: InputEvent) -> void:
	# 터치(폰) — 화면 우측 절반 홀드 = 전진, 좌측 = 후진. 종료 패널이 뜬 뒤엔 버튼에 양보.
	if _phase == "done":
		_touch_forward = false
		_touch_back = false
		return
	if event is InputEventScreenTouch:
		var tch := event as InputEventScreenTouch
		var right_half: bool = tch.position.x > get_viewport_rect().size.x * 0.5
		if tch.pressed:
			_touch_forward = right_half
			_touch_back = not right_half
		else:
			_touch_forward = false
			_touch_back = false

# ═══════════════════════════════════════════════════════════════════════════
# 렌더러 — 소실점 원근 투영으로 복도를 그린다. 컨트롤러 상태(player_z·전등·코어·밥)만
# 읽는 순수 뷰. 교체 지점: 이 클래스만 소실점 2D 버전으로 갈아끼우면 비트는 그대로다.
class _TunnelView:
	extends Control

	var t = null   # CoreTunnel 참조(비순환 타입을 위해 untyped — 상태 읽기 전용)

	# 복도 단면 치수(월드 단위)와 투영 파라미터 — 렌더러 소관.
	const HALF_W: float = 250.0      # 복도 반폭
	const CEIL_Y: float = -165.0     # 천장(눈높이 기준 위)
	const FLOOR_Y: float = 185.0     # 바닥(눈높이 기준 아래)
	const SEG: float = 140.0         # 벽 세그먼트 간격(월드 정렬 — 걸어도 이음새가 흐르지 않게)
	const NEAR: float = 26.0         # 근평면
	const DRAW_DIST: float = 3200.0  # 그리기 한계

	const LAMP_COL := Color(0.78, 0.84, 0.90)      # 형광등 냉백색
	const CORE_COL := Color(0.72, 0.50, 0.98)      # 코어 바이올렛(라이벌)
	const CORE_HOT := Color(0.62, 0.92, 1.00)      # 코어 중심 시안(VEIL의 몸)

	func _proj(x: float, y: float, d: float, cx: float, cy: float, focal: float) -> Vector2:
		var s: float = focal / maxf(d, NEAR * 0.5)
		return Vector2(cx + x * s, cy + y * s)

	func _draw() -> void:
		if t == null:
			return
		var vs: Vector2 = size
		if vs.x < 2.0 or vs.y < 2.0:
			return
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0.006, 0.006, 0.010), true)
		var cx: float = vs.x * 0.5 + float(t.view_bob.x)
		var cy: float = vs.y * 0.52 + float(t.view_bob.y)
		var focal: float = float(t.current_focal())
		var pz: float = float(t.player_z)

		_draw_end_cap(pz, cx, cy, focal)
		_draw_corridor(pz, cx, cy, focal)
		_draw_core(pz, cx, cy, focal)
		_draw_lamps(pz, cx, cy, focal)
		_draw_vignette(vs)
		var fa: float = float(t.fade_alpha())
		if fa > 0.001:
			draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, fa), true)

	# 끝 벽(캡) — 코어 뒤의 막다른 면. 코어 광의 역광만 은은히 받는다.
	func _draw_end_cap(pz: float, cx: float, cy: float, focal: float) -> void:
		var d: float = float(t.TUNNEL_LEN) - pz
		if d <= NEAR or d > DRAW_DIST + 1600.0:
			return
		var tl := _proj(-HALF_W, CEIL_Y, d, cx, cy, focal)
		var br := _proj(HALF_W, FLOOR_Y, d, cx, cy, focal)
		var glow: float = float(t.core_light_at(float(t.TUNNEL_LEN))) * 0.35
		var col := Color(0.02 + CORE_COL.r * glow * 0.3, 0.02 + CORE_COL.g * glow * 0.3, 0.03 + CORE_COL.b * glow * 0.3)
		draw_rect(Rect2(tl, br - tl), col, true)

	# 복도 본체 — 먼 세그먼트부터(painter's algorithm) 바닥·천장·좌우 벽 4면 + 이음 리브.
	func _draw_corridor(pz: float, cx: float, cy: float, focal: float) -> void:
		var far_z: float = minf(float(t.TUNNEL_LEN), pz + DRAW_DIST)
		var first_seg: int = int(floor(pz / SEG))
		var last_seg: int = int(floor(far_z / SEG))
		for k in range(last_seg, first_seg - 1, -1):
			var z_a: float = float(k) * SEG          # 가까운 경계
			var z_b: float = z_a + SEG               # 먼 경계
			var d_a: float = maxf(z_a - pz, NEAR)
			var d_b: float = z_b - pz
			if d_b <= NEAR:
				continue
			var mid_z: float = (z_a + z_b) * 0.5
			var lamp_l: float = float(t.light_at(mid_z))
			var core_l: float = float(t.core_light_at(mid_z))
			var amb: float = 0.05
			# 면별 알베도 × (주변광 + 전등광 + 코어광). 바닥은 전등 풀빛을 더 받는다.
			var wall_col := _shade(Color(0.30, 0.33, 0.38), amb, lamp_l, core_l)
			var floor_col := _shade(Color(0.24, 0.26, 0.30), amb, lamp_l * 1.18, core_l)
			var ceil_col := _shade(Color(0.19, 0.21, 0.25), amb, lamp_l * 0.85, core_l * 0.8)
			var nl_t := _proj(-HALF_W, CEIL_Y, d_a, cx, cy, focal)
			var nr_t := _proj(HALF_W, CEIL_Y, d_a, cx, cy, focal)
			var nl_b := _proj(-HALF_W, FLOOR_Y, d_a, cx, cy, focal)
			var nr_b := _proj(HALF_W, FLOOR_Y, d_a, cx, cy, focal)
			var fl_t := _proj(-HALF_W, CEIL_Y, d_b, cx, cy, focal)
			var fr_t := _proj(HALF_W, CEIL_Y, d_b, cx, cy, focal)
			var fl_b := _proj(-HALF_W, FLOOR_Y, d_b, cx, cy, focal)
			var fr_b := _proj(HALF_W, FLOOR_Y, d_b, cx, cy, focal)
			draw_colored_polygon(PackedVector2Array([nl_b, nr_b, fr_b, fl_b]), floor_col)
			draw_colored_polygon(PackedVector2Array([nl_t, nr_t, fr_t, fl_t]), ceil_col)
			draw_colored_polygon(PackedVector2Array([nl_t, fl_t, fl_b, nl_b]), wall_col)
			draw_colored_polygon(PackedVector2Array([nr_t, fr_t, fr_b, nr_b]), wall_col)
			# 먼 경계 리브(구조 이음새) — 밝을수록 또렷.
			var rib_a: float = clampf(0.10 + lamp_l * 0.25 + core_l * 0.2, 0.0, 0.5)
			var rib_col := Color(0.05, 0.06, 0.08, rib_a)
			draw_line(fl_t, fr_t, rib_col, 2.0)
			draw_line(fl_t, fl_b, rib_col, 2.0)
			draw_line(fr_t, fr_b, rib_col, 2.0)
			draw_line(fl_b, fr_b, rib_col, 2.0)
			# 벽 가이드 레일(허리 높이) — 원근 단서 보강.
			var rail_col := Color(0.09, 0.10, 0.13, clampf(0.25 + lamp_l * 0.3, 0.0, 0.6))
			draw_line(_proj(-HALF_W, 42.0, d_a, cx, cy, focal), _proj(-HALF_W, 42.0, d_b, cx, cy, focal), rail_col, 2.0)
			draw_line(_proj(HALF_W, 42.0, d_a, cx, cy, focal), _proj(HALF_W, 42.0, d_b, cx, cy, focal), rail_col, 2.0)

	func _shade(albedo: Color, amb: float, lamp_l: float, core_l: float) -> Color:
		var r: float = albedo.r * (amb + lamp_l * LAMP_COL.r + core_l * CORE_COL.r)
		var g: float = albedo.g * (amb + lamp_l * LAMP_COL.g + core_l * CORE_COL.g)
		var b: float = albedo.b * (amb + lamp_l * LAMP_COL.b + core_l * CORE_COL.b)
		return Color(minf(r, 1.0), minf(g, 1.0), minf(b, 1.0))

	# 천장 전등 — 꺼진 등은 어둠에 묻힌 실루엣, 켜진 등은 글로우 + 바닥 풀빛.
	func _draw_lamps(pz: float, cx: float, cy: float, focal: float) -> void:
		for i in range(t.LIGHT_ZS.size() - 1, -1, -1):
			var lz: float = float(t.LIGHT_ZS[i])
			var d: float = lz - pz
			if d <= NEAR or d > DRAW_DIST:
				continue
			var s: float = focal / d
			var fix_pos := _proj(0.0, CEIL_Y + 4.0, d, cx, cy, focal)
			var inten: float = float(t.lamp_intensity(i))
			var near_l: float = float(t.light_at(lz))
			# 등기구 몸체 — 주변이 밝아야 실루엣이 보인다.
			var body_a: float = clampf(0.25 + near_l * 0.5, 0.0, 0.9)
			var body_w: float = 46.0 * s
			var body_h: float = 7.0 * s
			draw_rect(Rect2(fix_pos - Vector2(body_w * 0.5, body_h * 0.5), Vector2(body_w, body_h)), Color(0.10, 0.11, 0.13, body_a), true)
			if inten <= 0.01:
				continue
			# 발광부 + 글로우.
			var tube_col := Color(LAMP_COL.r, LAMP_COL.g, LAMP_COL.b, clampf(inten, 0.0, 1.0))
			draw_rect(Rect2(fix_pos - Vector2(body_w * 0.42, body_h * 0.28), Vector2(body_w * 0.84, body_h * 0.56)), tube_col, true)
			draw_circle(fix_pos, 26.0 * s, Color(LAMP_COL.r, LAMP_COL.g, LAMP_COL.b, 0.20 * inten))
			draw_circle(fix_pos, 52.0 * s, Color(LAMP_COL.r, LAMP_COL.g, LAMP_COL.b, 0.08 * inten))
			# 바닥 풀빛(타원) — 전등 바로 아래.
			var pool_pos := _proj(0.0, FLOOR_Y, d, cx, cy, focal)
			draw_set_transform(pool_pos, 0.0, Vector2(1.0, 0.32))
			draw_circle(Vector2.ZERO, 120.0 * s, Color(LAMP_COL.r, LAMP_COL.g, LAMP_COL.b, 0.10 * inten))
			draw_circle(Vector2.ZERO, 62.0 * s, Color(LAMP_COL.r, LAMP_COL.g, LAMP_COL.b, 0.10 * inten))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 코어 — 복도 끝의 그것. 멀리선 희미한 빛점, 다가서면 바이올렛 헤일로 + 시안 심장.
	func _draw_core(pz: float, cx: float, cy: float, focal: float) -> void:
		var vis: float = float(t.core_vis())
		if vis <= 0.005:
			return
		var d: float = float(t.CORE_Z) - pz
		if d <= NEAR:
			return
		var s: float = focal / d
		var pos := _proj(0.0, 26.0, d, cx, cy, focal)
		var wprog: float = float(t.witness_progress())
		var pulse: float = 0.85 + 0.15 * sin(float(t._elapsed) * (1.6 + wprog * 1.2))
		var r_base: float = 130.0 * s * pulse
		# 지지 케이블 실루엣 — 천장에서 코어로 수렴.
		var cable_col := Color(0.03, 0.03, 0.05, clampf(vis * 0.8, 0.0, 0.8))
		for off in [-90.0, -30.0, 30.0, 90.0]:
			var top := _proj(float(off), CEIL_Y, d - 60.0, cx, cy, focal)
			draw_line(top, pos, cable_col, maxf(1.5, 2.5 * s))
		# 바이올렛 헤일로(겹겹) → 시안 심장 → 백색 핵.
		draw_circle(pos, r_base * 2.6, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.05 * vis))
		draw_circle(pos, r_base * 1.7, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.10 * vis))
		draw_circle(pos, r_base * 1.15, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.18 * vis))
		draw_circle(pos, r_base * 0.72, Color(CORE_HOT.r, CORE_HOT.g, CORE_HOT.b, 0.34 * vis))
		draw_circle(pos, r_base * 0.40, Color(CORE_HOT.r, CORE_HOT.g, CORE_HOT.b, 0.65 * vis))
		draw_circle(pos, r_base * 0.18, Color(0.96, 0.98, 1.0, 0.9 * vis))
		# 코어 바닥 반사 — 세로로 눌린 바이올렛 타원.
		var refl_pos := _proj(0.0, FLOOR_Y, d, cx, cy, focal)
		draw_set_transform(refl_pos, 0.0, Vector2(1.0, 0.22))
		draw_circle(Vector2.ZERO, r_base * 1.5, Color(CORE_COL.r, CORE_COL.g, CORE_COL.b, 0.10 * vis))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 상하 비네트 — 시야를 좁혀 터널감을 강화.
	func _draw_vignette(vs: Vector2) -> void:
		var strips: int = 6
		var band: float = vs.y * 0.16 / float(strips)
		for i in strips:
			var a: float = 0.30 * (1.0 - float(i) / float(strips))
			draw_rect(Rect2(Vector2(0, float(i) * band), Vector2(vs.x, band + 1.0)), Color(0, 0, 0, a), true)
			draw_rect(Rect2(Vector2(0, vs.y - float(i + 1) * band), Vector2(vs.x, band + 1.0)), Color(0, 0, 0, a), true)
