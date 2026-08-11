class_name LevelUpOverlay
extends RefCounted

# 레벨업 시 호출. 스킬 3장 중 1장 선택 → on_picked.call(picked_id) 실행 후 오버레이 자동 정리.
# Stage / Tutorial 양쪽에서 동일하게 사용.

# 만렙(모든 라인 T3) 오버플로 보상 카드의 특수 id — _finish가 add_skill 대신 grant_overflow_reward.
const OVERFLOW_PICK_ID: String = "__overflow"

static func show(host: Node, advice: Variant, on_picked: Callable, forced_picks: Array = []) -> CanvasLayer:
	# advice: Dictionary {"line": String, "family": String} 권장.
	# 호환성: String을 받으면 line만 있는 dict로 처리 (튜토리얼 등 family 없음).
	# forced_picks: 비어있지 않으면 roll_choices 대신 이 카드 배열 사용 (튜토리얼 강제 픽).
	var advice_line: String = ""
	var advice_family: String = ""
	var advice_skill_id: String = ""
	if advice is Dictionary:
		advice_line = str((advice as Dictionary).get("line", ""))
		advice_family = str((advice as Dictionary).get("family", ""))
		advice_skill_id = str((advice as Dictionary).get("skill_id", ""))
	elif advice is String:
		advice_line = advice as String
	# 픽 산출을 UI보다 먼저 — 만렙(모든 라인 T3)이면 스킬 카드가 0장이라 조용히 닫혔고, 레벨업이
	# 무보상으로 보였다(사용자 보고 2026-08-10). 오버플로 보상 카드 1장으로 대체한다.
	var overflow_mode: bool = false
	var picks: Array
	if forced_picks.size() > 0:
		picks = forced_picks
	else:
		picks = SkillSystem.roll_choices(GameState.skills, 3, GameState.current_route_id)
		if picks.size() == 0:
			overflow_mode = true
			# 카드 종류는 GameState.grant_overflow_reward 우선순위와 동일하게 산출: 최대 체력 →
			# 응급 처치(회복 여지) → 점수 폴백(가득일 때만 — 점수가 빈 보상으로 읽힌 피드백 2026-08-11).
			if GameState.has_overflow_hp_room():
				picks = [{"id": OVERFLOW_PICK_ID, "name": "예비 장갑", "family": "", "tier": 0,
					"desc": "모든 스킬이 최고 단계예요. 최대 체력이 1 올라요."}]
			elif GameState.player_hp < GameState.player_max_hp:
				picks = [{"id": OVERFLOW_PICK_ID, "name": "응급 처치", "family": "", "tier": 0,
					"desc": "모든 스킬이 최고 단계예요. 체력을 %d 회복해요." % GameState.OVERFLOW_HEAL_AMOUNT}]
			else:
				picks = [{"id": OVERFLOW_PICK_ID, "name": "전술 기록", "family": "", "tier": 0,
					"desc": "모든 스킬이 최고 단계예요. 점수를 %d 더 받아요. 점수는 화면 오른쪽 위에 보여요." % GameState.OVERFLOW_SCORE_BONUS}]
	if overflow_mode:
		# 만렙 상태에선 추천 멘트가 가리킬 스킬 카드가 없다 — 혼란 방지로 멘트/추천 생략.
		advice_line = ""
		advice_family = ""
		advice_skill_id = ""
	SfxPlayer.play("levelup")
	var layer := CanvasLayer.new()
	layer.layer = 40
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	# 안전판: layer가 _on_levelup_picked 콜백 없이 외부 경로(scene 전환, host free 등)로
	# 사라져도 paused 누락 차단. host(Stage)가 set한 paused=true가 carry되어 다음 씬 freeze 방지.
	layer.tree_exited.connect(func() -> void:
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.paused = false
	)

	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.82)
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
	title.text = "LEVEL UP   보상을 받아요" if overflow_mode else "LEVEL UP   스킬을 선택해요"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)

	# VEIL 신뢰도 게이지 — 카드 위에 5단계 점으로 표시.
	# 신뢰도 따라 색이 바뀌어 플레이어와 VEIL의 관계가 매 선택에 보이게.
	var gauge := Label.new()
	gauge.text = "VEIL 신뢰   " + GameState.veil_trust_gauge_dots()
	gauge.add_theme_font_size_override("font_size", 13)
	gauge.add_theme_color_override("font_color", GameState.veil_tone_color())
	gauge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(gauge)

	if advice_line != "":
		# 신뢰도는 폰트 색(veil_tone_color)으로 표현. prefix는 안 붙임 — 실력 lead-in을
		# 위협 문장 앞에 붙이면 "필요하면, 저격수가 노려요"처럼 어색해 폐지(플레이테스트 피드백).
		var advice_label := Label.new()
		advice_label.text = "VEIL   " + advice_line
		advice_label.add_theme_font_size_override("font_size", 22)
		advice_label.add_theme_color_override("font_color", GameState.veil_tone_color())
		advice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(advice_label)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	# 카드가 1장일 때(튜토리얼 강제 픽 등) 좌측이 아니라 가운데 정렬되도록.
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(hb)

	if picks.size() == 0:
		# 안전판 — forced_picks가 비는 등 예외 경로(일반 만렙은 위에서 오버플로 카드로 대체됨).
		host.add_child(layer)
		_finish(layer, "", on_picked)
		return layer

	# VEIL 추천 — 멘트가 가리키는 family를 그대로 따라 표시. 멘트와 ★가 어긋나지
	# 않게 단일 source(advice.family)로 통일. family가 없으면(generic 멘트) 추천 없음.
	var recommended_families: Array = []
	if advice_family != "":
		recommended_families.append(advice_family)

	for p in picks:
		var skill: Dictionary = p
		var sid: String = str(skill.get("id", ""))
		var family: String = str(skill.get("family", ""))
		var tier: int = int(skill.get("tier", 1))
		# 상성 추천(skill_id 지정)이면 그 스킬만 ★ — family 폴백이면 해당 계열 전체.
		var is_recommended: bool
		if advice_skill_id != "":
			is_recommended = (sid == advice_skill_id)
		else:
			is_recommended = family != "" and family in recommended_families

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(220, 208)
		btn.process_mode = Node.PROCESS_MODE_ALWAYS
		btn.pressed.connect(func() -> void: _finish(layer, sid, on_picked))
		btn.focus_entered.connect(SfxPlayer.play.bind("ui_focus", 0.0))

		# 카드 내용 — 아이콘 + 텍스트를 버튼 위에 얹는다. 자식은 mouse IGNORE라
		# 클릭·키보드 포커스는 그대로 버튼이 받는다(포커스 네비/SFX 보존).
		var content := VBoxContainer.new()
		content.set_anchors_preset(Control.PRESET_FULL_RECT)
		content.add_theme_constant_override("separation", 7)
		content.alignment = BoxContainer.ALIGNMENT_CENTER
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.process_mode = Node.PROCESS_MODE_ALWAYS

		# 오버플로 카드는 스킬이 아니라 아이콘/티어 pip 생략(SkillIcon이 모르는 id).
		if sid != OVERFLOW_PICK_ID:
			var icon := SkillIcon.new()
			icon.skill_id = sid
			icon.family = family
			icon.custom_minimum_size = Vector2(52, 52)
			icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			icon.process_mode = Node.PROCESS_MODE_ALWAYS
			content.add_child(icon)

		var name_lbl := Label.new()
		if family != "":
			name_lbl.text = "%s\n[%s]" % [str(skill.get("name", "")), family]
		else:
			name_lbl.text = str(skill.get("name", ""))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.add_theme_font_size_override("font_size", 16)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(name_lbl)

		# 티어 pip(●●○) — "T2" 텍스트 대신 시각화. 새 스킬이 아니라 *레벨업*임을 한눈에(피드백:
		# "T1/T2 말고 동그라미 n개로"). 채운 동그라미=이번에 도달할 티어 / 빈 동그라미=남은 상위 티어.
		if sid != OVERFLOW_PICK_ID:
			var _line: Dictionary = SkillTreeData.find_line(sid)
			var _tiers: Array = _line.get("tiers", [])
			var max_tier: int = _tiers.size() if _tiers.size() > 0 else tier
			var pip_lbl := Label.new()
			pip_lbl.text = "●".repeat(tier) + "○".repeat(maxi(max_tier - tier, 0))
			pip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pip_lbl.add_theme_font_size_override("font_size", 16)
			pip_lbl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))
			pip_lbl.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.6))
			pip_lbl.add_theme_constant_override("outline_size", 3)
			pip_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(pip_lbl)

		var desc_lbl := Label.new()
		desc_lbl.text = str(skill.get("desc", ""))
		desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(196, 0)
		desc_lbl.add_theme_font_size_override("font_size", 14)
		desc_lbl.add_theme_color_override("font_color", Color(0.82, 0.85, 0.9))
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(desc_lbl)

		if is_recommended:
			name_lbl.add_theme_color_override("font_color", Color(0.98, 0.9, 0.55))
			var rec := Label.new()
			rec.text = "★ VEIL 추천"
			rec.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			rec.add_theme_font_size_override("font_size", 14)
			rec.add_theme_color_override("font_color", Color(0.98, 0.88, 0.5))
			rec.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(rec)

		btn.add_child(content)
		hb.add_child(btn)
	# 전체 스킬 트리 보기 — 픽 3장만으론 안 보이는 라인 점증(T2·T3)을 확인하고 결정.
	# 자체 완결 오버레이를 layer 위에 얹고 스스로 닫힘. paused 유지.
	var tree_btn := Button.new()
	tree_btn.text = "전체 스킬 트리 보기"
	tree_btn.custom_minimum_size = Vector2(0, 34)
	tree_btn.add_theme_font_size_override("font_size", 14)
	tree_btn.process_mode = Node.PROCESS_MODE_ALWAYS
	tree_btn.pressed.connect(func() -> void: SkillTreeOverlay.open(layer))
	v.add_child(tree_btn)

	host.add_child(layer)
	# 카드 버튼은 ui_confirm + skill_pick 중복 방지를 위해 wire_sfx=false.
	# focus_entered만 별도로 ui_focus에 연결됨 (위 loop 안).
	GameState.arm_focus_with_delay(layer, hb.get_child(0) as Button, GameState.INPUT_LOCKOUT_DURATION, false)
	return layer

static func _finish(layer: CanvasLayer, picked_id: String, on_picked: Callable) -> void:
	if picked_id == OVERFLOW_PICK_ID:
		# 만렙 오버플로 보상 — 스킬 대신 예비 장갑(최대 HP +1) → 응급 처치(회복) → 점수 폴백.
		SfxPlayer.play("skill_pick")
		GameState.grant_overflow_reward()
	elif picked_id != "":
		SfxPlayer.play("skill_pick")
		GameState.add_skill(picked_id)
	if on_picked.is_valid():
		on_picked.call(picked_id)
	if is_instance_valid(layer):
		layer.queue_free()
