extends Control

signal closed

const ACTIONS: Array = [
	{"id": "move_left",  "name": "이동 (왼쪽)"},
	{"id": "move_right", "name": "이동 (오른쪽)"},
	{"id": "jump",       "name": "점프"},
	{"id": "attack",     "name": "사격"},
	{"id": "dash",       "name": "대시"},
	{"id": "skill",      "name": "액티브 스킬 (폭발물 등)"},
	{"id": "pause",      "name": "일시정지 / 메뉴"},
]

const MAX_KEYS_PER_ACTION: int = 2

var capturing_action: String = ""
var capturing_index: int = -1
var capturing_button: Button = null

var key_buttons: Dictionary = {}  # action_id -> Array[Button]

var dim: ColorRect
var panel: PanelContainer
var tabs: TabContainer

# 위/아래 포커스 hold 연속 이동 (사용자 피드백: "쭉 누르고 있어도 드르륵").
# 사용자 후속: 속도 좀 더 늦게 — 0.06 → 0.18로.
const NAV_INITIAL_DELAY: float = 0.4
const NAV_REPEAT_INTERVAL: float = 0.18
var nav_dir: int = 0
var nav_hold_t: float = 0.0
var nav_repeat_t: float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	dim = ColorRect.new()
	dim.color = Color(0, 0, 0, 0.85)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(center)

	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 580)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.07, 0.08, 0.10, 0.98)
	panel_style.border_color = Color(0.55, 0.62, 0.78, 0.55)
	panel_style.set_border_width_all(1)
	panel_style.content_margin_left = 36
	panel_style.content_margin_right = 36
	panel_style.content_margin_top = 32
	panel_style.content_margin_bottom = 32
	panel_style.corner_radius_top_left = 6
	panel_style.corner_radius_top_right = 6
	panel_style.corner_radius_bottom_left = 6
	panel_style.corner_radius_bottom_right = 6
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	panel.add_child(v)

	var title := Label.new()
	title.text = "설정"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	v.add_child(title)

	var divider := ColorRect.new()
	divider.color = Color(0.55, 0.62, 0.78, 0.30)
	divider.custom_minimum_size = Vector2(0, 1)
	v.add_child(divider)

	var tab_hint := Label.new()
	tab_hint.text = "탭 전환: Q / E   (패드: LB / RB)"
	tab_hint.add_theme_font_size_override("font_size", 12)
	tab_hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
	v.add_child(tab_hint)

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.custom_minimum_size = Vector2(0, 380)
	# 위쪽 탭 헤더는 포커스 받지 않게 — 사용자: "포커스가 위로 올라가지 않게".
	# 탭 전환은 Q/E (패드 LB/RB)로만.
	tabs.focus_mode = Control.FOCUS_NONE
	v.add_child(tabs)

	tabs.add_child(_build_keybind_tab())
	tabs.add_child(_build_av_tab())
	tabs.add_child(_build_accessibility_tab())
	tabs.add_child(_build_credits_tab())
	# 디버그 탭은 잠금 해제(GameState.debug_unlocked) 시에만 노출.
	# 잠금 해제는 Title 화면에서 비밀 키 시퀀스 "snu" 입력으로.
	if GameState.debug_unlocked:
		tabs.add_child(_build_debug_tab())

	var divider2 := ColorRect.new()
	divider2.color = Color(0.55, 0.62, 0.78, 0.30)
	divider2.custom_minimum_size = Vector2(0, 1)
	v.add_child(divider2)

	var bottom_hb := HBoxContainer.new()
	bottom_hb.alignment = BoxContainer.ALIGNMENT_END
	bottom_hb.add_theme_constant_override("separation", 12)
	v.add_child(bottom_hb)
	var btn_reset := _make_secondary_button("기본값으로")
	btn_reset.pressed.connect(_on_reset_pressed)
	bottom_hb.add_child(btn_reset)
	var btn_close := _make_primary_button("닫기")
	btn_close.pressed.connect(_on_close_pressed)
	bottom_hb.add_child(btn_close)

	_refresh_all_keybind_buttons()
	# 진입 시 첫 키바인드 버튼에 포커스 잡기 (1s 락아웃 — 메뉴 연타 사고 방지).
	# arm_focus_with_delay가 host 아래 Button들에 ui_focus/ui_confirm SFX도 자동 wire.
	if ACTIONS.size() > 0:
		var first_btns: Array = key_buttons.get(str(ACTIONS[0]["id"]), [])
		if first_btns.size() > 0 and first_btns[0] is Button:
			GameState.arm_focus_with_delay(self, first_btns[0])

func _build_keybind_tab() -> Control:
	var outer := MarginContainer.new()
	outer.name = "조작법"
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	outer.add_child(v)

	var hint := Label.new()
	hint.text = "키 또는 마우스 버튼을 변경하려면 슬롯을 클릭한 뒤 새 입력을 누르세요. 각 액션당 최대 2개까지 등록할 수 있어요."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(hint)

	# 게임패드 안내 — Xbox 컨트롤러 기본 매핑. 슬롯에는 키/마우스만 표시되지만,
	# 패드는 별도로 항상 활성화되어 있음 (project.godot 기본값 + 리셋 시에도 복원).
	var pad_hint := Label.new()
	pad_hint.text = "Xbox 컨트롤러:  좌스틱/D-Pad 이동 · A 점프 · X 사격(또는 RT) · B 대시(또는 RB) · Y 스킬 · START 메뉴"
	pad_hint.add_theme_font_size_override("font_size", 12)
	pad_hint.add_theme_color_override("font_color", Color(0.55, 0.65, 0.78))
	pad_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(pad_hint)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	v.add_child(grid)

	for entry in ACTIONS:
		var action_id: String = str(entry["id"])
		var label := Label.new()
		label.text = str(entry["name"])
		label.custom_minimum_size = Vector2(180, 36)
		label.add_theme_font_size_override("font_size", 15)
		label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grid.add_child(label)

		var btns: Array = []
		for i in MAX_KEYS_PER_ACTION:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(160, 36)
			btn.add_theme_font_size_override("font_size", 15)
			# 가로/세로 size_flags를 SHRINK으로 고정 → 텍스트 길이로 인한 column 폭 변화 방지
			# (이전엔 "마우스 왼쪽" 등 긴 라벨이 있는 행에서 포커스 이동이 두 번 필요했음).
			btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			btn.clip_text = true
			btn.pressed.connect(_on_key_button_pressed.bind(action_id, i, btn))
			grid.add_child(btn)
			btns.append(btn)
		key_buttons[action_id] = btns
	# 명시적 focus_neighbor 설정 — 같은 column 내 위/아래 이동을 결정적으로.
	# Godot 자동 계산은 인접 cell의 geometry가 미세하게 어긋나면(라벨 폭 차이 등)
	# "두 번 눌러야 이동" 같은 결과를 낳을 수 있어서 직접 잡아준다.
	_wire_keybind_focus()
	return outer

func _wire_keybind_focus() -> void:
	for action_idx in ACTIONS.size():
		var aid: String = str(ACTIONS[action_idx]["id"])
		var btns: Array = key_buttons.get(aid, [])
		if btns.size() < MAX_KEYS_PER_ACTION:
			continue
		var prev_btns: Array = []
		var next_btns: Array = []
		if action_idx > 0:
			prev_btns = key_buttons.get(str(ACTIONS[action_idx - 1]["id"]), [])
		if action_idx < ACTIONS.size() - 1:
			next_btns = key_buttons.get(str(ACTIONS[action_idx + 1]["id"]), [])
		for col in MAX_KEYS_PER_ACTION:
			var btn: Button = btns[col] as Button
			if btn == null:
				continue
			if prev_btns.size() > col and prev_btns[col] is Control:
				btn.focus_neighbor_top = btn.get_path_to(prev_btns[col])
			else:
				# 첫 행 — 위로 더 못 가게 (탭 헤더로 안 새도록).
				btn.focus_neighbor_top = btn.get_path_to(btn)
			if next_btns.size() > col and next_btns[col] is Control:
				btn.focus_neighbor_bottom = btn.get_path_to(next_btns[col])
			if col == 0 and btns.size() > 1 and btns[1] is Control:
				btn.focus_neighbor_right = btn.get_path_to(btns[1])
			if col == 1 and btns[0] is Control:
				btn.focus_neighbor_left = btn.get_path_to(btns[0])

func _build_debug_tab() -> Control:
	var outer := MarginContainer.new()
	outer.name = "디버그"
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	outer.add_child(v)

	v.add_child(_make_section_header("연습장"))

	var note := Label.new()
	note.text = "스테이지/루트/난이도를 자유롭게 바꿔가며 테스트할 수 있어요. HUD에 토글 패널이 떠 있어 그 자리에서 설정을 바꾸면 맵이 즉시 다시 생성됩니다. 일반 진행 데이터에는 영향 없음."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)

	var enter_btn := Button.new()
	enter_btn.text = "연습장으로 진입"
	enter_btn.custom_minimum_size = Vector2(220, 40)
	enter_btn.add_theme_font_size_override("font_size", 14)
	enter_btn.pressed.connect(_on_playground_pressed)
	v.add_child(enter_btn)

	# 엔딩 미리보기 — 4종 직접 진입. trust/aggression 점수를 임시 세팅해 EndingResolver
	# 분기를 강제하고, lore도 explored 상태로 설정해 풀 멘트를 보여준다.
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	v.add_child(spacer)
	v.add_child(_make_section_header("엔딩 미리보기"))
	var endings_note := Label.new()
	endings_note.text = "각 엔딩을 즉시 진입해 텍스트·BGM·연출을 확인. 진행 데이터는 갱신되지 않아요."
	endings_note.add_theme_font_size_override("font_size", 13)
	endings_note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	endings_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(endings_note)
	var ending_row := HBoxContainer.new()
	ending_row.add_theme_constant_override("separation", 10)
	v.add_child(ending_row)
	var ending_btns: Array = []
	for entry in [
		{"id": "A", "label": "엔딩 A — 완벽한 도구"},
		{"id": "B", "label": "엔딩 B — 혼자였던 사람"},
		{"id": "C", "label": "엔딩 C — 공생"},
		{"id": "D", "label": "엔딩 D — 유령 임무"},
	]:
		var d: Dictionary = entry
		var btn := Button.new()
		btn.text = str(d["label"])
		btn.custom_minimum_size = Vector2(160, 36)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(_on_ending_preview_pressed.bind(str(d["id"])))
		ending_row.add_child(btn)
		ending_btns.append(btn)
	# 세로 포커스 연결 — 연습장 버튼 ↕ 엔딩 행. (HBox 내부 좌우는 Godot 자동.) 명시 안 하면
	# 키보드로 엔딩 버튼에 도달 못 하던 문제(사용자 보고). 좌우는 기본 geometry로 충분.
	if ending_btns.size() > 0:
		var first_ending: Button = ending_btns[0] as Button
		enter_btn.focus_neighbor_bottom = enter_btn.get_path_to(first_ending)
		for b in ending_btns:
			var eb: Button = b as Button
			eb.focus_neighbor_top = eb.get_path_to(enter_btn)

	return outer

# 엔딩 미리보기 진입 — trust/aggression을 EndingResolver 임계값에 맞춰 강제 세팅.
# explored_lore는 hidden_visit_count + visited_arcturus 둘 중 하나만 있어도 true.
# 기존 진행도는 백업 안 함 — 디버그 용도라 진행 데이터 손실은 무시 (사용자가 알고 누름).
func _on_ending_preview_pressed(ending_id: String) -> void:
	var t: int = GameState.SCORE_THRESHOLD
	# 엔딩 미리보기 — 새 엔딩축(추천 수용률 + 공격성)을 강제. rec_count=4 분모 고정,
	# followed_count로 신뢰 on/off. trust_score는 stats 표시용으로만 같이 세팅.
	GameState.rec_count = 4
	match ending_id:
		"A":
			GameState.followed_count = 4
			GameState.aggression_score = t
			GameState.trust_score = 12
		"B":
			GameState.followed_count = 0
			GameState.aggression_score = t
			GameState.trust_score = 0
		"C":
			GameState.followed_count = 4
			GameState.aggression_score = 0
			GameState.trust_score = 12
		"D":
			GameState.followed_count = 0
			GameState.aggression_score = 0
			GameState.trust_score = 0
	# explored_lore=true 풀 멘트 보기. (false 버전 보고 싶으면 둘 다 false 후 진입)
	GameState.visited_arcturus = true
	get_tree().paused = false
	get_tree().change_scene_to_file(SceneRouter.ENDING)

func _on_playground_pressed() -> void:
	GameState.playground_active = true
	GameState.current_stage = 0
	GameState.current_route_id = "route_lab"
	GameState.current_route_tags = ["전투", "드론", "밝은_환경"]
	GameState.current_route_risk = 2
	GameState.current_route_reward = 2
	GameState.player_hp = GameState.player_max_hp
	GameState.player_xp = 0
	GameState.player_level = 1
	# pause 메뉴에서 진입한 경우 paused 해제 후 scene 전환
	get_tree().paused = false
	get_tree().change_scene_to_file(SceneRouter.STAGE)

func _build_av_tab() -> Control:
	var outer := MarginContainer.new()
	outer.name = "그래픽 / 사운드"
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	outer.add_child(v)

	v.add_child(_make_display_section())

	var section_b := VBoxContainer.new()
	section_b.add_theme_constant_override("separation", 10)
	v.add_child(section_b)
	section_b.add_child(_make_section_header("사운드"))
	section_b.add_child(_make_volume_row("배경음 볼륨", "bgm"))
	section_b.add_child(_make_volume_row("효과음 볼륨", "sfx"))
	return outer

# 화면 섹션 — 전체화면 토글 + 창 크기 프리셋. 값은 GameState에 영속, apply_display_settings로 즉시 반영.
# 웹에선 창 크기를 브라우저가 정하므로 전체화면 토글과 안내만 노출.
var _fullscreen_toggle: CheckButton
var _size_buttons: Array = []

func _make_display_section() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.add_child(_make_section_header("화면"))

	var fs_row := HBoxContainer.new()
	fs_row.add_theme_constant_override("separation", 14)
	var fs_l := Label.new()
	fs_l.text = "전체화면"
	fs_l.custom_minimum_size = Vector2(140, 28)
	fs_l.add_theme_font_size_override("font_size", 14)
	fs_l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	fs_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fs_row.add_child(fs_l)
	_fullscreen_toggle = CheckButton.new()
	_fullscreen_toggle.button_pressed = GameState.fullscreen
	_fullscreen_toggle.text = "켜짐" if GameState.fullscreen else "꺼짐"
	_fullscreen_toggle.add_theme_font_size_override("font_size", 14)
	_fullscreen_toggle.toggled.connect(_on_fullscreen_toggled)
	fs_row.add_child(_fullscreen_toggle)
	v.add_child(fs_row)

	# 웹: 창 크기는 브라우저 캔버스가 정함 → 프리셋 버튼 없이 안내만.
	if OS.has_feature("web"):
		var web_note := Label.new()
		web_note.text = "창 크기는 브라우저 창에 맞춰져요. 전체화면은 위 토글로 전환하세요."
		web_note.add_theme_font_size_override("font_size", 13)
		web_note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
		web_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(web_note)
		return v

	var size_l := Label.new()
	size_l.text = "창 크기"
	size_l.add_theme_font_size_override("font_size", 14)
	size_l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	v.add_child(size_l)
	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 10)
	v.add_child(size_row)
	_size_buttons.clear()
	for i in GameState.WINDOW_SIZES.size():
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(140, 36)
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(_on_window_size_pressed.bind(i))
		size_row.add_child(btn)
		_size_buttons.append(btn)
	_refresh_size_buttons()
	# 에디터 임베드 미리보기는 창 리사이즈를 막는다("Embedded window can't be resized").
	# 내보낸 빌드에선 즉시 적용되므로, 에디터에서 돌릴 때만 안내를 띄운다(최종 빌드엔 안 보임).
	if OS.has_feature("editor"):
		var ed_note := Label.new()
		ed_note.text = "에디터 미리보기는 임베드 창이라 크기가 안 바뀔 수 있어요. 내보낸 빌드에선 바로 적용돼요."
		ed_note.add_theme_font_size_override("font_size", 12)
		ed_note.add_theme_color_override("font_color", Color(0.78, 0.7, 0.5))
		ed_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		v.add_child(ed_note)
	return v

# 창 크기 버튼 라벨·색·활성 상태 갱신. 선택=● 강조, 전체화면이면 전체 비활성(창 크기 무의미).
func _refresh_size_buttons() -> void:
	var fs: bool = GameState.fullscreen
	for i in _size_buttons.size():
		var btn: Button = _size_buttons[i] as Button
		if btn == null:
			continue
		var sz: Vector2i = GameState.WINDOW_SIZES[i]
		var selected: bool = (i == GameState.window_size_index)
		btn.text = "%s  %d × %d" % ["●" if selected else "○", sz.x, sz.y]
		btn.disabled = fs
		var col: Color = Color(0.5, 0.55, 0.62) if fs else (Color(0.96, 0.92, 0.55) if selected else Color(0.85, 0.88, 0.92))
		btn.add_theme_color_override("font_color", col)

func _on_fullscreen_toggled(pressed: bool) -> void:
	GameState.fullscreen = pressed
	if _fullscreen_toggle != null:
		_fullscreen_toggle.text = "켜짐" if pressed else "꺼짐"
	GameState.apply_display_settings()
	GameState.save_settings()
	SfxPlayer.play("ui_slider_tick")
	_refresh_size_buttons()

func _on_window_size_pressed(index: int) -> void:
	GameState.window_size_index = index
	GameState.apply_display_settings()
	GameState.save_settings()
	SfxPlayer.play("ui_slider_tick")
	_refresh_size_buttons()

# 접근성 탭 — 화면 밝기 + 효과음 자막. 값은 GameState에 영속, Accessibility 오버레이가 반영.
func _build_accessibility_tab() -> Control:
	var outer := MarginContainer.new()
	outer.name = "접근성"
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	outer.add_child(v)

	v.add_child(_make_section_header("화면 밝기"))
	var bri_note := Label.new()
	bri_note.text = "화면이 너무 어둡거나 밝게 느껴지면 조절하세요. 기본 100%."
	bri_note.add_theme_font_size_override("font_size", 13)
	bri_note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	bri_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(bri_note)
	v.add_child(_make_brightness_row())

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	v.add_child(spacer)

	v.add_child(_make_section_header("효과음 자막"))
	var cap_note := Label.new()
	cap_note.text = "소리 없이 플레이할 때, 중요한 효과음(적 사격·폭발·경보 등)을 화면 우하단에 글로 표시해요."
	cap_note.add_theme_font_size_override("font_size", 13)
	cap_note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	cap_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(cap_note)
	v.add_child(_make_captions_row())
	return outer

var _brightness_value_label: Label

func _make_brightness_row() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = "밝기"
	l.custom_minimum_size = Vector2(110, 28)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.5
	slider.max_value = 1.5
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(260, 28)
	slider.value = GameState.screen_brightness
	slider.value_changed.connect(_on_brightness_changed)
	hb.add_child(slider)
	_brightness_value_label = Label.new()
	_brightness_value_label.custom_minimum_size = Vector2(56, 28)
	_brightness_value_label.add_theme_font_size_override("font_size", 14)
	_brightness_value_label.add_theme_color_override("font_color", Color(0.78, 0.82, 0.9))
	_brightness_value_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_brightness_value_label.text = "%d%%" % int(round(GameState.screen_brightness * 100.0))
	hb.add_child(_brightness_value_label)
	return hb

func _on_brightness_changed(value: float) -> void:
	GameState.screen_brightness = value
	Accessibility.apply()
	if _brightness_value_label != null:
		_brightness_value_label.text = "%d%%" % int(round(value * 100.0))
	SfxPlayer.play("ui_slider_tick")
	GameState.save_settings()

func _make_captions_row() -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = "효과음 자막"
	l.custom_minimum_size = Vector2(110, 28)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	var toggle := CheckButton.new()
	toggle.button_pressed = GameState.sfx_captions
	toggle.text = "켜짐" if GameState.sfx_captions else "꺼짐"
	toggle.add_theme_font_size_override("font_size", 14)
	toggle.toggled.connect(_on_captions_toggled.bind(toggle))
	hb.add_child(toggle)
	return hb

func _on_captions_toggled(pressed: bool, toggle: CheckButton) -> void:
	GameState.sfx_captions = pressed
	toggle.text = "켜짐" if pressed else "꺼짐"
	GameState.save_settings()
	# 켤 때 위치/모양을 보여주는 예시 한 줄.
	if pressed:
		Accessibility.preview_caption()

# 크레딧 탭 — 패널에서 직접 띄우는 오버레이. Settings를 닫지 않고 그 위에 겹쳐 띄움.
func _build_credits_tab() -> Control:
	var outer := MarginContainer.new()
	outer.name = "크레딧"
	outer.add_theme_constant_override("margin_left", 16)
	outer.add_theme_constant_override("margin_right", 16)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	outer.add_child(v)
	v.add_child(_make_section_header("크레딧"))
	var note := Label.new()
	note.text = "제작·음악·폰트 등 이 게임에 들어간 것들. 게임 마지막에도 자동으로 한 번 흐름.\n오버레이로 띄워서 ESC로 즉시 닫을 수 있어요."
	note.add_theme_font_size_override("font_size", 13)
	note.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var open_btn := Button.new()
	open_btn.text = "크레딧 보기"
	open_btn.custom_minimum_size = Vector2(220, 40)
	open_btn.add_theme_font_size_override("font_size", 14)
	open_btn.pressed.connect(_on_credits_open_pressed)
	v.add_child(open_btn)
	return outer

var credits_overlay: Control = null

func _on_credits_open_pressed() -> void:
	if credits_overlay != null:
		return
	var packed := load(SceneRouter.CREDITS) as PackedScene
	if packed == null:
		return
	credits_overlay = packed.instantiate()
	credits_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	# overlay 모드 진입 — 닫혀도 scene 전환 없이 emit_signal("closed")만.
	if credits_overlay.has_method("open_as_overlay"):
		credits_overlay.open_as_overlay()
	add_child(credits_overlay)
	if credits_overlay.has_signal("closed"):
		credits_overlay.closed.connect(_on_credits_closed)

func _on_credits_closed() -> void:
	if credits_overlay != null:
		credits_overlay.queue_free()
		credits_overlay = null

func _make_section_header(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", Color(0.85, 0.88, 0.95))
	return l

func _make_volume_row(label_text: String, kind: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var l := Label.new()
	l.text = label_text
	l.custom_minimum_size = Vector2(140, 28)
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(280, 28)
	slider.value = GameState.bgm_volume if kind == "bgm" else GameState.sfx_volume
	slider.value_changed.connect(_on_volume_changed.bind(kind))
	hb.add_child(slider)
	return hb

func _make_primary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(120, 36)
	b.add_theme_font_size_override("font_size", 14)
	return b

func _make_secondary_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(140, 36)
	b.add_theme_font_size_override("font_size", 13)
	return b

func _on_volume_changed(value: float, kind: String) -> void:
	SfxPlayer.play("ui_slider_tick")
	if kind == "bgm":
		GameState.bgm_volume = value
		# BGM autoload — 배경음 볼륨 즉시 반영(다음 트랙 전환까지 기다리지 않게).
		BgmPlayer.refresh_volume()
	else:
		GameState.sfx_volume = value
		# SfxPlayer._target_db()가 매 play 호출 시 GameState.sfx_volume 참조 — 즉시 반영.
	GameState.save_settings()

func _refresh_all_keybind_buttons() -> void:
	for entry in ACTIONS:
		var action_id: String = str(entry["id"])
		var btns: Array = key_buttons.get(action_id, [])
		var events: Array = []
		if InputMap.has_action(action_id):
			events = InputMap.action_get_events(action_id)
		for i in btns.size():
			var btn: Button = btns[i]
			if i < events.size():
				btn.text = _event_label(events[i])
			else:
				btn.text = "—"
			btn.disabled = false

func _event_label(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var ke := ev as InputEventKey
		var kc: int = ke.physical_keycode
		if kc == 0:
			kc = ke.keycode
		var n := OS.get_keycode_string(kc)
		if n == "":
			n = "Key %d" % kc
		return n
	elif ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:   return "마우스 왼쪽"
			MOUSE_BUTTON_RIGHT:  return "마우스 오른쪽"
			MOUSE_BUTTON_MIDDLE: return "마우스 가운데"
			MOUSE_BUTTON_XBUTTON1: return "마우스 X1"
			MOUSE_BUTTON_XBUTTON2: return "마우스 X2"
			_: return "마우스 버튼 %d" % mb.button_index
	elif ev is InputEventJoypadButton:
		var jb := ev as InputEventJoypadButton
		match jb.button_index:
			JOY_BUTTON_A: return "패드 A"
			JOY_BUTTON_B: return "패드 B"
			JOY_BUTTON_X: return "패드 X"
			JOY_BUTTON_Y: return "패드 Y"
			JOY_BUTTON_LEFT_SHOULDER: return "패드 LB"
			JOY_BUTTON_RIGHT_SHOULDER: return "패드 RB"
			JOY_BUTTON_BACK: return "패드 BACK"
			JOY_BUTTON_START: return "패드 START"
			JOY_BUTTON_DPAD_UP: return "패드 ↑"
			JOY_BUTTON_DPAD_DOWN: return "패드 ↓"
			JOY_BUTTON_DPAD_LEFT: return "패드 ←"
			JOY_BUTTON_DPAD_RIGHT: return "패드 →"
			_: return "패드 버튼 %d" % jb.button_index
	elif ev is InputEventJoypadMotion:
		var jm := ev as InputEventJoypadMotion
		var sign_str: String = "+" if jm.axis_value >= 0.0 else "-"
		match jm.axis:
			JOY_AXIS_LEFT_X: return "좌스틱 " + ("→" if sign_str == "+" else "←")
			JOY_AXIS_LEFT_Y: return "좌스틱 " + ("↓" if sign_str == "+" else "↑")
			JOY_AXIS_RIGHT_X: return "우스틱 " + ("→" if sign_str == "+" else "←")
			JOY_AXIS_RIGHT_Y: return "우스틱 " + ("↓" if sign_str == "+" else "↑")
			JOY_AXIS_TRIGGER_LEFT: return "패드 LT"
			JOY_AXIS_TRIGGER_RIGHT: return "패드 RT"
			_: return "축 %d %s" % [jm.axis, sign_str]
	return "—"

func _on_key_button_pressed(action_id: String, index: int, btn: Button) -> void:
	if capturing_action != "":
		return
	capturing_action = action_id
	capturing_index = index
	capturing_button = btn
	btn.text = "새 키를 누르세요..."
	_set_all_buttons_disabled(true)
	btn.disabled = true

func _set_all_buttons_disabled(value: bool) -> void:
	for action_id in key_buttons.keys():
		for b in key_buttons[action_id]:
			(b as Button).disabled = value

func _process(delta: float) -> void:
	# 위/아래 hold 연속 이동 — Godot 기본 ui_up/down은 echo로 자동 반복되지 않음.
	if capturing_action != "":
		return
	# 포커스 가드 — 포커스가 설정창 밖(뒤 메뉴 버튼 등)으로 새면 즉시 현재 탭으로 회수.
	# (사용자 보고: 설정창이 떠 있는데 뒤 메뉴가 선택되던 누수.) focus가 null인 경우는
	# 진입 직후 arm_focus_with_delay의 1초 락아웃이라 건드리지 않는다.
	var fo: Control = get_viewport().gui_get_focus_owner()
	if fo != null and not is_ancestor_of(fo):
		_focus_first_in_current_tab()
		return
	var new_dir: int = 0
	if Input.is_action_pressed("ui_up"):
		new_dir = -1
	elif Input.is_action_pressed("ui_down"):
		new_dir = 1
	if new_dir != nav_dir:
		nav_dir = new_dir
		nav_hold_t = 0.0
		nav_repeat_t = NAV_INITIAL_DELAY
		return
	if nav_dir == 0:
		return
	nav_hold_t += delta
	nav_repeat_t -= delta
	if nav_hold_t >= NAV_INITIAL_DELAY and nav_repeat_t <= 0.0:
		_step_focus_vertical(nav_dir)
		nav_repeat_t = NAV_REPEAT_INTERVAL

func _step_focus_vertical(dir: int) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused == null or not (focused is Control):
		return
	var ctrl: Control = focused as Control
	var side: int = SIDE_TOP if dir < 0 else SIDE_BOTTOM
	var nb: Control = ctrl.find_valid_focus_neighbor(side)
	if nb != null:
		nb.grab_focus()

# 현재 탭의 첫 조작 가능한 컨트롤로 포커스를 옮긴다. 탭 전환(Q/E) 직후 호출 — 안 그러면
# 포커스가 이전 탭(숨겨진 키바인드 버튼 등)에 남아 키보드 네비가 안 되고 뒤 메뉴로 새어나간다.
func _focus_first_in_current_tab() -> void:
	if tabs == null:
		return
	var content: Control = tabs.get_current_tab_control()
	if content == null:
		return
	var target: Control = _first_focusable(content)
	if target != null:
		target.grab_focus()

func _first_focusable(node: Node) -> Control:
	if node is Control:
		var c: Control = node as Control
		if c.visible and c.focus_mode != Control.FOCUS_NONE and not (c is Button and (c as Button).disabled):
			return c
	for child in node.get_children():
		var found: Control = _first_focusable(child)
		if found != null:
			return found
	return null

func _input(event: InputEvent) -> void:
	# 캡쳐 중엔 아래 분기만. 그 외엔 Q/E or LB/RB로 탭 전환 가능.
	if capturing_action == "":
		# ESC/뒤로 = 닫기 (최우선). 캡쳐 중 ESC는 아래에서 캡쳐 취소로 처리되므로 여기선 제외.
		if event.is_action_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			_on_close_pressed()
			return
		var tab_dir: int = 0
		if event is InputEventKey:
			var ke := event as InputEventKey
			if ke.pressed and not ke.echo:
				if ke.keycode == KEY_Q:
					tab_dir = -1
				elif ke.keycode == KEY_E:
					tab_dir = 1
		elif event is InputEventJoypadButton:
			var jb := event as InputEventJoypadButton
			if jb.pressed:
				if jb.button_index == JOY_BUTTON_LEFT_SHOULDER:
					tab_dir = -1
				elif jb.button_index == JOY_BUTTON_RIGHT_SHOULDER:
					tab_dir = 1
		if tab_dir != 0 and tabs != null:
			var n: int = tabs.get_tab_count()
			if n > 0:
				tabs.current_tab = (tabs.current_tab + tab_dir + n) % n
				# 새 탭의 첫 컨트롤로 포커스 이동 — 모든 탭에서 키보드 네비가 되고 포커스가 안 샌다.
				_focus_first_in_current_tab()
			get_viewport().set_input_as_handled()
			return
	if capturing_action == "":
		return
	var new_ev: InputEvent = null
	if event is InputEventKey:
		var ke := event as InputEventKey
		if not ke.pressed or ke.echo:
			return
		get_viewport().set_input_as_handled()
		if ke.physical_keycode == KEY_ESCAPE and capturing_action != "pause":
			_cancel_capture()
			return
		var key_ev := InputEventKey.new()
		key_ev.physical_keycode = ke.physical_keycode
		new_ev = key_ev
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed or mb.canceled:
			return
		# 휠/드래그는 무시
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_LEFT or mb.button_index == MOUSE_BUTTON_WHEEL_RIGHT:
			return
		get_viewport().set_input_as_handled()
		var mouse_ev := InputEventMouseButton.new()
		mouse_ev.button_index = mb.button_index
		new_ev = mouse_ev
	else:
		return

	var action_id: String = capturing_action
	var index: int = capturing_index
	# UI 슬롯은 키보드/마우스만 표시·편집. 조이패드 이벤트는 보존해 따로 다시 등록.
	var kb_events: Array = []
	var preserved_pad: Array = []
	if InputMap.has_action(action_id):
		for ev in InputMap.action_get_events(action_id):
			if ev is InputEventKey or ev is InputEventMouseButton:
				kb_events.append(ev)
			else:
				preserved_pad.append(ev)
	var new_events: Array = []
	for e in kb_events:
		new_events.append(e)
	while new_events.size() <= index:
		new_events.append(null)
	new_events[index] = new_ev

	InputMap.action_erase_events(action_id)
	for e in new_events:
		if e is InputEventKey or e is InputEventMouseButton:
			InputMap.action_add_event(action_id, e)
	for e in preserved_pad:
		InputMap.action_add_event(action_id, e)

	capturing_action = ""
	capturing_index = -1
	capturing_button = null
	_set_all_buttons_disabled(false)
	_refresh_all_keybind_buttons()
	GameState.save_settings()

func _cancel_capture() -> void:
	capturing_action = ""
	capturing_index = -1
	capturing_button = null
	_set_all_buttons_disabled(false)
	_refresh_all_keybind_buttons()

func _on_reset_pressed() -> void:
	_apply_default_keybindings()
	_refresh_all_keybind_buttons()
	GameState.save_settings()

func _apply_default_keybindings() -> void:
	# 각 entry: ["key", keycode] / ["mouse", button] / ["pad", JOY_BUTTON_*] / ["axis", axis, value]
	var defaults := {
		"move_left":  [["key", KEY_A], ["key", KEY_LEFT], ["pad", JOY_BUTTON_DPAD_LEFT], ["axis", JOY_AXIS_LEFT_X, -1.0]],
		"move_right": [["key", KEY_D], ["key", KEY_RIGHT], ["pad", JOY_BUTTON_DPAD_RIGHT], ["axis", JOY_AXIS_LEFT_X, 1.0]],
		"jump":       [["key", KEY_W], ["key", KEY_SPACE], ["key", KEY_Z], ["key", KEY_UP], ["pad", JOY_BUTTON_A]],
		"attack":     [["key", KEY_J], ["key", KEY_X], ["mouse", MOUSE_BUTTON_LEFT], ["pad", JOY_BUTTON_X], ["axis", JOY_AXIS_TRIGGER_RIGHT, 1.0]],
		"dash":       [["key", KEY_K], ["key", KEY_C], ["key", KEY_SHIFT], ["pad", JOY_BUTTON_B], ["pad", JOY_BUTTON_RIGHT_SHOULDER]],
		"skill":      [["key", KEY_L], ["key", KEY_V], ["mouse", MOUSE_BUTTON_RIGHT], ["pad", JOY_BUTTON_Y]],
		"pause":      [["key", KEY_ESCAPE], ["pad", JOY_BUTTON_START]],
	}
	for action_id in defaults.keys():
		if not InputMap.has_action(action_id):
			continue
		InputMap.action_erase_events(action_id)
		for entry in defaults[action_id]:
			var t: String = str(entry[0])
			if t == "key":
				var ev := InputEventKey.new()
				ev.physical_keycode = int(entry[1])
				InputMap.action_add_event(action_id, ev)
			elif t == "mouse":
				var mev := InputEventMouseButton.new()
				mev.button_index = int(entry[1])
				InputMap.action_add_event(action_id, mev)
			elif t == "pad":
				var pev := InputEventJoypadButton.new()
				pev.button_index = int(entry[1])
				InputMap.action_add_event(action_id, pev)
			elif t == "axis":
				var aev := InputEventJoypadMotion.new()
				aev.axis = int(entry[1])
				aev.axis_value = float(entry[2])
				InputMap.action_add_event(action_id, aev)

func _on_close_pressed() -> void:
	emit_signal("closed")
