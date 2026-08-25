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
# 캡 추격 속도 상한 · 이전엔 max_gap 초과 시 벽을 플레이어 뒤로 *즉시 스냅*해서, 대시 순간 벽이
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
# y_up 시각 · 낙하 잔해(시각 전용, 피해 없음) · "위에서 떨어져 아래에 쌓인다"를 만든다
# (2026-08-18 사용자 "가시가 올라오는 이상한 느낌" · 톱니 경계 폐지의 짝).
var _debris: Array = []           # {x, y, vy, w, h}
var _debris_t: float = 0.0
var _puffs: Array = []            # {x, t} · 착탄 분진
# y_up 맥동 · 붕괴는 일정한 속도로 올라오지 않는다. 위층이 버티다 한 번에 내려앉는다
# (사용자 2026-08-19: "등속으로 쭉 올라오니 무너진 게 차오르는 느낌이 전혀 안 난다").
# 버팀(거의 정지) → 붕락(굉음·흔들림과 함께 훅) 반복 · 한 주기 평균 속도는 speed 그대로라
# 밸런스(등반 여유·max_gap)는 건드리지 않고 체감만 바꾼다.
const SURGE_DWELL: float = 1.5    # 버티는 구간(초)
const SURGE_RISE: float = 0.75    # 내려앉는 구간(초)
const SURGE_DWELL_MUL: float = 0.3
var _surge_t: float = SURGE_DWELL
var _surging: bool = false

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
		_tick_debris_x(delta)
	else:
		# y_up · edge가 위로(y 감소) 전진. 선두 아래(py > edge)가 삼켜진 영역.
		_edge -= speed * _surge_factor(delta) * delta
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
		_tick_debris(delta)
	queue_redraw()

# 맥동 배수 · 버팀 구간과 붕락 구간을 오가며, 한 주기 평균이 1.0이 되게 붕락 배수를 역산한다.
func _surge_factor(delta: float) -> float:
	_surge_t -= delta
	if _surge_t <= 0.0:
		_surging = not _surging
		_surge_t = SURGE_RISE if _surging else SURGE_DWELL
		if _surging:
			_on_surge_start()
	if not _surging:
		return SURGE_DWELL_MUL
	return (SURGE_DWELL + SURGE_RISE - SURGE_DWELL * SURGE_DWELL_MUL) / SURGE_RISE

# 붕락 시작 · 굉음 + 화면 흔들림 + 잔해 한 무더기. "위에서 무너져 내려 쌓였다"는 인과를
# 소리와 진동으로 먼저 알리고, 그 결과로 표면이 올라온다.
func _on_surge_start() -> void:
	# 폭탄 소스 재활용이지만 낮고 느리게(pitch 0.68) · 플레이어 폭탄과 소리로 구분
	# (2026-08-21 사용자 "낙석 소리가 내 폭탄 소리랑 똑같아 위화감").
	SfxPlayer.play("bomb_explode", -9.0, 0.68)
	var st: Node = get_tree().get_first_node_in_group("stage")
	if st != null and st.has_method("_camera_shake"):
		st.call("_camera_shake", 5.0, 0.3)
	for i in 5:
		_spawn_debris()

func _spawn_debris() -> void:
	_debris.append({
		"x": randf_range(80.0, 1200.0),
		"y": _edge - randf_range(560.0, 860.0),
		"vy": randf_range(260.0, 420.0),
		"w": randf_range(10.0, 30.0),
		"h": randf_range(8.0, 22.0),
	})

# ── x축(수평 · 붕괴 갱도) 시각(2026-08-21 사용자 "가시 벽이랑 '붕괴 갱도'가 무슨 상관") ──
# 톱니 경계가 "쫓아오는 가시 벽"으로 읽혔다 → y_up(붕괴 회랑)에서 검증된 문법 이식:
# 잔해 더미 실루엣 + 천장 낙하 잔해 + 주기 굉음·흔들림. 속도·판정은 불변(시각 전용).
var _rumble_t: float = 1.4

func _tick_debris_x(delta: float) -> void:
	_rumble_t -= delta
	if _rumble_t <= 0.0:
		_rumble_t = randf_range(1.8, 3.0)
		SfxPlayer.play("bomb_explode", -12.0, 0.66)
		var st: Node = get_tree().get_first_node_in_group("stage")
		if st != null and st.has_method("_camera_shake"):
			st.call("_camera_shake", 3.5, 0.22)
		for i in 3:
			_spawn_debris_x()
	_debris_t -= delta
	if _debris_t <= 0.0:
		_debris_t = randf_range(0.35, 0.8)
		_spawn_debris_x()
	var keep: Array = []
	for d0 in _debris:
		var d: Dictionary = d0
		d["vy"] = float(d["vy"]) + 760.0 * delta
		d["y"] = float(d["y"]) + float(d["vy"]) * delta
		if float(d["y"]) >= float(d.get("gy", 610.0)):
			_puffs.append({"x": float(d["x"]), "t": 0.0, "y": float(d.get("gy", 610.0))})
		else:
			keep.append(d)
	_debris = keep
	var keep_p: Array = []
	for q0 in _puffs:
		var q: Dictionary = q0
		q["t"] = float(q["t"]) + delta
		if float(q["t"]) < 0.5:
			keep_p.append(q)
	_puffs = keep_p

func _spawn_debris_x() -> void:
	# 선두 언저리(-30~+190)의 천장에서 떨어져 바닥에 박힌다 · "무너지며 전진"의 인과.
	_debris.append({
		"x": _edge + randf_range(-30.0, 190.0),
		"y": randf_range(-380.0, -160.0),
		"vy": randf_range(180.0, 340.0),
		"w": randf_range(8.0, 26.0),
		"h": randf_range(7.0, 18.0),
		"gy": randf_range(580.0, 625.0),
	})

# 낙하 잔해 갱신(y_up 전용 · 시각만, 판정 없음). 더미 표면(edge)에 닿으면 분진 퍼프.
func _tick_debris(delta: float) -> void:
	_debris_t -= delta
	if _debris_t <= 0.0:
		_debris_t = randf_range(0.45, 1.0)
		_spawn_debris()
	var keep: Array = []
	for d0 in _debris:
		var d: Dictionary = d0
		d["vy"] = float(d["vy"]) + 760.0 * delta
		d["y"] = float(d["y"]) + float(d["vy"]) * delta
		if float(d["y"]) >= _edge - 4.0:
			_puffs.append({"x": float(d["x"]), "t": 0.0})
			if randf() < 0.3:
				SfxPlayer.play_at("bullet_impact_wall", Vector2(float(d["x"]), _edge))
		else:
			keep.append(d)
	_debris = keep
	var keep_p: Array = []
	for q0 in _puffs:
		var q: Dictionary = q0
		q["t"] = float(q["t"]) + delta
		if float(q["t"]) < 0.5:
			keep_p.append(q)
	_puffs = keep_p

func _hit(p: Node) -> void:
	if p.has_method("take_hit"):
		p.call("take_hit", DMG)
	_dmg_cd = 0.3

func _draw() -> void:
	if axis == "x":
		# 삼켜진 어두운 영역(선두 왼쪽 전부)
		draw_rect(Rect2(Vector2(-4200.0, V_TOP), Vector2(4200.0, V_BOT - V_TOP)), Color(0.05, 0.04, 0.05, 0.97))
		# 선두 = 무너져 쌓인 잔해 더미 실루엣(2026-08-21 톱니 폐지 · "쫓아오는 가시 벽"으로
		# 읽혔다 · y_up 문법 이식). 결정적 해시로 덩어리 변주 · 매 프레임 동일(지글거림 방지).
		var y: float = V_TOP
		var k: int = 0
		while y < V_BOT:
			var hsh: float = fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0)
			var ch: float = 40.0 + hsh * 64.0                          # 덩어리 세로 길이
			var cw: float = 10.0 + fposmod(hsh * 7.31, 1.0) * 34.0    # 오른쪽 돌출 폭
			var tone: float = 0.12 + fposmod(hsh * 3.17, 1.0) * 0.08
			draw_rect(Rect2(Vector2(-8.0, y), Vector2(cw + 8.0, ch)), Color(tone + 0.04, tone, tone * 0.9, 1.0))
			draw_rect(Rect2(Vector2(cw - 2.0, y), Vector2(2.5, ch)), Color(0.38, 0.32, 0.28, 0.75))
			# 더미 틈의 잔불 · 드문 주황 점(y_up과 동일 어휘).
			if fposmod(hsh * 11.7, 1.0) < 0.22:
				draw_rect(Rect2(Vector2(cw * 0.35, y + ch * 0.4), Vector2(5.0, 4.0)), Color(0.85, 0.38, 0.14, 0.7))
			y += ch + 4.0
			k += 1
		# 낙하 잔해 + 착지 분진(로컬 x = 월드 x - _edge · position.x = _edge).
		for d0 in _debris:
			var d: Dictionary = d0
			draw_rect(Rect2(Vector2(float(d["x"]) - _edge, float(d["y"])), Vector2(float(d["w"]), float(d["h"]))),
				Color(0.30, 0.26, 0.23, 0.95))
		for q0 in _puffs:
			var q: Dictionary = q0
			var qa: float = 1.0 - float(q["t"]) / 0.5
			draw_circle(Vector2(float(q["x"]) - _edge, float(q.get("y", 610.0))),
				6.0 + 14.0 * float(q["t"]) / 0.5, Color(0.4, 0.35, 0.3, 0.35 * qa))
		# 앞쪽 먼지 경고대(반투명) · "곧 삼켜진다"
		draw_rect(Rect2(Vector2(0.0, V_TOP), Vector2(DUST_W, V_BOT - V_TOP)), Color(0.36, 0.30, 0.26, 0.16))
		draw_rect(Rect2(Vector2(DUST_W, V_TOP), Vector2(DUST_W * 0.7, V_BOT - V_TOP)), Color(0.36, 0.30, 0.26, 0.07))
	else:
		# 삼켜진 어두운 영역(선두 아래 전부).
		draw_rect(Rect2(Vector2(H_LEFT, 0.0), Vector2(H_RIGHT - H_LEFT, 4600.0)), Color(0.05, 0.04, 0.05, 0.97))
		# 선두 = 쌓인 잔해 더미 실루엣(2026-08-18 재작업 · 등간격 톱니는 "올라오는 가시"로
		# 읽혔다). 결정적 해시로 덩어리 폭·높이 변주 · 매 프레임 동일(지글거림 방지).
		var x: float = H_LEFT
		var k: int = 0
		while x < H_RIGHT:
			var hsh: float = fposmod(sin(float(k) * 12.9898) * 43758.5453, 1.0)
			var cw: float = 44.0 + hsh * 72.0
			var ch: float = 14.0 + fposmod(hsh * 7.31, 1.0) * 44.0
			var tone: float = 0.12 + fposmod(hsh * 3.17, 1.0) * 0.08
			draw_rect(Rect2(Vector2(x, -ch), Vector2(cw, ch + 10.0)), Color(tone + 0.04, tone, tone * 0.9, 1.0))
			draw_rect(Rect2(Vector2(x, -ch), Vector2(cw, 2.5)), Color(0.38, 0.32, 0.28, 0.75))
			# 더미 틈의 잔불(소각 여파) · 드문 주황 점.
			if fposmod(hsh * 11.7, 1.0) < 0.22:
				draw_rect(Rect2(Vector2(x + cw * 0.4, -ch * 0.4), Vector2(5.0, 4.0)), Color(0.85, 0.38, 0.14, 0.7))
			x += cw + 6.0 + fposmod(hsh * 5.3, 1.0) * 24.0
			k += 1
		# 낙하 잔해(월드 좌표 → 로컬 y = y - _edge) · 위에서 떨어져 더미에 박힌다.
		for d0 in _debris:
			var d: Dictionary = d0
			draw_rect(Rect2(Vector2(float(d["x"]), float(d["y"]) - _edge - float(d["h"])),
				Vector2(float(d["w"]), float(d["h"]))), Color(0.22, 0.19, 0.17, 0.95))
		# 착탄 분진 퍼프 · 확장하며 사라지는 원.
		for q0 in _puffs:
			var q: Dictionary = q0
			var qt: float = float(q["t"]) / 0.5
			draw_circle(Vector2(float(q["x"]), -6.0), 10.0 + 26.0 * qt, Color(0.36, 0.30, 0.26, 0.30 * (1.0 - qt)))
		# 위쪽 먼지 경고대 · "아래가 무너지며 차오른다"
		draw_rect(Rect2(Vector2(H_LEFT, -DUST_W), Vector2(H_RIGHT - H_LEFT, DUST_W)), Color(0.36, 0.30, 0.26, 0.16))
		draw_rect(Rect2(Vector2(H_LEFT, -DUST_W - DUST_W * 0.7), Vector2(H_RIGHT - H_LEFT, DUST_W * 0.7)), Color(0.36, 0.30, 0.26, 0.07))
