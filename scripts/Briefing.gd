extends Control

@onready var stage_label: Label = $Box/Margin/V/Stage
@onready var speaker_label: Label = $Box/Margin/V/Speaker
@onready var text_label: Label = $Box/Margin/V/Text
@onready var hint_label: Label = $Box/Margin/V/Hint
@onready var visual: Control = $Visual
@onready var mission_visual: Control = $MissionVisual

const TYPE_INTERVAL: float = 0.04
# 막 진입 카드(B-1) — 막의 첫 stage(0/3/6)에서 브리핑 *앞*에 "ACT N · 이름"을 띄워 막을 *느껴지게* 한다.
# (act_identity.md §3 B-1. 데이터 단일 소스 = GameState.ACTS.)
const ACT_ROMAN: Array = ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX"]

# 시퀀스 모델: 각 line은 {speaker: "SYS"/"VEIL", text: String}
# stage 0 진입 시 시스템 텍스트(OPERATION PALIMPSEST) + VEIL 첫 마디들이 먼저 나오고,
# 그 다음 평소처럼 stage 브리핑 한 줄. 그 외 stage는 brief 한 줄만.
var lines: Array = []
var line_idx: int = 0

# 막 진입 카드 진행 상태 — true인 동안 브리핑 타이핑을 보류하고 카드 페이드만 돈다.
var card_active: bool = false
var _act_card: Control = null
var _card_tween: Tween = null

var revealed_chars: int = 0
var type_t: float = 0.0
var done: bool = false
# 진입 직후 입력 lockout — 보스 클리어 후 LevelUp + Briefing이 점프 연타로 자동
# 넘어가는 치명적 버그(사용자 보고) 차단.
var input_lockout_t: float = GameState.INPUT_LOCKOUT_DURATION

func _ready() -> void:
	# 안전망: 이전 scene에서 paused=true 상태가 carry되어 Briefing이 freeze되는 패턴 차단
	# (사용자 보고: "stage 6/7만 뜨고 텍스트 없는 멈춤" — 도전방 fail/LevelUpOverlay 등에서 paused 해제 누락).
	get_tree().paused = false
	# VEIL 눈은 모든 브리핑에 — "당신을 본다" 정체성을 매 스테이지 유지.
	# 미션 목표물 아이콘은 첫 진입(OPERATION PALIMPSEST)에서만. 박스는 중앙 폭 그대로.
	var intro: bool = (GameState.current_stage == 0)
	visual.visible = true
	mission_visual.visible = intro
	stage_label.text = "STAGE %d / %d" % [GameState.current_stage + 1, GameState.effective_total_stages()]
	lines = _build_lines()
	GameState.input_kind_changed.connect(_on_input_kind_changed)
	_build_tip_label()
	# 막 진입 카드는 본편(비스토리)에서 막의 첫 stage일 때만. 그 외엔 곧장 브리핑 타이핑.
	if (not GameState.story_mode) and GameState.is_act_start(GameState.current_stage):
		_begin_act_card()
	else:
		_start_line()

func _build_tip_label() -> void:
	# 로딩 팁 — 맵마다 1개씩 로테이션(피드백 "게임이 안 알려준다" 보완). 화면 하단.
	var tip := Label.new()
	tip.text = "TIP   " + GameInfo.tip_at(GameState.current_stage)
	tip.add_theme_font_size_override("font_size", 15)
	tip.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82))
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	tip.anchor_top = 0.89
	tip.anchor_bottom = 0.98
	tip.offset_left = 140
	tip.offset_right = -140
	tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tip)

# --- 막 진입 카드 (B-1) ---
# 페이드인(0.4) → 유지(1.1) → 페이드아웃(0.5) 후 브리핑 타이핑 시작. 입력으로 건너뛸 수 있다.
func _begin_act_card() -> void:
	card_active = true
	var act_idx: int = GameState.act_for_stage(GameState.current_stage)
	var act: Dictionary = GameState.ACTS[act_idx]
	_act_card = _build_act_card(act_idx, str(act.get("name", "")))
	add_child(_act_card)  # 마지막 자식 = 최상단 → 브리핑 위를 덮음
	# 카드 배경(ColorRect)은 불투명 그대로 첫 프레임부터 화면을 덮어 브리핑 박스·그림 누수를 차단하고,
	# 텍스트(Content)만 페이드한다 — 카드 전체를 페이드하면 투명 구간에 아래 브리핑이 비친다(사용자 보고).
	var content: Control = _act_card.get_node("Content")
	content.modulate.a = 0.0
	_card_tween = create_tween()
	_card_tween.tween_property(content, "modulate:a", 1.0, 0.4)
	_card_tween.tween_interval(1.1)
	_card_tween.tween_property(content, "modulate:a", 0.0, 0.5)
	_card_tween.tween_callback(_finish_card)

func _build_act_card(act_idx: int, act_name: String) -> Control:
	var card := ColorRect.new()
	card.color = Color(0.03, 0.035, 0.05, 1.0)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := VBoxContainer.new()
	center.name = "Content"  # _begin_act_card가 이 노드만 페이드 (배경은 불투명 유지)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.add_theme_constant_override("separation", 12)
	card.add_child(center)
	# ACT N (로마숫자)
	var roman: String = str(ACT_ROMAN[act_idx]) if act_idx < ACT_ROMAN.size() else str(act_idx + 1)
	var big := Label.new()
	big.text = "ACT " + roman
	big.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	big.add_theme_font_size_override("font_size", 64)
	big.add_theme_color_override("font_color", Color(0.86, 0.91, 1.0))
	big.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	big.add_theme_constant_override("outline_size", 6)
	center.add_child(big)
	# 구분선
	var rule := ColorRect.new()
	rule.color = Color(0.4, 0.55, 0.7, 0.6)
	rule.custom_minimum_size = Vector2(160, 2)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	center.add_child(rule)
	# 막 이름
	var sub := Label.new()
	sub.text = act_name
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 30)
	sub.add_theme_color_override("font_color", Color(0.62, 0.7, 0.82))
	center.add_child(sub)
	return card

func _finish_card() -> void:
	if not card_active:
		return
	card_active = false
	if _card_tween != null and _card_tween.is_valid():
		_card_tween.kill()
	if is_instance_valid(_act_card):
		_act_card.queue_free()
		_act_card = null
	_start_line()

func _on_input_kind_changed(_kind: String) -> void:
	# 타이핑 진행 중엔 hint 비어 있음. 완료 상태에서만 갱신.
	if done:
		hint_label.text = _continue_hint()

func _continue_hint() -> String:
	return GameState.hint("[ SPACE — 계속 ]", "[ A — 계속 ]")

func _build_lines() -> Array:
	var out: Array = []
	# 첫 진입 시 1회만 OPERATION PALIMPSEST 시스템 텍스트 + VEIL 인사
	if GameState.current_stage == 0:
		out.append({"speaker": "SYS", "text": VeilDialogue.get_intro_system_text()})
		for s in VeilDialogue.get_intro_veil_lines():
			out.append({"speaker": "VEIL", "text": str(s)})
	out.append({"speaker": "VEIL", "text": VeilDialogue.get_briefing(GameState.current_stage)})
	return out

func _start_line() -> void:
	revealed_chars = 0
	type_t = 0.0
	done = false
	hint_label.text = ""
	var line: Dictionary = lines[line_idx]
	var sp: String = str(line.get("speaker", ""))
	if sp == "SYS":
		speaker_label.text = ""
		text_label.add_theme_color_override("font_color", Color(0.62, 0.72, 0.85))
	else:
		speaker_label.text = "VEIL"
		text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	text_label.text = ""

func _process(delta: float) -> void:
	if input_lockout_t > 0.0:
		input_lockout_t -= delta
	if card_active:
		return  # 막 진입 카드가 도는 동안엔 브리핑 타이핑 보류
	if done:
		return
	type_t += delta
	if type_t >= TYPE_INTERVAL:
		type_t = 0.0
		revealed_chars += 1
		var full: String = str(lines[line_idx].get("text", ""))
		if revealed_chars >= full.length():
			revealed_chars = full.length()
			done = true
			hint_label.text = _continue_hint()
		text_label.text = full.substr(0, revealed_chars)

func _unhandled_input(event: InputEvent) -> void:
	# ESC는 최우선 — 입력 락아웃과 무관하게 브리핑 전체를 건너뛰고 루트 선택으로.
	# (오프닝/브리핑에서 ESC가 안 먹던 문제. 어떤 화면에서도 ESC는 즉시 반응.)
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file(SceneRouter.ROUTE_MAP)
		return
	if card_active:
		# 막 진입 카드는 락아웃 경과 후 점프/스킵으로 건너뛴다(ESC는 위에서 처리됨).
		if input_lockout_t <= 0.0 and (event.is_action_pressed("ui_skip") or event.is_action_pressed("jump")):
			get_viewport().set_input_as_handled()
			_finish_card()
		return
	if input_lockout_t > 0.0:
		# 보스 클리어 후 잔여 점프 연타 차단.
		return
	if event.is_action_pressed("ui_skip") or event.is_action_pressed("jump"):
		if not done:
			# 한 줄 즉시 완성
			var full: String = str(lines[line_idx].get("text", ""))
			revealed_chars = full.length()
			text_label.text = full
			done = true
			hint_label.text = _continue_hint()
			return
		_advance()

func _advance() -> void:
	line_idx += 1
	if line_idx >= lines.size():
		get_tree().change_scene_to_file(SceneRouter.ROUTE_MAP)
		return
	_start_line()
