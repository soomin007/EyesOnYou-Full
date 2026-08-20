class_name TrainHazard
extends Node2D

# 폐쇄 지하철 시그니처 해저드 · 무인 화물 열차(map_identity_rework §4, 2026-08-16).
# 서사: 폐역이지만 선로는 살아 있다 · ARCTURUS가 발주한 무인 운행(MAINTENANCE ONLY 표지와 정합).
# 주기: 대기(interval) → 텔레그래프(신호등 적색 전환 + 경고음, telegraph초) → 고속 통과.
# 선로 대역(바닥 위 TRAIN_H)에 있으면 대뎀 + 진행 방향 넉백. 즉사 아님 · 반복 조우 해저드
# (사용자 확정 2026-08-16: 즉사 대신 대뎀+넉백). 대피 = 벽감(niche) 안 / 단차 위 / 타이밍 점프.
# 광과민: 점멸 없음 · 신호등은 색 전환 후 유지.
#
# 사용: MapData "train_hazard" = {interval?, telegraph?, speed?, dmg?, lights?: [x...], triggers?: [x...]}.
# 벽감은 기존 "cover_niches"/"niche_half"를 그대로 읽는다(시각 = Stage._build_cover_niches).
#
# 조우 횟수 보장(2026-08-17): 주기식은 실주기 = interval + telegraph + 통과(~2.6s)라 빠른 주파
# (길이÷240)에선 조우가 계산보다 적게 나온다(known_issues "체류 시간" 규칙 · "4~5회라더니 2회").
# triggers = 플레이어가 그 x를 지나는 순간 다음 열차 예고를 즉시 시작하는 위치 트리거 ·
# 플레이 속도와 무관하게 트리거 수만큼의 조우를 보장한다. interval은 정지 시 배경 리듬용 폴백.

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
var triggers: Array = []         # 조우 보장 위치 트리거 x들(오름차순) · 지나면 즉시 예고 시작

# 통과 후 최소 간격 — 위치 트리거가 연달아 걸려도 열차가 "거의 계속 지나다니는" 느낌이
# 안 나게 숨을 강제한다(사용자 2026-08-18). 조우 보장(트리거 수)은 그대로 · 리듬만 벌린다.
const MIN_GAP: float = 6.5

var _trigger_idx: int = 0
var _state: int = S.IDLE
var _t: float = 0.0
var _gap_t: float = 0.0          # 직전 통과 후 남은 최소 간격
var _dir: int = 1                # 통과 방향 · 매회 교대
var _train_x: float = 0.0
var _hit_done: bool = false      # 통과당 플레이어 피해 1회
var _hit_enemies: Dictionary = {}  # 통과당 개체별 피해 1회(instance_id)
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
	triggers = cfg.get("triggers", [])
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
	_gap_t = maxf(_gap_t - delta, 0.0)
	match _state:
		S.IDLE:
			# 위치 트리거 · 통과 중 지나쳤어도 IDLE 복귀 시 조건이 남아 있어 이어서 발동(누락 없음).
			if _trigger_idx < triggers.size():
				var p: Node = get_tree().get_first_node_in_group("player")
				if p is Node2D and (p as Node2D).global_position.x >= float(triggers[_trigger_idx]):
					_trigger_idx += 1
					_t = 0.0
			# 최소 간격(_gap_t)이 남았으면 예고를 미룬다 — 트리거 연쇄여도 숨은 보장.
			if _t <= 0.0 and _gap_t <= 0.0:
				_state = S.TELEGRAPH
				_t = telegraph
				_set_lights_red(true)
				SfxPlayer.play("enemy_sniper_charge")
		S.TELEGRAPH:
			if _t <= 0.0:
				_state = S.PASS
				_hit_done = false
				_hit_enemies.clear()
				_train_x = x_min if _dir > 0 else x_max
				SfxPlayer.play("boss_missile_launch")
		S.PASS:
			_train_x += speed * float(_dir) * delta
			_check_player_hit()
			_check_enemy_hits()
			queue_redraw()
			if (_dir > 0 and _train_x > x_max) or (_dir < 0 and _train_x < x_min):
				_state = S.IDLE
				_t = interval
				_gap_t = MIN_GAP
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

# 열차는 누구 편도 아니다(사용자 2026-08-18 "왜 적은 안 치이지") — 선로 대역의 적도 대뎀.
# 환경 내성 캐논(물·감전 = 시설 유닛 설계 내성)과 구분: 열차는 물리 충돌이라 예외 없음.
# 전술 부가: 경보 끌고 선로에 세우면 열차가 대신 정리한다.
func _check_enemy_hits() -> void:
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e) or not (e is Node2D):
			continue
		var en: Node2D = e as Node2D
		# 일반 Enemy만 — "enemy" 그룹의 보스/더미는 속성이 없어 bool(null) 크래시(2026-08-20
		# FallingDebris에서 실측된 동형 잠복 버그). truthiness로 전환 + enemy_type 게이트.
		if en.get("enemy_type") == null:
			continue
		if en.get("dead") or en.get("harmless"):
			continue
		if _hit_enemies.has(en.get_instance_id()):
			continue
		var pos: Vector2 = en.global_position
		if pos.y < ground_y - TRAIN_H:
			continue   # 단차·공중은 세이프(플레이어와 동일 규칙)
		var in_niche: bool = false
		for nx in niches:
			if absf(pos.x - float(nx)) <= niche_half:
				in_niche = true
				break
		if in_niche:
			continue
		if absf(pos.x - _train_x) > TRAIN_W * 0.5:
			continue
		_hit_enemies[en.get_instance_id()] = true
		if en.has_method("take_damage"):
			# 환경 처치 표식 — 이 타격으로 죽으면 XP·점수 없음. 살아남으면 즉시 해제해서
			# 나중에 플레이어가 마무리한 몫까지 삼키지 않게 한다.
			en.set("env_killed", true)
			en.call("take_damage", dmg, _dir)
			if is_instance_valid(en) and not en.get("dead"):
				en.set("env_killed", false)

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
