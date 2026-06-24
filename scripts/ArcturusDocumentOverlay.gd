class_name ArcturusDocumentOverlay
extends Node

# 이스터에그 ARCTURUS 아카이브 — 풀스크린 문서 연출.
# 종이 한 장에 위에서부터 줄들이 타이핑되며 나타나고, 카메라(종이)가 자동 스크롤.
# 시간 정지 + 스페이스/클릭으로 현재 줄 즉시 완성 + 다음 줄로.
#
# 사용:
#   var doc = ArcturusDocumentOverlay.new()
#   parent.add_child(doc)
#   doc.finished.connect(_on_done)
#   doc.show_doc(lines)   # lines: Array of {text: String, kind: "title"/"body"/"speaker", delay: float}

signal finished

const TYPE_INTERVAL: float = 0.035
const PAPER_WIDTH: float = 720.0
const MARGIN_TOP: float = 80.0
const MARGIN_SIDE: float = 36.0
const LINE_HEIGHT_BODY: float = 32.0
const LINE_HEIGHT_TITLE: float = 48.0
const LINE_HEIGHT_BLANK: float = 18.0
# 디자인 기준 화면 크기 — show_doc 진입 시 실제 화면(visible_rect)으로 갱신(적응형).
# const가 아니라 var: 런타임에 현재 해상도/화면비로 덮어쓴다(아래 모든 사용처에 반영).
var VIEWPORT_W: float = 1280.0
var VIEWPORT_H: float = 720.0
const SCROLL_LERP: float = 0.085  # 카메라 부드럽게 따라옴

var layer: CanvasLayer
var bg: ColorRect
var paper: Control
var paper_visual: ColorRect
var labels: Array = []   # Label 배열, 입력 lines와 1:1
var lines_data: Array = []
var current_line: int = 0
var revealed: int = 0
var typing: bool = false
var t: float = 0.0
var pause_after_line: float = 0.0
var done: bool = false
var paper_target_y: float = 0.0
# 다 나온 뒤 사용자 조작 단계 — 위/아래로 스크롤 + 확인 키로 닫기.
var reading_done: bool = false
var read_lockout_t: float = 0.0
const READ_LOCKOUT: float = 0.7
const SCROLL_STEP: float = 200.0
var close_hint_label: Label = null
# 페이드인 중 _process가 자동 진행해 line 1/2가 미리 visible되던 버그(사용자:
# "[A] 인사팀 온보까지만 보이다가 지워졌다 다시 써짐") 차단. _start_typing이
# 콜백으로 호출될 때 비로소 typing 시작.
var started: bool = false
# 진입 직전(이스터에그 hold 완료 직후) jump 키 잔여 입력이 _input으로 들어와
# typing이 자동 진행되어 [A] 인사팀 온보딩 본문까지 시작부터 보이는 버그 차단.
# _start_typing 콜백 후에도 짧게 더 무시.
const ENTER_LOCKOUT: float = 0.4
var enter_lockout_t: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func show_doc(input_lines: Array) -> void:
	SfxPlayer.play("arcturus_enter")
	lines_data = input_lines
	# 적응형 — 실제 화면 크기로 기준 갱신 (종이 중앙·하단 안내·스크롤 한계가 화면비 무관).
	var vp: Vector2 = get_viewport().get_visible_rect().size
	VIEWPORT_W = vp.x
	VIEWPORT_H = vp.y
	layer = CanvasLayer.new()
	layer.layer = 25
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	# 풀스크린 어두운 배경
	bg = ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.04, 0.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bg)
	# 종이 컨테이너 (화면 가운데 가로 정렬)
	paper = Control.new()
	paper.position = Vector2((VIEWPORT_W - PAPER_WIDTH) * 0.5, MARGIN_TOP)
	paper.size = Vector2(PAPER_WIDTH, _calc_paper_height())
	paper.modulate.a = 0.0
	layer.add_child(paper)
	# paper_target_y 초기값을 시작 position과 동기화 — 안 그러면 0(기본값)으로
	# lerp되어 페이드인 0.7s 동안 paper가 화면 위로 빠져나가서 제목이 안 보이고
	# 본문(A 온보딩 등)이 먼저 등장하는 것처럼 보임 (사용자 보고).
	paper_target_y = MARGIN_TOP
	# 종이 본체 — 옅은 크림색
	paper_visual = ColorRect.new()
	paper_visual.color = Color(0.92, 0.90, 0.84, 0.96)
	paper_visual.position = Vector2(-MARGIN_SIDE, -40.0)
	paper_visual.size = paper.size + Vector2(MARGIN_SIDE * 2.0, 80.0)
	paper.add_child(paper_visual)
	# 종이 옆 가는 그림자 라인 (저격 같은 디테일)
	var shadow := ColorRect.new()
	shadow.color = Color(0.0, 0.0, 0.0, 0.18)
	shadow.position = Vector2(-MARGIN_SIDE - 6.0, -40.0 + 6.0)
	shadow.size = paper_visual.size
	shadow.z_index = -1
	paper.add_child(shadow)
	# 줄들 미리 배치 (alpha=0)
	var y: float = 0.0
	for entry in lines_data:
		var d: Dictionary = entry
		var kind: String = str(d.get("kind", "body"))
		var lbl := Label.new()
		lbl.text = ""
		lbl.position = Vector2(0.0, y)
		lbl.size = Vector2(PAPER_WIDTH, _line_height_for(kind))
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lbl.modulate.a = 0.0
		match kind:
			"title":
				lbl.add_theme_font_size_override("font_size", 22)
				lbl.add_theme_color_override("font_color", Color(0.18, 0.20, 0.28))
			"speaker":
				lbl.add_theme_font_size_override("font_size", 14)
				lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
			"blank":
				lbl.add_theme_font_size_override("font_size", 14)
			_:
				lbl.add_theme_font_size_override("font_size", 17)
				lbl.add_theme_color_override("font_color", Color(0.10, 0.12, 0.18))
		paper.add_child(lbl)
		labels.append(lbl)
		y += _line_height_for(kind)
	# 페이드 인 → 타이핑 시작
	get_tree().paused = true
	var tw_bg := bg.create_tween()
	tw_bg.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_bg.tween_property(bg, "color:a", 0.92, 0.6)
	var tw_paper := paper.create_tween()
	tw_paper.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_paper.tween_property(paper, "modulate:a", 1.0, 0.7)
	tw_paper.tween_callback(_start_typing)

func _calc_paper_height() -> float:
	var h: float = 0.0
	for entry in lines_data:
		var d: Dictionary = entry
		h += _line_height_for(str(d.get("kind", "body")))
	return max(h, VIEWPORT_H - MARGIN_TOP * 2.0)

func _line_height_for(kind: String) -> float:
	match kind:
		"title":
			return LINE_HEIGHT_TITLE
		"blank":
			return LINE_HEIGHT_BLANK
	return LINE_HEIGHT_BODY

func _start_typing() -> void:
	started = true
	enter_lockout_t = ENTER_LOCKOUT
	current_line = 0
	revealed = 0
	t = 0.0
	if labels.size() > 0:
		typing = true
		labels[0].modulate.a = 1.0

func _process(delta: float) -> void:
	if done:
		return
	# 종이 부드럽게 스크롤 (현재 줄을 화면 중앙 ~40%에 위치)
	paper.position.y = lerp(paper.position.y, paper_target_y, SCROLL_LERP)
	# 페이드인 중엔 typing 진행 X — _start_typing 콜백이 started=true로 바꿔야 시작.
	if not started:
		return
	if enter_lockout_t > 0.0:
		enter_lockout_t -= delta
	# 다 읽고 나면 자동 진행 멈추고 사용자 스크롤 + 확인 키 대기.
	if reading_done:
		if read_lockout_t > 0.0:
			read_lockout_t -= delta
		_handle_user_scroll(delta)
		return
	if current_line >= lines_data.size():
		return
	if typing:
		t += delta
		if t >= TYPE_INTERVAL:
			t = 0.0
			revealed += 1
			var line: Dictionary = lines_data[current_line]
			var full: String = str(line.get("text", ""))
			var label: Label = labels[current_line]
			if revealed >= full.length():
				revealed = full.length()
				label.text = full
				typing = false
				pause_after_line = float(line.get("delay", 0.4))
			else:
				label.text = full.substr(0, revealed)
				SfxPlayer.play("terminal_typewrite")
		_update_scroll_target()
		return
	# 줄 사이 침묵 → 다음 줄로
	pause_after_line -= delta
	if pause_after_line <= 0.0:
		current_line += 1
		if current_line >= lines_data.size():
			_enter_reading_done()
		else:
			revealed = 0
			t = 0.0
			typing = true
			labels[current_line].modulate.a = 1.0
			# blank 줄은 텍스트 없어 즉시 통과
			var ln: Dictionary = lines_data[current_line]
			if str(ln.get("kind", "body")) == "blank":
				typing = false
				pause_after_line = float(ln.get("delay", 0.2))
			_update_scroll_target()

func _update_scroll_target() -> void:
	# 현재 줄의 종이 내부 y 좌표
	if current_line >= labels.size():
		return
	var lbl_y: float = labels[current_line].position.y
	# paper의 절대 좌표가 (VIEWPORT_H * 0.42 - lbl_y)일 때 그 줄이 화면 약 42% 위치.
	var target: float = VIEWPORT_H * 0.42 - lbl_y
	# 종이가 너무 위로 올라가지 않게 clamp (최대 상단 = MARGIN_TOP)
	if target > MARGIN_TOP:
		target = MARGIN_TOP
	paper_target_y = target

func _enter_reading_done() -> void:
	# 자동 진행 종료. 사용자 스크롤 + 확인 키 대기.
	if reading_done:
		return
	reading_done = true
	read_lockout_t = READ_LOCKOUT
	# 화면 하단 닫기 안내.
	close_hint_label = Label.new()
	close_hint_label.text = "[ ↑↓ · W/S · 휠 스크롤   Space·Enter로 닫기 ]"
	close_hint_label.add_theme_font_size_override("font_size", 14)
	close_hint_label.add_theme_color_override("font_color", Color(0.95, 0.92, 0.78))
	close_hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	close_hint_label.add_theme_constant_override("outline_size", 4)
	close_hint_label.position = Vector2(0, VIEWPORT_H - 40.0)
	close_hint_label.size = Vector2(VIEWPORT_W, 28.0)
	close_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint_label.modulate.a = 0.0
	layer.add_child(close_hint_label)
	var tw := close_hint_label.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(READ_LOCKOUT)
	tw.tween_property(close_hint_label, "modulate:a", 1.0, 0.4)

func _handle_user_scroll(_delta: float) -> void:
	# 위/아래 hold로 paper_target_y 조정 — 사용자가 다시 읽을 수 있게.
	# W/S는 jump 등에 묶여 ui_up/down에 안 붙을 수 있어 물리 키로 직접 체크(사용자: WS로도 스크롤).
	if Input.is_action_pressed("ui_up") or Input.is_action_pressed("move_left") or Input.is_key_pressed(KEY_W):
		_scroll_paper(12.0)
	elif Input.is_action_pressed("ui_down") or Input.is_action_pressed("move_right") or Input.is_key_pressed(KEY_S):
		_scroll_paper(-12.0)

# 종이를 amount만큼 스크롤하고 윗단/아랫단 클램프. 키 hold·마우스 휠 공용.
func _scroll_paper(amount: float) -> void:
	paper_target_y += amount
	var min_y: float = -(paper.size.y - VIEWPORT_H + MARGIN_TOP * 2.0)
	if min_y > MARGIN_TOP:
		min_y = MARGIN_TOP
	paper_target_y = clamp(paper_target_y, min_y, MARGIN_TOP)

func _input(event: InputEvent) -> void:
	if done:
		return
	# 페이드인 중 + 진입 직후 마진 — 이전 화면 점프 키 잔여 입력 차단.
	if not started or enter_lockout_t > 0.0:
		return
	# 다 읽힌 상태 — 위/아래는 _process polling, 확인 키는 lockout 후 닫기.
	if reading_done:
		if read_lockout_t > 0.0:
			return
		# 마우스 휠 — 종이 스크롤 (휠 업=위로 거슬러 보기). 사용자: 휠로도 스크롤.
		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_scroll_paper(48.0)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_paper(-48.0)
				get_viewport().set_input_as_handled()
				return
		# 닫기 — 확인 키(Space/Enter)·스킵·공격·좌클릭. jump(W)는 스크롤에 쓰므로 닫기에서 뺀다.
		var close_pressed: bool = false
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_skip") or event.is_action_pressed("attack"):
			close_pressed = true
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			close_pressed = true
		if close_pressed:
			get_viewport().set_input_as_handled()
			_start_finalize()
		return
	var pressed: bool = false
	if event.is_action_pressed("jump") or event.is_action_pressed("ui_skip") or event.is_action_pressed("attack"):
		pressed = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed = true
	if not pressed:
		return
	get_viewport().set_input_as_handled()
	if current_line >= lines_data.size():
		_enter_reading_done()
		return
	if typing:
		# 현재 줄 즉시 완성
		var full: String = str(lines_data[current_line].get("text", ""))
		labels[current_line].text = full
		revealed = full.length()
		typing = false
		pause_after_line = 0.0
	else:
		# 다음 줄로 스킵
		current_line += 1
		if current_line >= lines_data.size():
			_enter_reading_done()
			return
		revealed = 0
		t = 0.0
		typing = true
		labels[current_line].modulate.a = 1.0
		var ln: Dictionary = lines_data[current_line]
		if str(ln.get("kind", "body")) == "blank":
			typing = false
			pause_after_line = 0.0
		_update_scroll_target()

func _start_finalize() -> void:
	if done:
		return
	done = true
	var tw := bg.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(1.4)
	tw.tween_property(bg, "color:a", 0.0, 0.9)
	var tw_p := paper.create_tween()
	tw_p.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw_p.tween_interval(1.4)
	tw_p.tween_property(paper, "modulate:a", 0.0, 0.9)
	tw_p.tween_callback(_emit_done)

func _emit_done() -> void:
	get_tree().paused = false
	emit_signal("finished")
	if layer != null and is_instance_valid(layer):
		layer.queue_free()

# 안전판: _emit_done이 어떤 이유로든 호출 안 된 채 self가 tree에서 빠지면 paused 해제.
# (외부 free / scene 전환 / 예외 등)
func _exit_tree() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
