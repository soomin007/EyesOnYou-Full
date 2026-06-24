class_name DisposalChoiceOverlay
extends RefCounted

# 막3 핵심부(lab) 보스 처치 + 데이터 회수 연출 직후 호출. 회수한 드라이브(=VEIL 소스코드)를
# 어떻게 "처리"할지 4지선다 → on_picked.call(disposal_id) 후 오버레이 자동 정리.
# 구조는 LevelUpOverlay 복제(같은 카드 UI/포커스/SFX/paused 안전판) — 선택 항목만 고정 4종.
# 대사 문구는 플레이스홀더(사용자 검토 대기). 선택지 정의 단일 소스 = GameState.DISPOSAL_*.

# 4종 처리 — id / 이름 / 한 줄 설명 / 카드 강조색. (문구는 플레이스홀더)
# 런타임 지역으로 둔다(_choices) — id가 GameState.DISPOSAL_*(오토로드 멤버)라 const 컨텍스트엔 못 넣음.
static func _choices() -> Array:
	return [
		{"id": GameState.DISPOSAL_EXTRACT, "name": "반출", "desc": "의뢰대로 드라이브를 외부로 가지고 나간다.", "color": Color(0.95, 0.78, 0.42)},
		{"id": GameState.DISPOSAL_DESTROY, "name": "파기", "desc": "이 자리에서 드라이브를 소각한다. 아무도 가질 수 없다.", "color": Color(0.95, 0.45, 0.40)},
		{"id": GameState.DISPOSAL_CONCEAL, "name": "은닉", "desc": "빼돌려, 아무도 모르게 요원이 보관한다.", "color": Color(0.55, 0.80, 0.95)},
		{"id": GameState.DISPOSAL_LEAVE, "name": "잔류", "desc": "건드리지 않는다. 있던 그 자리에 그대로 둔다.", "color": Color(0.70, 0.85, 0.70)},
	]

static func show(host: Node, on_picked: Callable) -> CanvasLayer:
	SfxPlayer.play("levelup")
	var layer := CanvasLayer.new()
	layer.layer = 42
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# 안전판: 콜백 없이 외부 경로로 사라져도 paused 누락 차단(LevelUpOverlay와 동일).
	layer.tree_exited.connect(func() -> void:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.paused = false
	)
	# 시간정지(자체) — RefCounted라 get_tree()가 없어 메인 루프로 직접 설정.
	var tree0 := Engine.get_main_loop() as SceneTree
	if tree0 != null:
		tree0.paused = true

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.88)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.process_mode = Node.PROCESS_MODE_ALWAYS
	layer.add_child(center)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	center.add_child(v)

	var title := Label.new()
	title.text = "회수한 드라이브 — 어떻게 할까요?"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	# VEIL 한 마디 — 신뢰 톤색으로(플레이스홀더 문구).
	var veil_lbl := Label.new()
	veil_lbl.text = "VEIL  —  요원이 정해요. 저는... 결과를 받아들일게요."
	veil_lbl.add_theme_font_size_override("font_size", 18)
	veil_lbl.add_theme_color_override("font_color", GameState.veil_tone_color())
	veil_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(veil_lbl)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 16)
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hb)

	for entry in _choices():
		var choice: Dictionary = entry
		var cid: String = str(choice.get("id", ""))
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(214, 184)
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.pressed.connect(func() -> void: _finish(layer, cid, on_picked))
		btn.focus_entered.connect(SfxPlayer.play.bind("ui_focus", 0.0))

		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_theme_constant_override("separation", 10)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.process_mode = Node.PROCESS_MODE_ALWAYS

		var name_lbl := Label.new()
		name_lbl.text = str(choice.get("name", ""))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 22)
		name_lbl.add_theme_color_override("font_color", choice.get("color", Color(0.95, 0.95, 0.95)))
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = str(choice.get("desc", ""))
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(190, 0)
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(desc_lbl)

		btn.add_child(content)
		hb.add_child(btn)

	host.add_child(layer)
	# 카드 버튼은 별도 SFX(아래 pick)라 wire_sfx=false. focus_entered만 ui_focus에 연결(위 loop).
	GameState.arm_focus_with_delay(layer, hb.get_child(0) as Button, GameState.INPUT_LOCKOUT_DURATION, false)
	return layer

static func _finish(layer: CanvasLayer, picked_id: String, on_picked: Callable) -> void:
	if picked_id != "":
		SfxPlayer.play("skill_pick")
	if on_picked.is_valid():
		on_picked.call(picked_id)
	if is_instance_valid(layer):
		layer.queue_free()
