class_name ChaseHazard
extends Node2D

# 강제 전진 기믹 — 뒤(왼쪽)에서 전진하는 붕괴 벽(킬존). 멈추면 따라잡혀 죽는다.
# 왼쪽의 모든 것을 삼킨 어두운 벽 + 선두 톱니 경계 + 앞쪽 먼지 경고대. 플레이어가 선두 edge보다
# (여유 GRACE 안쪽으로) 뒤처지면 큰 피해(사실상 치명, 방어막이면 1회 소생 후 탈출 기회).
#
# 속도는 플레이어 달리기(240)보다 약간 느려(계속 달리면 앞선다), max_gap으로 너무 뒤처지지 않게 캡해
# 상시 위협을 유지한다. 시간 손실(수직 등반·장애물 봉크)이 나면 벽이 따라붙는 구조.
#
# 사용: MapData 맵의 "chase_hazard" = {start_x, speed, max_gap?}.

const DUST_W: float = 72.0        # 선두 앞 먼지 경고대 폭
const GRACE: float = 26.0         # 선두를 이만큼 넘어 들어가야 치명(가장자리 스침은 안 죽음)
const DMG: int = 20               # 접촉 = 사실상 치명
const V_TOP: float = -420.0
const V_BOT: float = 820.0

var speed: float = 210.0
var max_gap: float = 700.0
var _edge_x: float = -300.0       # 선두(치명) edge의 월드 x
var _dmg_cd: float = 0.0

func setup(start_x: float, spd: float, gap: float = 700.0) -> void:
	_edge_x = start_x
	speed = maxf(spd, 20.0)
	max_gap = maxf(gap, 200.0)
	z_index = 4                    # 플레이어(0) 위 — 삼켜지면 벽이 플레이어를 덮는다
	position = Vector2(_edge_x, 0.0)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_edge_x += speed * delta
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and p is Node2D:
		var px: float = (p as Node2D).global_position.x
		# 너무 뒤처지지 않게 캡 — 상시 위협 유지.
		if px - _edge_x > max_gap:
			_edge_x = px - max_gap
		# 선두 안쪽으로 삼켜짐 → 치명.
		_dmg_cd -= delta
		if px < _edge_x - GRACE and _dmg_cd <= 0.0:
			if p.has_method("take_hit"):
				p.call("take_hit", DMG)
			_dmg_cd = 0.3
	position.x = _edge_x
	queue_redraw()

func _draw() -> void:
	# 삼켜진 어두운 영역(선두 왼쪽 전부)
	draw_rect(Rect2(Vector2(-4200.0, V_TOP), Vector2(4200.0, V_BOT - V_TOP)), Color(0.05, 0.04, 0.05, 0.97))
	# 선두 톱니 경계 — 무너지는 가장자리
	var jag: PackedVector2Array = PackedVector2Array()
	var y: float = V_TOP
	var i: int = 0
	while y < V_BOT:
		var jx: float = -18.0 if (i % 2 == 0) else 5.0
		jag.append(Vector2(jx, y))
		y += 34.0
		i += 1
	draw_polyline(jag, Color(0.34, 0.29, 0.26, 0.9), 3.0, true)
	# 앞쪽 먼지 경고대(반투명) — "곧 삼켜진다"
	draw_rect(Rect2(Vector2(0.0, V_TOP), Vector2(DUST_W, V_BOT - V_TOP)), Color(0.36, 0.30, 0.26, 0.16))
	draw_rect(Rect2(Vector2(DUST_W, V_TOP), Vector2(DUST_W * 0.7, V_BOT - V_TOP)), Color(0.36, 0.30, 0.26, 0.07))
