class_name SweepBeam
extends Node2D

# 감시 스위프(리듬) 기믹 — 수직 스캔 빔이 통로를 왼→오로 주기적으로 훑는다. 빔이 지날 때 차폐
# 사각(cover niche) 안에 있으면 스캔을 피하고, 노출되면 피해. rest(빔 없음) → telegraph(왼쪽 경고)
# → sweep(훑기) → rest 를 반복 = 예측 가능한 리듬.
#
# 손맛: 빔이 오면 가까운 니치로 대피(멈춤), 빔이 지나가면 다음 니치로 달린다(이동). stop-and-go.
# ChaseHazard(멈추면 죽음, 계속 달려)와 정반대의 절제 리듬.
#
# 세이프 판정: 니치 x밴드 안이면 스캔 사각. 추가로 피해는 빔의 y구간 안에서만 — 빔이 그려지는
# 범위 밖(레일 위·구덩이 아래)까지 맞는 유령 판정 금지(화면=판정 일치, 2026-08-22).
# 피해는 Player.take_hit이 invuln(연타 묶기)·hit 카운트를 자체 처리하므로 호출만 한다(+짧은 자체 cd).
#
# 실물 출처(2026-08-22 사용자 "스캔 빔은 뭔데"): 천장 레일 + 이동식 스캐너 헤드를 함께 그린다 —
# 빔은 레일에 매달린 수색등이 쏘는 광선이고, 레일 길이가 곧 수색 구간(어디까지 오는지 보인다).
#
# 사용: MapData 맵 "sweep_beam" = {x_start, x_end, y_top, y_bot, speed, rest, telegraph, beam_half,
#       arm_x?(이 x를 지나면 점등·기동 — 서사 비트용. 없으면 즉시 기동)}
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
var _armed: bool = true             # false = 아직 점등 전(arm_x 대기) — 레일만 어둡게 보인다
var arm_x: float = 0.0

func setup(cfg: Dictionary, niches: Array, s_half: float) -> void:
	x_start = float(cfg.get("x_start", 0.0))
	x_end = float(cfg.get("x_end", 4000.0))
	y_top = float(cfg.get("y_top", -120.0))
	y_bot = float(cfg.get("y_bot", 640.0))
	speed = maxf(float(cfg.get("speed", 380.0)), 40.0)
	rest_dur = maxf(float(cfg.get("rest", 1.8)), 0.2)
	tele_dur = maxf(float(cfg.get("telegraph", 0.7)), 0.1)
	beam_half = maxf(float(cfg.get("beam_half", 24.0)), 6.0)
	_armed = not cfg.has("arm_x")
	arm_x = float(cfg.get("arm_x", 0.0))
	safe_bands = niches.duplicate()
	safe_half = maxf(s_half, 20.0)
	_beam_x = x_start
	z_index = 3                     # 플레이어(0) 위 — 위협 가시(반투명 글로우 + 얇은 코어)
	position = Vector2.ZERO         # 로컬=월드(빔 x는 _draw에서 직접 그림, DefenseCore 방식)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_pulse += delta
	if not _armed:
		# 점등 대기 — 플레이어가 arm_x를 지나면 수색등 기동(은닉 "밀고" 비트가 화면에서 시작되는 순간).
		var pw: Node = get_tree().get_first_node_in_group("player")
		if pw is Node2D and (pw as Node2D).global_position.x >= arm_x:
			_armed = true
			_phase = "telegraph"
			_t = 0.0
			_beam_x = x_start
			SfxPlayer.play_at("enemy_sniper_charge", Vector2(x_start, (y_top + y_bot) * 0.5), -6.0)
		queue_redraw()
		return
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
	# 빔이 그려지는 y구간 밖이면 안 맞는다 — 화면과 판정 일치(레일 위·범위 밖 유령 판정 금지).
	var py: float = (p as Node2D).global_position.y
	if py < y_top - 24.0 or py > y_bot + 24.0:
		return
	# 차폐 사각(니치) 안이면 스캔을 피한다 — x밴드만(높이 무관).
	for band in safe_bands:
		if absf(px - float(band)) <= safe_half:
			return
	if p.has_method("take_hit"):
		p.call("take_hit", DMG)
	_dmg_cd = 0.35

# ─── 렌더 ──────────────────────────────────────────────────────
func _draw() -> void:
	_draw_rail()
	if not _armed:
		return
	if _phase == "telegraph":
		_draw_telegraph()
	elif _phase == "sweep":
		_draw_beam()

# 천장 레일 + 스캐너 헤드 — 빔의 실물 출처. 레일 길이 = 수색 구간(광선이 어디서 시작해
# 어디서 멈추는지 화면으로 보인다). 미기동(점등 전)엔 레일과 꺼진 렌즈만 어둡게.
func _draw_rail() -> void:
	var a: float = 0.85 if _armed else 0.4
	draw_line(Vector2(x_start, y_top), Vector2(x_end, y_top), Color(0.44, 0.49, 0.56, a), 4.0)
	draw_line(Vector2(x_start, y_top - 3.0), Vector2(x_end, y_top - 3.0), Color(0.24, 0.27, 0.32, a), 2.0)
	# 양끝 스토퍼 — 수색 구간이 여기서 끝난다는 물리적 신호.
	for ex in [x_start, x_end]:
		draw_rect(Rect2(Vector2(float(ex) - 4.0, y_top - 8.0), Vector2(8.0, 22.0)), Color(0.50, 0.55, 0.62, a))
	# 고정 행어(레일을 천장에 거는 브래킷) — 시설물 질감.
	var hx: float = x_start
	while hx <= x_end + 1.0:
		draw_rect(Rect2(Vector2(hx - 3.0, y_top - 10.0), Vector2(6.0, 10.0)), Color(0.38, 0.42, 0.48, a))
		hx += 560.0
	# 스캐너 헤드 — sweep 중엔 빔을 따라 이동, 그 외엔 시작점에 대기.
	var head_x: float = _beam_x if _phase == "sweep" else x_start
	draw_rect(Rect2(Vector2(head_x - 14.0, y_top), Vector2(28.0, 16.0)), Color(0.20, 0.23, 0.27))
	draw_rect(Rect2(Vector2(head_x - 14.0, y_top), Vector2(28.0, 4.0)), Color(0.36, 0.40, 0.46))
	var lens: Color
	if not _armed:
		lens = Color(0.28, 0.22, 0.22)                    # 꺼진 렌즈
	elif _phase == "sweep":
		lens = COL_BEAM
	elif _phase == "telegraph":
		lens = COL_WARN
	else:
		lens = Color(0.55, 0.30, 0.28)                    # 대기 잔광
	draw_circle(Vector2(head_x, y_top + 18.0), 5.0, lens)

func _draw_telegraph() -> void:
	# 왼쪽 가장자리 "스캔 시작" 경고 — 세로 경고 밴드가 빠르게 맥동. 광선은 헤드 렌즈(y_top+18)에서 시작.
	var a: float = lerp(0.15, 0.55, 0.5 + 0.5 * sin(_pulse * 18.0))
	var top: float = y_top + 18.0
	draw_rect(Rect2(Vector2(x_start - 6.0, top), Vector2(44.0, y_bot - top)), Color(COL_WARN.r, COL_WARN.g, COL_WARN.b, a * 0.45))
	draw_line(Vector2(x_start, top), Vector2(x_start, y_bot), Color(COL_WARN.r, COL_WARN.g, COL_WARN.b, a), 3.0)

func _draw_beam() -> void:
	var top: float = y_top + 18.0   # 헤드 렌즈에서 광선이 나온다(실물 출처 일치)
	var glow: float = 0.6 + 0.4 * sin(_pulse * 30.0)
	# 넓은 반투명 글로우 밴드
	draw_rect(Rect2(Vector2(_beam_x - beam_half, top), Vector2(beam_half * 2.0, y_bot - top)), Color(COL_BEAM.r, COL_BEAM.g, COL_BEAM.b, 0.16))
	# 코어 광선(밝은 심 + 채색 외곽)
	draw_line(Vector2(_beam_x, top), Vector2(_beam_x, y_bot), Color(COL_BEAM.r, COL_BEAM.g, COL_BEAM.b, 0.85), 6.0)
	draw_line(Vector2(_beam_x, top), Vector2(_beam_x, y_bot), Color(1.0, 0.86, 0.8, glow), 3.0)
	# 진행 방향 화살표(빔 상단) — "오른쪽으로 훑는 중"
	var ay: float = top + 22.0
	var tri := PackedVector2Array([
		Vector2(_beam_x + 6.0, ay), Vector2(_beam_x + 20.0, ay + 8.0), Vector2(_beam_x + 6.0, ay + 16.0)])
	draw_colored_polygon(tri, Color(COL_BEAM.r, COL_BEAM.g, COL_BEAM.b, 0.7))
