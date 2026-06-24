class_name ArchiveOverlay
extends Node

# ??? 맵 단말기 자막 — 화면 하단 중앙에 발화자 태그 + 텍스트 한 줄씩 타자기 출력.
# Stage._build_hidden_archive에서 단말기 트리거 시 play() 호출.
#
# lines: Array of {speaker: "VEIL-1"/"VEIL-2"/"VEIL", text: String, delay: float}
# 다 끝나면 finished 시그널 emit.

signal finished

# 텍스트 속도 — 사용자: "좀 늦춰줘". 기존 0.045 → 0.08로 한 박자 느리게.
const TYPE_INTERVAL: float = 0.08
# 시작 전 정지 — 사용자: "시작하기 전에 1초 정도 딜레이".
const START_DELAY: float = 1.0

var layer: CanvasLayer
var panel: PanelContainer
var speaker_label: Label
var text_label: Label

var queued_lines: Array = []
var line_idx: int = 0
var current_full: String = ""
var revealed: int = 0
var typing: bool = false
var pause_remaining: float = 0.0
var t: float = 0.0
var _finalizing: bool = false

func _ready() -> void:
	layer = CanvasLayer.new()
	layer.layer = 25
	add_child(layer)

	panel = PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	style.border_color = Color(0.55, 0.62, 0.78, 0.45)
	style.set_border_width_all(1)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(120, 540)
	panel.size = Vector2(1040, 140)
	panel.visible = false
	layer.add_child(panel)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)

	speaker_label = Label.new()
	speaker_label.add_theme_font_size_override("font_size", 14)
	speaker_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
	v.add_child(speaker_label)

	text_label = Label.new()
	text_label.add_theme_font_size_override("font_size", 18)
	text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.custom_minimum_size = Vector2(980, 0)
	v.add_child(text_label)

func play(lines: Array) -> void:
	queued_lines = lines
	# -1로 시작 → _process가 pause_remaining 다 쓰고 line_idx += 1 = 0 → _start_line(line 0).
	line_idx = -1
	_finalizing = false
	panel.visible = true
	panel.modulate.a = 1.0
	# 시작 전 한 박자 — 텍스트가 갑자기 떠오르는 느낌 줄이고 패널이 인지된 뒤 전개.
	speaker_label.text = ""
	text_label.text = ""
	typing = false
	pause_remaining = START_DELAY
	t = 0.0

func _start_line() -> void:
	if line_idx >= queued_lines.size():
		typing = false
		_start_finalize()
		return
	var line: Dictionary = queued_lines[line_idx]
	current_full = str(line.get("text", ""))
	revealed = 0
	t = 0.0
	typing = true
	pause_remaining = 0.0
	speaker_label.text = str(line.get("speaker", ""))
	_color_for_speaker(str(line.get("speaker", "")))
	text_label.text = ""

func _color_for_speaker(sp: String) -> void:
	match sp:
		"VEIL-1":
			speaker_label.add_theme_color_override("font_color", Color(0.95, 0.55, 0.55))
		"VEIL-2":
			speaker_label.add_theme_color_override("font_color", Color(0.85, 0.78, 0.45))
		"VEIL":
			speaker_label.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95))
		_:
			speaker_label.add_theme_color_override("font_color", Color(0.78, 0.78, 0.78))

func _process(delta: float) -> void:
	if line_idx >= queued_lines.size():
		return
	if typing:
		t += delta
		if t >= TYPE_INTERVAL:
			t = 0.0
			revealed += 1
			if revealed >= current_full.length():
				revealed = current_full.length()
				typing = false
				pause_remaining = float(queued_lines[line_idx].get("delay", 1.6))
			text_label.text = current_full.substr(0, revealed)
		return
	# 줄 사이 침묵
	pause_remaining -= delta
	if pause_remaining <= 0.0:
		line_idx += 1
		_start_line()

func hide_panel() -> void:
	if panel != null:
		panel.visible = false

func _start_finalize() -> void:
	# 마지막 대사가 delay까지 다 보여진 시점. 한 박자 더 띄워두고 부드럽게 페이드아웃 후 finished.
	if _finalizing:
		return
	_finalizing = true
	if panel == null:
		emit_signal("finished")
		return
	var tw := panel.create_tween()
	tw.tween_interval(1.4)  # 마지막 대사 더 보여줌
	tw.tween_property(panel, "modulate:a", 0.0, 1.6)  # 부드러운 페이드아웃
	tw.tween_callback(func() -> void:
		if panel != null:
			panel.visible = false
		emit_signal("finished")
	)
