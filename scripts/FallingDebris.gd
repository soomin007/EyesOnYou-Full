class_name FallingDebris
extends Node2D

# 철거구역 시그니처 해저드 · 낙하 잔해(map_identity_rework §5 확산, 2026-08-17).
# 구간(x_min~x_max) 안 임의 지점에 주기적으로 콘크리트 덩이가 떨어진다.
# 사이클: 대기 → 예고 0.9s(바닥 그림자 마커 + 천장 먼지) → 낙하(고속) → 잔해 페이드.
# "위를 조심한다"는 수직 위협 · 회피 = 그림자 마커 피하기. 즉사 없음(dmg 1).
# 광과민: 점멸 없음 · 마커는 램프로 진해진다.
#
# 사용: MapData "debris_zones" = [{x_min, x_max, interval?, phase?, dmg?}].

enum S { IDLE, TELE, FALL, IMPACT }

const TELE_DUR: float = 0.9
const FALL_SPEED: float = 1050.0
const IMPACT_DUR: float = 0.5
const CHUNK_R: float = 20.0

var x_min: float = 400.0
var x_max: float = 1200.0
var interval: float = 5.5
var damage: int = 1
var ground_y: float = 600.0
var top_y: float = -40.0

var _state: int = S.IDLE
var _t: float = 0.0
var _drop_x: float = 0.0
var _chunk_y: float = 0.0
var _hit_done: bool = false

func setup(cfg: Dictionary, g_y: float) -> void:
	x_min = float(cfg.get("x_min", x_min))
	x_max = float(cfg.get("x_max", x_max))
	interval = float(cfg.get("interval", interval))
	damage = int(cfg.get("dmg", 1))
	ground_y = g_y
	z_index = 2
	add_to_group("falling_debris")
	# 첫 낙하는 이르게(기믹 조기 노출 · 열차·수위·돌풍과 동형).
	_t = interval - float(cfg.get("phase", 0.0)) * interval - 2.2

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	match _state:
		S.IDLE:
			if _t >= interval:
				_state = S.TELE
				_t = 0.0
				_hit_done = false
				# 낙하점 · 구간 안 임의 + 플레이어가 구간 안이면 근처로 살짝 유도(위협 체감).
				_drop_x = randf_range(x_min, x_max)
				var p: Node = get_tree().get_first_node_in_group("player")
				if p is Node2D:
					var px: float = (p as Node2D).global_position.x
					if px > x_min and px < x_max and randf() < 0.5:
						_drop_x = clampf(px + randf_range(-90.0, 90.0), x_min, x_max)
				SfxPlayer.play_at("drop_platform_descend", Vector2(_drop_x, ground_y), -10.0)
		S.TELE:
			if _t >= TELE_DUR:
				_state = S.FALL
				_t = 0.0
				_chunk_y = top_y
		S.FALL:
			_chunk_y += FALL_SPEED * delta
			_check_hit()
			if _chunk_y >= ground_y - 8.0:
				_state = S.IMPACT
				_t = 0.0
				SfxPlayer.play_at("bullet_impact_wall", Vector2(_drop_x, ground_y), -2.0)
		S.IMPACT:
			if _t >= IMPACT_DUR:
				_state = S.IDLE
				_t = 0.0
	queue_redraw()

func _check_hit() -> void:
	if _hit_done:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D) or bool(p.get("clear_protect")):
		return
	var pos: Vector2 = (p as Node2D).global_position
	if absf(pos.x - _drop_x) <= CHUNK_R + 12.0 and pos.y > _chunk_y - 30.0 and pos.y < _chunk_y + 70.0:
		_hit_done = true
		if p.has_method("take_hit"):
			p.call("take_hit", damage)
			SfxPlayer.play_at("spike_hit", pos)

func _draw() -> void:
	match _state:
		S.TELE:
			var k: float = _t / TELE_DUR
			# 바닥 그림자 마커 · 낙하점이 점점 진해진다(회피 정보의 본체).
			draw_set_transform(Vector2(_drop_x, ground_y - 3.0), 0.0, Vector2(1.0, 0.30))
			draw_circle(Vector2.ZERO, 26.0, Color(0.0, 0.0, 0.0, 0.15 + 0.30 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_arc(Vector2(_drop_x, ground_y - 4.0), 24.0, PI, TAU, 16, Color(1.0, 0.6, 0.25, 0.3 + 0.5 * k), 2.0, true)
			# 천장 먼지 · 위에서 부스러기가 먼저 흘러내린다.
			for i in 3:
				var dy: float = top_y + 30.0 + fmod(_t * 260.0 + float(i) * 47.0, 130.0)
				draw_circle(Vector2(_drop_x + sin(float(i) * 2.4) * 10.0, dy), 2.0, Color(0.65, 0.58, 0.5, 0.6))
		S.FALL:
			# 덩이 · 각진 콘크리트 + 짧은 모션 트레일.
			draw_rect(Rect2(Vector2(_drop_x - 6.0, _chunk_y - 64.0), Vector2(12.0, 44.0)), Color(0.45, 0.42, 0.38, 0.25))
			var pts := PackedVector2Array([
				Vector2(_drop_x - CHUNK_R, _chunk_y - 6.0), Vector2(_drop_x - 6.0, _chunk_y - CHUNK_R),
				Vector2(_drop_x + CHUNK_R * 0.7, _chunk_y - CHUNK_R * 0.8), Vector2(_drop_x + CHUNK_R, _chunk_y),
				Vector2(_drop_x + CHUNK_R * 0.4, _chunk_y + CHUNK_R * 0.6), Vector2(_drop_x - CHUNK_R * 0.6, _chunk_y + CHUNK_R * 0.5)])
			draw_polygon(pts, PackedColorArray([Color(0.5, 0.47, 0.43)]))
			draw_polyline(pts, Color(0.28, 0.26, 0.23), 2.0, true)
		S.IMPACT:
			var k2: float = 1.0 - _t / IMPACT_DUR
			# 잔해 더미 + 먼지 퍼프(페이드).
			var rp := PackedVector2Array([
				Vector2(_drop_x - 24.0, ground_y), Vector2(_drop_x - 8.0, ground_y - 14.0),
				Vector2(_drop_x + 10.0, ground_y - 10.0), Vector2(_drop_x + 24.0, ground_y)])
			draw_polygon(rp, PackedColorArray([Color(0.42, 0.39, 0.35, 0.5 + 0.4 * k2)]))
			for i in 4:
				var a2: float = float(i) * 1.7
				draw_circle(Vector2(_drop_x + cos(a2) * (18.0 + 26.0 * (1.0 - k2)), ground_y - 8.0 - sin(a2) * 14.0 * (1.0 - k2)),
					5.0 * k2 + 2.0, Color(0.6, 0.55, 0.5, 0.3 * k2))
