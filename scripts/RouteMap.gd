extends Control

@onready var stage_label: Label = $Header/Stage
@onready var subtitle_label: Label = $Header/Subtitle
@onready var nodes_container: HBoxContainer = $Center/Nodes
@onready var veil_box: PanelContainer = $VeilBox
@onready var veil_text: Label = $VeilBox/Margin/V/Text
@onready var hint_label: Label = $Footer/Hint

var pool: Array = []
var recommended_id: String = ""
var recommended_reason: String = ""
var hovered_idx: int = 0
var buttons: Array = []
# 고위험/고보상 별도 패널 (사용자 피드백: 본 멘트에 겹치면 너무 많아짐).
var risk_reward_panel: PanelContainer = null
var risk_reward_label: Label = null
# 권장 스킬 칩 — VEIL 평문에 묻히던 추천을 좌측 아이콘 칩으로 분리(가독성).
var skill_rec_panel: PanelContainer = null
var skill_rec_icon: SkillIcon = null
var skill_rec_name: Label = null
var skill_rec_reason: Label = null
# ESC 일시정지 메뉴 — Stage와 동일 패턴(계속/스킬트리/설정/처음으로).
var pause_overlay: CanvasLayer = null
var settings_overlay: Control = null

func _ready() -> void:
	# 안전망: 이전 scene에서 paused가 carry되어 메뉴가 freeze되는 패턴 차단.
	get_tree().paused = false
	# 자체 일시정지(ESC) 중에도 입력을 받아 ESC로 열고 닫기가 모두 되게 — RouteMap엔
	# _process 게임로직이 없어 ALWAYS여도 안전(PAUSABLE이면 paused 중 ESC를 못 받아 못 닫힘).
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 자동저장 — 스테이지 사이(다음 루트 선택 직전)의 깨끗한 스냅샷. 웹에서 닫아도 "이어하기"로 복귀.
	# (이 시점 불변식: route_history.size() == current_stage)
	GameState.save_run()
	stage_label.text = "STAGE %d / %d  —  루트 선택" % [GameState.current_stage + 1, GameState.effective_total_stages()]
	subtitle_label.text = "● 위험도 / 보상   —   ? 미상"
	pool = RouteData.get_route_pool_for_stage(GameState.current_stage, GameState.route_history)
	var rec: Dictionary = RouteData.choose_veil_recommendation_with_reason(pool)
	recommended_id = str(rec.get("id", ""))
	recommended_reason = str(rec.get("reason", ""))
	# VEIL 멘트 — 신뢰도 톤(색)을 _ready에서 한 번만 적용. 폰트는 22로 키워
	# 선택 화면에서 분명히 눈에 들어오게 (이전 15는 카드에 묻혀 안 보였음).
	veil_text.add_theme_font_size_override("font_size", 22)
	veil_text.add_theme_color_override("font_color", GameState.veil_tone_color())
	# 긴 description이 박스 밖으로 빠져나가던 문제 — 자동 줄바꿈.
	veil_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	veil_text.custom_minimum_size = Vector2(560, 0)
	_setup_trust_gauge()
	_build_progress_strip()
	_build_risk_reward_panel()
	_build_skill_rec_panel()
	_build_node_buttons()
	_update_veil_comment()
	_refresh_hint()
	GameState.input_kind_changed.connect(_on_input_kind_changed)

func _build_risk_reward_panel() -> void:
	# VeilBox 우측에 작은 패널 — 고위험/고보상 경고를 본 멘트와 분리해서 표시.
	risk_reward_panel = PanelContainer.new()
	risk_reward_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	risk_reward_panel.anchor_left = 0.78
	# VeilBox가 0.68로 위로 올라간 데 맞춰 risk 패널도 같이 이동 (사용자 보고:
	# VeilBox와 Footer 키 안내 겹침 — VeilBox top 0.76→0.68 변경).
	risk_reward_panel.anchor_top = 0.54
	risk_reward_panel.anchor_right = 0.97
	risk_reward_panel.anchor_bottom = 0.66
	risk_reward_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.13, 0.10, 0.08, 0.88)
	sb.border_color = Color(0.85, 0.55, 0.35, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	risk_reward_panel.add_theme_stylebox_override("panel", sb)
	risk_reward_panel.visible = false
	add_child(risk_reward_panel)
	risk_reward_label = Label.new()
	risk_reward_label.add_theme_font_size_override("font_size", 13)
	risk_reward_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	risk_reward_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	risk_reward_panel.add_child(risk_reward_label)

# 권장 스킬 칩 — VeilBox 좌측 위(risk/reward 패널과 좌우 대칭). 아이콘 + 이름 + 사유.
func _build_skill_rec_panel() -> void:
	skill_rec_panel = PanelContainer.new()
	# 좌측 마진(카드 왼쪽 빈 공간)에 배치 — 우측 risk/reward 패널과 좌우 대칭.
	# 풀은 최대 3장이라 가운데 정렬된 카드 왼쪽에 마진이 남는다(카드와 안 겹치게 폭 제한).
	skill_rec_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	skill_rec_panel.anchor_left = 0.025
	skill_rec_panel.anchor_top = 0.54
	skill_rec_panel.anchor_right = 0.205
	skill_rec_panel.anchor_bottom = 0.66
	skill_rec_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.11, 0.14, 0.9)
	sb.border_color = Color(0.45, 0.7, 0.9, 0.55)
	sb.set_border_width_all(1)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	skill_rec_panel.add_theme_stylebox_override("panel", sb)
	skill_rec_panel.visible = false
	add_child(skill_rec_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_rec_panel.add_child(row)
	skill_rec_icon = SkillIcon.new()
	skill_rec_icon.custom_minimum_size = Vector2(46, 46)
	skill_rec_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	skill_rec_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(skill_rec_icon)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 1)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var head := Label.new()
	head.text = "권장 스킬"
	head.add_theme_font_size_override("font_size", 12)
	head.add_theme_color_override("font_color", Color(0.6, 0.66, 0.74))
	col.add_child(head)
	skill_rec_name = Label.new()
	skill_rec_name.add_theme_font_size_override("font_size", 17)
	col.add_child(skill_rec_name)
	skill_rec_reason = Label.new()
	skill_rec_reason.add_theme_font_size_override("font_size", 12)
	skill_rec_reason.add_theme_color_override("font_color", Color(0.75, 0.82, 0.9))
	col.add_child(skill_rec_reason)

func _on_input_kind_changed(_kind: String) -> void:
	_refresh_hint()

func _refresh_hint() -> void:
	hint_label.text = GameState.hint(
		"[ ←/→ : 선택 이동   ENTER : 결정 ]",
		"[ D-Pad/스틱 : 선택 이동   A : 결정 ]")

func _setup_trust_gauge() -> void:
	# 상단 Header에 신뢰도 게이지 추가. (이전엔 VeilBox 안에 있어서 하단 Footer
	# 조작 안내와 시각적으로 겹쳤음 — 사용자 피드백 2026-05-05.)
	var header: Node = stage_label.get_parent()
	if header == null:
		return
	var gauge := Label.new()
	gauge.name = "TrustGauge"
	gauge.text = "VEIL 신뢰   " + GameState.veil_trust_gauge_dots()
	gauge.add_theme_font_size_override("font_size", 14)
	gauge.add_theme_color_override("font_color", GameState.veil_tone_color())
	header.add_child(gauge)

# 진행 노드맵 — 헤더와 루트 카드 사이 가로 띠로 "지나온 경로 / 지금 / 남은 단계"를 표시.
# 데이터는 이미 존재(route_history·current_stage·effective_total_stages) — 시각화만 추가.
# 불변식: RouteMap이 뜬 시점에 route_history.size() == current_stage (i단계 선택 = history[i]).
const PROG_DONE_DOT: Color = Color(0.45, 0.80, 0.62)    # 클리어한 단계 (차분한 초록)
const PROG_DONE_TEXT: Color = Color(0.58, 0.66, 0.62)
const PROG_DONE_LINE: Color = Color(0.34, 0.50, 0.44)
const PROG_FUTURE: Color = Color(0.40, 0.43, 0.50)      # 미상 단계 (흐릿)
const PROG_FUTURE_LINE: Color = Color(0.24, 0.26, 0.32)

func _build_progress_strip() -> void:
	var total: int = GameState.effective_total_stages()
	var cur: int = GameState.current_stage
	var strip := CenterContainer.new()
	strip.name = "ProgressStrip"
	strip.anchor_left = 0.0
	strip.anchor_top = 0.175
	strip.anchor_right = 1.0
	strip.anchor_bottom = 0.245
	strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(strip)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 0)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip.add_child(row)
	for i in total:
		if i > 0:
			# i단계로 들어가는 연결선 — 그 단계에 도달했으면(i <= cur) "지나온" 색.
			row.add_child(_make_progress_connector(i <= cur))
		row.add_child(_make_progress_node(i, cur))

func _make_progress_node(i: int, cur: int) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(88, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Label.new()
	dot.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot.add_theme_font_size_override("font_size", 16)
	var name_l := Label.new()
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_size_override("font_size", 11)
	name_l.clip_text = true
	if i < cur:
		# 지나온 단계 — 선택했던 맵 이름 표시.
		var rid: String = str(GameState.route_history[i]) if i < GameState.route_history.size() else ""
		dot.text = "●"
		dot.add_theme_color_override("font_color", PROG_DONE_DOT)
		name_l.text = RouteData.name_for_id(rid)
		name_l.add_theme_color_override("font_color", PROG_DONE_TEXT)
	elif i == cur:
		# 지금 고르는 단계 — VEIL 신뢰 톤색으로 강조.
		var tone: Color = GameState.veil_tone_color()
		dot.text = "◆"
		dot.add_theme_color_override("font_color", tone)
		name_l.text = "지금"
		name_l.add_theme_color_override("font_color", tone)
	else:
		# 아직 모르는 앞 단계.
		dot.text = "○"
		dot.add_theme_color_override("font_color", PROG_FUTURE)
		name_l.text = "?"
		name_l.add_theme_color_override("font_color", PROG_FUTURE)
	box.add_child(dot)
	box.add_child(name_l)
	return box

func _make_progress_connector(done: bool) -> Control:
	# 노드와 같은 2단 구조(선 / 빈칸)로 만들어 점·이름 행 높이를 맞춘다.
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(24, 0)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var line := Label.new()
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 16)
	line.text = "──"
	line.add_theme_color_override("font_color", PROG_DONE_LINE if done else PROG_FUTURE_LINE)
	var spacer := Label.new()
	spacer.add_theme_font_size_override("font_size", 11)
	spacer.text = " "
	box.add_child(line)
	box.add_child(spacer)
	return box

func _build_node_buttons() -> void:
	for child in nodes_container.get_children():
		child.queue_free()
	buttons.clear()
	for i in pool.size():
		var route: Dictionary = pool[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(220, 188)
		b.toggle_mode = false
		b.text = _format_button_text(route, route.get("id", "") == recommended_id)
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(_on_button_pressed.bind(i))
		b.focus_entered.connect(_on_focus.bind(i))
		b.mouse_entered.connect(_on_focus.bind(i))
		# 카드 하단에 등장 적 타입 아이콘 — 본 적은 그림, 미확인은 ?(발견 루프 존중).
		# hidden(???)/challenge 맵은 적 데이터가 특수하니 생략.
		if not bool(route.get("hidden", false)) and not bool(route.get("challenge", false)):
			_attach_enemy_row(b, str(route.get("id", "")))
		nodes_container.add_child(b)
		buttons.append(b)
	if buttons.size() > 0:
		# 메뉴 등장 직후 1초 동안 포커스 보류 — 점프 연타로 자동 활성화되는 사고 방지.
		GameState.arm_focus_with_delay(self, buttons[0])

func _format_button_text(route: Dictionary, recommended: bool) -> String:
	var route_name: String = route.get("name", "?")
	var hidden: bool = route.get("hidden", false)
	var challenge: bool = route.get("challenge", false)
	var risk_str: String = "?" if hidden else _dots(route.get("risk", 0))
	var reward_str: String = "?" if hidden else _dots(route.get("reward", 0))
	var prefix: String = "[도전]\n" if challenge else ""
	var rec: String = "  ★" if recommended else ""
	return "%s%s%s\n\n위험  %s\n보상  %s" % [prefix, route_name, rec, risk_str, reward_str]

# 맵에 등장하는 적 타입(중복 제거, 등장 순서). enemies(고정) + waves(ARENA) 합산.
func _route_enemy_kinds(route_id: String) -> Array:
	var layout: Dictionary = MapData.get_layout(route_id)
	if layout.is_empty():
		return []
	var kinds: Array = []
	var enemies: Dictionary = layout.get("enemies", {})
	for k in enemies.keys():
		var arr: Array = enemies[k]
		if arr.size() > 0 and not (str(k) in kinds):
			kinds.append(str(k))
	for w in layout.get("waves", []):
		var wd: Dictionary = w
		var wen: Dictionary = wd.get("enemies", {})
		for k in wen.keys():
			# wen[k]는 적 위치 배열(개수 아님) — int() 생성자 없음(크래시 원인). size()로 검사.
			var arr: Array = wen[k]
			if arr.size() > 0 and not (str(k) in kinds):
				kinds.append(str(k))
	return kinds

# 카드 하단 중앙에 적 타입 아이콘 행. 본 적(seen_enemies)은 EnemyIcon, 미확인은 흐린 "?".
func _attach_enemy_row(card: Button, route_id: String) -> void:
	var kinds: Array = _route_enemy_kinds(route_id)
	if kinds.is_empty():
		return
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 7)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.anchor_left = 0.0
	row.anchor_right = 1.0
	row.anchor_top = 1.0
	row.anchor_bottom = 1.0
	row.offset_top = -34.0
	row.offset_bottom = -8.0
	card.add_child(row)
	for k in kinds:
		var kind: String = str(k)
		if kind in GameState.seen_enemies:
			var ic := EnemyIcon.new()
			ic.enemy_id = kind
			ic.custom_minimum_size = Vector2(24, 24)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(ic)
		else:
			var q := Label.new()
			q.text = "?"
			q.custom_minimum_size = Vector2(24, 24)
			q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			q.add_theme_font_size_override("font_size", 16)
			q.add_theme_color_override("font_color", Color(0.5, 0.52, 0.58))
			q.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(q)

func _dots(n: int) -> String:
	var s: String = ""
	for i in n:
		s += "●"
	for i in (3 - n):
		s += "○"
	return s

func _on_focus(idx: int) -> void:
	hovered_idx = idx
	_update_veil_comment()

func _update_veil_comment() -> void:
	if hovered_idx < 0 or hovered_idx >= pool.size():
		return
	var route: Dictionary = pool[hovered_idx]
	var msg: String = ""
	# 맵 소개(존재 이유) — 이 장소가 *무엇인가*. veil_comment(전술 "어떻게")와 다른 축이라 중복 아님.
	var lore: String = str(route.get("description", ""))
	if lore != "":
		msg += lore + "\n\n"
	# 추천 맵: ★ + 추천 사유(VEIL이 직접 말로). 비추천 맵: 그 맵 고유 veil_comment.
	var is_recommended: bool = (route.get("id", "") == recommended_id and recommended_reason != "")
	if is_recommended:
		msg += "★ 베일 추천\nVEIL  —  " + recommended_reason
	else:
		msg += "VEIL  —  " + str(route.get("veil_comment", ""))
	veil_text.text = msg
	# 고위험/고보상 경고는 별도 우측 패널, 권장 스킬은 별도 좌측 칩 — 본 멘트와 시각 분리.
	_update_risk_reward_panel(route)
	_update_skill_rec_panel(route)

const _SKILL_DISPLAY: Dictionary = {"explosive": "폭발물", "barrier": "방어막", "glide": "글라이드", "fire_boost": "사격 강화", "multishot": "다중사격"}
const _ENEMY_DISPLAY: Dictionary = {"shield": "방패병", "sniper": "저격수", "drone": "드론", "bomber": "폭격기", "patrol": "정찰병"}

# 이 맵 적 구성에 가장 잘 듣는 상성 스킬(SkillTreeData.MATCHUP 우선순위순).
# 스포일러 방지: 아직 안 만난 적은 추천 근거로 쓰지 않는다(루트 카드의 ? 아이콘과 일관).
# → 본 적이 없으면 추천도 안 뜬다. {skill_id, enemy} 또는 빈 Dictionary.
func _recommended_skill_for_route(route_id: String) -> Dictionary:
	var kinds: Array = _route_enemy_kinds(route_id)
	if kinds.is_empty():
		return {}
	for m in SkillTreeData.MATCHUP:
		var en: String = str(m.get("enemy", ""))
		if en in kinds and en in GameState.seen_enemies:
			return {"skill_id": str(m.get("skill", "")), "enemy": en}
	return {}

# 좌측 권장 스킬 칩 갱신 — 본 적이 없거나 hidden/challenge 맵이면 숨김.
func _update_skill_rec_panel(route: Dictionary) -> void:
	if skill_rec_panel == null:
		return
	if bool(route.get("hidden", false)) or bool(route.get("challenge", false)):
		skill_rec_panel.visible = false
		return
	var rec: Dictionary = _recommended_skill_for_route(str(route.get("id", "")))
	if rec.is_empty():
		skill_rec_panel.visible = false
		return
	var sid: String = str(rec.get("skill_id", ""))
	var en: String = str(rec.get("enemy", ""))
	var fam: String = str(SkillTreeData.find_line(sid).get("family", ""))
	skill_rec_icon.skill_id = sid
	skill_rec_icon.family = fam
	skill_rec_icon.queue_redraw()
	skill_rec_name.text = str(_SKILL_DISPLAY.get(sid, sid))
	var fam_col: Color = SkillTreeData.FAMILY_COLORS.get(fam, Color(0.9, 0.93, 0.97))
	skill_rec_name.add_theme_color_override("font_color", fam_col)
	skill_rec_reason.text = "%s에 강해요" % str(_ENEMY_DISPLAY.get(en, en))
	skill_rec_panel.visible = true

func _update_risk_reward_panel(route: Dictionary) -> void:
	if risk_reward_panel == null or risk_reward_label == null:
		return
	if route.get("hidden", false):
		risk_reward_panel.visible = false
		return
	var lines: Array = []
	var risk: int = int(route.get("risk", 0))
	if risk >= 3:
		lines.append("[고위험]\n적 수와 반응 속도가 강해요.")
	var reward: int = int(route.get("reward", 0))
	if reward >= 3:
		lines.append("[고보상]\n클리어 보너스 경험치가 큽니다.")
	if lines.is_empty():
		risk_reward_panel.visible = false
		return
	risk_reward_label.text = "\n\n".join(lines)
	risk_reward_panel.visible = true

func _input(event: InputEvent) -> void:
	# 일시정지 중엔 SPACE 소비 안 함 — 일시정지 메뉴 버튼의 ui_accept(SPACE)를 막지 않게.
	if pause_overlay != null:
		return
	# 스페이스(점프 키)로는 맵 확정 금지 — 플레이 중 점프 습관 탓에 맵이 뜨자마자 의도치 않게
	# 카드가 선택돼버리는 것 방지(사용자). _input은 GUI·_unhandled_input보다 먼저 처리되므로
	# 여기서 소비하면 버튼 ui_accept와 아래 jump 분기 양쪽 다 막힌다. Enter·W·클릭으로는 정상 확정.
	if event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	# ESC는 최우선 — 선택 화면에서도 일시정지 메뉴를 연다(이전엔 ESC가 아무 반응 없었음).
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if pause_overlay == null:
			_show_pause()
		else:
			_hide_pause()
		return
	if pause_overlay != null:
		return  # 일시정지 중엔 카드 확정 입력 무시(점프/스킵으로 뒤에서 결정되는 사고 방지).
	if event.is_action_pressed("ui_skip") or event.is_action_pressed("jump"):
		_on_button_pressed(hovered_idx)

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

func _on_button_pressed(idx: int) -> void:
	if idx < 0 or idx >= pool.size():
		return
	var route: Dictionary = pool[idx]
	GameState.record_route_choice(route, recommended_id)
	get_tree().change_scene_to_file(SceneRouter.STAGE)
