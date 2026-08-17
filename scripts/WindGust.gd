class_name WindGust
extends Node2D

# 옥상 시그니처 해저드 · 돌풍(map_identity_rework §5 "옥상 = 바람·낙하", 2026-08-17).
# 잠잠(calm) → 예고(telegraph · 먼지 줄기가 흐르기 시작) → 돌풍(gust · 공중에서 옆으로
# 밀림, 지상은 살짝) 사이클. 방향은 매번 교대. 낙하 페널티는 등반 맵의 자연 구조(아래
# 지붕으로 추락 = 재등반)를 그대로 쓴다 · 즉사 없음.
# 공정성: 예고 1.3s 동안 줄기가 눈에 보이게 가속 + 돌풍 중에도 조작 보정 가능(속도
# 오프셋 170 = 점프 하나당 표류 ~100px). 광과민 준수: 연속 이동 줄기, 점멸 없음.
#
# 사용: MapData "wind" = {calm?, telegraph?, gust?, speed?}. Player.wind_x에 매 프레임
# 오프셋을 세팅하고 종료·소멸 시 0으로 되돌린다.

enum S { CALM, TELE, GUST }

var calm_dur: float = 7.0
var tele_dur: float = 1.3
var gust_dur: float = 2.6
var speed: float = 170.0
var world_w: float = 1280.0
var world_h: float = 2500.0

var _state: int = S.CALM
var _t: float = 0.0
var _dir: int = 1
var _streaks: Array = []

func setup(cfg: Dictionary, w: float, h: float) -> void:
	calm_dur = float(cfg.get("calm", calm_dur))
	tele_dur = float(cfg.get("telegraph", tele_dur))
	gust_dur = float(cfg.get("gust", gust_dur))
	speed = float(cfg.get("speed", speed))
	world_w = w
	world_h = h
	z_index = 4
	add_to_group("wind_gust")
	# 첫 돌풍은 이르게 · 기믹을 초반에 한 번 보여준다(열차·수위와 동형).
	_t = calm_dur - 2.4
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.current_stage * 577 + 11
	# 밀도 = 세로 240px당 ~5줄(수직 맵에서 화면 어디에 있어도 줄기가 보이게).
	var n: int = clampi(int(world_h / 48.0), 26, 60)
	for i in n:
		_streaks.append({
			"x": rng.randf_range(-100.0, world_w + 100.0),
			"y": rng.randf_range(-100.0, world_h),
			"len": rng.randf_range(34.0, 80.0),
			"a": rng.randf_range(0.14, 0.28),
		})

func _intensity() -> float:
	match _state:
		S.TELE:
			return 0.35 * minf(1.0, _t / maxf(0.2, tele_dur))
		S.GUST:
			# 돌풍 끝 0.4s 감쇠 · 뚝 끊기지 않게.
			return minf(1.0, (gust_dur - _t) / 0.4) if _t > gust_dur - 0.4 else 1.0
	return 0.0

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	match _state:
		S.CALM:
			if _t >= calm_dur:
				_state = S.TELE
				_t = 0.0
				_dir = -_dir
		S.TELE:
			if _t >= tele_dur:
				_state = S.GUST
				_t = 0.0
		S.GUST:
			if _t >= gust_dur:
				_state = S.CALM
				_t = 0.0
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null:
		p.set("wind_x", speed * float(_dir) * _intensity())
	queue_redraw()

func _exit_tree() -> void:
	# 씬 전환·클리어 시 잔류 바람 차단.
	var tree := get_tree()
	if tree == null:
		return
	var p: Node = tree.get_first_node_in_group("player")
	if p != null:
		p.set("wind_x", 0.0)

func _draw() -> void:
	var k: float = _intensity()
	if k <= 0.01:
		return
	# 먼지 줄기 · 바람 방향으로 흐르는 짧은 선(연속 이동 · 점멸 없음).
	var flow: float = _t * speed * 3.4 * float(_dir)
	for e in _streaks:
		var d: Dictionary = e
		var sx: float = wrapf(float(d["x"]) + flow, -120.0, world_w + 120.0)
		var ln: float = float(d["len"]) * (0.5 + 0.5 * k)
		draw_line(Vector2(sx, float(d["y"])), Vector2(sx - ln * float(_dir), float(d["y"])),
			Color(0.85, 0.90, 0.96, float(d["a"]) * k), 2.0)
