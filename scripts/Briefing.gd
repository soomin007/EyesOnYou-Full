extends Control

@onready var stage_label: Label = $Box/Margin/V/Stage
@onready var speaker_label: Label = $Box/Margin/V/Speaker
@onready var text_label: Label = $Box/Margin/V/Text
@onready var hint_label: Label = $Box/Margin/V/Hint
@onready var visual: Control = $Visual
@onready var mission_visual: Control = $MissionVisual

const TYPE_INTERVAL: float = 0.04

# 시퀀스 모델: 각 line은 {speaker: "SYS"/"VEIL", text: String}
# stage 0 진입 시 시스템 텍스트(OPERATION PALIMPSEST) + VEIL 첫 마디들이 먼저 나오고,
# 그 다음 평소처럼 stage 브리핑 한 줄. 그 외 stage는 brief 한 줄만.
var lines: Array = []
var line_idx: int = 0

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
	_start_line()
	GameState.input_kind_changed.connect(_on_input_kind_changed)

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
