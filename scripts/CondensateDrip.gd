class_name CondensateDrip
extends Node2D

# 응축기 구역 시그니처 해저드 · 응축수 낙수(map_identity_rework §8, 2026-08-17).
# 천장 배관의 응축수가 맺혀서 떨어진다. 냉각 시설(바닥에서 솟는 증기)과 축 반전:
# 위에서 떨어지는 고온 응축수 · 사이클: 맺힘 0.9s(방울이 커진다 + 바닥 착점 마커) →
# 낙하 → 튐. 회피 = 맺히는 방울/바닥 마커 보고 비키기. dmg 1 · 즉사 없음.
# 광과민: 점멸 없음 · 마커는 램프로 진해진다.
#
# 사용: MapData "drips" = [{x, src_y?, interval?, phase?, dmg?}]. Stage가 ground_y 전달.

enum S { IDLE, FORM, FALL, SPLASH }

const FORM_DUR: float = 0.9
const FALL_SPEED: float = 820.0
const SPLASH_DUR: float = 0.35

var src_y: float = 210.0
var interval: float = 2.6
var damage: int = 1
var ground_y: float = 600.0

var _state: int = S.IDLE
var _t: float = 0.0
var _drop_y: float = 0.0
var _hit_done: bool = false

func setup(cfg: Dictionary, g_y: float) -> void:
	position = Vector2(float(cfg.get("x", 0.0)), 0.0)
	src_y = float(cfg.get("src_y", 210.0))
	interval = float(cfg.get("interval", 2.6))
	damage = int(cfg.get("dmg", 1))
	ground_y = g_y
	z_index = 1
	add_to_group("condensate_drip")
	_t = fmod(float(cfg.get("phase", 0.0)), 1.0) * interval

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	match _state:
		S.IDLE:
			if _t >= interval:
				_state = S.FORM
				_t = 0.0
				_hit_done = false
		S.FORM:
			if _t >= FORM_DUR:
				_state = S.FALL
				_t = 0.0
				_drop_y = src_y + 8.0
		S.FALL:
			_drop_y += FALL_SPEED * delta
			_check_hit()
			if _drop_y >= ground_y - 4.0:
				_state = S.SPLASH
				_t = 0.0
				SfxPlayer.play_at("spike_hit", Vector2(global_position.x, ground_y), -14.0)
		S.SPLASH:
			if _t >= SPLASH_DUR:
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
	if absf(pos.x - global_position.x) <= 16.0 and pos.y > _drop_y - 10.0 and pos.y < _drop_y + 66.0:
		_hit_done = true
		if p.has_method("take_hit"):
			p.call("take_hit", damage)
			SfxPlayer.play_at("spike_hit", pos)

func _draw() -> void:
	# 배관 스터브 · 낙수점이 상시 보인다(위치 학습).
	draw_rect(Rect2(Vector2(-10.0, src_y - 10.0), Vector2(20.0, 10.0)), Color(0.15, 0.20, 0.22))
	draw_rect(Rect2(Vector2(-4.0, src_y), Vector2(8.0, 6.0)), Color(0.22, 0.29, 0.31))
	match _state:
		S.FORM:
			var k: float = _t / FORM_DUR
			# 맺히는 방울 · 점점 커지고 늘어진다.
			var r: float = 2.5 + 4.0 * k
			draw_circle(Vector2(0.0, src_y + 8.0 + 3.0 * k), r, Color(0.62, 0.92, 1.0, 0.85))
			draw_circle(Vector2(-1.0, src_y + 6.0 + 3.0 * k), r * 0.4, Color(0.9, 1.0, 1.0, 0.7))
			# 바닥 착점 마커 · 어디에 떨어질지(회피 정보) 램프로 진해진다.
			draw_arc(Vector2(0.0, ground_y - 3.0), 16.0, PI, TAU, 12, Color(1.0, 0.6, 0.25, 0.25 + 0.45 * k), 2.0, true)
		S.FALL:
			# 낙하 방울 + 짧은 꼬리.
			draw_rect(Rect2(Vector2(-1.5, _drop_y - 26.0), Vector2(3.0, 22.0)), Color(0.62, 0.92, 1.0, 0.35))
			draw_circle(Vector2(0.0, _drop_y), 5.0, Color(0.62, 0.92, 1.0, 0.9))
			draw_arc(Vector2(0.0, ground_y - 3.0), 16.0, PI, TAU, 12, Color(1.0, 0.6, 0.25, 0.6), 2.0, true)
		S.SPLASH:
			var k2: float = 1.0 - _t / SPLASH_DUR
			# 튐 · 좌우로 벌어지는 물점 + 김 한 줌(고온).
			for sgn in [-1.0, 1.0]:
				draw_circle(Vector2(float(sgn) * (6.0 + 14.0 * (1.0 - k2)), ground_y - 6.0 - 10.0 * (1.0 - k2) * k2 * 4.0),
					2.2 * k2 + 0.8, Color(0.62, 0.92, 1.0, 0.6 * k2))
			draw_circle(Vector2(0.0, ground_y - 8.0), 6.0 * (1.0 - k2) + 2.0, Color(0.85, 0.95, 1.0, 0.25 * k2))
