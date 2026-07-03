extends Node

# 디버그 모드 표시등 (autoload). GameState.debug_unlocked가 켜지면 화면 우상단 구석에 작은 칩을 띄운다.
# 전역 오버레이라 타이틀·맵선택·인게임·설정 등 모든 씬에서 보인다(디버그가 켜져 있음을 항상 알림).
# debug_unlocked는 세션 한정(비영속)이라 새 세션엔 자동으로 사라진다.

var _layer: CanvasLayer = null
var _chip: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 127  # OrientationGuard(128) 바로 아래, 그 외 모든 오버레이 위
	add_child(_layer)
	_chip = Label.new()
	_chip.text = "● DEBUG"
	_chip.add_theme_font_size_override("font_size", 13)
	_chip.add_theme_color_override("font_color", Color(0.98, 0.75, 0.25))
	_chip.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.9))
	_chip.add_theme_constant_override("outline_size", 3)
	_chip.mouse_filter = Control.MOUSE_FILTER_IGNORE  # 입력 절대 안 막음
	_chip.visible = false
	_layer.add_child(_chip)
	_reposition()
	get_viewport().size_changed.connect(_reposition)

func _process(_delta: float) -> void:
	if _chip == null:
		return
	var on: bool = GameState.debug_unlocked
	if _chip.visible != on:
		_chip.visible = on

# CanvasLayer 자식 Control은 anchor로 화면 크기를 못 받으므로(known_issues) 위치를 직접 맞춘다.
func _reposition() -> void:
	if _chip == null:
		return
	var vs: Vector2 = get_viewport().get_visible_rect().size
	_chip.position = Vector2(vs.x - 94.0, 8.0)  # 우상단 구석
