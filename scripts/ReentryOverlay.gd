class_name ReentryOverlay
extends RefCounted

# 기록 재진입(팔림프세스트) · 타이틀에서 진입(replay_support_plan §2).
# 완주한 런의 막 경계 스냅샷(act0~4)을 골라 그 지점부터 재개한다. 재진입 지점이 곧 전략:
# 늦게 들어가면 빠르지만 바꿀 수 있는 게 적고(막5 = 처리 선택뿐), 일찍 들어가면 느리지만
# 신뢰·진실(???)까지 갈아탈 수 있다(§2.3 속도 vs 가변성). Zero Escape "보이되 잠김" 문법.
# 구조는 DisposalChoiceOverlay 계열(static show → CanvasLayer). 문구는 초안(dialogue_review 대상).

const ROMAN: Array = ["I", "II", "III", "IV", "V"]

static func show(host: Node) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 42

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.04, 0.94)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	center.add_child(v)

	var title := Label.new()
	title.text = "기록 재진입"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	v.add_child(title)

	var sub := Label.new()
	sub.text = "덮어쓴 작전 기록의 막 경계에서 다시 시작합니다.  ·  기록된 결말  %d / 9" % GameState.endings_seen.size()
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", Color(0.72, 0.75, 0.80))
	v.add_child(sub)

	if GameState.has_run():
		var warn := Label.new()
		warn.text = "진행 중인 작전이 있습니다. 재진입하면 그 기록 위에 덮어씁니다."
		warn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warn.add_theme_font_size_override("font_size", 13)
		warn.add_theme_color_override("font_color", Color(0.95, 0.78, 0.5))
		v.add_child(warn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	v.add_child(spacer)

	var first_btn: Button = null
	for act in range(GameState.ACTS.size()):
		var row := _make_row(layer, act)
		v.add_child(row)
		if first_btn == null and row is Button and not (row as Button).disabled:
			first_btn = row as Button

	var spacer2 := Control.new()
	spacer2.custom_minimum_size = Vector2(0, 6)
	v.add_child(spacer2)

	var b_close := Button.new()
	b_close.text = "돌아가기"
	b_close.custom_minimum_size = Vector2(640, 40)
	b_close.pressed.connect(func() -> void:
		if is_instance_valid(layer):
			layer.queue_free()
	)
	v.add_child(b_close)

	host.add_child(layer)
	SfxPlayer.wire_ui_buttons(v)
	if first_btn != null:
		first_btn.grab_focus.call_deferred()
	else:
		b_close.grab_focus.call_deferred()
	return layer

static func _make_row(layer: CanvasLayer, act: int) -> Control:
	var d: Dictionary = GameState.ACTS[act]
	var snap: Dictionary = GameState.get_act_snapshot_summary(act)
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(640, 76)
	if snap.is_empty():
		btn.disabled = true
	else:
		btn.pressed.connect(func() -> void: _pick(layer, act))

	var content := VBoxContainer.new()
	content.set_anchors_preset(Control.PRESET_FULL_RECT)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_theme_constant_override("separation", 2)
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var head := Label.new()
	head.text = "ACT %s  %s   ·   스테이지 %d부터" % [
		str(ROMAN[act]), str(d.get("name", "")), GameState.act_start_stage(act) + 1]
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 18)
	head.add_theme_color_override("font_color",
		Color(0.92, 0.92, 0.92) if not snap.is_empty() else Color(0.55, 0.55, 0.58))
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(head)

	var info := Label.new()
	if snap.is_empty():
		info.text = "기록 없음 · 이 구간을 지나 완주하면 기록이 남습니다"
		info.add_theme_color_override("font_color", Color(0.52, 0.52, 0.56))
	else:
		var truth_mark: String = "  ·  진실 목격" if bool(snap.get("truth_seen", false)) else ""
		info.text = "Lv %d  ·  체력 %d  ·  스킬 %d  ·  추천 수용 %d/%d%s" % [
			int(snap.get("level", 1)), int(snap.get("max_hp", 3)), int(snap.get("skill_count", 0)),
			int(snap.get("followed_count", 0)), int(snap.get("rec_count", 0)), truth_mark]
		info.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_font_size_override("font_size", 13)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(info)

	if not snap.is_empty():
		var hint := Label.new()
		hint.text = "여기서 바꿀 수 있는 것: " + _mutable_hint(act, snap)
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		hint.add_theme_font_size_override("font_size", 12)
		hint.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(hint)

	btn.add_child(content)
	return btn

# 이 지점에서 아직 바꿀 수 있는 엔딩 축 안내(§2.3). 진실을 이미 목격한 기록은 결말이 진실로
# 수렴하므로(EndingResolver) 정직하게 고지 · 다른 갈래를 원하면 더 이른 기록으로.
static func _mutable_hint(act: int, snap: Dictionary) -> String:
	if bool(snap.get("truth_seen", false)):
		return "없음 · 이 기록의 결말은 진실로 고정"
	if act >= 4:
		return "처리 선택"
	if act == 3:
		return "처리 선택 · 신뢰(남은 구간만큼)"
	return "처리 선택 · 신뢰 · 기록에 없는 방(???)"

static func _pick(layer: CanvasLayer, act: int) -> void:
	if not GameState.start_reentry(act):
		return
	SfxPlayer.play("skill_pick")
	var tree := Engine.get_main_loop() as SceneTree
	if is_instance_valid(layer):
		layer.queue_free()
	if tree != null:
		SceneRouter.go(tree, SceneRouter.BRIEFING)
