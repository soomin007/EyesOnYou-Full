extends Control

@onready var title_label: Label = $Center/V/Title
@onready var sub_title_label: Label = $Center/V/Subtitle
@onready var text_label: Label = $Center/V/Text
@onready var choice_box: HBoxContainer = $Center/V/Choices
@onready var hint_label: Label = $Center/V/Hint
@onready var stats_label: Label = $Footer/Stats

const TYPE_INTERVAL: float = 0.045

const HOLD_TO_QUIT_DURATION: float = 3.0

var ending_id: String = ""
var lines: Array = []
var line_idx: int = 0
var revealed: int = 0
var t: float = 0.0
var typing_done: bool = false
var waiting_choice: bool = false
var sequence_complete: bool = false
var silent_timer: float = 0.0
var hold_progress: float = 0.0
var hold_hint: Label
var hold_progress_bar: ColorRect
# 입력 락아웃 — 진입 후 1초 동안 ui_skip/jump 입력 무시. 점프 연타 사고 방지.
var input_lockout_t: float = GameState.INPUT_LOCKOUT_DURATION
# 안전판 — _process가 어떤 이유로든 typing을 시작 못 하면 2초 후 첫 줄을 강제 표시.
# (사용자 보고: "결말 C 제목만 나오고 그 아래 비어있음" 추적용 fallback.)
var stall_watchdog_t: float = 0.0

func _ready() -> void:
	# 안전망: 이전 scene에서 paused가 carry되어 Ending이 freeze되는 패턴 차단.
	get_tree().paused = false
	ending_id = EndingResolver.resolve(GameState.followed_count, GameState.rec_count, GameState.aggression_score)
	# 런 완주 1회 처리 — 본 엔딩 기록(엔딩 모으기/리플레이 토대) + 완주 카운트 + 진행 저장(run.cfg) 삭제.
	GameState.record_ending(ending_id)
	title_label.text = "MISSION COMPLETE"
	sub_title_label.text = "결말  %s — %s" % [ending_id, EndingResolver.get_ending_title(ending_id)]
	stats_label.text = "신뢰  %d   |   공격성  %d   |   사망  %d   |   스코어  %d" % [
		GameState.trust_score, GameState.aggression_score, GameState.death_count, GameState.score
	]
	# ??? 방 방문(hidden_visit_count > 0) 또는 ARCTURUS 아카이브 읽음(visited_arcturus) 시
	# 라이브 lore 라인을 보여주고, 미방문 시엔 짧고 호기심 hint 라인.
	var explored_lore: bool = GameState.hidden_visit_count > 0 or GameState.visited_arcturus
	lines = EndingResolver.get_ending_lines(ending_id, explored_lore)
	if lines.is_empty():
		push_warning("[Ending] lines is EMPTY for ending_id='%s' — fallback line 표시" % ending_id)
		# 안전판 — 빈 결말이면 최소한 마무리 한 줄 보여주기.
		lines = [{"speaker": "VEIL", "text": "임무 종료. 수고했어요, 요원.", "delay": 3.0}]
	choice_box.visible = false
	hint_label.text = ""
	text_label.text = ""
	if ending_id == EndingResolver.ENDING_D:
		title_label.modulate.a = 0.3
		sub_title_label.modulate.a = 0.3
		_setup_ending_d_atmosphere()
	_build_hold_hint()
	# 엔딩별 전용 BGM. ending_id에 맞춰 ending_a/b/c/d 트랙으로 cross-fade.
	BgmPlayer.play("ending_" + ending_id.to_lower())
	_start_line()

func _hold_hint_text() -> String:
	return GameState.hint("SPACE 길게 — 크레딧 (3초)", "A 길게 — 크레딧 (3초)")

func _on_input_kind_changed(_kind: String) -> void:
	if hold_hint != null:
		hold_hint.text = _hold_hint_text()

func _build_hold_hint() -> void:
	# 우측 하단 안내 — 시퀀스 완료 후에만 표시. SPACE를 3초간 누르고 있어야 타이틀로 이동.
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	box.size = Vector2(260, 50)
	box.position = Vector2(-260.0 - 20.0, -50.0 - 10.0)
	layer.add_child(box)
	hold_hint = Label.new()
	hold_hint.text = _hold_hint_text()
	hold_hint.add_theme_font_size_override("font_size", 12)
	hold_hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	GameState.input_kind_changed.connect(_on_input_kind_changed)
	hold_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hold_hint.size = Vector2(260, 16)
	hold_hint.visible = false
	box.add_child(hold_hint)
	# progress bar (배경 + 채우기)
	var bg := ColorRect.new()
	bg.color = Color(0.18, 0.20, 0.24, 0.7)
	bg.custom_minimum_size = Vector2(260, 4)
	bg.size = Vector2(260, 4)
	hold_progress_bar = ColorRect.new()
	hold_progress_bar.color = Color(0.55, 0.85, 0.95)
	hold_progress_bar.size = Vector2(0, 4)
	bg.add_child(hold_progress_bar)
	bg.visible = false
	box.add_child(bg)

func _setup_ending_d_atmosphere() -> void:
	# 미세한 노이즈 레이어 — 정적 느낌. 진폭/주기 사용자 피드백 후 완화 (이전엔 0.08s
	# 주기로 alpha 1.2까지 가서 화면이 번쩍였음 — 결말 D 진입 시 거슬리는 깜빡임).
	var noise_layer := CanvasLayer.new()
	noise_layer.layer = 50
	add_child(noise_layer)
	var noise := ColorRect.new()
	noise.color = Color(0.95, 0.95, 0.95, 0.04)
	noise.set_anchors_preset(Control.PRESET_FULL_RECT)
	noise.mouse_filter = Control.MOUSE_FILTER_IGNORE
	noise_layer.add_child(noise)
	var noise_tw := noise.create_tween()
	noise_tw.set_loops()
	noise_tw.tween_property(noise, "modulate:a", 0.6, 0.9)
	noise_tw.tween_property(noise, "modulate:a", 1.0, 0.8)
	noise_tw.tween_property(noise, "modulate:a", 0.4, 1.1)
	# 우상단 VEIL: ... 깜빡이다 꺼짐
	var veil_blink := Label.new()
	veil_blink.text = "VEIL: ..."
	veil_blink.add_theme_font_size_override("font_size", 14)
	veil_blink.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95, 0.6))
	veil_blink.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	veil_blink.size = Vector2(180, 20)
	veil_blink.position = Vector2(-180.0 - 20.0, 24.0)
	noise_layer.add_child(veil_blink)
	var blink_tw := veil_blink.create_tween()
	blink_tw.tween_property(veil_blink, "modulate:a", 0.0, 0.5)
	blink_tw.tween_interval(1.2)
	blink_tw.tween_property(veil_blink, "modulate:a", 1.0, 0.5)
	blink_tw.tween_interval(0.8)
	blink_tw.tween_property(veil_blink, "modulate:a", 0.0, 0.5)
	blink_tw.tween_interval(2.0)
	blink_tw.tween_property(veil_blink, "modulate:a", 0.7, 0.3)
	blink_tw.tween_interval(0.4)
	blink_tw.tween_property(veil_blink, "modulate:a", 0.0, 1.5)

func _start_line() -> void:
	# 매 새 라인마다 watchdog reset — 첫 라인뿐 아니라 followup·이후 라인 모두 보호.
	stall_watchdog_t = 0.0
	if line_idx >= lines.size():
		_on_sequence_done()
		return
	var line: Dictionary = lines[line_idx]
	revealed = 0
	t = 0.0
	typing_done = false
	silent_timer = 0.0
	if line.get("silent", false):
		text_label.text = ""
		typing_done = true
		return
	text_label.text = ""
	_color_for_speaker(str(line.get("speaker", "")))

func _color_for_speaker(sp: String) -> void:
	match sp:
		"VEIL":
			text_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		"SUB":
			text_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.65))
		_:
			text_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))

func _process(delta: float) -> void:
	if input_lockout_t > 0.0:
		input_lockout_t -= delta
	# Stall watchdog — typing이 시작되지 않으면 짧은 시간 후 강제 표시.
	# 매 _start_line에서 reset되므로 모든 라인에 대해 보호 작동.
	if not sequence_complete and not waiting_choice and lines.size() > 0 and revealed == 0 and not typing_done:
		stall_watchdog_t += delta
		if stall_watchdog_t > 0.6:
			push_warning("[Ending] stall watchdog 발동 line_idx=%d/%d" % [line_idx, lines.size()])
			var line: Dictionary = lines[line_idx] if line_idx < lines.size() else {}
			var full: String = str(line.get("text", ""))
			var prefix: String = "VEIL  —  " if str(line.get("speaker", "")) == "VEIL" else ""
			text_label.text = prefix + full
			revealed = full.length()
			typing_done = true
			silent_timer = 0.0
			# 한 라인만 보호 (stall이 잡힌 라인). 다음 _start_line이 다시 0으로 reset.
			stall_watchdog_t = -999.0
	# 시퀀스 완료 후엔 SPACE 누른 시간 누적 → 3초 채우면 타이틀로.
	if sequence_complete:
		if Input.is_action_pressed("jump") or Input.is_action_pressed("ui_skip"):
			hold_progress += delta
			if hold_progress_bar != null:
				hold_progress_bar.size.x = 260.0 * clamp(hold_progress / HOLD_TO_QUIT_DURATION, 0.0, 1.0)
			if hold_progress >= HOLD_TO_QUIT_DURATION:
				# 결말 → 크레딧. 크레딧 종료 시 GameState.reset() 후 타이틀로.
				get_tree().change_scene_to_file(SceneRouter.CREDITS)
				return
		else:
			hold_progress = max(0.0, hold_progress - delta * 1.5)  # 손 떼면 빠르게 줄어듦
			if hold_progress_bar != null:
				hold_progress_bar.size.x = 260.0 * clamp(hold_progress / HOLD_TO_QUIT_DURATION, 0.0, 1.0)
		return
	if line_idx >= lines.size():
		return
	var line: Dictionary = lines[line_idx]
	if line.get("silent", false):
		silent_timer += delta
		if silent_timer >= float(line.get("delay", 0.0)):
			line_idx += 1
			_start_line()
		return
	if not typing_done:
		t += delta
		if t >= TYPE_INTERVAL:
			t = 0.0
			revealed += 1
			var full: String = str(line.get("text", ""))
			if revealed >= full.length():
				revealed = full.length()
				typing_done = true
				silent_timer = 0.0
			var prefix: String = ""
			if str(line.get("speaker", "")) == "VEIL":
				prefix = "VEIL  —  "
			text_label.text = prefix + full.substr(0, revealed)
		return
	if line.get("choice", false):
		# choice 라인은 사용자가 선택할 때까지 진행 멈춤 — silent_timer로 자동 line_idx
		# 진행되어 _on_sequence_done이 먼저 호출되던 버그(사용자 보고: choice 누른 뒤
		# followup 안 나옴) 차단.
		if not waiting_choice:
			_show_choice()
		return
	silent_timer += delta
	if silent_timer >= float(line.get("delay", 1.5)):
		line_idx += 1
		_start_line()

func _show_choice() -> void:
	waiting_choice = true
	choice_box.visible = true
	for c in choice_box.get_children():
		c.queue_free()
	var b1 := Button.new()
	b1.text = "있어요"
	b1.add_theme_font_size_override("font_size", 16)
	b1.pressed.connect(_pick_choice.bind(true))
	choice_box.add_child(b1)
	var b2 := Button.new()
	b2.text = "없어요"
	b2.add_theme_font_size_override("font_size", 16)
	b2.pressed.connect(_pick_choice.bind(false))
	choice_box.add_child(b2)
	GameState.arm_focus_with_delay(self, b1)

func _pick_choice(asked: bool) -> void:
	waiting_choice = false
	choice_box.visible = false
	# 이전 choice 버튼 명시 정리 — 잔재 노드가 layout에 영향 주는 일 차단.
	for c in choice_box.get_children():
		c.queue_free()
	var explored_lore: bool = GameState.hidden_visit_count > 0 or GameState.visited_arcturus
	lines = EndingResolver.get_ending_c_followup(asked, explored_lore)
	line_idx = 0
	# typing 상태 변수 다시 정렬 — _start_line이 처리하지만 명시.
	revealed = 0
	t = 0.0
	typing_done = false
	silent_timer = 0.0
	stall_watchdog_t = 0.0
	# 안전판 — 어떤 경로로든 sequence_complete=true가 됐으면 다시 풀어줘야
	# _process의 typing 분기가 동작함 (이전 버그: hold_to_quit 분기로만 감).
	sequence_complete = false
	if hold_hint != null:
		hold_hint.visible = false
	if hold_progress_bar != null and hold_progress_bar.get_parent() is Control:
		(hold_progress_bar.get_parent() as Control).visible = false
	_start_line()

func _on_sequence_done() -> void:
	sequence_complete = true
	hint_label.text = ""
	if hold_hint != null:
		hold_hint.visible = true
	if hold_progress_bar != null and hold_progress_bar.get_parent() is Control:
		(hold_progress_bar.get_parent() as Control).visible = true

func _unhandled_input(event: InputEvent) -> void:
	# ESC는 최우선 — 결말 연출을 건너뛴다(입력 락아웃 무관). 선택지(있어요/없어요)는
	# 서사 분기라 ESC로 건너뛰지 않는다(그 경우 버튼으로만 진행).
	if event.is_action_pressed("ui_cancel") and not waiting_choice:
		get_viewport().set_input_as_handled()
		if sequence_complete:
			get_tree().change_scene_to_file(SceneRouter.CREDITS)  # 종료 프롬프트 → 바로 크레딧
		else:
			line_idx = lines.size()   # 내러티브 즉시 종료
			_on_sequence_done()       # 종료 프롬프트 노출
		return
	if waiting_choice:
		return
	# 시퀀스 완료 후엔 SPACE 단발은 무시 — 길게 누르기로만 타이틀 이동 (process에서 처리).
	if sequence_complete:
		return
	if input_lockout_t > 0.0:
		# 진입 직후 1초 동안 입력 무시 — 점프 연타 사고 방지.
		return
	if event.is_action_pressed("ui_skip") or event.is_action_pressed("jump"):
		# 한 줄 즉시 완성
		if line_idx < lines.size():
			var line: Dictionary = lines[line_idx]
			if line.get("silent", false):
				return  # 정적은 스킵 불가 (의도된 연출)
			if not typing_done:
				var full: String = str(line.get("text", ""))
				revealed = full.length()
				var prefix: String = "VEIL  —  " if str(line.get("speaker", "")) == "VEIL" else ""
				text_label.text = prefix + full
				typing_done = true
				silent_timer = 0.0
			else:
				silent_timer = 999.0
