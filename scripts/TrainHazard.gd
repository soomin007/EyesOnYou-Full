class_name TrainHazard
extends Node2D

# 폐쇄 지하철 시그니처 해저드 · 무인 화물 열차(map_identity_rework §4, 2026-08-16).
# 서사: 폐역이지만 선로는 살아 있다 · ARCTURUS가 발주한 무인 운행(MAINTENANCE ONLY 표지와 정합).
# 주기: 대기(interval) → 텔레그래프(신호등 적색 전환 + 경고음, telegraph초) → 고속 통과.
# 선로 대역(바닥 위 TRAIN_H)에 있으면 대뎀 + 진행 방향 넉백. 즉사 아님 · 반복 조우 해저드
# (사용자 확정 2026-08-16: 즉사 대신 대뎀+넉백). 대피 = 벽감(niche) 안 / 단차 위 / 타이밍 점프.
# 광과민: 점멸 없음 · 신호등은 색 전환 후 유지.
#
# 사용: MapData "train_hazard" = {interval?, telegraph?, speed?, dmg?, lights?: [x...]}.
# 벽감은 기존 "cover_niches"/"niche_half"를 그대로 읽는다(시각 = Stage._build_cover_niches).

const TRAIN_W: float = 520.0
const TRAIN_H: float = 130.0     # 저상 화물 열차 · 이단 점프(~190px) 정점이면 넘을 수 있는 높이
const KNOCKBACK_X: float = 620.0
const KNOCKBACK_Y: float = -260.0

enum S { IDLE, TELEGRAPH, PASS }

var interval: float = 8.5
var telegraph: float = 2.2
var speed: float = 2400.0
var dmg: int = 2
var ground_y: float = 420.0
var x_min: float = -800.0        # 통과 시작/끝 x(맵 밖 여유)
var x_max: float = 6000.0
var niches: Array = []           # 세이프 벽감 x 중심들(cover_niches와 동일 값)
var niche_half: float = 90.0

var _state: int = S.IDLE
var _t: float = 0.0
var _dir: int = 1                # 통과 방향 · 매회 교대
var _train_x: float = 0.0
var _hit_done: bool = false      # 통과당 피해 1회
var _lights: Array = []          # 신호등 램프 노드들

func setup(cfg: Dictionary, g_y: float, stage_len: float, niche_xs: Array, n_half: float) -> void:
	interval = float(cfg.get("interval", 8.5))
	telegraph = float(cfg.get("telegraph", 2.2))
	speed = float(cfg.get("speed", 2400.0))
	dmg = int(cfg.get("dmg", 2))
	ground_y = g_y
	x_min = -TRAIN_W - 300.0
	x_max = stage_len + TRAIN_W + 300.0
	niches = niche_xs
	niche_half = n_half
	add_to_group("train_hazard")  # 조회용(하니스·향후 VEIL 콜아웃 연동)
	z_index = 6                   # 플레이어 위 · 치이면 차체가 덮는 그림
	_t = interval * 0.55          # 첫 열차는 조금 이르게 · 기믹을 초반에 한 번 보여준다
	for lx in cfg.get("lights", []):
		_spawn_light(float(lx))

# 선로 신호등 · 평시 녹색, 텔레그래프/통과 중 적색(점멸 없이 전환 유지).
func _spawn_light(lx: float) -> void:
	var pole := ColorRect.new()
	pole.color = Color(0.16, 0.17, 0.20)
	pole.position = Vector2(lx - 3.0, ground_y - 250.0)
	pole.size = Vector2(6.0, 84.0)
	pole.z_index = -3
	add_child(pole)
	var lamp := ColorRect.new()
	lamp.color = Color(0.25, 0.85, 0.45, 0.9)
	lamp.position = Vector2(lx - 8.0, ground_y - 266.0)
	lamp.size = Vector2(16.0, 16.0)
	lamp.z_index = -3
	add_child(lamp)
	_lights.append(lamp)

func _set_lights_red(red: bool) -> void:
	for l in _lights:
		if is_instance_valid(l):
			(l as ColorRect).color = Color(0.95, 0.25, 0.2, 1.0) if red else Color(0.25, 0.85, 0.45, 0.9)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t -= delta
	match _state:
		S.IDLE:
			if _t <= 0.0:
				_state = S.TELEGRAPH
				_t = telegraph
				_set_lights_red(true)
				SfxPlayer.play("enemy_sniper_charge")
		S.TELEGRAPH:
			if _t <= 0.0:
				_state = S.PASS
				_hit_done = false
				_train_x = x_min if _dir > 0 else x_max
				SfxPlayer.play("boss_missile_launch")
		S.PASS:
			_train_x += speed * float(_dir) * delta
			_check_player_hit()
			queue_redraw()
			if (_dir > 0 and _train_x > x_max) or (_dir < 0 and _train_x < x_min):
				_state = S.IDLE
				_t = interval
				_dir = -_dir
				_set_lights_red(false)
				queue_redraw()

func _check_player_hit() -> void:
	if _hit_done:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D):
		return
	if bool(p.get("clear_protect")):
		return   # 세그먼트 전환/클리어 연출 중 · 피해도 넉백도 없음
	var pos: Vector2 = (p as Node2D).global_position
	# 선로 대역 밖(단차 위·공중 점프 정점)이면 세이프.
	if pos.y < ground_y - TRAIN_H:
		return
	# 벽감 안이면 세이프.
	for nx in niches:
		if absf(pos.x - float(nx)) <= niche_half:
			return
	if absf(pos.x - _train_x) > TRAIN_W * 0.5:
		return
	_hit_done = true
	if p.has_method("apply_knockback"):
		p.call("apply_knockback", Vector2(KNOCKBACK_X * float(_dir), KNOCKBACK_Y), 0.28)
	if p.has_method("take_hit"):
		p.call("take_hit", dmg)

func _draw() -> void:
	if _state != S.PASS:
		return
	var top: float = ground_y - TRAIN_H
	var half: float = TRAIN_W * 0.5
	# 속도 잔상 · 차체 뒤로 페이드되는 밴드(진행 반대쪽).
	for i in 3:
		var trail_x: float = _train_x - half * float(_dir) - float(_dir) * (half * 2.0) * (0.35 + 0.35 * float(i))
		var trail_w: float = half * 0.7
		var tx0: float = minf(trail_x, trail_x - float(_dir) * trail_w)
		draw_rect(Rect2(Vector2(tx0, top + 10.0), Vector2(trail_w, TRAIN_H - 22.0)), Color(0.06, 0.065, 0.085, 0.22 - 0.06 * float(i)))
	# 차체 · 거의 검정 저상 화물차 + 밝은 외곽선(어두운 터널 배경과 분리).
	draw_rect(Rect2(Vector2(_train_x - half, top), Vector2(TRAIN_W, TRAIN_H - 6.0)), Color(0.055, 0.06, 0.08, 1.0))
	draw_rect(Rect2(Vector2(_train_x - half, top), Vector2(TRAIN_W, TRAIN_H - 6.0)), Color(0.50, 0.53, 0.62, 0.8), false, 2.0)
	draw_rect(Rect2(Vector2(_train_x - half, top), Vector2(TRAIN_W, 8.0)), Color(0.32, 0.34, 0.40))
	# 창/해치 열 · 따뜻한 불빛 4개.
	for i in 4:
		var wx: float = _train_x - half + 60.0 + float(i) * 120.0
		draw_rect(Rect2(Vector2(wx, top + 34.0), Vector2(42.0, 26.0)), Color(0.95, 0.82, 0.45, 0.85))
	# 헤드라이트 · 진행 방향 앞쪽 원뿔 글로우.
	var nose: float = _train_x + half * float(_dir)
	for i in 3:
		var r: float = 26.0 + 20.0 * float(i)
		draw_circle(Vector2(nose + float(_dir) * 10.0, top + TRAIN_H * 0.45), r, Color(1.0, 0.95, 0.7, 0.10))
	# 하부 대차 그림자.
	draw_rect(Rect2(Vector2(_train_x - half, ground_y - 8.0), Vector2(TRAIN_W, 8.0)), Color(0.05, 0.05, 0.06))
