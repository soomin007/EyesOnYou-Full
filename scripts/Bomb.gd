class_name Bomb
extends Area2D

# 드론이 투하하는 폭탄. 중력을 받아 떨어지며 벽/플랫폼/플레이어와 닿으면 폭발.
# 퓨즈 시간 내 충돌이 없으면 공중에서 자동 폭발.

const GRAVITY: float = 900.0
const FUSE: float = 1.6
const RADIUS: float = 70.0
const DAMAGE: int = 1

var velocity: Vector2 = Vector2.ZERO
var fuse: float = FUSE
var exploded: bool = false

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 2  # 벽/플랫폼 + 플레이어
	body_entered.connect(_on_body_entered)
	z_index = 2

	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 7.0
	col.shape = shape
	add_child(col)

	var sprite := ColorRect.new()
	sprite.color = Color(0.85, 0.40, 0.20)
	sprite.position = Vector2(-6, -6)
	sprite.size = Vector2(12, 12)
	add_child(sprite)
	var fuse_dot := ColorRect.new()
	fuse_dot.color = Color(1.0, 0.9, 0.4)
	fuse_dot.position = Vector2(-2, -10)
	fuse_dot.size = Vector2(4, 3)
	add_child(fuse_dot)
	# 투척 SFX는 spawner에서 호출 — 드론은 enemy_drone_drop, 보스는 bomb_throw.
	# 자동 재생하면 두 사운드가 겹치고 보스/드론 구분이 안 됨.

func _process(delta: float) -> void:
	if exploded:
		return
	velocity.y += GRAVITY * delta
	position += velocity * delta
	fuse -= delta
	if fuse <= 0.0:
		_explode()

func _on_body_entered(_body: Node) -> void:
	if exploded:
		return
	_explode()

func _explode() -> void:
	exploded = true
	SfxPlayer.play_at("bomb_explode", global_position)
	for n in get_tree().get_nodes_in_group("player"):
		if not (n is Node2D):
			continue
		var p := n as Node2D
		if p.global_position.distance_to(global_position) <= RADIUS:
			if p.has_method("take_hit"):
				p.take_hit(DAMAGE)
	var blast := Polygon2D.new()
	blast.color = Color(0.95, 0.55, 0.30, 0.85)
	blast.z_index = 3
	var pts: Array = []
	for i in 24:
		var a: float = float(i) * TAU / 24.0
		pts.append(Vector2(cos(a) * RADIUS, sin(a) * RADIUS))
	blast.polygon = PackedVector2Array(pts)
	blast.global_position = global_position
	blast.scale = Vector2(0.2, 0.2)
	get_parent().add_child(blast)
	var tw := blast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2(1.0, 1.0), 0.25)
	tw.tween_property(blast, "modulate", Color(1, 1, 1, 0), 0.40)
	tw.chain().tween_callback(blast.queue_free)
	queue_free()
