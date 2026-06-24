class_name LeverInteractable
extends Area2D

# 환경 퍼즐용 레버. 플레이어가 영역 안에 있을 때 attack 키로 한 번 당겨진다.
# - body_entered/exited로 player.nearby_lever를 세팅 → Player._try_attack이 사격 대신 레버를 흡수.
# - try_pull()이 실제 활성화. one_shot=true(기본)면 한 번 당기고 잠김.
# - signal pulled(lever_id)로 Stage가 효과(발판 내림 / 환기구 열림 등)를 trigger.

signal pulled(lever_id: String)

@export var lever_id: String = ""
@export var one_shot: bool = true
@export var hint_color: Color = Color(0.55, 0.85, 0.95)  # ARCTURUS 청색 — 기본 hint

var active: bool = false
var locked: bool = false  # one_shot 후 다시 못 당기게

var _base: ColorRect
var _handle: ColorRect
var _glow: ColorRect

func _ready() -> void:
	add_to_group("lever")
	collision_layer = 0
	collision_mask = 2  # 플레이어 layer (Player.gd 기준 layer 2)
	monitoring = true
	monitorable = true

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(40.0, 64.0)
	col.shape = shape
	add_child(col)

	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)

	_build_visual()

func _build_visual() -> void:
	# 베이스(고정 받침)
	_base = ColorRect.new()
	_base.color = Color(0.35, 0.35, 0.40)
	_base.position = Vector2(-10.0, 8.0)
	_base.size = Vector2(20.0, 14.0)
	_base.z_index = -1
	add_child(_base)
	# 손잡이 — idle은 위로 기울어짐, active는 아래로
	_handle = ColorRect.new()
	_handle.color = Color(0.75, 0.75, 0.78)
	_handle.position = Vector2(-3.0, -28.0)
	_handle.size = Vector2(6.0, 36.0)
	_handle.pivot_offset = Vector2(3.0, 36.0)
	_handle.rotation = deg_to_rad(-22.0)
	add_child(_handle)
	# hint 빛 — 처음 발견을 돕는 작은 점멸
	_glow = ColorRect.new()
	_glow.color = Color(hint_color.r, hint_color.g, hint_color.b, 0.55)
	_glow.position = Vector2(-14.0, -36.0)
	_glow.size = Vector2(28.0, 6.0)
	_glow.z_index = -2
	add_child(_glow)
	var tw := _glow.create_tween()
	tw.set_loops()
	tw.tween_property(_glow, "modulate:a", 0.25, 0.9)
	tw.tween_property(_glow, "modulate:a", 1.0, 0.9)

func _on_body_entered(body: Node) -> void:
	if locked:
		return
	if body.is_in_group("player"):
		body.set("nearby_lever", self)

func _on_body_exited(body: Node) -> void:
	if body.is_in_group("player"):
		if body.get("nearby_lever") == self:
			body.set("nearby_lever", null)

func try_pull() -> bool:
	if locked:
		return false
	if active and one_shot:
		return false
	active = true
	if one_shot:
		locked = true
		# 플레이어가 이 레버를 더 이상 참조하지 않도록 정리
		for n in get_tree().get_nodes_in_group("player"):
			if n.get("nearby_lever") == self:
				n.set("nearby_lever", null)
	SfxPlayer.play("lever_pull")
	_animate_pull()
	pulled.emit(lever_id)
	return true

func _animate_pull() -> void:
	# 손잡이 회전 + 색 변화
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_handle, "rotation", deg_to_rad(28.0), 0.18)
	tw.tween_property(_handle, "color", Color(0.95, 0.55, 0.35), 0.18)
	# hint 빛 사라짐 — 더 이상 안내할 필요 없음
	if is_instance_valid(_glow):
		var tw2 := _glow.create_tween()
		tw2.tween_property(_glow, "modulate:a", 0.0, 0.30)
