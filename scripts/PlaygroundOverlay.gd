class_name PlaygroundOverlay
extends Node

# 디버그 연습장 패널 — Stage._ready에서 playground_active일 때만 부착.
# 토글 버튼은 항상 떠 있고, 패널은 클릭 시 펼쳐짐.
# 항목을 누르면 GameState 값을 갱신하고 scene을 reload.

const ROUTE_OPTIONS: Array = [
	{"id": "route_back_alley", "label": "외곽"},
	{"id": "route_rooftops",   "label": "옥상"},
	{"id": "route_sewers",     "label": "배수로"},
	{"id": "route_subway",     "label": "지하철"},
	{"id": "route_cooling",    "label": "냉각"},
	{"id": "route_watchtower", "label": "감시탑"},
	{"id": "route_ward",       "label": "병동"},
	{"id": "route_datacenter", "label": "데이터"},
	{"id": "route_escape",     "label": "탈출로"},
	{"id": "route_lab",        "label": "핵심부"},
	{"id": "route_blackout",   "label": "도전"},
	{"id": "route_hidden",     "label": "???"},
]

# 스킬 라인 — 연습장에서 티어 자유 조정용(짧은 라벨).
const SKILL_LINES: Array = [
	{"id": "fire_boost", "label": "사격강화"},
	{"id": "multishot",  "label": "다중사격"},
	{"id": "explosive",  "label": "폭발물"},
	{"id": "glide",      "label": "활강"},
	{"id": "dash_boost", "label": "대시강화"},
	{"id": "hp",         "label": "체력"},
	{"id": "shield",     "label": "부활"},
	{"id": "barrier",    "label": "방어막"},
]

var layer: CanvasLayer
var toggle_button: Button
var panel: PanelContainer
var open: bool = false

func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	toggle_button = Button.new()
	toggle_button.text = "▼ 연습장"
	toggle_button.add_theme_font_size_override("font_size", 13)
	toggle_button.position = Vector2(20, 56)
	toggle_button.custom_minimum_size = Vector2(110, 28)
	toggle_button.pressed.connect(_toggle_panel)
	layer.add_child(toggle_button)

func _toggle_panel() -> void:
	if open:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	open = true
	toggle_button.text = "▲ 연습장"
	panel = PanelContainer.new()
	panel.position = Vector2(20, 92)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.10, 0.95)
	style.border_color = Color(0.55, 0.62, 0.78, 0.55)
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	panel.add_child(v)

	v.add_child(_build_stage_row())
	v.add_child(_build_route_row())
	v.add_child(_build_int_row("Risk", "current_route_risk", _on_risk_pressed))
	v.add_child(_build_int_row("Reward", "current_route_reward", _on_reward_pressed))
	v.add_child(_build_veil_row())

	v.add_child(HSeparator.new())
	v.add_child(_make_row_label("스킬 (3계열 · 티어 직접 지정)"))
	v.add_child(_build_skill_families())
	v.add_child(_build_baseline_row())
	v.add_child(_build_skill_quick_row())

	var sep := HSeparator.new()
	v.add_child(sep)
	var exit_btn := Button.new()
	exit_btn.text = "연습장 종료 (타이틀로)"
	exit_btn.add_theme_font_size_override("font_size", 13)
	exit_btn.pressed.connect(_on_exit)
	v.add_child(exit_btn)

func _close_panel() -> void:
	open = false
	toggle_button.text = "▼ 연습장"
	if panel != null and is_instance_valid(panel):
		panel.queue_free()
	panel = null

# ─── 행 빌더 ────────────────────────────────────────────────

func _build_stage_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label("스테이지"))
	for i in GameState.TOTAL_STAGES:
		var b := Button.new()
		b.text = "%d" % (i + 1)
		b.custom_minimum_size = Vector2(36, 28)
		b.add_theme_font_size_override("font_size", 13)
		if GameState.current_stage == i:
			b.disabled = true
		b.pressed.connect(_on_stage_pressed.bind(i))
		hb.add_child(b)
	return hb

func _build_route_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label("루트"))
	for opt in ROUTE_OPTIONS:
		var d: Dictionary = opt
		var rid: String = str(d.get("id", ""))
		var b := Button.new()
		b.text = str(d.get("label", rid))
		b.custom_minimum_size = Vector2(70, 28)
		b.add_theme_font_size_override("font_size", 13)
		if GameState.current_route_id == rid:
			b.disabled = true
		b.pressed.connect(_on_route_pressed.bind(rid))
		hb.add_child(b)
	return hb

func _build_int_row(label_text: String, prop_name: String, cb: Callable) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label(label_text))
	for n in [1, 2, 3]:
		var b := Button.new()
		b.text = "%d" % n
		b.custom_minimum_size = Vector2(36, 28)
		b.add_theme_font_size_override("font_size", 13)
		if int(GameState.get(prop_name)) == n:
			b.disabled = true
		b.pressed.connect(cb.bind(n))
		hb.add_child(b)
	return hb

# 스킬 라인 한 줄 — 0/1/2/3 티어 버튼(현재 티어는 disabled로 표시).
func _build_skill_row(line_id: String, label_text: String) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label(label_text))
	var cur: int = GameState.get_skill_tier(line_id)
	for n in [0, 1, 2, 3]:
		var b := Button.new()
		b.text = "%d" % n
		b.custom_minimum_size = Vector2(30, 26)
		b.add_theme_font_size_override("font_size", 12)
		if cur == n:
			b.disabled = true
		b.pressed.connect(_on_skill_set.bind(line_id, n))
		hb.add_child(b)
	return hb

# 스킬을 스킬트리와 동일한 3계열(전투/이동/생존)로 묶어 세 열로 배치한다.
# 8줄 세로 나열이 패널을 화면 밖으로 밀어 "연습장 종료" 버튼이 안 보이던 문제도 함께 해소(사용자 보고).
# 계열 구분·색은 SkillTreeData(FAMILY_*/FAMILY_COLORS) 단일 소스를 참조 — 스킬트리 화면과 일관.
func _build_skill_families() -> HBoxContainer:
	# id → family 매핑(SkillTreeData 단일 소스).
	var fam_of: Dictionary = {}
	for line in SkillTreeData.LINES:
		var ld: Dictionary = line
		fam_of[str(ld.get("id", ""))] = str(ld.get("family", ""))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 16)
	for fam in [SkillTreeData.FAMILY_COMBAT, SkillTreeData.FAMILY_MOBILITY, SkillTreeData.FAMILY_SURVIVAL]:
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		# 계열 헤더 — FAMILY_COLORS 색으로 스킬트리와 동일한 계열 식별.
		var head := Label.new()
		head.text = str(fam)
		head.add_theme_font_size_override("font_size", 12)
		var fc: Color = SkillTreeData.FAMILY_COLORS.get(fam, Color(0.8, 0.85, 0.95))
		head.add_theme_color_override("font_color", fc)
		col.add_child(head)
		for line in SKILL_LINES:
			var d: Dictionary = line
			var sid: String = str(d.get("id", ""))
			if str(fam_of.get(sid, "")) == str(fam):
				col.add_child(_build_skill_row(sid, str(d.get("label", ""))))
		cols.add_child(col)
	return cols

# 시야 붕괴(veil_degraded) 토글 — ACT3 진입 경고/붕괴 톤 대사·비네트를 연습장에서 테스트.
func _build_veil_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label("시야"))
	var b := Button.new()
	b.text = "붕괴 %s" % ("켜짐" if GameState.veil_degraded else "꺼짐")
	b.custom_minimum_size = Vector2(110, 26)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(_on_veil_degraded_toggle)
	hb.add_child(b)
	return hb

func _on_veil_degraded_toggle() -> void:
	GameState.veil_degraded = not GameState.veil_degraded
	_reload()

# 베이스라인(대시·이중점프) on/off.
func _build_baseline_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label("기본"))
	for entry in [["dash", "대시"], ["double_jump", "이중점프"]]:
		var bid: String = str(entry[0])
		var has: bool = GameState.has_skill(bid)
		var b := Button.new()
		b.text = "%s %s" % [str(entry[1]), "켜짐" if has else "꺼짐"]
		b.custom_minimum_size = Vector2(96, 26)
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_on_skill_set.bind(bid, 0 if has else 1))
		hb.add_child(b)
	return hb

# 빠른 전체 조작.
func _build_skill_quick_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	hb.add_child(_make_row_label(""))
	var b_max := Button.new()
	b_max.text = "전체 MAX"
	b_max.add_theme_font_size_override("font_size", 12)
	b_max.pressed.connect(_on_skill_all.bind(3))
	hb.add_child(b_max)
	var b_clr := Button.new()
	b_clr.text = "전체 해제"
	b_clr.add_theme_font_size_override("font_size", 12)
	b_clr.pressed.connect(_on_skill_all.bind(0))
	hb.add_child(b_clr)
	return hb

func _make_row_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(70, 28)
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.78, 0.85, 0.95))
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l

# ─── 버튼 핸들러 ────────────────────────────────────────────

func _on_stage_pressed(idx: int) -> void:
	GameState.current_stage = idx
	_reload()

func _on_route_pressed(rid: String) -> void:
	GameState.current_route_id = rid
	# 맵 선택 시 그 맵의 기본 위험/보상/스테이지로 자동 설정(직관적 테스트 — 사용자 요청).
	# (이후 Risk/Reward/스테이지 행에서 따로 미세조정 가능.)
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		if route.get("id", "") == rid:
			GameState.current_route_tags = route.get("tags", [])
			GameState.current_route_risk = int(route.get("risk", GameState.current_route_risk))
			GameState.current_route_reward = int(route.get("reward", GameState.current_route_reward))
			GameState.current_stage = int(route.get("min_stage", GameState.current_stage))
			break
	_reload()

func _on_risk_pressed(n: int) -> void:
	GameState.current_route_risk = n
	_reload()

func _on_reward_pressed(n: int) -> void:
	GameState.current_route_reward = n
	_reload()

# 스킬 티어 직접 지정 — 0이면 해제. hp는 add_skill의 max_hp 즉시효과를 재현.
func _set_skill_tier(id: String, n: int) -> void:
	if n <= 0:
		GameState.skills.erase(id)
	else:
		GameState.skills[id] = n
	if id == "hp":
		# hp: 기본 max 3 + min(tier,2). T3는 max 변화 없음.
		GameState.player_max_hp = 3 + min(n, 2)
		GameState.player_hp = GameState.player_max_hp

func _on_skill_set(id: String, n: int) -> void:
	_set_skill_tier(id, n)
	_reload()

func _on_skill_all(n: int) -> void:
	for line in SKILL_LINES:
		_set_skill_tier(str((line as Dictionary).get("id", "")), n)
	# 베이스라인은 MAX=켜짐, 해제=꺼짐
	_set_skill_tier("dash", 1 if n > 0 else 0)
	_set_skill_tier("double_jump", 1 if n > 0 else 0)
	_reload()

func _on_exit() -> void:
	GameState.playground_active = false
	GameState.reset()
	get_tree().change_scene_to_file(SceneRouter.TITLE)

func _reload() -> void:
	# Stage scene을 다시 로드 — _ready에서 새 GameState 값으로 빌드.
	# playground_active가 true이므로 패널도 다시 부착됨.
	get_tree().reload_current_scene()
