class_name PlaygroundOverlay
extends Node

# 디버그 연습장 패널 — Stage._ready에서 playground_active일 때만 부착.
# 토글 버튼은 항상 떠 있고, 패널은 클릭 시 펼쳐짐.
# 항목을 누르면 GameState 값을 갱신하고 scene을 reload.

# 루트 목록은 RouteData.ALL_ROUTES 단일 소스에서 파생한다(_build_route_section). 예전엔 여기에 12개를
# 하드코딩해서 새 맵(반응로 제어실·붕괴 갱도 등 17종)이 연습장에 안 뜨는 문제가 있었다(2026-07-04 수정).

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
	# 패널이 열리면 트리를 일시정지하므로(키보드 내비), 오버레이 자신은 항상 동작해야 한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = CanvasLayer.new()
	layer.layer = 30
	add_child(layer)

	toggle_button = Button.new()
	toggle_button.text = "▼ 연습장 [F1]"
	toggle_button.add_theme_font_size_override("font_size", 13)
	toggle_button.position = Vector2(20, 56)
	toggle_button.custom_minimum_size = Vector2(110, 28)
	toggle_button.pressed.connect(_toggle_panel)
	layer.add_child(toggle_button)

# F1 = 패널 여닫기(마우스 없이도 접근), 열린 상태의 ESC = 닫기.
# 패널이 열리면 paused라 Stage(PAUSABLE)는 입력을 못 받고, 이 노드(ALWAYS)만 받는다.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		if key.keycode == KEY_F1 or (open and key.keycode == KEY_ESCAPE):
			get_viewport().set_input_as_handled()
			_toggle_panel()

func _toggle_panel() -> void:
	if open:
		_close_panel()
	else:
		_open_panel()

func _open_panel() -> void:
	open = true
	toggle_button.text = "▲ 연습장 [F1]"
	# 열려 있는 동안 일시정지 — 화살표/Enter로 패널을 조작해도 뒤의 플레이어가 움직이지 않게
	# (키보드 내비 지원). 닫기/reload/이탈 모든 경로에서 해제(known_issues paused carry 참조).
	get_tree().paused = true
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

	# 행이 늘며 패널이 720px 화면 밖으로 넘치는 재발 방지(과거 스킬 8줄 사례와 동형 — 하단
	# 버튼이 안 보인다는 보고 2026-08-12). 전체를 스크롤 박스에 담고 포커스를 따라 자동 스크롤.
	var outer := ScrollContainer.new()
	outer.custom_minimum_size = Vector2(700, 560)
	outer.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	outer.follow_focus = true
	panel.add_child(outer)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	outer.add_child(v)

	# 14-2 프로토 바로가기 — 맨 위 고정(맨 아래에 두면 오버플로로 안 보였음).
	var tunnel_btn := Button.new()
	tunnel_btn.text = "14-2 터널 프로토 (유사 1인칭) 진입"
	tunnel_btn.add_theme_font_size_override("font_size", 13)
	tunnel_btn.pressed.connect(_on_tunnel_proto)
	v.add_child(tunnel_btn)
	v.add_child(HSeparator.new())

	v.add_child(_build_stage_row())
	v.add_child(_build_route_section())
	v.add_child(_build_int_row("Risk", "current_route_risk", _on_risk_pressed))
	v.add_child(_build_int_row("Reward", "current_route_reward", _on_reward_pressed))
	v.add_child(_build_veil_row())

	v.add_child(HSeparator.new())
	v.add_child(_make_row_label("스킬 (3계열 · 티어 직접 지정)"))
	v.add_child(_build_skill_families())
	v.add_child(_build_baseline_row())
	v.add_child(_build_skill_quick_row())

	v.add_child(HSeparator.new())
	var inv_hb := HBoxContainer.new()
	inv_hb.add_theme_constant_override("separation", 6)
	inv_hb.add_child(_make_row_label("무적"))
	var inv_cb := CheckButton.new()
	inv_cb.text = "피해 무시"
	inv_cb.button_pressed = GameState.debug_invincible
	inv_cb.add_theme_font_size_override("font_size", 13)
	inv_cb.toggled.connect(_on_invincible_toggled)
	inv_hb.add_child(inv_cb)
	v.add_child(inv_hb)

	var el_hb := HBoxContainer.new()
	el_hb.add_theme_constant_override("separation", 6)
	el_hb.add_child(_make_row_label("엘리트"))
	var el_cb := CheckButton.new()
	el_cb.text = "강제 승격 (전 타입 체험)"
	el_cb.button_pressed = GameState.debug_force_elite
	el_cb.add_theme_font_size_override("font_size", 13)
	el_cb.toggled.connect(_on_force_elite_toggled)
	el_hb.add_child(el_cb)
	v.add_child(el_hb)

	var sep := HSeparator.new()
	v.add_child(sep)
	var exit_btn := Button.new()
	exit_btn.text = "연습장 종료 (타이틀로)"
	exit_btn.add_theme_font_size_override("font_size", 13)
	exit_btn.pressed.connect(_on_exit)
	v.add_child(exit_btn)
	# 키보드 내비 — 첫 버튼 포커스(화살표/Tab 이동 · Enter 실행 · 포커스 따라 자동 스크롤).
	tunnel_btn.call_deferred("grab_focus")

func _on_invincible_toggled(on: bool) -> void:
	# 무적은 연습장에서만 효과가 있다(Player.take_hit이 playground_active로 가드) — 일반 모드엔 영향 없음.
	GameState.debug_invincible = on

func _on_force_elite_toggled(on: bool) -> void:
	# 실런은 확률 램프(s9 5%→s12 30%)라 엘리트 전 타입을 못 만날 수 있다(2026-08-11 피드백).
	# 연습장 한정 강제 승격 — 켠 뒤 맵을 다시 진입하면 적용. 재머/둥지 저격수/위장·시선 거짓
	# 제외는 실런과 동일(Stage._spawn_enemy 가드). 일반 모드엔 영향 없음(playground_active 가드).
	GameState.debug_force_elite = on

func _close_panel() -> void:
	open = false
	toggle_button.text = "▼ 연습장 [F1]"
	get_tree().paused = false
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

# 루트 목록 — RouteData.ALL_ROUTES 전체를 **막(Act)별로 그룹화**해 스크롤 박스에 보인다.
# 막 경계는 GameState.ACTS(act_for_stage) 단일 소스에서 파생 — 맵이 늘거나 막이 추가돼도 자동 정렬.
# 라이벌 VEIL 요소(재머/위장/reveal)가 있는 맵은 바이올렛으로 강조 + 툴팁에 상세(사용자: "정돈해서 보여줘").
func _build_route_section() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var lbl := _make_row_label("루트")
	lbl.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	hb.add_child(lbl)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(560, 200)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.follow_focus = true
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	# 막별 버킷 — min_stage가 속한 막으로 분류. min_stage 없는 특수(도전방 등)는 별도.
	var buckets: Array = []
	for _i in GameState.ACTS.size():
		buckets.append([])
	var special: Array = []
	for r in RouteData.ALL_ROUTES:
		var route: Dictionary = r
		if str(route.get("id", "")) == "":
			continue
		if not route.has("min_stage"):
			special.append(route)
			continue
		var ai: int = GameState.act_for_stage(int(route.get("min_stage", 0)))
		if ai >= 0 and ai < buckets.size():
			buckets[ai].append(route)
		else:
			special.append(route)
	# 각 막 섹션 — 헤더(막 이름 + 스테이지 범위) + 그 막 맵 그리드.
	var acc: int = 0
	for ai in GameState.ACTS.size():
		var adef: Dictionary = GameState.ACTS[ai]
		var s_from: int = acc + 1
		acc += int(adef.get("stages", 0))
		var s_to: int = acc
		var header: String = "막%d · %s (스%d~%d)" % [ai + 1, str(adef.get("name", "")), s_from, s_to]
		if not (buckets[ai] as Array).is_empty():
			vb.add_child(_route_act_section(header, buckets[ai]))
	if not special.is_empty():
		vb.add_child(_route_act_section("특수 · 도전/서사", special))
	sc.add_child(vb)
	hb.add_child(sc)
	return hb

# 한 막 섹션 — 헤더 라벨 + 그 막에 속한 맵 버튼 그리드(5열).
func _route_act_section(header: String, routes: Array) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	var h := Label.new()
	h.text = header
	h.add_theme_font_size_override("font_size", 12)
	h.add_theme_color_override("font_color", Color(0.60, 0.70, 0.95))
	col.add_child(h)
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for r in routes:
		var route: Dictionary = r
		var rid: String = str(route.get("id", ""))
		var b := Button.new()
		b.text = str(route.get("name", rid))
		b.custom_minimum_size = Vector2(104, 28)
		b.add_theme_font_size_override("font_size", 12)
		b.clip_text = true
		# 툴팁 — id·위험/보상·태그(+라이벌 요소). 이름만으론 안 보이는 정보.
		var rival: String = _route_rival_info(rid)
		var tip: String = "%s\nrisk %d · reward %d" % [rid, int(route.get("risk", 1)), int(route.get("reward", 1))]
		if rival != "":
			tip += "\n라이벌: " + rival
			b.add_theme_color_override("font_color", Color(0.82, 0.60, 1.0))   # 라이벌 맵 = 바이올렛 강조
			b.add_theme_color_override("font_hover_color", Color(0.90, 0.72, 1.0))
		b.tooltip_text = tip
		if GameState.current_route_id == rid:
			b.disabled = true
		b.pressed.connect(_on_route_pressed.bind(rid))
		grid.add_child(b)
	col.add_child(grid)
	return col

# 맵에 배치된 라이벌 VEIL 요소를 MapData 레이아웃에서 파생(단일 소스 — 새 배치도 자동 반영).
func _route_rival_info(rid: String) -> String:
	var layout: Dictionary = MapData.get_layout(rid)
	var parts: Array = []
	if _layout_has_jammer(layout):
		parts.append("재머")
	if not (layout.get("deceits", []) as Array).is_empty():
		parts.append("위장 적")
	if not (layout.get("feigns", []) as Array).is_empty():
		parts.append("시선 거짓")
	if not (layout.get("deceit_spikes", []) as Array).is_empty():
		parts.append("위장 함정")
	if rid == "route_lab":
		parts.append("SENTINEL reveal")
	return " / ".join(parts)

func _layout_has_jammer(layout: Dictionary) -> bool:
	if not (layout.get("enemies", {}).get("jammer", []) as Array).is_empty():
		return true
	for w in layout.get("waves", []):
		if not ((w as Dictionary).get("enemies", {}).get("jammer", []) as Array).is_empty():
			return true
	return false

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

func _on_tunnel_proto() -> void:
	# 14-2 코어 대면 터널 프로토(rival_veil_concept §7.1) — 손맛 검증용 진입.
	# 플래그 누수 차단: 터널의 모든 퇴장 경로는 Title(reset)로 가지만, 여기서도 미리 끈다.
	GameState.playground_active = false
	SceneRouter.go(get_tree(), SceneRouter.CORE_TUNNEL)

func _on_exit() -> void:
	GameState.playground_active = false
	GameState.reset()
	# SceneRouter.go = paused 해제 보장(패널 열림 = paused 상태에서 눌릴 수 있음).
	SceneRouter.go(get_tree(), SceneRouter.TITLE)

func _reload() -> void:
	# Stage scene을 다시 로드 — _ready에서 새 GameState 값으로 빌드.
	# playground_active가 true이므로 패널도 다시 부착됨.
	# paused는 SceneTree 전역이라 reload에도 carry된다 — 패널 열림 상태에서 눌리므로 반드시 해제.
	get_tree().paused = false
	get_tree().reload_current_scene()
