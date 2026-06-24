extends Node

func _ready() -> void:
	# 저장된 키설정을 먼저 적용한 뒤, 핵심 마우스(좌=사격/우=스킬)·WASD-UI 기본을 보강한다.
	# 순서 중요: load_settings가 attack 이벤트를 cfg값으로 덮어쓰므로(erase+reload), 마우스 보강은
	# 그 뒤에 둬야 한다. 안 그러면 cfg에 마우스 좌클릭이 빠진 경우 좌클릭 사격이 사라진다(사용자 보고 버그).
	GameState.load_settings()
	_bind_default_mouse_inputs()
	_bind_wasd_to_ui()
	GameState.apply_display_settings()
	Accessibility.apply()
	GameState.reset()
	# call_deferred로 미룸: _ready 중 부트스트랩 노드가 아직 트리에 붙는 중에 씬을 교체하면
	# "Parent node is busy adding/removing children" 경고가 난다. 한 프레임 미뤄 안전하게 전환.
	get_tree().change_scene_to_file.call_deferred(SceneRouter.TITLE)

# 마우스 좌/우 클릭을 attack/skill의 기본 이벤트로 보강(이미 있으면 그대로). load_settings 뒤에 호출 —
# 좌클릭 사격·우클릭 스킬은 핵심 조작이라 cfg가 잃어버려도 항상 살아 있게 한다.
func _bind_default_mouse_inputs() -> void:
	_ensure_mouse_event("attack", MOUSE_BUTTON_LEFT)
	_ensure_mouse_event("skill", MOUSE_BUTTON_RIGHT)

func _ensure_mouse_event(action: String, btn: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventMouseButton and (e as InputEventMouseButton).button_index == btn:
			return
	var ev := InputEventMouseButton.new()
	ev.button_index = btn
	# 마우스 이벤트를 첫 번째 슬롯으로 (primary)
	var existing: Array = []
	for e in InputMap.action_get_events(action):
		existing.append(e)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)
	for e in existing:
		InputMap.action_add_event(action, e)

# WASD를 ui_left/right/up/down에 추가 → 메뉴/스킬 선택을 WASD로 이동 가능
# 동시에 ui_accept/cancel/방향에 패드 매핑이 빠져 있으면 보강 (Godot 빌트인이
# 누락된 환경 또는 기존 cfg 잔재로 비어 있을 때 대비).
func _bind_wasd_to_ui() -> void:
	_ensure_key_event("ui_up", KEY_W)
	_ensure_key_event("ui_down", KEY_S)
	_ensure_key_event("ui_left", KEY_A)
	_ensure_key_event("ui_right", KEY_D)
	# 패드 — A=accept, B=cancel, D-Pad/좌스틱 = 방향
	_ensure_pad_button("ui_accept", JOY_BUTTON_A)
	_ensure_pad_button("ui_cancel", JOY_BUTTON_B)
	_ensure_pad_button("ui_up", JOY_BUTTON_DPAD_UP)
	_ensure_pad_button("ui_down", JOY_BUTTON_DPAD_DOWN)
	_ensure_pad_button("ui_left", JOY_BUTTON_DPAD_LEFT)
	_ensure_pad_button("ui_right", JOY_BUTTON_DPAD_RIGHT)
	_ensure_pad_axis("ui_left",  JOY_AXIS_LEFT_X, -1.0)
	_ensure_pad_axis("ui_right", JOY_AXIS_LEFT_X,  1.0)
	_ensure_pad_axis("ui_up",    JOY_AXIS_LEFT_Y, -1.0)
	_ensure_pad_axis("ui_down",  JOY_AXIS_LEFT_Y,  1.0)
	_ensure_pad_axis("ui_focus_next", JOY_AXIS_TRIGGER_RIGHT, 1.0)
	_ensure_pad_axis("ui_focus_prev", JOY_AXIS_TRIGGER_LEFT, 1.0)

func _ensure_key_event(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and (e as InputEventKey).physical_keycode == keycode:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _ensure_pad_button(action: String, button_index: int) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and (e as InputEventJoypadButton).button_index == button_index:
			return
	var ev := InputEventJoypadButton.new()
	ev.button_index = button_index
	InputMap.action_add_event(action, ev)

func _ensure_pad_axis(action: String, axis: int, value: float) -> void:
	if not InputMap.has_action(action):
		return
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadMotion:
			var jm := e as InputEventJoypadMotion
			if jm.axis == axis and signf(jm.axis_value) == signf(value):
				return
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
