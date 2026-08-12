class_name FalseVeil
extends CharacterBody2D

# 14-1 P3 분신전 본체 — 거짓 VEIL (rival_veil_concept §7.2, 2026-08-12 확정 스펙).
# 시각 = "인간적인 눈 + 구형 렌더 tell": 본체는 유기적 계열의 눈 도상(곡선·부드러운 깜빡임·
# 플레이어 시선 추적·반 박자 긴 응시, 그로테스크 배제). 공격 문법 = 내 VEIL 흉내:
#  - 가짜 마커(_FakeMarker): 아무것도 없는 곳에 구형 렌더 문법(두꺼운 브래킷·스캔라인·커서)의
#    표적 표시를 뿌린다. 스타일 차이 자체가 §4.1 공정 tell(내 VEIL 마커는 얇은 시안).
#  - 진짜 위협 무표시: Stage가 volley_started마다 no_marker 적을 투입(VeilSight가 마커 생략).
# 사이클: PHASED(잠복·무적, 가짜 마커 볼리) → TELE(동공 수축 응시 = 실체화 예고) →
# SOLID(실체·피격 가능, 조준 3연탄) → PHASED... hp 소진 시 눈을 감으며 소멸(defeated).
# 광과민성 기준(known_issues) 준수 — 점멸 없음, 깜빡임은 완만한 눈꺼풀 모션.

signal defeated
signal volley_started

enum State { PHASED, TELE, SOLID, DYING }

const MAX_HP: int = 6
const PHASED_DUR: float = 7.0
const TELE_DUR: float = 0.7
const SOLID_DUR: float = 3.4
const FAKES_PER_VOLLEY: int = 4
const DRIFT_SPEED: float = 60.0

var hp: int = MAX_HP
var state: State = State.PHASED
var _state_t: float = 0.0
var _t: float = 0.0
var _gaze: Vector2 = Vector2.ZERO       # 동공 오프셋(플레이어 추적, 지연 = 긴 응시)
var _lid: float = 0.0                   # 0=뜸 1=감음
var _blink_t: float = 0.0
var _hit_flash_t: float = 0.0
var _die_t: float = 0.0
var _anchors: Array = []                # 부유 이동 지점(순환)
var _anchor_idx: int = 0
var _fake_spots: Array = []             # 가짜 마커 후보 위치(순환)
var _spot_idx: int = 0
var _fakes: Array = []                  # 살아있는 _FakeMarker 참조

func setup(anchors: Array, fake_spots: Array) -> void:
	_anchors = anchors
	_fake_spots = fake_spots

func _ready() -> void:
	collision_layer = 4   # 적 레이어 — 플레이어 탄이 맞는다(Bullet.take_damage 덕타이핑)
	collision_mask = 0    # 물리 충돌 없음(부유)
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 34.0
	col.shape = shape
	add_child(col)
	z_index = 2
	_enter_phased()

func _enter_phased() -> void:
	state = State.PHASED
	_state_t = 0.0
	if not _anchors.is_empty():
		_anchor_idx = (_anchor_idx + 1) % _anchors.size()
	_spawn_fakes()
	emit_signal("volley_started")

func _spawn_fakes() -> void:
	if _fake_spots.is_empty():
		return
	var parent := get_parent()
	if parent == null:
		return
	for i in FAKES_PER_VOLLEY:
		var spot: Vector2 = _fake_spots[_spot_idx % _fake_spots.size()]
		_spot_idx += 1
		var m := _FakeMarker.new()
		m.position = spot
		m.lifetime = PHASED_DUR + 1.0
		parent.add_child(m)
		_fakes.append(m)

# 내 VEIL의 지각 보조(§7.2 신뢰=개입 빈도) — 가장 오래된 가짜 하나를 시안 소거로 지운다.
func erase_one_fake() -> bool:
	while not _fakes.is_empty():
		var m = _fakes.pop_front()
		if m != null and is_instance_valid(m) and not bool(m.get("erasing")):
			(m as Node).call("erase", true)
			return true
	return false

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	_state_t += delta
	_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
	# 살아있는 가짜 참조 정리.
	var i: int = _fakes.size() - 1
	while i >= 0:
		if _fakes[i] == null or not is_instance_valid(_fakes[i]):
			_fakes.remove_at(i)
		i -= 1
	# 시선 추적 — 지연 lerp(반 박자 긴 응시).
	var p := _find_player()
	if p != null:
		var want: Vector2 = (p.global_position - global_position).normalized() * 10.0
		_gaze = _gaze.lerp(want, minf(1.0, delta * 2.0))
	match state:
		State.PHASED:
			_drift(delta)
			_update_blink(delta)
			if _state_t >= PHASED_DUR:
				state = State.TELE
				_state_t = 0.0
		State.TELE:
			_lid = maxf(0.0, _lid - delta * 6.0)   # 크게 뜬다 — 응시 예고
			if _state_t >= TELE_DUR:
				state = State.SOLID
				_state_t = 0.0
				_fire_volley()
		State.SOLID:
			_lid = 0.0
			if _state_t >= SOLID_DUR:
				_enter_phased()
		State.DYING:
			_die_t += delta
			_lid = minf(1.0, _die_t / 1.1)   # 천천히 눈을 감는다
			if _die_t >= 1.9:
				queue_free()
	queue_redraw()

func _drift(delta: float) -> void:
	if _anchors.is_empty():
		return
	var target: Vector2 = _anchors[_anchor_idx % _anchors.size()]
	global_position = global_position.move_toward(target, DRIFT_SPEED * delta)

func _update_blink(delta: float) -> void:
	# 완만한 깜빡임 — 3.6s 주기, 0.28s 동안 감았다 뜬다(점멸 아님).
	_blink_t += delta
	var cycle: float = fmod(_blink_t, 3.6)
	if cycle < 0.14:
		_lid = cycle / 0.14
	elif cycle < 0.28:
		_lid = 1.0 - (cycle - 0.14) / 0.14
	else:
		_lid = 0.0

# 실체화 순간의 조준 3연탄 — "볼 수 있는 창 = 위험한 창"의 리스크 교환.
func _fire_volley() -> void:
	var p := _find_player()
	if p == null:
		return
	SfxPlayer.play_at("enemy_patrol_fire", global_position)
	var base_dir: Vector2 = (p.global_position + Vector2(0, -24.0) - global_position).normalized()
	for spread in [-0.22, 0.0, 0.22]:
		var b := EnemyBullet.new()
		b.damage = 1
		b.velocity = base_dir.rotated(float(spread)) * EnemyBullet.BASE_SPEED * 0.9
		b.global_position = global_position + base_dir * 30.0
		get_parent().add_child(b)

func take_damage(amount: int, _from_dir: int = 0) -> void:
	if state == State.DYING:
		return
	if state != State.SOLID:
		# 잠복 중엔 실체가 없다 — 탄이 흘러나감(공정: 실체화 창이 명확히 보임).
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -6.0)
		return
	hp -= amount
	_hit_flash_t = 0.25
	SfxPlayer.play_at("boss_hurt", global_position, -2.0)
	if hp <= 0:
		state = State.DYING
		_die_t = 0.0
		_clear_fakes()
		set_collision_layer_value(3, false)
		emit_signal("defeated")

func _clear_fakes() -> void:
	for m in _fakes:
		if m != null and is_instance_valid(m):
			(m as Node).call("erase", false)
	_fakes.clear()

func _find_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("player")
	if nodes.size() == 0:
		return null
	return nodes[0] as Node2D

# ─── 렌더 — 유기적 눈(그로테스크 배제: 곡선·부드러운 발광·정갈한 도상) ───
func _draw() -> void:
	var a: float = 1.0
	match state:
		State.PHASED:
			a = 0.42
		State.TELE:
			a = lerpf(0.42, 1.0, clampf(_state_t / TELE_DUR, 0.0, 1.0))
		State.SOLID:
			a = 1.0
		State.DYING:
			a = maxf(0.0, 1.0 - maxf(0.0, _die_t - 1.1) / 0.8)
	var open_amt: float = 1.0 - _lid
	if open_amt <= 0.02 and state != State.DYING:
		open_amt = 0.02
	var w: float = 46.0
	var h: float = 26.0 * open_amt
	# 뒤 글로우 — 부드러운 바이올렛 이중 타원.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.62))
	draw_circle(Vector2.ZERO, w * 1.5, Color(0.72, 0.42, 1.0, 0.07 * a))
	draw_circle(Vector2.ZERO, w * 1.1, Color(0.72, 0.42, 1.0, 0.10 * a))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if h > 1.0:
		# 아몬드 윤곽(위/아래 호) + 내부 채움.
		var seg: int = 22
		var upper := PackedVector2Array()
		var lower := PackedVector2Array()
		for k in seg + 1:
			var tt: float = float(k) / float(seg)
			var x: float = lerpf(-w, w, tt)
			var lift: float = sin(PI * tt)
			upper.append(Vector2(x, -h * lift))
			lower.append(Vector2(x, h * 0.8 * lift))
		var fill := PackedVector2Array()
		fill.append_array(upper)
		for k in range(lower.size() - 1, -1, -1):
			fill.append(lower[k])
		draw_colored_polygon(fill, Color(0.13, 0.09, 0.19, 0.88 * a))
		draw_polyline(upper, Color(0.88, 0.74, 1.0, 0.85 * a), 2.5, true)
		draw_polyline(lower, Color(0.88, 0.74, 1.0, 0.7 * a), 2.5, true)
		# 홍채/동공 — 시선(지연 추적) 오프셋. SOLID/TELE에선 동공 수축(응시).
		var iris_p: Vector2 = _gaze.limit_length(10.0)
		var pupil_r: float = 7.0
		if state == State.TELE:
			pupil_r = lerpf(7.0, 4.2, clampf(_state_t / TELE_DUR, 0.0, 1.0))
		elif state == State.SOLID:
			pupil_r = 4.2
		var clip_h: float = minf(15.0, h)
		draw_circle(iris_p, clip_h, Color(0.58, 0.34, 0.88, 0.9 * a))
		draw_circle(iris_p, clip_h * 0.72, Color(0.42, 0.24, 0.66, 0.95 * a))
		draw_circle(iris_p, pupil_r, Color(0.05, 0.03, 0.09, a))
		draw_circle(iris_p + Vector2(-3.5, -3.5), 2.2, Color(1.0, 1.0, 1.0, 0.8 * a))
	# 실체(피격 가능) 링 — SOLID에서만 완만히 맥동.
	if state == State.SOLID:
		var ring_a: float = 0.35 + 0.15 * sin(_t * 3.0)
		draw_arc(Vector2.ZERO, 52.0, 0.0, TAU, 40, Color(0.92, 0.80, 1.0, ring_a), 2.0, true)
	# 피격 플래시 — 확장 링(짧고 국소적).
	if _hit_flash_t > 0.0:
		var k: float = 1.0 - _hit_flash_t / 0.25
		draw_arc(Vector2.ZERO, 40.0 + 30.0 * k, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - k)), 2.5, true)

# ═══ 가짜 마커 — 구형 렌더 문법(두꺼운 브래킷 + 스캔라인 + 깜빡이는 커서) ═══
# 내 VEIL의 얇은 시안 마커와 스타일로 구분된다(= 공정 tell). 아무것도 없는 위치에 선다.
class _FakeMarker extends Node2D:
	var lifetime: float = 8.0
	var t: float = 0.0
	var erasing: bool = false
	var _erase_t: float = 0.0
	var _erase_cyan: bool = false

	func _ready() -> void:
		z_index = 6

	func _process(delta: float) -> void:
		t += delta
		if erasing:
			_erase_t += delta
			if _erase_t > 0.4:
				queue_free()
				return
		elif t >= lifetime:
			erase(false)
		queue_redraw()

	func erase(by_veil: bool) -> void:
		if erasing:
			return
		erasing = true
		_erase_cyan = by_veil
		_erase_t = 0.0

	func _draw() -> void:
		var appear: float = clampf(t / 0.3, 0.0, 1.0)
		var a: float = appear
		if erasing:
			a = maxf(0.0, 1.0 - _erase_t / 0.4)
		var vi := Color(0.82, 0.58, 1.0, 0.9 * a)
		# 표적 박스(발 기준 44×58) — 두꺼운 모서리 브래킷 4개(구형 문법: 굵고 각짐).
		var bw: float = 22.0
		var top: float = -58.0
		var arm: float = 10.0
		var thick: float = 4.0
		for corner in [Vector2(-bw, top), Vector2(bw, top), Vector2(-bw, 0.0), Vector2(bw, 0.0)]:
			var c: Vector2 = corner
			var sx: float = -1.0 if c.x > 0.0 else 1.0
			var sy: float = 1.0 if c.y < -20.0 else -1.0
			draw_line(c, c + Vector2(sx * arm, 0.0), vi, thick)
			draw_line(c, c + Vector2(0.0, sy * arm), vi, thick)
		# 스캔라인 — 박스 안을 위→아래로 훑는 가로선(1.4s 주기, 완만).
		var scan: float = fmod(t, 1.4) / 1.4
		var sy2: float = lerpf(top + 4.0, -4.0, scan)
		draw_line(Vector2(-bw + 3.0, sy2), Vector2(bw - 3.0, sy2), Color(vi.r, vi.g, vi.b, 0.45 * a), 1.5)
		# 깜빡이는 커서(밑줄) — 1.6Hz 소면적(광과민성 기준 내).
		if fmod(t, 0.62) < 0.34:
			draw_line(Vector2(-8.0, 10.0), Vector2(8.0, 10.0), vi, 3.0)
		# VEIL 소거 — 시안 취소선(내 VEIL이 그은 줄).
		if erasing and _erase_cyan:
			var k: float = clampf(_erase_t / 0.22, 0.0, 1.0)
			var x0: float = -bw - 6.0
			var x1: float = lerpf(x0, bw + 6.0, k)
			draw_line(Vector2(x0, top * 0.5), Vector2(x1, top * 0.5), Color(0.45, 0.90, 1.0, 0.9), 2.5)
