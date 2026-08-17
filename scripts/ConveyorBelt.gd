class_name ConveyorBelt
extends Node2D

# 물류 창고 시그니처 해저드 · 컨베이어 바닥(map_identity_rework §8, 2026-08-17).
# 지면 구간이 한 방향으로 흐른다: 결을 타면 빨라지고, 거스르면 느려진다(돌풍의 실내 변주 ·
# 공중이 아니라 지면에서만 민다). 피해는 없고 이동 자체가 룰 · 거스르는 벨트 위에서
# 폭격기/방패병과 싸우는 게 이 맵의 손맛.
# 시각: 벨트 밴드 + 흐르는 셰브런(연속 이동 · 점멸 없음) + 양끝 롤러.
#
# 사용: MapData "conveyors" = [{x1, x2, dir(1/-1), speed?}]. Player.floor_push_x에 세팅.

var x1: float = 400.0
var x2: float = 1200.0
var dir: int = 1
var speed: float = 120.0
var ground_y: float = 600.0

var _t: float = 0.0
var _pushing: bool = false

func setup(cfg: Dictionary, g_y: float) -> void:
	x1 = float(cfg.get("x1", x1))
	x2 = float(cfg.get("x2", x2))
	dir = int(cfg.get("dir", 1))
	speed = float(cfg.get("speed", 120.0))
	ground_y = g_y
	z_index = -1
	add_to_group("conveyor_belt")

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	var p: Node = get_tree().get_first_node_in_group("player")
	if p is Node2D:
		var pos: Vector2 = (p as Node2D).global_position
		var inside: bool = pos.x >= x1 and pos.x <= x2 and absf(pos.y - ground_y) < 12.0
		if inside:
			p.set("floor_push_x", speed * float(dir))
			_pushing = true
		elif _pushing:
			# 내가 밀던 경우에만 해제 · 다른 벨트가 세팅한 값을 덮지 않는다.
			p.set("floor_push_x", 0.0)
			_pushing = false
	queue_redraw()

func _exit_tree() -> void:
	if not _pushing:
		return
	var tree := get_tree()
	if tree == null:
		return
	var p: Node = tree.get_first_node_in_group("player")
	if p != null:
		p.set("floor_push_x", 0.0)

func _draw() -> void:
	var w: float = x2 - x1
	# 벨트 밴드 · 어두운 고무 + 상단 하이라이트.
	draw_rect(Rect2(Vector2(x1, ground_y - 8.0), Vector2(w, 8.0)), Color(0.10, 0.10, 0.12))
	draw_rect(Rect2(Vector2(x1, ground_y - 8.0), Vector2(w, 2.0)), Color(0.30, 0.32, 0.38))
	# 흐르는 셰브런 · 방향과 속도가 그대로 보인다(연속 이동).
	var off: float = fmod(_t * speed, 56.0) * float(dir)
	var cx: float = x1 + (off if dir > 0 else 56.0 + off)
	while cx < x2 - 8.0:
		if cx > x1 + 4.0:
			var tip: float = 7.0 * float(dir)
			draw_polyline(PackedVector2Array([
				Vector2(cx - tip, ground_y - 7.0), Vector2(cx, ground_y - 4.0), Vector2(cx - tip, ground_y - 1.0)]),
				Color(0.85, 0.72, 0.30, 0.55), 2.0)
		cx += 56.0
	# 양끝 롤러 · 회전 표시 점.
	for rx in [x1, x2]:
		draw_circle(Vector2(float(rx), ground_y - 4.0), 7.0, Color(0.22, 0.23, 0.27))
		var ra: float = _t * speed * 0.03 * float(dir)
		draw_circle(Vector2(float(rx), ground_y - 4.0) + Vector2.from_angle(ra) * 4.0, 1.6, Color(0.55, 0.58, 0.66))
