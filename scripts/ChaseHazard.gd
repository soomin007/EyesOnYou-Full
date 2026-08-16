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
# 선두가 이 x에 도달하면 전진 종료: 붕괴는 구조물 안까지만(건물 밖 야외까지 벽이 따라오면
# 서사가 깨진다는 지적, 사용자 2026-08-16). INF = 제한 없음(전 구간 실내 맵).
var stop_x: float = INF
# 클리어 시퀀스 진입 시 Stage가 halt() 호출: 전진·피해 전부 정지. 엔딩 연출 중
# 벽이 따라잡아 사망 판정이 뜨는 문제 차단(사용자 2026-08-16).
var _halted: bool = false
# 캡 추격 속도 상한 — 이전엔 max_gap 초과 시 벽을 플레이어 뒤로 *즉시 스냅*해서, 대시 순간 벽이
# 플레이어 속도를 그대로 미러링하는 게 들켰다(사용자 체감 2026-08-10 "대시 쓰니 같이 빨리 옴").
# 이제 상한 속도로만 따라붙는다: 대시(720)로는 잠깐 거리를 벌 수 있지만 달리기(240)보다 빨라
# 몇 초 안에 자연스럽게 회수된다. 체감상 "벽이 꾸준히 밀고 온다"로만 읽히게.
const CATCHUP_SPEED: float = 340.0
var _edge_x: float = -300.0       # 선두(치명) edge의 월드 x
var _dmg_cd: float = 0.0

func setup(start_x: float, spd: float, gap: float = 700.0, stop: float = INF) -> void:
	_edge_x = start_x
	speed = maxf(spd, 20.0)
	max_gap = maxf(gap, 200.0)
	stop_x = stop
	z_index = 4                    # 플레이어(0) 위 — 삼켜지면 벽이 플레이어를 덮는다
	position = Vector2(_edge_x, 0.0)

# 전진·피해 완전 정지(클리어 시퀀스 진입 시 Stage가 호출). 시각은 그대로 남는다.
func halt() -> void:
	_halted = true

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	if _halted:
		return
	_edge_x += speed * delta
	var p: Node = get_tree().get_first_node_in_group("player")
	if p != null and p is Node2D:
		var px: float = (p as Node2D).global_position.x
		# 너무 뒤처지지 않게 캡 — 상시 위협 유지. 스냅 대신 상한 속도 추격(위 CATCHUP_SPEED 주석).
		if px - _edge_x > max_gap:
			var target_x: float = px - max_gap
			_edge_x = minf(_edge_x + (CATCHUP_SPEED - speed) * delta, target_x)
		# 구조물 끝 도달 = 전진 종료(캡 추격 포함). 피해 판정 전에 클램프.
		_edge_x = minf(_edge_x, stop_x)
		# 선두 안쪽으로 삼켜짐 → 치명. 정지한 벽에 스스로 들어가는 것도 여전히 치명.
		_dmg_cd -= delta
		if px < _edge_x - GRACE and _dmg_cd <= 0.0:
			if p.has_method("take_hit"):
				p.call("take_hit", DMG)
			_dmg_cd = 0.3
	_edge_x = minf(_edge_x, stop_x)
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
