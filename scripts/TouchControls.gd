class_name TouchControls
extends CanvasLayer

# 모바일 터치 조작 오버레이 — 인게임(Stage)에 얹는 가상 버튼 패드.
#
# 동작 원리: 이 게임의 인게임 입력은 전부 폴링(Input.get_axis / is_action_pressed /
# is_action_just_pressed)이라, 가상 버튼이 Input.action_press/release만 호출하면 Player.gd를
# 고치지 않고 그대로 먹는다. (이 게임은 마우스 조준이 아니라 facing 방향 횡사격이라 조준 스틱이
# 불필요 — mobile_feasibility.md 참조.)
#
# 예외: pause는 Stage가 _unhandled_input의 *이벤트*(event.is_action_pressed("pause"))로 토글하므로
# action_press로는 안 잡힌다 → InputEventAction을 parse_input_event로 주입한다.
#
# 멀티터치: 손가락(index)별로 어떤 버튼을 누르는지 추적해 "이동하면서 점프+사격 동시"를 지원한다.
# 게이팅: DisplayServer.is_touchscreen_available()인 기기에서만 Stage가 생성한다(데스크톱 무영향).

const FONT_PATH: String = "res://assets/fonts/Pretendard-Regular.otf"

const BG_COL: Color = Color(0.70, 0.78, 0.92, 0.13)
const BG_DOWN_COL: Color = Color(0.45, 0.78, 1.0, 0.42)
const EDGE_COL: Color = Color(0.82, 0.90, 1.0, 0.42)
const EDGE_DOWN_COL: Color = Color(0.78, 0.96, 1.0, 0.95)
const ICON_COL: Color = Color(0.92, 0.96, 1.0, 0.88)

var _font: Font = null
var _pad: Control = null
# 버튼 목록 — 각 항목 {action,label,kind,center:Vector2,radius:float}.
# kind: "tri_left"/"tri_right"/"tri_down"/"text"/"pause".
var _buttons: Array = []
var _finger: Dictionary = {}   # 터치 index -> 누르고 있는 버튼 인덱스
var _down: Dictionary = {}     # 버튼 인덱스 -> true (시각 하이라이트용)
var _portrait: bool = false
var _was_paused: bool = false

# 그리기 전용 자식 Control — CanvasLayer 자신은 CanvasItem이 아니라 _draw가 없어서,
# Control 하나를 두고 그 _draw에서 host._render(self)를 호출하게 한다.
class _Pad extends Control:
	var host: Object = null
	func _draw() -> void:
		if host != null and host.has_method("_render"):
			host.call("_render", self)

func _ready() -> void:
	# paused(레벨업·일시정지) 중에도 _process로 가시성을 끄려면 ALWAYS여야 한다. 대신 _input은
	# paused/portrait면 직접 가드해 게임에 입력이 새지 않게 한다.
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 5
	if ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	if _font == null:
		_font = ThemeDB.fallback_font
	_pad = _Pad.new()
	_pad.host = self
	_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE  # gui_input을 가로채지 않게 — 입력은 _input에서 직접 처리
	add_child(_pad)
	_build_buttons()
	_fit()
	# CanvasLayer 자식 Control은 anchor로 화면 크기를 못 받는다(known_issues) → 직접 맞추고
	# 해상도/방향 변경 시 재배치.
	get_viewport().size_changed.connect(_fit)

func _build_buttons() -> void:
	_buttons = [
		{"action": "move_left",  "label": "",   "kind": "tri_left",  "radius": 58.0, "center": Vector2.ZERO},
		{"action": "move_right", "label": "",   "kind": "tri_right", "radius": 58.0, "center": Vector2.ZERO},
		{"action": "move_down",  "label": "",   "kind": "tri_down",  "radius": 44.0, "center": Vector2.ZERO},
		{"action": "attack",     "label": "사격", "kind": "text",      "radius": 62.0, "center": Vector2.ZERO},
		{"action": "jump",       "label": "점프", "kind": "text",      "radius": 56.0, "center": Vector2.ZERO},
		{"action": "dash",       "label": "대시", "kind": "text",      "radius": 46.0, "center": Vector2.ZERO},
		{"action": "skill",      "label": "스킬", "kind": "text",      "radius": 46.0, "center": Vector2.ZERO},
		{"action": "pause",      "label": "",   "kind": "pause",     "radius": 30.0, "center": Vector2.ZERO},
	]

func _fit() -> void:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	if _pad != null:
		_pad.position = Vector2.ZERO
		_pad.size = vs
	_portrait = vs.y > vs.x
	_layout(vs)
	if _pad != null:
		_pad.queue_redraw()

# 코너 기준 배치 — 화면 폭/높이에 맞춰 매 _fit마다 다시 계산(폰 비율이 1280x720보다 넓어도 코너에 붙음).
func _layout(vs: Vector2) -> void:
	var w: float = vs.x
	var h: float = vs.y
	# 좌하단 = 이동 클러스터(왼손 엄지)
	_set_center("move_left",  Vector2(108.0, h - 92.0))
	_set_center("move_right", Vector2(248.0, h - 92.0))
	_set_center("move_down",  Vector2(178.0, h - 204.0))
	# 우하단 = 액션 클러스터(오른손 엄지). 사격을 코너 가장 가까이(가장 자주 씀).
	_set_center("attack", Vector2(w - 104.0, h - 96.0))
	_set_center("jump",   Vector2(w - 230.0, h - 120.0))
	_set_center("dash",   Vector2(w - 112.0, h - 232.0))
	_set_center("skill",  Vector2(w - 224.0, h - 256.0))
	# 우상단 = 일시정지
	_set_center("pause",  Vector2(w - 58.0, 54.0))

func _set_center(action: String, c: Vector2) -> void:
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		if b["action"] == action:
			b["center"] = c
			return

func _input(event: InputEvent) -> void:
	# 세로(조작 불가 안내 중) 또는 일시정지 중엔 터치를 게임으로 흘리지 않는다.
	if _portrait or get_tree().paused:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_finger_down(t.index, t.position)
		else:
			_finger_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		_finger_move(d.index, d.position)

# 위치에 해당하는 버튼 인덱스(없으면 -1). 엄지 빗맞음 관용으로 반경을 살짝 넉넉히 본다.
func _button_at(pos: Vector2) -> int:
	var best: int = -1
	var best_d: float = 1.0e20
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		var c: Vector2 = b["center"]
		var r: float = b["radius"]
		var dist: float = pos.distance_to(c)
		if dist <= r * 1.18 and dist < best_d:
			best_d = dist
			best = i
	return best

func _finger_down(index: int, pos: Vector2) -> void:
	var bi: int = _button_at(pos)
	if bi < 0:
		return
	_finger[index] = bi
	_activate(bi, true)

func _finger_move(index: int, pos: Vector2) -> void:
	var cur: int = int(_finger.get(index, -1))
	var bi: int = _button_at(pos)
	if bi == cur:
		return
	# 손가락이 다른 버튼(또는 밖)으로 옮겨감 — 이전 해제 후 새 버튼 활성(좌↔우 슬라이드에 유용).
	if cur >= 0:
		_activate(cur, false)
		_finger.erase(index)
	if bi >= 0:
		_finger[index] = bi
		_activate(bi, true)

func _finger_up(index: int) -> void:
	var cur: int = int(_finger.get(index, -1))
	if cur >= 0:
		_activate(cur, false)
	_finger.erase(index)

func _activate(bi: int, on: bool) -> void:
	var b: Dictionary = _buttons[bi]
	var action: String = b["action"]
	if on:
		_down[bi] = true
	else:
		_down.erase(bi)
	if action == "pause":
		# Stage는 이벤트로 pause를 토글하므로 합성 InputEventAction을 주입.
		var ev := InputEventAction.new()
		ev.action = "pause"
		ev.pressed = on
		Input.parse_input_event(ev)
	elif on:
		Input.action_press(action)
	else:
		Input.action_release(action)
	if _pad != null:
		_pad.queue_redraw()

func _process(_delta: float) -> void:
	var p: bool = get_tree().paused
	if p != _was_paused:
		_was_paused = p
		if p:
			_release_all()  # 일시정지 진입 시 눌린 채로 멈춘 액션이 carry되지 않게
		if _pad != null:
			_pad.visible = not p

# 눌려 있던 모든 액션 해제 — 일시정지 진입/씬 이탈 시 유령 입력 방지.
func _release_all() -> void:
	for index in _finger.keys():
		var cur: int = int(_finger[index])
		if cur >= 0:
			var b: Dictionary = _buttons[cur]
			var action: String = b["action"]
			if action != "pause" and InputMap.has_action(action):
				Input.action_release(action)
	_finger.clear()
	_down.clear()
	if _pad != null:
		_pad.queue_redraw()

func _exit_tree() -> void:
	_release_all()

# --- 그리기 (자식 _Pad의 _draw에서 호출) ---

func _render(pad: Control) -> void:
	if _portrait:
		_render_rotate_hint(pad)
		return
	for i in _buttons.size():
		var b: Dictionary = _buttons[i]
		_draw_button(pad, b, _down.has(i))

func _render_rotate_hint(pad: Control) -> void:
	var vs: Vector2 = pad.size
	pad.draw_rect(Rect2(Vector2.ZERO, vs), Color(0.03, 0.04, 0.05, 0.96))
	if _font != null:
		var msg: String = "기기를 가로로 돌려주세요"
		var fs: int = 38
		pad.draw_string(_font, Vector2(0.0, vs.y * 0.5), msg, HORIZONTAL_ALIGNMENT_CENTER, vs.x, fs, Color(0.85, 0.92, 1.0, 0.95))

func _draw_button(pad: Control, b: Dictionary, down: bool) -> void:
	var c: Vector2 = b["center"]
	var r: float = b["radius"]
	var kind: String = b["kind"]
	pad.draw_circle(c, r, BG_DOWN_COL if down else BG_COL)
	pad.draw_arc(c, r, 0.0, TAU, 40, EDGE_DOWN_COL if down else EDGE_COL, 2.5, true)
	if kind == "tri_left":
		pad.draw_colored_polygon(PackedVector2Array([
			c + Vector2(-r * 0.38, 0.0), c + Vector2(r * 0.26, -r * 0.42), c + Vector2(r * 0.26, r * 0.42)]), ICON_COL)
	elif kind == "tri_right":
		pad.draw_colored_polygon(PackedVector2Array([
			c + Vector2(r * 0.38, 0.0), c + Vector2(-r * 0.26, -r * 0.42), c + Vector2(-r * 0.26, r * 0.42)]), ICON_COL)
	elif kind == "tri_down":
		pad.draw_colored_polygon(PackedVector2Array([
			c + Vector2(0.0, r * 0.38), c + Vector2(-r * 0.42, -r * 0.26), c + Vector2(r * 0.42, -r * 0.26)]), ICON_COL)
	elif kind == "pause":
		var bw: float = r * 0.22
		var bh: float = r * 0.72
		pad.draw_rect(Rect2(c + Vector2(-bw * 1.6, -bh * 0.5), Vector2(bw, bh)), ICON_COL)
		pad.draw_rect(Rect2(c + Vector2(bw * 0.6, -bh * 0.5), Vector2(bw, bh)), ICON_COL)
	elif kind == "text" and _font != null:
		var label: String = b["label"]
		var fs: int = 28
		pad.draw_string(_font, c + Vector2(-r, fs * 0.34), label, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, fs, ICON_COL)
