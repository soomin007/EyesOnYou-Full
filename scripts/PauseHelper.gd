class_name PauseHelper
extends RefCounted

static func build(_owner: Node, on_resume: Callable, on_settings: Callable, on_to_title: Callable) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = 50
	layer.process_mode = Node.PROCESS_MODE_ALWAYS

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	center.add_child(v)

	var title := Label.new()
	title.text = "일시정지"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	var btn_resume := _make_button("계속하기")
	btn_resume.pressed.connect(on_resume)
	v.add_child(btn_resume)

	# 스킬 트리 열람 — 전체 트리(라인 점증)를 일시정지 중 확인. 자체 완결 오버레이라
	# 콜백 불필요(layer 위에 직접 얹고 스스로 닫힘). paused는 건드리지 않음.
	var btn_tree := _make_button("스킬 트리")
	btn_tree.pressed.connect(func() -> void: SkillTreeOverlay.open(layer))
	v.add_child(btn_tree)

	var btn_settings := _make_button("설정")
	btn_settings.pressed.connect(on_settings)
	v.add_child(btn_settings)

	var btn_title := _make_button("처음으로")
	btn_title.pressed.connect(on_to_title)
	v.add_child(btn_title)

	GameState.arm_focus_with_delay(layer, btn_resume)
	return layer

static func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 40)
	b.add_theme_font_size_override("font_size", 16)
	b.process_mode = Node.PROCESS_MODE_ALWAYS
	return b
