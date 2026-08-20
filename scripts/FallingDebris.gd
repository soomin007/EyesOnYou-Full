class_name FallingDebris
extends Node2D

# 철거구역 시그니처 해저드 · 낙하 잔해(map_identity_rework §5 확산, 2026-08-17).
# 구간(x_min~x_max) 안 임의 지점에 주기적으로 콘크리트 덩이가 떨어진다.
# 사이클: 대기 → 예고 0.9s(바닥 그림자 마커 + 천장 먼지) → 낙하(고속) → 잔해 페이드.
# "위를 조심한다"는 수직 위협 · 회피 = 그림자 마커 피하기. 즉사 없음(dmg 1).
# 광과민: 점멸 없음 · 마커는 램프로 진해진다.
#
# 2026-08-20 확장(사용자 "기믹 활용 없음"):
#  - 적도 맞는다(ENEMY_DAMAGE 3) — 유인 처치 전술 성립. 환경 처치 규약(env_killed = XP·점수
#    없음)은 열차(TrainHazard)와 동형.
#  - 발판 높이 예고 — 낙하선이 지나는 발판 표면에도 그림자 마커를 그린다(상단 캠퍼에게도
#    회피 정보 제공 · 공정성 문법). Stage가 맵 platforms에서 자동 파생해 넘긴다.
#
# 사용: MapData "debris_zones" = [{x_min, x_max, interval?, phase?, dmg?}].

enum S { IDLE, TELE, FALL, IMPACT }

const TELE_DUR: float = 0.9
const FALL_SPEED: float = 1050.0
const IMPACT_DUR: float = 0.5
const CHUNK_R: float = 20.0
const ENEMY_DAMAGE: int = 3   # 무거운 덩이 — 정찰/자폭/저격 즉사, 방패병도 크게

var x_min: float = 400.0
var x_max: float = 1200.0
var interval: float = 5.5
var damage: int = 1
var ground_y: float = 600.0
var top_y: float = -40.0
# 낙하선이 지나는 발판들 [{x_min, x_max, y}] — 예고 그림자를 그 표면에도 그린다.
var mark_platforms: Array = []

var _state: int = S.IDLE
var _t: float = 0.0
var _drop_x: float = 0.0
var _chunk_y: float = 0.0
var _hit_done: bool = false
var _hit_enemies: Dictionary = {}   # 이번 낙하에 이미 맞은 적(instance_id) — 중복 타격 방지

func setup(cfg: Dictionary, g_y: float, plats: Array = []) -> void:
	x_min = float(cfg.get("x_min", x_min))
	x_max = float(cfg.get("x_max", x_max))
	interval = float(cfg.get("interval", interval))
	damage = int(cfg.get("dmg", 1))
	ground_y = g_y
	mark_platforms = plats
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
				_hit_enemies.clear()
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
			_check_enemy_hits()
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

# 적 타격(2026-08-20) — 그림자 밑으로 유인해 잡는 전술. TrainHazard._check_enemy_hits와 동형:
# 환경 처치는 env_killed 표식으로 XP·점수를 주지 않는다(해저드로 얻는 것은 안전이지 경험치가
# 아니다 · 2026-08-19 사용자). 치명이 아니면 표식 즉시 해제.
func _check_enemy_hits() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var en := e as Node2D
		if bool(en.get("dead")) or bool(en.get("harmless")):
			continue
		if _hit_enemies.has(en.get_instance_id()):
			continue
		var ep: Vector2 = en.global_position
		if absf(ep.x - _drop_x) <= CHUNK_R + 12.0 and ep.y > _chunk_y - 30.0 and ep.y < _chunk_y + 70.0:
			_hit_enemies[en.get_instance_id()] = true
			if en.has_method("take_damage"):
				en.set("env_killed", true)
				en.call("take_damage", ENEMY_DAMAGE, 0)
				if is_instance_valid(en) and not bool(en.get("dead")):
					en.set("env_killed", false)
				SfxPlayer.play_at("bullet_impact_enemy", ep, -4.0)

func _draw() -> void:
	match _state:
		S.TELE:
			var k: float = _t / TELE_DUR
			# 바닥 그림자 마커 · 낙하점이 점점 진해진다(회피 정보의 본체).
			draw_set_transform(Vector2(_drop_x, ground_y - 3.0), 0.0, Vector2(1.0, 0.30))
			draw_circle(Vector2.ZERO, 26.0, Color(0.0, 0.0, 0.0, 0.15 + 0.30 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			draw_arc(Vector2(_drop_x, ground_y - 4.0), 24.0, PI, TAU, 16, Color(1.0, 0.6, 0.25, 0.3 + 0.5 * k), 2.0, true)
			# 낙하선이 지나는 발판 표면에도 예고 — 상단에 있는 플레이어에게도 같은 정보(공정성).
			for pe in mark_platforms:
				var pd: Dictionary = pe
				if _drop_x < float(pd.get("x_min", 0.0)) or _drop_x > float(pd.get("x_max", 0.0)):
					continue
				var py: float = float(pd.get("y", 0.0))
				draw_set_transform(Vector2(_drop_x, py - 3.0), 0.0, Vector2(1.0, 0.30))
				draw_circle(Vector2.ZERO, 22.0, Color(0.0, 0.0, 0.0, 0.13 + 0.26 * k))
				draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
				draw_arc(Vector2(_drop_x, py - 4.0), 20.0, PI, TAU, 14, Color(1.0, 0.6, 0.25, 0.25 + 0.4 * k), 2.0, true)
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
