class_name EnemyBullet
extends Area2D

# 적이 발사하는 프로젝타일. 벽/플레이어와 충돌하면 사라짐.
# 플레이어 Bullet과 분리한 이유: collision mask, 색상, 속도, 데미지 규칙이 달라
# 한 클래스에 분기를 넣기보다 별도 클래스가 깔끔.

# 사용자 피드백(2026-05-16): 360은 회피가 거의 불가능 — 240으로 낮춤.
# Player bullet 900 대비 27% 속도라 점프/대시로 충분히 피할 수 있는 영역.
const BASE_SPEED: float = 240.0
const BASE_LIFETIME: float = 1.6  # 속도 낮춘 만큼 lifetime 늘려 사거리 유지(384px → 384px)

var velocity: Vector2 = Vector2.ZERO
var damage: int = 1
var lifetime: float = BASE_LIFETIME

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2  # 벽/플랫폼 + 플레이어
	body_entered.connect(_on_body_entered)
	z_index = 2

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(10.0, 5.0)
	col.shape = shape
	add_child(col)

	# 진행 방향으로 회전 — 아래/위/대각 발사에서도 총알이 나아가는 쪽을 향하게(좌우 전용 그림 버그 수정).
	if velocity != Vector2.ZERO:
		rotation = velocity.angle()

	# 적 톤(주황) — 플레이어 노랑과 시각적으로 구분. 로컬 +x = 진행 방향.
	var trail := ColorRect.new()
	trail.color = Color(1.0, 0.55, 0.30, 0.55)
	trail.size = Vector2(16.0, 2.0)
	trail.position = Vector2(-20.0, -1.0)  # 본체 뒤로(꼬리)
	add_child(trail)

	var body := ColorRect.new()
	body.color = Color(1.0, 0.65, 0.35, 1.0)
	body.size = Vector2(8.0, 4.0)
	body.position = Vector2(-4.0, -2.0)
	add_child(body)

func _process(delta: float) -> void:
	position += velocity * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("player"):
		if body.has_method("take_hit"):
			body.take_hit(damage)
		queue_free()
	elif body is StaticBody2D:
		queue_free()
