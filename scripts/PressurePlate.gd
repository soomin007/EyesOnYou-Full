class_name PressurePlate
extends Area2D

# 발판(pressure plate) 인터랙션. 플레이어가 위에 올라서면 stepped(plate_id)을 emit.
# - one_shot=true(기본)면 한 번만 트리거된 뒤 잠김.
# - require_armed=true면 armed=true가 될 때까지는 step 무시 (예: 레버를 먼저 당겨야 활성).
# - LeverInteractable과 같은 시각 톤(헛광 + ARCTURUS 청색 hint)을 따름.

signal stepped(plate_id: String)

@export var plate_id: String = ""
@export var one_shot: bool = true
@export var require_armed: bool = false
@export var hint_color: Color = Color(0.55, 0.85, 0.95)
# 발판 외형 — 폭/두께. 베이스 사이즈에 맞춰 visual + collision 둘 다 조절.
@export var plate_width: float = 60.0
@export var plate_thickness: float = 8.0

var armed: bool = false   # require_armed=true일 때만 의미. 외부에서 arm()으로 활성.
var pressed: bool = false # 한 번이라도 step 됐는지
var locked: bool = false
var _player_inside: bool = false

var _base: ColorRect
var _glow: ColorRect
var _glow_tween: Tween = null

func _ready() -> void:
	add_to_group("pressure_plate")
	collision_layer = 0
	collision_mask = 2  # 플레이어
	monitoring = true
	monitorable = true
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(plate_width, plate_thickness * 2.0)
	col.shape = shape
	add_child(col)
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_build_visual()
	_refresh_visual()

func _build_visual() -> void:
	# 베이스 — 짙은 금속색 사각판
	_base = ColorRect.new()
	_base.color = Color(0.18, 0.20, 0.24)
	_base.position = Vector2(-plate_width * 0.5, -plate_thickness * 0.5)
	_base.size = Vector2(plate_width, plate_thickness)
	_base.z_index = -1
	add_child(_base)
	# 가운데 hint 띠 — armed 상태에 따라 색·강도 변화
	_glow = ColorRect.new()
	_glow.position = Vector2(-plate_width * 0.5 + 4.0, -plate_thickness * 0.5 + 1.0)
	_glow.size = Vector2(plate_width - 8.0, 1.5)
	add_child(_glow)

func _refresh_visual() -> void:
	if _glow == null:
		return
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	if pressed:
		# 눌린 상태 — 베이스 살짝 어둡게, glow 꺼짐.
		_base.color = Color(0.10, 0.12, 0.16)
		_glow.color = Color(hint_color.r, hint_color.g, hint_color.b, 0.25)
		_glow.modulate.a = 1.0
		return
	if require_armed and not armed:
		# 비활성 — 회색 glow, 점멸 없음.
		_glow.color = Color(0.45, 0.45, 0.50, 0.45)
		_glow.modulate.a = 1.0
		return
	# 활성 대기 — hint_color로 점멸.
	_glow.color = Color(hint_color.r, hint_color.g, hint_color.b, 0.85)
	_glow_tween = _glow.create_tween()
	_glow_tween.set_loops()
	_glow_tween.tween_property(_glow, "modulate:a", 0.30, 0.7)
	_glow_tween.tween_property(_glow, "modulate:a", 1.0, 0.7)

func arm() -> void:
	if armed:
		return
	armed = true
	_refresh_visual()
	# armed 직후 이미 발판 위에 서 있으면 즉시 step (요원이 미리 올라가 기다리는 케이스).
	if _player_inside:
		_try_step()

func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = true
	_try_step()

func _on_body_exited(body: Node) -> void:
	if not body.is_in_group("player"):
		return
	_player_inside = false

func _try_step() -> void:
	if locked:
		return
	if pressed and one_shot:
		return
	if require_armed and not armed:
		SfxPlayer.play("plate_step_inactive")
		return
	pressed = true
	if one_shot:
		locked = true
	_refresh_visual()
	SfxPlayer.play("plate_step_active")
	stepped.emit(plate_id)
