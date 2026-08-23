class_name StoryDialogue
extends CanvasLayer

# 컷씬 대사 오버레이(2026-08-23 사용자: "스토리용 대사·보스전 오프닝은 온전히 그 대사에만
# 집중할 환경을 만들라") — 세계를 일시정지하고 대사를 한 줄씩 보여준다.
#  - 대상: 구조/스토리 발화 비트(막3 reveal · 회선 잠금 · 14-1 페이즈 오프닝/자백/격파).
#    전투 중 위협 콜아웃·조언·route_lines는 기존 자막 유지(눈앞의 것이 지시 대상이라 겹침이 정상).
#  - 조작: 스페이스/클릭/탭 = 줄 완성 → 다음 줄. ESC = 전체 건너뛰기. 아무 키나 길게(0.55s)도
#    전체 건너뛰기(터치·패드 대응). 진입 직후 0.3s는 잔여 입력 무시(문서 오버레이와 동형 가드).
#  - 일시정지 자립 관리: 열 때 pause, 닫을 때 복원(+ _exit_tree 안전판 — ArcturusDocumentOverlay 패턴).
#  - 시각: 어둡게 깔린 정지 화면 + 레터박스(표준 컷씬 문법) + 기존 자막 pill 문법(화자 색 동일)을
#    큰 폰트로. 게임 세계가 배경 무대로 얼어 있는 채 대사만 진행된다.

signal finished

const TYPE_SEC_PER_CHAR: float = 0.022   # Stage._subtitle_type_time과 같은 속도
const HOLD_SKIP_SEC: float = 0.55
const ENTER_LOCKOUT: float = 0.3

# 줄 서식: {who: "rival"/"veil", text: String}
var _lines: Array = []
var _idx: int = -1
var _typing: bool = false
var _type_t: float = 0.0
var _msg_label: Label = null
var _pill: PanelContainer = null
var _dots: Label = null
var _dim: ColorRect = null
var _bar_top: ColorRect = null
var _bar_bot: ColorRect = null
var _hint: Label = null
var _holder: Control = null
var _pill_slot: CenterContainer = null
var _hold_t: float = 0.0
var _lockout_t: float = ENTER_LOCKOUT
var _done: bool = false
var _prev_paused: bool = false

static var active: StoryDialogue = null

func open(lines: Array) -> void:
	_lines = lines.duplicate()

func append_lines(lines: Array) -> void:
	for ln in lines:
		_lines.append(ln)
	_refresh_dots()

func _ready() -> void:
	layer = 47
	process_mode = Node.PROCESS_MODE_ALWAYS
	active = self
	_prev_paused = get_tree().paused
	get_tree().paused = true
	# 어둡게 — 정지된 게임 화면이 무대 배경으로 남는다(완전 암전 아님).
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	var dtw := _dim.create_tween()
	dtw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	dtw.tween_property(_dim, "color:a", 0.5, 0.22)
	# 레터박스 — 위/아래 바가 화면 밖에서 밀려 들어온다(컷씬 신호, 표준 기법).
	_bar_top = _make_bar(true)
	_bar_bot = _make_bar(false)
	# 대사 홀더 — 하단 1/3, 중앙 정렬.
	_holder = Control.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_holder)
	# pill 자리 — 하단 중앙(수동 좌표 대신 CenterContainer, 폭이 텍스트마다 달라도 정확히 중앙).
	_pill_slot = CenterContainer.new()
	_pill_slot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_pill_slot.offset_top = -282.0
	_pill_slot.offset_bottom = -150.0
	_pill_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_holder.add_child(_pill_slot)
	# 진행 점 + 조작 힌트.
	_dots = Label.new()
	_dots.add_theme_font_size_override("font_size", 14)
	_dots.add_theme_color_override("font_color", Color(0.75, 0.75, 0.8, 0.75))
	_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dots.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_dots.offset_top = -140.0
	_dots.offset_bottom = -114.0
	_holder.add_child(_dots)
	_hint = Label.new()
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.78, 0.8))
	_hint.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hint.add_theme_constant_override("outline_size", 4)
	if OrientationGuard.is_touch_device():
		_hint.text = "탭: 다음   길게 누르기: 건너뛰기"
	else:
		_hint.text = "스페이스: 다음   ESC: 건너뛰기"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = -1000.0
	_hint.offset_right = -18.0
	_hint.offset_top = -40.0
	_hint.offset_bottom = -14.0
	_hint.modulate.a = 0.0
	_holder.add_child(_hint)
	var htw := _hint.create_tween()
	htw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	htw.tween_interval(0.6)
	htw.tween_property(_hint, "modulate:a", 1.0, 0.4)
	call_deferred("_advance")   # 첫 줄

func _make_bar(top: bool) -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0, 0, 0, 0.92)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if top:
		bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
		bar.offset_bottom = 0.0
	else:
		bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		bar.offset_top = 0.0
	add_child(bar)
	var tw := bar.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if top:
		tw.tween_property(bar, "offset_bottom", 52.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_property(bar, "offset_top", -52.0, 0.28).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	return bar

# 현재 줄 pill 재구성 — Stage 자막 pill과 같은 화자 문법(? 바이올렛 / VEIL 시안), 폰트만 큼.
func _build_line(ln: Dictionary) -> void:
	if _pill != null and is_instance_valid(_pill):
		_pill.queue_free()
	var who: String = str(ln.get("who", "veil"))
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 24.0
	sb.content_margin_right = 24.0
	sb.content_margin_top = 12.0
	sb.content_margin_bottom = 12.0
	var sp_color: Color
	var msg_color: Color
	var speaker: String
	if who == "rival":
		sb.bg_color = Color(0.07, 0.02, 0.11, 0.9)
		sb.border_color = Color(0.55, 0.30, 0.95, 0.85)
		sb.set_border_width_all(1)
		sp_color = Color(0.85, 0.50, 1.0)
		msg_color = Color(0.92, 0.84, 1.0)
		speaker = "?"
	else:
		sb.bg_color = Color(0.03, 0.05, 0.09, 0.9)
		sp_color = Color(0.42, 0.86, 1.0)
		msg_color = Color(0.90, 0.96, 1.0)
		speaker = "VEIL"
	_pill = PanelContainer.new()
	_pill.add_theme_stylebox_override("panel", sb)
	_pill_slot.add_child(_pill)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	_pill.add_child(hb)
	var name_l := Label.new()
	name_l.text = speaker
	name_l.add_theme_font_size_override("font_size", 22)
	name_l.add_theme_color_override("font_color", sp_color)
	name_l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	name_l.add_theme_constant_override("outline_size", 6)
	name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(name_l)
	var divider := ColorRect.new()
	divider.color = Color(sp_color.r, sp_color.g, sp_color.b, 0.55)
	divider.custom_minimum_size = Vector2(2.0, 22.0)
	divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(divider)
	_msg_label = Label.new()
	_msg_label.text = str(ln.get("text", ""))
	_msg_label.add_theme_font_size_override("font_size", 22)
	_msg_label.add_theme_color_override("font_color", msg_color)
	_msg_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_msg_label.add_theme_constant_override("outline_size", 4)
	_msg_label.visible_characters = 0
	hb.add_child(_msg_label)
	_typing = true
	_type_t = 0.0
	SfxPlayer.play("veil_subtitle_in")
	_refresh_dots()

func _refresh_dots() -> void:
	if _dots == null or not is_instance_valid(_dots):
		return
	var s: String = ""
	for i in _lines.size():
		s += "●" if i <= _idx else "○"
		if i < _lines.size() - 1:
			s += " "
	_dots.text = s

func _advance() -> void:
	if _done:
		return
	if _typing and _msg_label != null and is_instance_valid(_msg_label):
		# 타자 중 입력 = 현재 줄 즉시 완성.
		_msg_label.visible_characters = -1
		_typing = false
		return
	_idx += 1
	if _idx >= _lines.size():
		_finish()
		return
	var ln: Dictionary = _lines[_idx]
	_build_line(ln)

func _skip_all() -> void:
	if _done:
		return
	_idx = _lines.size()
	_finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	if active == self:
		active = null
	get_tree().paused = _prev_paused
	emit_signal("finished")
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	for n: CanvasItem in ([_dim, _bar_top, _bar_bot, _holder] as Array[CanvasItem]):
		if n != null and is_instance_valid(n):
			tw.parallel().tween_property(n, "modulate:a", 0.0, 0.25)
	tw.tween_callback(queue_free)

# 안전판 — 어떤 경로로든 트리에서 빠지면 pause 복원(문서 오버레이와 동형).
func _exit_tree() -> void:
	if active == self:
		active = null
	if not _done:
		var tree := get_tree()
		if tree != null:
			tree.paused = _prev_paused

func _process(delta: float) -> void:
	if _done:
		return
	if _lockout_t > 0.0:
		_lockout_t -= delta
		return
	# 타자 진행.
	if _typing and _msg_label != null and is_instance_valid(_msg_label):
		_type_t += delta
		var chars: int = int(_type_t / TYPE_SEC_PER_CHAR)
		_msg_label.visible_characters = chars
		if chars >= _msg_label.text.length():
			_msg_label.visible_characters = -1
			_typing = false
	# 길게 누르면 전체 건너뛰기(터치·패드 포함) — 힌트 라벨이 채워지는 걸로 진행 표시.
	var held: bool = Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_skip") \
		or Input.is_action_pressed("attack") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if held:
		_hold_t += delta
		if _hint != null and is_instance_valid(_hint):
			_hint.modulate = Color(1.0, 1.0, 1.0, 1.0).lerp(Color(0.85, 0.5, 1.0, 1.0), clampf(_hold_t / HOLD_SKIP_SEC, 0.0, 1.0))
		if _hold_t >= HOLD_SKIP_SEC:
			_skip_all()
	else:
		_hold_t = 0.0
		if _hint != null and is_instance_valid(_hint):
			_hint.modulate = Color(1, 1, 1, _hint.modulate.a)

func _input(event: InputEvent) -> void:
	if _done or _lockout_t > 0.0:
		return
	# ESC = 전체 건너뛰기(즉시). ui_skip에 스페이스도 묶여 있어 키코드로 구분한다.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_skip_all()
		return
	var pressed: bool = false
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_skip") \
			or event.is_action_pressed("attack") or OrientationGuard.is_tap(event):
		pressed = true
	# 터치 기기에선 탭이 좌클릭으로도 합성돼 중복 진행 → 데스크톱만 좌클릭 인정(문서 오버레이와 동형).
	elif not OrientationGuard.is_touch_device() and event is InputEventMouseButton \
			and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	_advance()
