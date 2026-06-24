class_name EnemyIcon
extends Control

# 적 도감(조우 카드)용 절차적 아이콘 — 자산 없이 _draw 도형. enemy_id별 알아보기 쉬운 글리프.
# 도감이 전부 텍스트라 "텍스트→그래픽" 방향으로 한 장씩 그림을 곁들인다.

var enemy_id: String = ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _draw() -> void:
	var c: Vector2 = size * 0.5
	var r: float = minf(size.x, size.y) * 0.5 * 0.8
	if r < 6.0:
		return
	match enemy_id:
		"patrol": _patrol(c, r)
		"sniper": _sniper(c, r)
		"drone": _drone(c, r)
		"bomber": _bomber(c, r)
		"shield": _shield(c, r)
		_: _generic(c, r)

# 정찰병 — 머리 LED + 좌우 순찰 화살표
func _patrol(c: Vector2, r: float) -> void:
	var col := Color(0.93, 0.64, 0.46)
	var head: Vector2 = c + Vector2(0.0, -r * 0.22)
	draw_arc(head, r * 0.45, 0.0, TAU, 24, col, 2.5, true)
	draw_circle(head + Vector2(0.0, -r * 0.18), r * 0.13, Color(1.0, 0.32, 0.3))  # LED
	var y: float = c.y + r * 0.62
	draw_line(Vector2(c.x - r * 0.66, y), Vector2(c.x + r * 0.66, y), col, 2.0, true)
	draw_colored_polygon(_arrow(Vector2(c.x - r * 0.45, y), Vector2(c.x - r * 0.7, y), 5.0), col)
	draw_colored_polygon(_arrow(Vector2(c.x + r * 0.45, y), Vector2(c.x + r * 0.7, y), 5.0), col)

# 저격수 — 스코프 십자선 + 레이저
func _sniper(c: Vector2, r: float) -> void:
	var col := Color(0.96, 0.43, 0.43)
	draw_arc(c, r * 0.62, 0.0, TAU, 30, col, 2.5, true)
	draw_line(c + Vector2(-r * 0.62, 0.0), c + Vector2(r * 0.62, 0.0), col, 1.5, true)
	draw_line(c + Vector2(0.0, -r * 0.62), c + Vector2(0.0, r * 0.62), col, 1.5, true)
	draw_circle(c, r * 0.1, col)
	draw_line(c, c + Vector2(r * 1.0, r * 0.5), Color(1.0, 0.3, 0.3, 0.85), 1.5, true)

# 공습 드론 — 쿼드콥터(중앙 + 4 로터)
func _drone(c: Vector2, r: float) -> void:
	var col := Color(0.56, 0.8, 0.96)
	draw_circle(c, r * 0.2, col)
	for ang in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var d := Vector2(cos(ang), sin(ang))
		var rotor: Vector2 = c + d * r * 0.72
		draw_line(c, rotor, col, 2.0, true)
		draw_arc(rotor, r * 0.22, 0.0, TAU, 14, col, 1.5, true)

# 자폭병 — 폭탄 + 퓨즈 + 경고 펄스 링
func _bomber(c: Vector2, r: float) -> void:
	var col := Color(0.97, 0.62, 0.35)
	var body: Vector2 = c + Vector2(0.0, r * 0.15)
	draw_arc(body, r * 0.5, 0.0, TAU, 26, col, 2.5, true)
	draw_arc(body, r * 0.78, 0.0, TAU, 30, Color(1.0, 0.4, 0.3, 0.5), 1.5, true)
	draw_line(c + Vector2(0.0, -r * 0.35), c + Vector2(r * 0.28, -r * 0.72), col, 2.0, true)
	draw_circle(c + Vector2(r * 0.28, -r * 0.72), r * 0.11, Color(1.0, 0.74, 0.35))

# 방패병 — 큰 방패 + 중앙 보스
func _shield(c: Vector2, r: float) -> void:
	var col := Color(0.73, 0.81, 0.91)
	var pts := PackedVector2Array([
		c + Vector2(-r * 0.6, -r * 0.7), c + Vector2(r * 0.6, -r * 0.7),
		c + Vector2(r * 0.6, r * 0.25), c + Vector2(0.0, r * 0.85), c + Vector2(-r * 0.6, r * 0.25)])
	draw_polyline(_closed(pts), col, 2.5, true)
	draw_circle(c + Vector2(0.0, -r * 0.1), r * 0.17, col)

func _generic(c: Vector2, r: float) -> void:
	draw_arc(c, r * 0.7, 0.0, TAU, 24, Color(0.8, 0.5, 0.45), 2.0, true)
	draw_circle(c, r * 0.18, Color(0.8, 0.5, 0.45))

# ── 헬퍼 ──
func _arrow(from_p: Vector2, to_p: Vector2, sz: float) -> PackedVector2Array:
	var dir: Vector2 = (to_p - from_p).normalized()
	var perp := Vector2(-dir.y, dir.x)
	return PackedVector2Array([to_p, to_p - dir * sz * 1.6 + perp * sz, to_p - dir * sz * 1.6 - perp * sz])

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if pts.size() > 0:
		out.append(pts[0])
	return out
