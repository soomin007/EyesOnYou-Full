class_name ChaseHazard
extends Node2D

# 강제 전진 기믹 · 전진하는 붕괴 킬존. 멈추면 따라잡혀 죽는다.
# 축 2종(map_identity_rework §2 방향 붕괴):
#   axis "x"    · 뒤(왼쪽)에서 오른쪽으로 전진하는 벽(수평 질주). 붕괴 갱도.
#   axis "y_up" · 아래에서 위로 차오르는 붕괴(수직 상승 탈출). 붕괴 회랑 승강 샤프트.
# 삼킨 영역 + 선두 톱니 경계 + 전방 먼지 경고대. 선두를 GRACE 넘어 들어가면 큰 피해.
#
# 속도는 플레이어 이동(달리기 240 / 등반 체감 ~100)보다 약간 느리고, max_gap 캡 추격이
# 상시 위협을 유지한다. stop(구조물 끝)에 닿으면 전진 종료 · 붕괴는 구조 안까지만
# (2026-08-16 사용자 지적). 클리어/세그먼트 전환 시 Stage가 halt() 호출.
#
# 사용: MapData "chase_hazard" = {start_x, speed, max_gap?, stop_x?, axis?, catchup?}.
#   (start_x·stop_x는 axis "y_up"에선 y 좌표를 담는다 · 키 이름은 호환 유지.)

const DUST_W: float = 72.0        # 선두 앞 먼지 경고대 폭
const GRACE: float = 26.0         # 선두를 이만큼 넘어 들어가야 치명(가장자리 스침은 안 죽음)
const DMG: int = 20               # 접촉 = 사실상 치명
const V_TOP: float = -420.0       # 수평 축 · 벽의 세로 범위
const V_BOT: float = 820.0
const H_LEFT: float = -400.0      # 수직 축 · 붕괴의 가로 범위(VERTICAL 폭 1280 + 여유)
const H_RIGHT: float = 1700.0

var axis: String = "x"
var speed: float = 210.0
var max_gap: float = 700.0
# 캡 추격 속도 상한 — 이전엔 max_gap 초과 시 벽을 플레이어 뒤로 *즉시 스냅*해서, 대시 순간 벽이
# 플레이어 속도를 그대로 미러링하는 게 들켰다(사용자 체감 2026-08-10 "대시 쓰니 같이 빨리 옴").
# 상한 속도로만 따라붙는다. 수평 기본 340(달리기 240 대비), 수직은 cfg로 낮춰 잡는다(등반은 느리므로).
var catchup: float = 340.0
# 구조물 끝 좌표 · 선두가 여기 닿으면 전진 종료: 붕괴는 구조물 안까지만(사용자 2026-08-16).
# is_finite일 때만 활성(수평=x 상한, 수직=y 하한).
var stop_edge: float = INF
var _stop_active: bool = false
# 클리어/세그먼트 전환 시 Stage가 halt() 호출: 전진·피해 전부 정지(엔딩 연출 중 사망 차단).
var _halted: bool = false
var _edge: float = -300.0         # 선두(치명) edge의 월드 좌표(axis에 따라 x 또는 y)
var _dmg_cd: float = 0.0

func setup(start: float, spd: float, gap: float = 700.0, stop: float = INF, ax: String = "x", catchup_spd: float = 340.0) -> void:
	axis = ax
	_edge = start
	speed = maxf(spd, 20.0)
	max_gap = maxf(gap, 200.0)
	catchup = maxf(catchup_spd, speed)
	stop_edge = stop
	_stop_active = is_finite(stop)
	z_index = 4                    # 플레이어(0) 위 · 삼켜지면 붕괴가 플레이어를 덮는다
	position = Vector2(_edge, 0.0) if axis == "x" else Vector2(0.0, _edge)

# 전진·피해 완전 정지(클리어 시퀀스/세그먼트 전환 진입 시 Stage가 호출). 시각은 그대로 남는다.
func halt() -> void:
	_halted = true

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if _halted:
		return
	var p: Node = get_tree().get_first_node_in_group("player")
	if axis == "x":
		_edge += speed * delta
		if p != null and p is Node2D:
			var px: float = (p as Node2D).global_position.x
			if px - _edge > max_gap:
				_edge = minf(_edge + (catchup - speed) * delta, px - max_gap)
			if _stop_active:
				_edge = minf(_edge, stop_edge)
			_dmg_cd -= delta
			if px < _edge - GRACE and _dmg_cd <= 0.0:
				_hit(p)
		if _stop_active:
			_edge = minf(_edge, stop_edge)
		position.x = _edge
	else:
		# y_up · edge가 위로(y 감소) 전진. 선두 아래(py > edge)가 삼켜진 영역.
		_edge -= speed * delta
		if p != null and p is Node2D:
			var py: float = (p as Node2D).global_position.y
			if _edge - py > max_gap:
				_edge = maxf(_edge - (catchup - speed) * delta, py + max_gap)
			if _stop_active:
				_edge = maxf(_edge, stop_edge)
			_dmg_cd -= delta
			if py > _edge + GRACE and _dmg_cd <= 0.0:
				_hit(p)
		if _stop_active:
			_edge = maxf(_edge, stop_edge)
		position.y = _edge
	queue_redraw()

func _hit(p: Node) -> void:
	if p.has_method("take_hit"):
		p.call("take_hit", DMG)
	_dmg_cd = 0.3

func _draw() -> void:
	if axis == "x":
		# 삼켜진 어두운 영역(선두 왼쪽 전부)
		draw_rect(Rect2(Vector2(-4200.0, V_TOP), Vector2(4200.0, V_BOT - V_TOP)), Color(0.05, 0.04, 0.05, 0.97))
		# 선두 톱니 경계 · 무너지는 가장자리
		var jag: PackedVector2Array = PackedVector2Array()
		var y: float = V_TOP
		var i: int = 0
		while y < V_BOT:
			var jx: float = -18.0 if (i % 2 == 0) else 5.0
			jag.append(Vector2(jx, y))
			y += 34.0
			i += 1
		draw_polyline(jag, Color(0.34, 0.29, 0.26, 0.9), 3.0, true)
		# 앞쪽 먼지 경고대(반투명) · "곧 삼켜진다"
		draw_rect(Rect2(Vector2(0.0, V_TOP), Vector2(DUST_W, V_BOT - V_TOP)), Color(0.36, 0.30, 0.26, 0.16))
		draw_rect(Rect2(Vector2(DUST_W, V_TOP), Vector2(DUST_W * 0.7, V_BOT - V_TOP)), Color(0.36, 0.30, 0.26, 0.07))
	else:
		# 삼켜진 어두운 영역(선두 아래 전부) · 소각 여파라 상단 경계에 잔불 기운 한 줄.
		draw_rect(Rect2(Vector2(H_LEFT, 0.0), Vector2(H_RIGHT - H_LEFT, 4600.0)), Color(0.05, 0.04, 0.05, 0.97))
		draw_rect(Rect2(Vector2(H_LEFT, 0.0), Vector2(H_RIGHT - H_LEFT, 10.0)), Color(0.55, 0.24, 0.12, 0.5))
		var jag_v: PackedVector2Array = PackedVector2Array()
		var x: float = H_LEFT
		var j: int = 0
		while x < H_RIGHT:
			var jy: float = -18.0 if (j % 2 == 0) else 5.0
			jag_v.append(Vector2(x, jy))
			x += 34.0
			j += 1
		draw_polyline(jag_v, Color(0.34, 0.29, 0.26, 0.9), 3.0, true)
		# 위쪽 먼지 경고대 · "아래가 무너지며 차오른다"
		draw_rect(Rect2(Vector2(H_LEFT, -DUST_W), Vector2(H_RIGHT - H_LEFT, DUST_W)), Color(0.36, 0.30, 0.26, 0.16))
		draw_rect(Rect2(Vector2(H_LEFT, -DUST_W - DUST_W * 0.7), Vector2(H_RIGHT - H_LEFT, DUST_W * 0.7)), Color(0.36, 0.30, 0.26, 0.07))
