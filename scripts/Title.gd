extends Control

# 다단계 메인 메뉴 — 키보드/마우스/패드 모두 동일한 흐름.
#   STATE_MAIN  : 게임 시작 / 설정 / 게임 종료
#   STATE_MODE  : 일반 모드 / 스토리 모드 / 뒤로
#   STATE_TUTOR : 튜토리얼부터 시작? 예 / 아니오 / 뒤로
# 각 단계는 Buttons VBox를 비우고 다시 빌드. ESC/패드 B는 한 단계 뒤로.

enum { STATE_MAIN, STATE_MODE, STATE_TUTOR, STATE_NEWGAME_CONFIRM }

@onready var hint_label: Label = $Center/V/Hint
@onready var buttons_box: VBoxContainer = $Center/V/Buttons
@onready var center_node: CenterContainer = $Center

var blink_t: float = 0.0
var settings_overlay: Control = null
var state: int = STATE_MAIN
# 모드 선택 단계에서 결정 — TUTOR 단계에서 사용.
var picked_story: bool = false
# STATE_MODE 전용 설명 패널 (오른쪽 회색 박스).
var description_panel: PanelContainer = null
var description_title_label: Label = null
var description_text_label: Label = null
var description_icon: ColorRect = null

func _ready() -> void:
	GameState.reset()
	# 웹 개인 플레이 — 도감(seen_enemies)·본 엔딩은 누적 영속. 부스 가정의 "매 진입=새 세션" 도감 리셋
	# 제거(2026-06-23 방향 전환). 진행 이어하기는 별도 run.cfg가 담당(reset과 무관).
	GameState.save_settings()
	GameState.input_kind_changed.connect(_on_input_kind_changed)
	# 메인 테마(Glass Protocol) — 타이틀/모드 선택/튜토리얼까지 동일 트랙 유지.
	BgmPlayer.play("main_theme")
	_build_description_panel()
	_set_state(STATE_MAIN)

func _build_description_panel() -> void:
	# STATE_MODE에서만 보이는 우측 회색 설명 박스. 포커스에 따라 동적 갱신.
	description_panel = PanelContainer.new()
	description_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	description_panel.anchor_left = 0.55
	# 사용자: 박스/텍스트 좀만 위로 — 0.36 → 0.20.
	description_panel.anchor_top = 0.20
	description_panel.anchor_right = 0.92
	description_panel.anchor_bottom = 0.65
	description_panel.visible = false
	description_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.14, 0.17, 0.92)
	sb.border_color = Color(0.45, 0.5, 0.6, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_left = 28
	sb.content_margin_right = 28
	sb.content_margin_top = 28
	sb.content_margin_bottom = 28
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	description_panel.add_theme_stylebox_override("panel", sb)
	add_child(description_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	description_panel.add_child(v)
	# 간단한 도형 아이콘 — 모드별 색깔 다름. 작은 사각형 + 외곽선 느낌.
	description_icon = ColorRect.new()
	description_icon.color = Color(0.62, 0.78, 0.92)
	description_icon.custom_minimum_size = Vector2(56, 56)
	description_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(description_icon)
	description_title_label = Label.new()
	description_title_label.add_theme_font_size_override("font_size", 22)
	description_title_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	description_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(description_title_label)
	description_text_label = Label.new()
	description_text_label.add_theme_font_size_override("font_size", 14)
	description_text_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	description_text_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	description_text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(description_text_label)

func _on_input_kind_changed(_kind: String) -> void:
	_refresh_hint()

func _refresh_hint() -> void:
	if hint_label == null:
		return
	match state:
		STATE_MAIN:
			hint_label.text = GameState.hint("[ ↑↓ 이동   Enter 선택 ]", "[ ↑↓ D-Pad   A 선택 ]")
			hint_label.add_theme_font_size_override("font_size", 16)
			hint_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		STATE_MODE:
			hint_label.text = "어느 모드로 시작할까요?"
			hint_label.add_theme_font_size_override("font_size", 22)
			hint_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
		STATE_TUTOR:
			hint_label.text = "튜토리얼부터 진행할까요?"
			hint_label.add_theme_font_size_override("font_size", 22)
			hint_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))

func _process(delta: float) -> void:
	blink_t += delta
	if hint_label != null:
		# 메인 메뉴에서만 가벼운 깜빡임. 질문 단계(MODE/TUTOR)는 또렷하게 고정.
		if state == STATE_MAIN:
			hint_label.modulate.a = 0.5 + 0.5 * sin(blink_t * 3.0)
		else:
			hint_label.modulate.a = 1.0
	# 포커스 가드 — 메뉴에서 포커스가 사라지면(예: snu 입력 중 's'(이동 매핑)가 포커스를 이탈시킴)
	# 첫 버튼으로 회수. 설정창 떠 있을 땐 설정창이 포커스를 가지므로 건드리지 않는다.
	if settings_overlay == null and buttons_box != null and buttons_box.get_child_count() > 0:
		if get_viewport().gui_get_focus_owner() == null:
			var first: Control = buttons_box.get_child(0) as Control
			if first != null:
				first.grab_focus()

func _set_state(new_state: int) -> void:
	state = new_state
	for c in buttons_box.get_children():
		c.queue_free()
	# 모드 선택일 때만 우측 설명 패널 + 좌측 정렬. 그 외엔 가운데 정렬·패널 숨김.
	if description_panel != null:
		description_panel.visible = (new_state == STATE_MODE)
	if center_node != null:
		center_node.anchor_right = 0.55 if new_state == STATE_MODE else 1.0
	match state:
		STATE_MAIN:
			var b_start := _make_button("게임 시작")
			b_start.pressed.connect(_on_start_pressed)
			buttons_box.add_child(b_start)
			# 이어하기 — 저장된 진행(run.cfg)이 있을 때만. 웹에서 닫았다 와도 스테이지 사이부터 재개.
			if GameState.has_run():
				var b_continue := _make_button("이어하기")
				b_continue.pressed.connect(_on_continue_pressed)
				buttons_box.add_child(b_continue)
			var b_settings := _make_button("설정")
			b_settings.pressed.connect(_on_settings_pressed)
			buttons_box.add_child(b_settings)
			var b_feedback := _make_button("피드백 보내기")
			b_feedback.pressed.connect(_on_feedback_pressed)
			buttons_box.add_child(b_feedback)
			# 웹(브라우저)에선 get_tree().quit()이 탭을 못 닫고 페이지만 멈춤(브라우저 보안: 스크립트가
			# 사용자가 직접 연 탭을 못 닫음) → 종료 버튼을 숨긴다(탭은 사용자가 닫음). 데스크톱만 종료 제공.
			if not OS.has_feature("web"):
				var b_quit := _make_button("게임 종료")
				b_quit.pressed.connect(_on_quit_pressed)
				buttons_box.add_child(b_quit)
			b_start.grab_focus.call_deferred()
		STATE_MODE:
			var b_normal := _make_button("일반 모드")
			b_normal.pressed.connect(_on_mode_pressed.bind(false))
			b_normal.focus_entered.connect(_on_mode_focused.bind("normal"))
			b_normal.mouse_entered.connect(_on_mode_focused.bind("normal"))
			buttons_box.add_child(b_normal)
			var b_story := _make_button("스토리 모드")
			b_story.pressed.connect(_on_mode_pressed.bind(true))
			b_story.focus_entered.connect(_on_mode_focused.bind("story"))
			b_story.mouse_entered.connect(_on_mode_focused.bind("story"))
			buttons_box.add_child(b_story)
			var b_back := _make_button("뒤로")
			b_back.pressed.connect(_on_back_pressed)
			b_back.focus_entered.connect(_on_mode_focused.bind("back"))
			b_back.mouse_entered.connect(_on_mode_focused.bind("back"))
			buttons_box.add_child(b_back)
			_on_mode_focused("normal")  # 초기 표시
			b_normal.grab_focus.call_deferred()
		STATE_TUTOR:
			var b_yes := _make_button("튜토리얼부터")
			b_yes.pressed.connect(_on_tutor_pressed.bind(true))
			buttons_box.add_child(b_yes)
			var b_no := _make_button("바로 시작")
			b_no.pressed.connect(_on_tutor_pressed.bind(false))
			buttons_box.add_child(b_no)
			var b_back := _make_button("뒤로")
			b_back.pressed.connect(_on_back_pressed)
			buttons_box.add_child(b_back)
			b_yes.grab_focus.call_deferred()
		STATE_NEWGAME_CONFIRM:
			# 진행 저장 덮어쓰기 경고(사용자 제안). 실제 삭제는 _on_tutor_pressed에서 — 여기선 안내·확인만.
			var warn := Label.new()
			warn.text = "진행 중인 게임이 있어요. 새로 시작하면 그 진행이 사라져요."
			warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.custom_minimum_size = Vector2(360, 0)
			warn.add_theme_font_size_override("font_size", 18)
			warn.add_theme_color_override("font_color", Color(0.95, 0.78, 0.5))
			warn.add_theme_color_override("font_outline_color", Color(0, 0, 0))
			warn.add_theme_constant_override("outline_size", 4)
			buttons_box.add_child(warn)
			var b_new := _make_button("새로 시작")
			b_new.pressed.connect(_set_state.bind(STATE_MODE))
			buttons_box.add_child(b_new)
			var b_cancel := _make_button("취소")
			b_cancel.pressed.connect(_set_state.bind(STATE_MAIN))
			buttons_box.add_child(b_cancel)
			b_cancel.grab_focus.call_deferred()
	SfxPlayer.wire_ui_buttons(buttons_box)
	_refresh_hint()

func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(360, 44)
	# 컨테이너 폭으로 늘어나지 않고 360 고정·가운데 — 박스가 너무 넓어 보이던 문제(사용자 보고).
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.add_theme_font_size_override("font_size", 18)
	return b

func _unhandled_input(event: InputEvent) -> void:
	if settings_overlay != null:
		return
	# 한 단계 뒤로 — ESC, 패드 B (둘 다 ui_cancel에 매핑).
	if event.is_action_pressed("ui_cancel"):
		if state != STATE_MAIN:
			_on_back_pressed()
			get_viewport().set_input_as_handled()

# 디버그 잠금 해제 키 시퀀스("snu") 추적은 _input에서 — _unhandled_input은 포커스/
# 내비게이션 시스템이 키를 소비한 뒤 호출되므로 's'(move_down 매핑)가 안 잡힘.
# (사용자 보고: snu 입력해도 잠금 해제 안 됨.)
# _input은 raw 이벤트 — 여기서는 추적만 하고 set_input_as_handled 호출 안 함 → 기존
# 이동/포커스 동작은 그대로 유지.
func _input(event: InputEvent) -> void:
	if settings_overlay != null:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_track_debug_unlock_sequence(event as InputEventKey)

const _DEBUG_CODE: String = "snu"
var _debug_input_buffer: String = ""

func _track_debug_unlock_sequence(ev: InputEventKey) -> void:
	if GameState.debug_unlocked:
		return
	# 키 라벨 가져오기 — 알파벳만 인정. unicode가 0이면 keycode로 폴백.
	var ch_int: int = ev.unicode
	if ch_int == 0:
		ch_int = ev.keycode
	if ch_int < 0x20 or ch_int > 0x7E:
		return
	var ch: String = String.chr(ch_int).to_lower()
	if ch.length() != 1:
		return
	_debug_input_buffer += ch
	if _debug_input_buffer.length() > _DEBUG_CODE.length():
		_debug_input_buffer = _debug_input_buffer.substr(_debug_input_buffer.length() - _DEBUG_CODE.length())
	if _debug_input_buffer == _DEBUG_CODE:
		GameState.debug_unlocked = true
		_show_debug_unlock_toast()

func _show_debug_unlock_toast() -> void:
	var toast := Label.new()
	toast.text = "디버그 모드 잠금 해제 — 설정 → 디버그 탭"
	toast.add_theme_font_size_override("font_size", 14)
	toast.add_theme_color_override("font_color", Color(0.95, 0.85, 0.30))
	toast.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	toast.add_theme_constant_override("outline_size", 3)
	toast.position = Vector2(20, 680)
	toast.size = Vector2(600, 24)
	add_child(toast)
	var tw := toast.create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(toast, "modulate:a", 0.0, 0.6)
	tw.tween_callback(toast.queue_free)

func _on_start_pressed() -> void:
	# 진행 중 저장이 있으면 새 게임이 그걸 덮어쓴다고 먼저 경고(사용자 제안). 없으면 바로 모드 선택.
	if GameState.has_run():
		_set_state(STATE_NEWGAME_CONFIRM)
	else:
		_set_state(STATE_MODE)

func _on_mode_focused(which: String) -> void:
	if description_title_label == null or description_text_label == null or description_icon == null:
		return
	match which:
		"normal":
			description_icon.color = Color(0.95, 0.55, 0.45)  # 주황 — 도전적
			description_title_label.text = "일반 모드"
			description_text_label.text = "전투와 회피가 중심.\n\n· HP 3\n· 7 스테이지\n· 보스 3페이즈\n· 드론·저격수 등 모든 적"
		"story":
			description_icon.color = Color(0.55, 0.85, 0.95)  # 푸름 — 부드러움
			description_title_label.text = "스토리 모드"
			description_text_label.text = "쉽게 따라오는 흐름.\n\n· HP 무제한\n· 5 스테이지\n· 보스 단순화\n· 드론 없음"
		"back":
			description_icon.color = Color(0.55, 0.6, 0.7)
			description_title_label.text = "뒤로"
			description_text_label.text = "메인 메뉴로 돌아가요."

func _on_mode_pressed(story: bool) -> void:
	picked_story = story
	GameState.story_mode = story
	_set_state(STATE_TUTOR)

func _on_continue_pressed() -> void:
	# 이어하기 — 저장된 런을 GameState에 복원하고 루트 선택(스테이지 사이)으로 복귀.
	if GameState.load_run():
		SceneRouter.go(get_tree(), SceneRouter.ROUTE_MAP)

func _on_tutor_pressed(want_tutorial: bool) -> void:
	# 새 게임 시작 — 이전 진행 저장(run.cfg) 삭제(이어하기와 분리). 모드는 모드 선택에서 이미 박혔다.
	GameState.clear_run()
	if want_tutorial:
		get_tree().change_scene_to_file(SceneRouter.TUTORIAL)
	else:
		get_tree().change_scene_to_file(SceneRouter.BRIEFING)

func _on_back_pressed() -> void:
	match state:
		STATE_TUTOR:
			# 모드 선택으로 — story_mode 다시 끄고 돌아감
			GameState.story_mode = false
			_set_state(STATE_MODE)
		STATE_MODE:
			_set_state(STATE_MAIN)
		STATE_NEWGAME_CONFIRM:
			_set_state(STATE_MAIN)

func _on_settings_pressed() -> void:
	if settings_overlay != null:
		return
	var packed := load(SceneRouter.SETTINGS) as PackedScene
	if packed == null:
		return
	settings_overlay = packed.instantiate()
	add_child(settings_overlay)
	if settings_overlay.has_signal("closed"):
		settings_overlay.closed.connect(_on_settings_closed)

func _on_settings_closed() -> void:
	if settings_overlay != null:
		settings_overlay.queue_free()
		settings_overlay = null
	# 설정 닫힌 뒤 포커스가 사라져 키/패드 입력이 먹히지 않던 버그 — 첫 버튼에 다시 포커스.
	if buttons_box.get_child_count() > 0:
		var first := buttons_box.get_child(0) as Button
		if first != null:
			first.grab_focus.call_deferred()

func _on_feedback_pressed() -> void:
	GameState.open_feedback()

func _on_quit_pressed() -> void:
	get_tree().quit()
