class_name GroundShadow
extends Node2D

# 접지 그림자 · 대상 발밑에서 지면(레이어 1)으로 투영되는 부드러운 타원(2026-08-17 폴리시).
# 점프·낙하 중에도 그림자가 바닥에 남아 착지 지점과 높이감이 읽힌다. 대상이 사라지면 함께
# 정리. 광원 연출이 아니라 접지 표시라 알파는 얕게, 거리에 따라 감쇠.

const MAX_DIST: float = 420.0

var target: Node2D = null
var base_width: float = 30.0

var _dist: float = -1.0

func _ready() -> void:
	z_index = -1   # 배경 위 · 엔티티 아래

func _physics_process(_delta: float) -> void:
	if target == null or not is_instance_valid(target):
		queue_free()
		return
	var world := get_world_2d()
	if world == null:
		return
	var from: Vector2 = target.global_position + Vector2(0.0, -4.0)
	var query := PhysicsRayQueryParameters2D.create(from, from + Vector2(0.0, MAX_DIST), 1)
	query.exclude = [target]
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_dist = -1.0
	else:
		var p: Vector2 = hit.get("position", from)
		global_position = Vector2(target.global_position.x, p.y)
		_dist = p.y - target.global_position.y
	queue_redraw()

func _draw() -> void:
	if _dist < 0.0:
		return
	var k: float = clampf(1.0 - _dist / MAX_DIST, 0.0, 1.0)
	var wgt: float = base_width * (0.45 + 0.55 * k)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.30))
	draw_circle(Vector2.ZERO, wgt * 0.5, Color(0.0, 0.0, 0.0, 0.10 + 0.16 * k))
	draw_circle(Vector2.ZERO, wgt * 0.3, Color(0.0, 0.0, 0.0, 0.10 + 0.10 * k))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
