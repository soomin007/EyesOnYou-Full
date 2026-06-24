class_name SkillTreeOverlay
extends CanvasLayer

# 전체 스킬 트리 열람 오버레이 (독립).
# 목적: 레벨업 픽 3장만으론 안 보이는 "라인 점증(T2·T3에 뭐가 오는지)"을 한눈에.
# 일시정지 메뉴 / 레벨업 화면에서 버튼으로 열고, Esc/취소로 닫는다.
# paused 상태는 건드리지 않는다 — 밑에 깔린 pause/levelup 오버레이가 계속 paused를 원함.
# 라인 포커스/호버 시 하단 패널에 그 계열 T1~T3 전체를 보유/다음/잠김으로 표시.

# 계열 색은 단일 소스(SkillTreeData)에서 — 트리 텍스트와 아이콘이 같은 색으로 보이게.
const FAMILY_COLORS: Dictionary = SkillTreeData.FAMILY_COLORS
const COL_NEXT: Color = Color(0.98, 0.85, 0.45)    # 다음 선택 가능 티어
const COL_LOCKED: Color = Color(0.45, 0.48, 0.55)  # 잠긴 티어

var desc_label: RichTextLabel = null
var _prev_focus: Control = null

# host(보통 pause/levelup CanvasLayer) 위에 얹어 띄운다.
static func open(host: Node) -> SkillTreeOverlay:
	var o := SkillTreeOverlay.new()
	host.add_child(o)
	return o

func _init() -> void:
	layer = 60  # pause(50)·levelup(40)보다 위
	process_mode = Node.PROCESS_MODE_ALWAYS

func _ready() -> void:
	_prev_focus = get_viewport().gui_get_focus_owner()
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	center.add_child(v)

	var title := Label.new()
	title.text = "스킬 트리"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var legend := RichTextLabel.new()
	legend.bbcode_enabled = true
	legend.fit_content = true
	legend.scroll_active = false
	legend.custom_minimum_size = Vector2(760, 0)
	legend.text = "[center]● 보유      [color=#%s]◆ 다음 선택 가능[/color]      [color=#%s]○ 잠김[/color][/center]" % [
		COL_NEXT.to_html(false), COL_LOCKED.to_html(false)]
	legend.add_theme_font_size_override("normal_font_size", 15)
	v.add_child(legend)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 22)
	cols.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(cols)
	cols.add_child(_build_column(SkillTreeData.FAMILY_COMBAT))
	cols.add_child(_build_column(SkillTreeData.FAMILY_MOBILITY))
	cols.add_child(_build_column(SkillTreeData.FAMILY_SURVIVAL))

	var desc_panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.11, 0.14, 0.94)
	sb.border_color = Color(0.30, 0.33, 0.40, 0.6)
	sb.set_border_width_all(1)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 14
	sb.content_margin_bottom = 14
	sb.set_corner_radius_all(4)
	desc_panel.add_theme_stylebox_override("panel", sb)
	v.add_child(desc_panel)
	desc_label = RichTextLabel.new()
	desc_label.bbcode_enabled = true
	desc_label.fit_content = true
	desc_label.scroll_active = false
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.custom_minimum_size = Vector2(760, 150)
	desc_label.add_theme_font_size_override("normal_font_size", 18)
	desc_label.add_theme_font_size_override("bold_font_size", 18)
	# 얇은 검정 아웃라인 — faux-bold([b])는 너무 두꺼웠으니, Regular + 외곽선으로 "중간 굵기 + 또렷한 가장자리".
	desc_label.add_theme_constant_override("outline_size", 4)
	desc_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	desc_label.add_theme_constant_override("line_separation", 8)  # T1~T3 줄 간격 — 빽빽하지 않게
	desc_label.text = "[color=#8a909a]계열에 마우스를 올리거나 방향키로 옮겨 보세요. T1~T3가 한눈에 보여요.[/color]"
	desc_panel.add_child(desc_label)

	var footer := Label.new()
	footer.text = GameState.hint("[ ←/→/↑/↓ : 둘러보기    ESC : 닫기 ]", "[ 방향 : 둘러보기    B : 닫기 ]")
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color(0.55, 0.55, 0.62))
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(footer)

	# 트리거 입력(메뉴 버튼 Enter)이 첫 라인에 carry돼 바로 눌리는 사고 방지 — 짧은 지연 후 포커스.
	var first: Button = cols.get_child(0).get_child(1) as Button  # 첫 계열 헤더(0) 다음 첫 라인
	if first != null:
		GameState.arm_focus_with_delay(self, first, 0.25)

func _build_column(fam: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 7)
	var head := Label.new()
	head.text = fam
	head.add_theme_font_size_override("font_size", 20)
	var hc: Color = FAMILY_COLORS.get(fam, Color.WHITE)
	head.add_theme_color_override("font_color", hc)
	head.add_theme_constant_override("outline_size", 4)
	head.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	for line in SkillTreeData.LINES:
		var l: Dictionary = line
		if str(l.get("family", "")) == fam:
			col.add_child(_make_line_button(str(l.get("id", "")), fam))
	# 이동 계열엔 베이스라인(대시·이중점프)도 함께 — 트리 외 기본 보유 스킬.
	if fam == SkillTreeData.FAMILY_MOBILITY:
		for bid in ["dash", "double_jump"]:
			col.add_child(_make_baseline_button(bid, fam))
	return col

func _make_line_button(line_id: String, fam: String) -> Button:
	var owned: int = GameState.get_skill_tier(line_id)
	var b := Button.new()
	b.custom_minimum_size = Vector2(248, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT  # 텍스트 왼쪽 — 오른쪽에 스킬 아이콘 자리
	var t1: Dictionary = SkillTreeData.find_tier(line_id, 1)
	b.text = "%s   %s" % [_tier_dots(owned), str(t1.get("name", line_id))]
	var tint: Color = FAMILY_COLORS.get(fam, Color.WHITE)
	if owned == 0:
		tint = tint.darkened(0.32)
	b.add_theme_color_override("font_color", tint)
	b.add_theme_color_override("font_focus_color", tint.lightened(0.2))
	b.add_theme_color_override("font_hover_color", tint.lightened(0.2))
	_style_tree_button(b)
	_attach_skill_icon(b, line_id, fam)
	b.focus_entered.connect(_show_line_desc.bind(line_id, fam, false))
	b.mouse_entered.connect(_show_line_desc.bind(line_id, fam, false))
	return b

func _make_baseline_button(bid: String, fam: String) -> Button:
	var base: Dictionary = SkillTreeData.BASELINE.get(bid, {})
	var b := Button.new()
	b.custom_minimum_size = Vector2(248, 48)
	b.add_theme_font_size_override("font_size", 17)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "●     %s  (기본)" % str(base.get("name", bid))
	var tint: Color = FAMILY_COLORS.get(fam, Color.WHITE)
	b.add_theme_color_override("font_color", tint)
	b.add_theme_color_override("font_focus_color", tint.lightened(0.2))
	b.add_theme_color_override("font_hover_color", tint.lightened(0.2))
	_style_tree_button(b)
	_attach_skill_icon(b, bid, fam)
	b.focus_entered.connect(_show_line_desc.bind(bid, fam, true))
	b.mouse_entered.connect(_show_line_desc.bind(bid, fam, true))
	return b

# 트리 버튼 공통 — 얇은 검정 아웃라인으로 가독성/중간 굵기.
func _style_tree_button(b: Button) -> void:
	b.add_theme_constant_override("outline_size", 4)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))

# 라인 이름 옆(버튼 오른쪽)에 작은 스킬 아이콘. mouse IGNORE라 버튼 클릭/포커스는 그대로.
func _attach_skill_icon(b: Button, sid: String, fam: String) -> void:
	var icon := SkillIcon.new()
	icon.skill_id = sid
	icon.family = fam
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.anchor_left = 1.0
	icon.anchor_right = 1.0
	icon.anchor_top = 0.5
	icon.anchor_bottom = 0.5
	icon.offset_left = -40.0
	icon.offset_right = -10.0
	icon.offset_top = -15.0
	icon.offset_bottom = 15.0
	b.add_child(icon)

func _tier_dots(owned: int) -> String:
	var s: String = ""
	for t in range(1, SkillTreeData.TIER_MAX + 1):
		if t <= owned:
			s += "●"
		elif t == owned + 1:
			s += "◆"
		else:
			s += "○"
		if t < SkillTreeData.TIER_MAX:
			s += "─"
	return s

func _active_note(d: Dictionary) -> String:
	if bool(d.get("active", false)):
		return "  [color=#c9a24a]· 액티브[/color]"
	return ""

func _show_line_desc(line_id: String, fam: String, is_baseline: bool) -> void:
	if desc_label == null:
		return
	var famc: Color = FAMILY_COLORS.get(fam, Color.WHITE)
	var fam_hex: String = famc.to_html(false)
	var next_hex: String = COL_NEXT.to_html(false)
	var lock_hex: String = COL_LOCKED.to_html(false)
	var txt: String = ""
	if is_baseline:
		var base: Dictionary = SkillTreeData.BASELINE.get(line_id, {})
		txt += "[b][color=#%s]%s · 기본 스킬[/color][/b]\n" % [fam_hex, str(base.get("name", line_id))]
		txt += "[color=#%s]✓ %s[/color]%s" % [fam_hex, str(base.get("desc", "")), _active_note(base)]
		desc_label.text = txt
		return
	var owned: int = GameState.get_skill_tier(line_id)
	var t1name: String = str(SkillTreeData.find_tier(line_id, 1).get("name", line_id))
	txt += "[b][color=#%s]%s 계열[/color][/b]    [color=#7a8088](보유 T%d / 3)[/color]\n" % [fam_hex, t1name, owned]
	for t in range(1, SkillTreeData.TIER_MAX + 1):
		var td: Dictionary = SkillTreeData.find_tier(line_id, t)
		var nm: String = str(td.get("name", ""))
		var ds: String = str(td.get("desc", ""))
		var note: String = _active_note(td)
		if t <= owned:
			txt += "[color=#%s]✓ T%d  %s — %s[/color]%s\n" % [fam_hex, t, nm, ds, note]
		elif t == owned + 1:
			txt += "[color=#%s]▶ T%d  %s — %s  (다음 선택 가능)[/color]%s\n" % [next_hex, t, nm, ds, note]
		else:
			txt += "[color=#%s]· T%d  %s — %s  (잠김)[/color]%s\n" % [lock_hex, t, nm, ds, note]
	desc_label.text = txt

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		_close()
		get_viewport().set_input_as_handled()

func _close() -> void:
	SfxPlayer.play("ui_cancel")
	if _prev_focus != null and is_instance_valid(_prev_focus):
		_prev_focus.grab_focus()
	queue_free()
