class_name BestiaryOverlay
extends RefCounted

# 적 첫 조우 시 일시정지하고 도감 카드 한 장을 띄움.
# 동시 조우가 발생해도 한 번에 하나만 표시되도록 정적 플래그로 가드.

static var _active: bool = false

static func is_active() -> bool:
	return _active

static func show_card(host: Node, enemy_id: String) -> CanvasLayer:
	if _active:
		return null
	var data: Dictionary = BestiaryData.get_data(enemy_id)
	if data.is_empty():
		return null
	_active = true
	host.get_tree().paused = true
	SfxPlayer.play("bestiary_first_seen")

	var layer := CanvasLayer.new()
	layer.layer = 45
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# 안전판: layer가 _close 콜백 없이 외부 경로(host free 등)로 사라져도 _active/paused 누락 차단.
	layer.tree_exited.connect(_on_layer_gone)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(540, 0)
	panel.process_mode = Node.PROCESS_MODE_ALWAYS
	center.add_child(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	margin.add_child(v)

	var header := Label.new()
	header.text = "[조우]"
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
	v.add_child(header)

	# 적 아이콘 — 도감이 전부 텍스트라 그림 한 장 곁들임(텍스트→그래픽).
	var icon := EnemyIcon.new()
	icon.enemy_id = enemy_id
	icon.custom_minimum_size = Vector2(76, 76)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.process_mode = Node.PROCESS_MODE_ALWAYS
	v.add_child(icon)

	var name_label := Label.new()
	name_label.text = str(data.get("name", "???"))
	name_label.add_theme_font_size_override("font_size", 24)
	name_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	v.add_child(name_label)

	# 관찰 메모 — 짧은 행동 단서. 공략은 플레이로 알아가게 (글로 풀지 않음).
	# 행동 키워드("LED", "조준선", "그림자" 등)만 강조 색으로 구분.
	var blurb := RichTextLabel.new()
	blurb.bbcode_enabled = true
	blurb.fit_content = true
	blurb.scroll_active = false
	blurb.text = _highlight_keywords(str(data.get("blurb", "")))
	blurb.add_theme_font_size_override("normal_font_size", 15)
	blurb.add_theme_color_override("default_color", Color(0.85, 0.85, 0.85))
	blurb.custom_minimum_size = Vector2(480, 0)
	v.add_child(blurb)

	var btn := Button.new()
	btn.text = "확인"
	btn.process_mode = Node.PROCESS_MODE_ALWAYS
	btn.pressed.connect(func() -> void: _close(layer))
	# ESC로도 닫히게 — 단축키(ui_cancel) 부여. 모달+일시정지 중이라 충돌 없음.
	# (단축키는 _unhandled_input보다 먼저 소비 → Stage의 pause 토글로 새지 않음.)
	var sc := Shortcut.new()
	var esc_ev := InputEventAction.new()
	esc_ev.action = "ui_cancel"
	var evs: Array[InputEvent] = []
	evs.append(esc_ev)
	sc.events = evs
	btn.shortcut = sc
	v.add_child(btn)

	host.add_child(layer)
	GameState.arm_focus_with_delay(layer, btn)
	return layer

# 행동 단서 단어를 노란색으로 강조 — 정보를 글로 풀지 않고 시선만 유도.
static func _highlight_keywords(text: String) -> String:
	var keywords: Array = [
		"붉게 깜빡", "조준선", "그림자", "빨갛게 깜빡", "방패", "튕겨낸다",
		"순찰", "호버", "자폭",
	]
	var result: String = text
	for k in keywords:
		var word: String = str(k)
		result = result.replace(word, "[color=#f5d873]%s[/color]" % word)
	return result

static func _close(layer: CanvasLayer) -> void:
	_active = false
	if not is_instance_valid(layer):
		return
	var tree := layer.get_tree()
	if tree != null:
		tree.paused = false
	layer.queue_free()

# layer가 _close 경로 외(scene 전환, host free 등)로 tree에서 빠질 때 호출. 안전판.
static func _on_layer_gone() -> void:
	_active = false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null:
		tree.paused = false
