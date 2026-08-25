class_name Fx
extends Object

# 원샷 전투 이펙트(2026-08-23 그래픽 패키지 1차 · juice) · 타격 스파크 · 처치 파편 ·
# 착지/스키드 먼지 · 처치 히트스톱. 파티클 노드 대신 하우스 스타일(_draw 수동 시뮬 +
# 자체 소멸). 전부 "그림"만: 판정·보상 없음. 호출자는 스테이지 좌표계 부모를 넘긴다.
# 시간 정지(pause)·슬로모(time_scale)에 자연 동조 · _physics_process 구동이라 세계와 같이 멈춘다.

const STEEL: Color = Color(0.42, 0.45, 0.52)
const ENEMY_ACCENT: Color = Color(0.85, 0.38, 0.34)   # 경비 유닛 적갈 계열
const ELITE_ACCENT: Color = Color(0.72, 0.42, 1.0)    # 엘리트 바이올렛
const SPARK_HOT: Color = Color(1.0, 0.85, 0.45)
const PLAYER_HURT: Color = Color(1.0, 0.45, 0.40)
const DUST: Color = Color(0.62, 0.58, 0.52, 0.42)

class _Burst extends Node2D:
	# parts 원소 = {pos, vel: Vector2 · size, grav, spin, rot, life, t: float · col: Color · kind}
	var parts: Array = []
	var max_life: float = 0.6
	var _t_total: float = 0.0
	func _physics_process(delta: float) -> void:
		_t_total += delta
		for e in parts:
			var d: Dictionary = e
			d["t"] = float(d["t"]) + delta
			var v: Vector2 = d["vel"]
			v.y += float(d.get("grav", 0.0)) * delta
			d["vel"] = v
			d["pos"] = (d["pos"] as Vector2) + v * delta
			d["rot"] = float(d.get("rot", 0.0)) + float(d.get("spin", 0.0)) * delta
		queue_redraw()
		if _t_total >= max_life:
			queue_free()
	func _draw() -> void:
		for e in parts:
			var d: Dictionary = e
			var k: float = clampf(float(d["t"]) / maxf(0.05, float(d["life"])), 0.0, 1.0)
			if k >= 1.0:
				continue
			var col: Color = d["col"]
			col.a *= 1.0 - k
			var s: float = float(d["size"]) * (1.0 - 0.35 * k)
			draw_set_transform(d["pos"], float(d.get("rot", 0.0)), Vector2.ONE)
			match str(d.get("kind", "shard")):
				"spark":
					draw_line(Vector2(-s, 0), Vector2(s, 0), col, 1.7)
				"puff":
					draw_circle(Vector2.ZERO, s, col)
				"flash":
					draw_circle(Vector2.ZERO, s * (1.0 + 2.2 * k), col)
				_:
					draw_colored_polygon(PackedVector2Array([
						Vector2(-s, -s * 0.6), Vector2(s * 0.8, -s * 0.3),
						Vector2(s * 0.5, s * 0.7), Vector2(-s * 0.6, s * 0.5)]), col)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func _make(parent: Node, origin: Vector2, life: float, z: int = 3) -> _Burst:
	var b := _Burst.new()
	b.global_position = origin
	b.max_life = life
	b.z_index = z
	parent.add_child(b)
	return b

# 타격 스파크 · 명중 지점에서 탄 진행 반대 반구로 튀는 짧은 선 불꽃.
# from_dir: 탄 진행 방향(+1 우 / -1 좌 / 0 = 폭발 등 전방향).
static func hit_sparks(parent: Node, pos: Vector2, from_dir: int = 0, col: Color = SPARK_HOT) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var b := _make(parent, pos, 0.24)
	for i in 5:
		var ang: float
		if from_dir == 0:
			ang = randf() * TAU
		else:
			# 튕김 = 탄이 온 쪽(진행의 반대)으로 부챗살.
			ang = (PI if from_dir > 0 else 0.0) + randf_range(-0.9, 0.9)
		var spd: float = randf_range(200.0, 420.0)
		b.parts.append({"pos": Vector2.ZERO, "vel": Vector2(cos(ang), sin(ang) * 0.7 - 0.25) * spd,
			"size": randf_range(3.0, 5.5), "grav": 500.0, "spin": 0.0, "rot": ang,
			"life": randf_range(0.10, 0.20), "t": 0.0, "col": col, "kind": "spark"})

# 처치 파편 · 몸이 강판 조각으로 흩어진다. elite/황금은 조각 수·색이 격상.
static func death_burst(parent: Node, pos: Vector2, elite: bool = false, shiny: bool = false) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var b := _make(parent, pos, 0.55)
	# 순간 플래시 1점 · 타격의 "끊김"을 한 프레임 크게.
	var fl_col: Color = ELITE_ACCENT if elite else (Color(1.0, 0.9, 0.5) if shiny else Color(1, 1, 1, 0.9))
	b.parts.append({"pos": Vector2.ZERO, "vel": Vector2.ZERO, "size": 10.0, "grav": 0.0,
		"spin": 0.0, "rot": 0.0, "life": 0.09, "t": 0.0,
		"col": Color(fl_col.r, fl_col.g, fl_col.b, 0.55), "kind": "flash"})
	var n: int = 9 if elite else 6
	for i in n:
		var ang: float = randf() * TAU
		var spd: float = randf_range(110.0, 300.0)
		var col: Color = STEEL if i % 2 == 0 else ENEMY_ACCENT
		if elite and i % 3 == 0:
			col = ELITE_ACCENT
		if shiny and i % 2 == 1:
			col = Color(1.0, 0.85, 0.4)
		b.parts.append({"pos": Vector2.ZERO,
			"vel": Vector2(cos(ang) * spd, sin(ang) * spd * 0.8 - 140.0),
			"size": randf_range(2.6, 4.6), "grav": 900.0, "spin": randf_range(-7.0, 7.0),
			"rot": randf() * TAU, "life": randf_range(0.32, 0.5), "t": 0.0,
			"col": col, "kind": "shard"})

# 착지 먼지 · 발밑에서 양옆으로 퍼졌다 가라앉는 퍼프. strength 0~1(낙하 속도 비례).
static func land_dust(parent: Node, pos: Vector2, strength: float = 0.6) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var b := _make(parent, pos, 0.42, 1)
	var n: int = 3 + int(round(strength * 3.0))
	for i in n:
		var side: float = -1.0 if i % 2 == 0 else 1.0
		b.parts.append({"pos": Vector2(side * randf_range(2.0, 8.0), -2.0),
			"vel": Vector2(side * randf_range(40.0, 90.0 + 70.0 * strength), randf_range(-46.0, -18.0)),
			"size": randf_range(2.4, 4.2) * (0.8 + 0.5 * strength), "grav": 60.0, "spin": 0.0,
			"rot": 0.0, "life": randf_range(0.26, 0.40), "t": 0.0, "col": DUST, "kind": "puff"})

# 스키드 먼지 · 급정지 때 진행하던 방향 뒤꿈치에서 끌리는 퍼프. dir = 달리던 방향.
static func skid_dust(parent: Node, pos: Vector2, dir: int) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	var b := _make(parent, pos, 0.36, 1)
	for i in 3:
		b.parts.append({"pos": Vector2(float(-dir) * randf_range(0.0, 5.0), -2.0),
			"vel": Vector2(float(-dir) * randf_range(50.0, 120.0), randf_range(-36.0, -12.0)),
			"size": randf_range(2.2, 3.6), "grav": 70.0, "spin": 0.0,
			"rot": 0.0, "life": randf_range(0.22, 0.34), "t": 0.0, "col": DUST, "kind": "puff"})

# 처치 히트스톱 · 엘리트/황금 등 "무게 있는" 처치만 아주 짧게 시간을 문다.
# 기존 슬로모(hp T3 피격 · 보스 격파 비트)와 겹치지 않게 time_scale이 정상일 때만.
static func kill_hitstop(tree: SceneTree) -> void:
	if tree == null or Engine.time_scale < 0.9:
		return
	Engine.time_scale = 0.12
	tree.create_timer(0.05, true, false, true).timeout.connect(func() -> void:
		# 복원은 "아직 히트스톱 값일 때"만 · 그 사이 다른 슬로모(hp T3 등)가 걸렸으면 존중.
		if absf(Engine.time_scale - 0.12) < 0.01:
			Engine.time_scale = 1.0)
