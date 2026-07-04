class_name SweepBeam
extends Node2D

# 감시 스위프(리듬) 기믹 — 수직 스캔 빔이 통로를 왼→오로 주기적으로 훑는다. 빔이 지날 때 차폐
# 사각(cover niche) 안에 있으면 스캔을 피하고, 노출되면 피해. rest(빔 없음) → telegraph(왼쪽 경고)
# → sweep(훑기) → rest 를 반복 = 예측 가능한 리듬.
#
# 손맛: 빔이 오면 가까운 니치로 대피(멈춤), 빔이 지나가면 다음 니치로 달린다(이동). stop-and-go.
# ChaseHazard(멈추면 죽음, 계속 달려)와 정반대의 절제 리듬.
#
# 세이프 판정은 x밴드만 본다(높이 무관) — 니치 x구간 안이면 스캔 사각. 니치 사이 갭이 위험 구간.
# 피해는 Player.take_hit이 invuln(연타 묶기)·hit 카운트를 자체 처리하므로 호출만 한다(+짧은 자체 cd).
#
# 사용: MapData 맵 "sweep_beam" = {x_start, x_end, y_top, y_bot, speed, rest, telegraph, beam_half}
#       + "cover_niches" = [x, ...](세이프 밴드 중심), "niche_half"(선택).

const DMG: int = 2                                 # 노출 피해(즉사 아님 — 리듬 학습 여지)
const COL_BEAM: Color = Color(0.98, 0.32, 0.26)    # 위험 적색 스캔 광선
const COL_WARN: Color = Color(0.98, 0.58, 0.25)    # telegraph 경고 주황

var x_start: float = 0.0
var x_end: float = 4000.0
var y_top: float = -120.0
var y_bot: float = 640.0
var speed: float = 380.0
var rest_dur: float = 1.8
var tele_dur: float = 0.7
var beam_half: float = 24.0
var safe_bands: Array = []          # 니치 중심 x들(세이프 밴드)
var safe_half: float = 90.0

var _phase: String = "rest"         # rest | telegraph | sweep
var _t: float = 0.0
var _beam_x: float = 0.0
var _dmg_cd: float = 0.0
var _pulse: float = 0.0

func setup(cfg: Dictionary, niches: Array, s_half: float) -> void:
	x_start = float(cfg.get("x_start", 0.0))
	x_end = float(cfg.get("x_end", 4000.0))
	y_top = float(cfg.get("y_top", -120.0))
	y_bot = float(cfg.get("y_bot", 640.0))
	speed = maxf(float(cfg.get("speed", 380.0)), 40.0)
	rest_dur = maxf(float(cfg.get("rest", 1.8)), 0.2)
	tele_dur = maxf(float(cfg.get("telegraph", 0.7)), 0.1)
	beam_half = maxf(float(cfg.get("beam_half", 24.0)), 6.0)
	safe_bands = niches.duplicate()
	safe_half = maxf(s_half, 20.0)
	_beam_x = x_start
	z_index = 3                     # 플레이어(0) 위 — 위협 가시(반투명 글로우 + 얇은 코어)
	position = Vector2.ZERO         # 로컬=월드(빔 x는 _draw에서 직접 그림, DefenseCore 방식)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_pulse += delta
	_dmg_cd -= delta
	_t += delta
	match _phase:
		"rest":
			if _t >= rest_dur:
				_t = 0.0
				_phase = "telegraph"
				_beam_x = x_start
		"telegraph":
			if _t >= tele_dur:
				_t = 0.0
				_phase = "sweep"
				_beam_x = x_start
		"sweep":
			_beam_x += speed * delta
			if _beam_x >= x_end:
				_beam_x = x_end
				_t = 0.0
				_phase = "rest"
			else:
				_check_hit()
	queue_redraw()

func _check_hit() -> void:
	if _dmg_cd > 0.0:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D):
		return
	var px: float = (p as Node2D).global_position.x
	if absf(px - _beam_x) > beam_half:
		return                      # 빔이 아직 플레이어를 안 덮음
	# 차폐 사각(니치) 안이면 스캔을 피한다 — x밴드만(높이 무관).
	for band in safe_bands:
		if absf(px - float(band)) <= safe_half:
			return
	if p.has_method("take_hit"):
		p.call("take_hit", DMG)
	_dmg_cd = 0.35

# ─── 렌더 ──────────────────────────────────────────────────────
func _draw() -> void:
	if _phase == "telegraph":
		_draw_telegraph()
	elif _phase == "sweep":
		_draw_beam()

func _draw_telegraph() -> void:
	# 왼쪽 가장자리 "스캔 시작" 경고 — 세로 경고 밴드가 빠르게 맥동.
	var a: float = lerp(0.15, 0.55, 0.5 + 0.5 * sin(_pulse * 18.0))
	var h: float = y_bot - y_top
	draw_rect(Rect2(Vector2(x_start - 6.0, y_top), Vector2(44.0, h)), Color(COL_WARN.r, COL_WARN.g, COL_WARN.b, a * 0.45))
	draw_line(Vector2(x_start, y_top), Vector2(x_start, y_bot), Color(COL_WARN.r, COL_WARN.g, COL_WARN.b, a), 3.0)

func _draw_beam() -> void:
	var h: float = y_bot - y_top
	var glow: float = 0.6 + 0.4 * sin(_pulse * 30.0)
	# 넓은 반투명 글로우 밴드
	draw_rect(Rect2(Vector2(_beam_x - beam_half, y_top), Vector2(beam_half * 2.0, h)), Color(COL_BEAM.r, COL_BEAM.g, COL_BEAM.b, 0.16))
	# 코어 광선(밝은 심 + 채색 외곽)
	draw_line(Vector2(_beam_x, y_top), Vector2(_beam_x, y_bot), Color(COL_BEAM.r, COL_BEAM.g, COL_BEAM.b, 0.85), 6.0)
	draw_line(Vector2(_beam_x, y_top), Vector2(_beam_x, y_bot), Color(1.0, 0.86, 0.8, glow), 3.0)
	# 진행 방향 화살표(빔 상단) — "오른쪽으로 훑는 중"
	var ay: float = y_top + 22.0
	var tri := PackedVector2Array([
		Vector2(_beam_x + 6.0, ay), Vector2(_beam_x + 20.0, ay + 8.0), Vector2(_beam_x + 6.0, ay + 16.0)])
	draw_colored_polygon(tri, Color(COL_BEAM.r, COL_BEAM.g, COL_BEAM.b, 0.7))
