extends Area2D

# 보스 SENTINEL 측면 미사일. 약한 유도 — HOMING_DURATION 동안 player 방향으로 천천히 회전,
# 이후 직진. 벽/플랫폼 충돌 시 파괴, 플레이어 닿으면 데미지 1.

const DAMAGE: int = 1
const LIFETIME: float = 4.0
const HOMING_DURATION: float = 1.4    # 1.4초까지 약한 유도
const TURN_RATE_RAD: float = 1.4      # rad/s — 약 80도/s, 직각 회전 못 하지만 따라옴

var velocity: Vector2 = Vector2.ZERO
var t: float = 0.0
var consumed: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2  # 벽/플랫폼 + 플레이어
	body_entered.connect(_on_body_entered)
	z_index = 2
	# 시각 — 빨간 작은 막대 + 후미 광점
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(20.0, 8.0)
	col.shape = shape
	add_child(col)
	var body := ColorRect.new()
	body.color = Color(0.95, 0.30, 0.30)
	body.position = Vector2(-10.0, -4.0)
	body.size = Vector2(20.0, 8.0)
	add_child(body)
	var glow := ColorRect.new()
	glow.color = Color(1.0, 0.55, 0.30, 0.55)
	glow.position = Vector2(-14.0, -3.0)
	glow.size = Vector2(6.0, 6.0)
	add_child(glow)
	# 미사일 rotation을 velocity 방향에 맞춰 초기화 — 자식 ColorRect들이 함께 회전.
	# 유도 중에 velocity가 회전하면 _process가 rotation을 갱신.
	if velocity.length() > 0.01:
		rotation = velocity.angle()

func _process(delta: float) -> void:
	if consumed:
		return
	t += delta
	# 약한 유도 — HOMING_DURATION 안에서만 player 방향으로 천천히 회전
	if t < HOMING_DURATION:
		var p: Node2D = _find_player()
		if p != null:
			var to_p: Vector2 = (p.global_position - global_position).normalized()
			var current: Vector2 = velocity.normalized()
			var angle_diff: float = current.angle_to(to_p)
			var max_turn: float = TURN_RATE_RAD * delta
			var clamped: float = clamp(angle_diff, -max_turn, max_turn)
			velocity = velocity.rotated(clamped)
			# 미사일 시각도 회전된 방향에 맞게 (rotation을 velocity 각도로)
			rotation = velocity.angle()
	position += velocity * delta
	if t >= LIFETIME:
		queue_free()

func _find_player() -> Node2D:
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node2D:
			return n as Node2D
	return null

func _on_body_entered(body: Node) -> void:
	if consumed:
		return
	consumed = true
	if body.is_in_group("player") and body.has_method("take_hit"):
		body.take_hit(DAMAGE)
	queue_free()
