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
# 리워크(§2.4) 변주 3단 · HP 문턱(66%/33%) 통과 시 emit. 1=중반(텔레포트 실체화),
# 2=후반(창 짧고 잦게 + 방 렌더 붕괴 연출은 Stage 담당).
signal stage_shifted(stage_idx: int)
# 실체화 창당 피해 상한 도달(조기 재잠복) · Stage가 첫 회에 VEIL 해설 1회를 단다.
signal window_capped

enum State { PHASED, TELE, SOLID, DYING }

const MAX_HP: int = 6   # 기본값 — Stage가 레벨 스케일로 덮어쓴다(max_hp/hp)
# 잠복 7.0 → 5.2 (2026-08-17): 상한 도입으로 창 수가 늘어난 만큼 창 사이 대기를 줄인다
# ("실체화 될 때까지 기다린다"가 지루하다는 지적과 정합).
const PHASED_DUR: float = 5.2
const TELE_DUR: float = 0.7
const SOLID_DUR: float = 3.4
const FAKES_PER_VOLLEY: int = 4
const DRIFT_SPEED: float = 60.0

var max_hp: int = MAX_HP
var hp: int = MAX_HP
var state: State = State.PHASED
# 다회차 기억 변주 시드(Stage가 setup 전에 세팅) — 가짜 눈 앵커 회전 폭 · 결정타 출처 기록.
var decoy_shift: int = 1
var last_hit_from_dir: int = 0
# 변주 단계(0 전반/1 중반/2 후반) · take_damage에서 HP 비율로 전이. 후반은 창이 짧고 잦다.
var fight_stage: int = 0
var phased_dur: float = PHASED_DUR
var solid_dur: float = SOLID_DUR
# 가짜 눈(§2.4 전반, 사용자 확정) · 실체화 때 함께 뜨는 미끼. 유도탄도 이쪽을 쫓는다
# (homing_decoy 그룹 · 유도가 판별을 공짜로 주지 않게, 사용자 지적 2026-08-16).
var _decoy: _DecoyEye = null
var _state_t: float = 0.0
var _t: float = 0.0
var _gaze: Vector2 = Vector2.ZERO       # 동공 오프셋(플레이어 추적, 지연 = 긴 응시)
var _lid: float = 0.0                   # 0=뜸 1=감음
var _blink_t: float = 0.0
var _hit_flash_t: float = 0.0
var _die_t: float = 0.0
var _ripple_t: float = 0.0              # 잠복 중 탄 통과 파문("지금은 그림이다"의 시각 언어)
var _ripple_cd: float = 0.0
var _anchors: Array = []                # 부유 이동 지점(순환)
var _anchor_idx: int = 0
var _fake_spots: Array = []             # 가짜 마커 후보 위치(순환)
var _spot_idx: int = 0
var _fakes: Array = []                  # 살아있는 _FakeMarker 참조
# 실체화 창당 피해 누적(상한 = max_hp/6) · 고DPS 빌드의 "첫 창에 끝" 차단(2026-08-17).
var _window_dmg: int = 0
var _next_phased_scale: float = 1.0     # 상한 도달 직후의 잠복만 짧게(화력의 보상)
# 텔레포트 워프 연출(중반+ 변주) · 이전 자리에 소멸 파문을 남긴다.
var _warp_from: Vector2 = Vector2.ZERO
var _warp_t: float = 0.0

func setup(anchors: Array, fake_spots: Array) -> void:
	_anchors = anchors
	_fake_spots = fake_spots

func _ready() -> void:
	# 잠복 = 콜리전 자체를 끈다 → 탄이 몸을 **통과**("실체 없음"이 총으로도 읽힘. 박히는데 무반응
	# 이라는 반려 2026-08-12). SOLID에서만 레이어 4(적) 켜져 탄이 박힌다.
	collision_layer = 0
	collision_mask = 0    # 물리 충돌 없음(부유)
	# 수류탄 폭발 경로(Grenade가 그룹 스캔) — "enemy" 그룹 밖 보스체용 그룹.
	add_to_group("boss_hittable")
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 34.0
	col.shape = shape
	add_child(col)
	z_index = 2
	# 가짜 눈 동반 스폰 · 부모(스테이지)에 형제로. 앵커는 본체 앵커를 decoy_shift칸 돌린 것
	# (같은 자리 금지). 기본 1 · 다회차 기억 변주(수류탄 격파 기억)면 Stage가 2로 시드 —
	# 지난 회차의 진짜 자리에 가짜가 선다.
	_decoy = _DecoyEye.new()
	_decoy.owner_fv = self
	var d_anchors: Array = []
	for i in _anchors.size():
		d_anchors.append(_anchors[(i + maxi(1, decoy_shift)) % _anchors.size()])
	_decoy.anchors = d_anchors
	_decoy.global_position = global_position + Vector2(300.0, 40.0)
	get_parent().call_deferred("add_child", _decoy)
	_enter_phased()

func _enter_phased() -> void:
	state = State.PHASED
	_state_t = 0.0
	_window_dmg = 0
	if not _anchors.is_empty():
		_anchor_idx = (_anchor_idx + 1) % _anchors.size()
	if _decoy != null and is_instance_valid(_decoy):
		_decoy.cycle_anchor()
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
	_ripple_t = maxf(0.0, _ripple_t - delta)
	_ripple_cd = maxf(0.0, _ripple_cd - delta)
	_warp_t = maxf(0.0, _warp_t - delta)
	# 잠복/응시 중 탄이 몸을 지나가면 파문 — "박히지 않고 통과한다"를 그 자리에서 보여준다.
	if (state == State.PHASED or state == State.TELE) and _ripple_cd <= 0.0:
		var btree := get_tree()
		if btree != null:
			for b in btree.get_nodes_in_group("player_bullet"):
				if b is Node2D and global_position.distance_to((b as Node2D).global_position) < 46.0:
					_ripple_t = 0.35
					_ripple_cd = 0.3
					break
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
			if _state_t >= phased_dur * _next_phased_scale:
				state = State.TELE
				_state_t = 0.0
				_next_phased_scale = 1.0
				# 중반+(변주 §2.4): 실체화 위치가 3지점 텔레포트 · 드리프트로 예측되던 위치가
				# 튄다. 가짜 눈도 동시에 다른 지점으로 튀어 "어느 쪽이 진짜인가"가 매번 갱신.
				# 워프 연출(사용자 2026-08-17 "위치 초기화 텔레포트가 맞나?") · 의도된 변주지만
				# 연출 없이 스냅해 버그처럼 읽혔다 · 이전 자리 소멸 파문을 남겨 "옮겨 갔다"로.
				if fight_stage >= 1 and not _anchors.is_empty():
					_anchor_idx = (_anchor_idx + 1 + (randi() % maxi(1, _anchors.size() - 1))) % _anchors.size()
					_warp_from = global_position
					_warp_t = 0.4
					global_position = _anchors[_anchor_idx]
					if _decoy != null and is_instance_valid(_decoy):
						_decoy.tele_jump()
		State.TELE:
			_lid = maxf(0.0, _lid - delta * 6.0)   # 크게 뜬다 — 응시 예고
			if _state_t >= TELE_DUR:
				state = State.SOLID
				_state_t = 0.0
				collision_layer = 4   # 실체화 — 이제 탄이 박힌다
				_fire_volley()
		State.SOLID:
			_lid = 0.0
			if _state_t >= solid_dur:
				collision_layer = 0   # 잠복 복귀 — 탄이 다시 통과
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

func take_damage(amount: int, from_dir: int = 0) -> void:
	if state == State.DYING:
		return
	# 결정타 출처 기록(다회차 기억) — 총알 ±1 / 폭발(수류탄) 0. Enemy.take_damage와 같은 규약.
	last_hit_from_dir = from_dir
	if state != State.SOLID:
		# 잠복 중엔 실체가 없다 — 탄이 흘러나감(공정: 실체화 창이 명확히 보임).
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -6.0)
		return
	# 실체화 창당 피해 상한 · "실체화까지 기다렸다 쏘면 5초 컷"(사용자 2026-08-17) 차단.
	# 상한 = max_hp/6 → 어떤 화력이든 실체화 창 ~6번은 상대해야 변주 3단이 실제로 등장.
	# 저DPS 빌드는 상한에 닿지 않으므로 영향 없음.
	var cap: int = maxi(3, int(ceil(float(max_hp) / 6.0)))
	var allowed: int = cap - _window_dmg
	if allowed <= 0:
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -6.0)
		return
	amount = mini(amount, allowed)
	_window_dmg += amount
	hp -= amount
	_hit_flash_t = 0.25
	SfxPlayer.play_at("bullet_impact_enemy", global_position)
	SfxPlayer.play_at("boss_hurt", global_position, -2.0)
	# 변주 3단 전이(§2.4) · 66%/33% 문턱. 후반은 실체화 창이 짧아지는 대신 자주 온다.
	var ratio: float = float(hp) / maxf(1.0, float(max_hp))
	var want_stage: int = 0
	if ratio <= 0.33:
		want_stage = 2
	elif ratio <= 0.66:
		want_stage = 1
	if want_stage > fight_stage:
		fight_stage = want_stage
		if fight_stage >= 2:
			phased_dur = 4.2
			solid_dur = 2.2
		emit_signal("stage_shifted", fight_stage)
	if hp <= 0:
		state = State.DYING
		_die_t = 0.0
		_clear_fakes()
		if _decoy != null and is_instance_valid(_decoy):
			_decoy.begin_erase()
		collision_layer = 0
		emit_signal("defeated")
	elif _window_dmg >= cap:
		# 상한 도달 · 깊게 박히기 전에 몸을 물린다(조기 재잠복). 화력의 보상 = 다음 잠복이 짧다.
		collision_layer = 0
		_hit_flash_t = 0.35
		_next_phased_scale = 0.6
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -4.0)
		emit_signal("window_capped")
		_enter_phased()

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
	# 워프 소멸 파문 · 이전 자리에서 잦아드는 링 2겹 + 새 자리로 향한 흐릿한 궤적
	# (텔레포트가 버그가 아니라 이동으로 읽히게 · 연속 감쇠, 점멸 없음).
	if _warp_t > 0.0:
		var wk: float = 1.0 - _warp_t / 0.4
		var rel: Vector2 = _warp_from - global_position
		draw_arc(rel, 14.0 + 34.0 * wk, 0.0, TAU, 24, Color(0.72, 0.42, 1.0, 0.55 * (1.0 - wk)), 2.5, true)
		draw_arc(rel, 6.0 + 18.0 * wk, 0.0, TAU, 18, Color(0.90, 0.75, 1.0, 0.4 * (1.0 - wk)), 2.0, true)
		draw_line(rel * (1.0 - wk), Vector2.ZERO, Color(0.72, 0.42, 1.0, 0.25 * (1.0 - wk)), 2.0)
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
	# 잠복도(ghost) — 1이면 "구형 렌더로 그려진 그림"(스캔라인 짜임), 0이면 실체.
	var ghost: float = 0.0
	if state == State.PHASED:
		ghost = 1.0
	elif state == State.TELE:
		ghost = 1.0 - clampf(_state_t / TELE_DUR, 0.0, 1.0)
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
		# 눈꺼풀과 함께 세로로 눌린다(transform y-스케일) — 감았는데 눈동자가 보이던 버그 수정
		# (사용자 2026-08-12): 개폐량 비율로 홍채·동공·하이라이트 전체를 압축.
		var iris_p: Vector2 = _gaze.limit_length(10.0)
		var pupil_r: float = 7.0
		if state == State.TELE:
			pupil_r = lerpf(7.0, 4.2, clampf(_state_t / TELE_DUR, 0.0, 1.0))
		elif state == State.SOLID:
			pupil_r = 4.2
		var squash: float = clampf(h / 26.0, 0.02, 1.0)
		draw_set_transform(iris_p, 0.0, Vector2(1.0, squash))
		draw_circle(Vector2.ZERO, 15.0, Color(0.58, 0.34, 0.88, 0.9 * a))
		draw_circle(Vector2.ZERO, 15.0 * 0.72, Color(0.42, 0.24, 0.66, 0.95 * a))
		draw_circle(Vector2.ZERO, pupil_r, Color(0.05, 0.03, 0.09, a))
		draw_circle(Vector2(-3.5, -3.5), 2.2, Color(1.0, 1.0, 1.0, 0.8 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 잠복 = 가짜 마커와 같은 스캔라인 짜임을 본체에도 — "지금은 그림"이 시각 언어로 읽힌다.
		# 실체화(TELE→SOLID)되며 짜임이 걷히고 몸이 꽉 찬다. 텍스트 라벨 없이 상태 전달
		# ("실체 없음" 라벨 작위적 반려 2026-08-13).
		if ghost > 0.02:
			var sy: float = -h + 2.0
			while sy < h * 0.8 - 1.0:
				var rel: float = (-sy / h) if sy < 0.0 else (sy / maxf(h * 0.8, 0.001))
				rel = clampf(rel, 0.0, 0.999)
				var t0: float = asin(rel) / PI
				var half_w: float = w * (1.0 - 2.0 * t0)
				if half_w > 2.0:
					draw_line(Vector2(-half_w, sy), Vector2(half_w, sy),
						Color(0.05, 0.03, 0.09, 0.5 * ghost * a), 2.0)
				sy += 4.0
	# 실체(피격 가능) 링 — SOLID에서만 완만히 맥동.
	if state == State.SOLID:
		var ring_a: float = 0.35 + 0.15 * sin(_t * 3.0)
		draw_arc(Vector2.ZERO, 52.0, 0.0, TAU, 40, Color(0.92, 0.80, 1.0, ring_a), 2.0, true)
	# 피격 플래시 — 확장 링(짧고 국소적).
	if _hit_flash_t > 0.0:
		var k: float = 1.0 - _hit_flash_t / 0.25
		draw_arc(Vector2.ZERO, 40.0 + 30.0 * k, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - k)), 2.5, true)
	# 실체화 스냅 — SOLID 진입 순간 밝은 링이 퍼진다("지금부터 박힌다").
	if state == State.SOLID and _state_t < 0.35:
		var sk: float = _state_t / 0.35
		draw_arc(Vector2.ZERO, 40.0 + 26.0 * sk, 0.0, TAU, 40, Color(0.95, 0.85, 1.0, 0.8 * (1.0 - sk)), 3.0, true)
	# 탄 통과 파문 — 잠복 중 탄이 몸을 지나간 흔적(박히지 않았음을 그 자리에서 보여줌).
	if _ripple_t > 0.0:
		var rk: float = 1.0 - _ripple_t / 0.35
		draw_arc(Vector2.ZERO, 30.0 + 42.0 * rk, 0.0, TAU, 36, Color(0.72, 0.42, 1.0, 0.38 * (1.0 - rk)), 2.0, true)

# ═══ 가짜 눈(§2.4 전반, 2026-08-16 사용자 확정) · 실체화 때 함께 뜨는 미끼 눈 ═══
# 본체와 같은 아몬드 눈 도상을 미러하되 tell = 구형 렌더 문법: ① 실체화해도 스캔라인 잔결이
# 남는다(본체는 걷힘) ② 주기적 x-슬립 ③ 탄이 통과하며 파문(콜리전 없음) ④ 볼리를 쏘지 않는다.
# homing_decoy 그룹 · 유도탄이 이쪽으로도 휘어 "유도 방향 = 공짜 판별"을 차단(사용자 지적).
class _DecoyEye extends Node2D:
	var owner_fv: Node2D = null
	var anchors: Array = []
	var anchor_idx: int = 0
	var _t: float = 0.0
	var _gaze: Vector2 = Vector2.ZERO
	var _ripple_t: float = 0.0
	var _ripple_cd: float = 0.0
	var _erasing: bool = false
	var _erase_t: float = 0.0

	func _ready() -> void:
		add_to_group("homing_decoy")
		z_index = 2

	func cycle_anchor() -> void:
		anchor_idx = (anchor_idx + 1) % maxi(1, anchors.size())

	func tele_jump() -> void:
		if anchors.is_empty():
			return
		anchor_idx = (anchor_idx + 1 + (randi() % maxi(1, anchors.size() - 1))) % anchors.size()
		global_position = anchors[anchor_idx]

	func begin_erase() -> void:
		_erasing = true
		_erase_t = 0.0

	func _physics_process(delta: float) -> void:
		if owner_fv == null or not is_instance_valid(owner_fv):
			queue_free()
			return
		_t += delta
		_ripple_t = maxf(0.0, _ripple_t - delta)
		_ripple_cd = maxf(0.0, _ripple_cd - delta)
		if _erasing:
			_erase_t += delta
			if _erase_t > 0.6:
				queue_free()
				return
		var st: int = int(owner_fv.get("state"))
		# 잠복 동안 자기 앵커로 부유(본체와 같은 리듬, 다른 자리).
		if st == 0 and not anchors.is_empty():
			global_position = global_position.move_toward(anchors[anchor_idx % anchors.size()], 60.0 * delta)
		# 시선 흉내 · 본체보다 뻣뻣하게(지연 절반 · 미세 tell).
		var tree := get_tree()
		if tree != null:
			var arr := tree.get_nodes_in_group("player")
			if arr.size() > 0:
				var want: Vector2 = ((arr[0] as Node2D).global_position - global_position).normalized() * 10.0
				_gaze = _gaze.lerp(want, minf(1.0, delta * 1.0))
			# 탄 통과 파문 · 쏘면 그림임이 드러난다(확정 판별 · 대신 탄과 시간을 쓴다).
			if _ripple_cd <= 0.0:
				for b in tree.get_nodes_in_group("player_bullet"):
					if b is Node2D and global_position.distance_to((b as Node2D).global_position) < 46.0:
						_ripple_t = 0.35
						_ripple_cd = 0.3
						break
		queue_redraw()

	func _draw() -> void:
		if owner_fv == null or not is_instance_valid(owner_fv):
			return
		var st: int = int(owner_fv.get("state"))
		var st_t: float = 0.0
		if owner_fv.get("_state_t") != null:
			st_t = float(owner_fv.get("_state_t"))
		var a: float = 0.42
		var open_amt: float = 0.55
		match st:
			1:   # TELE · 본체와 같이 떠오른다
				a = lerpf(0.42, 1.0, clampf(st_t / 0.7, 0.0, 1.0))
				open_amt = lerpf(0.55, 1.0, clampf(st_t / 0.7, 0.0, 1.0))
			2:   # SOLID · 실체처럼 보이지만 스캔라인 잔결이 남는다(tell ①)
				a = 1.0
				open_amt = 1.0
			3:   # 본체 소멸 · 미끼도 걷힌다
				a = 0.3
		if _erasing:
			a *= maxf(0.0, 1.0 - _erase_t / 0.6)
		# 주기 슬립(tell ②) · 1.9s마다 한순간 옆으로 밀린다.
		var slip: float = 3.0 if fmod(_t, 1.9) < 0.1 else 0.0
		var w: float = 46.0
		var h: float = 26.0 * open_amt
		draw_set_transform(Vector2(slip, 0.0), 0.0, Vector2(1.0, 0.62))
		draw_circle(Vector2.ZERO, w * 1.5, Color(0.72, 0.42, 1.0, 0.07 * a))
		draw_circle(Vector2.ZERO, w * 1.1, Color(0.72, 0.42, 1.0, 0.10 * a))
		draw_set_transform(Vector2(slip, 0.0), 0.0, Vector2.ONE)
		if h > 1.0:
			var seg: int = 22
			var upper := PackedVector2Array()
			var lower := PackedVector2Array()
			for k in seg + 1:
				var tt: float = float(k) / float(seg)
				var x: float = lerpf(-w, w, tt)
				var lift: float = sin(PI * tt)
				upper.append(Vector2(x + slip, -h * lift))
				lower.append(Vector2(x + slip, h * 0.8 * lift))
			var fill := PackedVector2Array()
			fill.append_array(upper)
			for k in range(lower.size() - 1, -1, -1):
				fill.append(lower[k])
			draw_colored_polygon(fill, Color(0.13, 0.09, 0.19, 0.88 * a))
			draw_polyline(upper, Color(0.88, 0.74, 1.0, 0.85 * a), 2.5, true)
			draw_polyline(lower, Color(0.88, 0.74, 1.0, 0.7 * a), 2.5, true)
			var iris_p: Vector2 = _gaze.limit_length(10.0) + Vector2(slip, 0.0)
			var squash: float = clampf(h / 26.0, 0.02, 1.0)
			draw_set_transform(iris_p, 0.0, Vector2(1.0, squash))
			draw_circle(Vector2.ZERO, 15.0, Color(0.58, 0.34, 0.88, 0.9 * a))
			draw_circle(Vector2.ZERO, 15.0 * 0.72, Color(0.42, 0.24, 0.66, 0.95 * a))
			draw_circle(Vector2.ZERO, 5.5, Color(0.05, 0.03, 0.09, a))
			draw_circle(Vector2(-3.5, -3.5), 2.2, Color(1.0, 1.0, 1.0, 0.8 * a))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
			# 스캔라인 잔결(tell ①) · 실체 상태에서도 얇게 남는다(본체는 SOLID에서 걷힘).
			var weave_a: float = 0.5 if st != 2 else 0.22
			var sy: float = -h + 2.0
			while sy < h * 0.8 - 1.0:
				var rel: float = (-sy / h) if sy < 0.0 else (sy / maxf(h * 0.8, 0.001))
				rel = clampf(rel, 0.0, 0.999)
				var t0: float = asin(rel) / PI
				var half_w: float = w * (1.0 - 2.0 * t0)
				if half_w > 2.0:
					draw_line(Vector2(-half_w + slip, sy), Vector2(half_w + slip, sy),
						Color(0.05, 0.03, 0.09, weave_a * a), 2.0)
				sy += 4.0
		# 탄 통과 파문(tell ③).
		if _ripple_t > 0.0:
			var rk: float = 1.0 - _ripple_t / 0.35
			draw_arc(Vector2.ZERO, 30.0 + 42.0 * rk, 0.0, TAU, 36, Color(0.72, 0.42, 1.0, 0.38 * (1.0 - rk)), 2.0, true)

# ═══ 가짜 적(거짓 렌더) — 구형 렌더 문법의 적 실루엣 ═══
# "허공에 네모만 떠 있어 뭔지 모르겠다" 반려(2026-08-12) → 마커가 아니라 **적처럼 보이는 것**을
# 그린다: 디더 스캔라인으로 짜인 옛 렌더러풍 병사 실루엣이 서서 플레이어를 겨눈다.
# tell = 구형 문법(디더 실루엣·굵은 브래킷) + 쏘면 탄이 통과하며 렌더가 찢김(콜리전 없음).
# "대기열 등록 #N" 라벨과 발사 없는 조준 점선은 스폰/사격 예고로 오독돼 제거(실플레이 2026-08-13).
class _FakeMarker extends Node2D:
	var lifetime: float = 8.0
	var t: float = 0.0
	var erasing: bool = false
	var _erase_t: float = 0.0
	var _erase_cyan: bool = false
	var _slip_burst_t: float = 0.0   # 탄 통과 순간의 찢김(회복되는 약한 tear)
	var _aim_to: Vector2 = Vector2.ZERO

	func _ready() -> void:
		z_index = 6
		# 유도 미끼 · 유도탄이 가짜 병사도 쫓는다(유도 방향 = 공짜 판별 차단, 2026-08-16).
		add_to_group("homing_decoy")

	func _process(delta: float) -> void:
		t += delta
		_slip_burst_t = maxf(0.0, _slip_burst_t - delta)
		if erasing:
			_erase_t += delta
			if _erase_t > 0.4:
				queue_free()
				return
		elif t >= lifetime:
			erase(false)
		var tree := get_tree()
		if tree != null:
			# 겨누는 척 — 실루엣이 플레이어를 계속 향한다(발사는 없다).
			var arr := tree.get_nodes_in_group("player")
			if arr.size() > 0:
				_aim_to = (arr[0] as Node2D).global_position - global_position
			# 탄이 실루엣을 지나가면 렌더가 찢겼다 재조립 — "쏘면 뚫리는 그림"을 즉석에서 학습.
			if not erasing and _slip_burst_t <= 0.0:
				for b in tree.get_nodes_in_group("player_bullet"):
					if b is Node2D:
						var lp: Vector2 = (b as Node2D).global_position - global_position
						if absf(lp.x) < 26.0 and lp.y > -60.0 and lp.y < 6.0:
							_slip_burst_t = 0.32
							break
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
		# 글리치 슬립 — 드물게(1.7s 주기) 한순간 실루엣이 옆으로 밀린다(구형 렌더의 미끄러짐).
		var slip: float = 3.0 if fmod(t, 1.7) < 0.1 else 0.0
		# 소멸 = 슬라이스 흩어짐 / 탄 통과 = 같은 문법의 약한 찢김(회복됨).
		var tear: float = 0.0
		if erasing:
			tear = _erase_t / 0.4
		elif _slip_burst_t > 0.0:
			tear = 0.35 * (_slip_burst_t / 0.32)
		# ① 병사 실루엣(발 기준, 높이 ~52) — 2px 가로 스트립 디더(CRT 짜임). 옛 렌더러가 그린 적.
		var seg_defs: Array = [
			{"y0": -52.0, "y1": -40.0, "hw": 6.0},    # 머리
			{"y0": -40.0, "y1": -16.0, "hw": 9.0},    # 몸통
			{"y0": -16.0, "y1": 0.0, "hw": 7.0},      # 다리
		]
		for sd_raw in seg_defs:
			var sd: Dictionary = sd_raw
			var y: float = float(sd.get("y0", 0.0))
			var y1: float = float(sd.get("y1", 0.0))
			var hw: float = float(sd.get("hw", 6.0))
			while y < y1:
				var band_off: float = slip + tear * (24.0 if fmod(y, 8.0) < 4.0 else -24.0)
				draw_rect(Rect2(Vector2(-hw + band_off, y), Vector2(hw * 2.0, 2.0)),
					Color(vi.r, vi.g, vi.b, 0.55 * a), true)
				y += 4.0
		# 팔(총 든 자세) — 조준 방향으로 뻗은 짧은 스트립(발사는 없다 — 긴 조준선은 제거).
		var aim_dir: Vector2 = _aim_to.normalized() if _aim_to.length() > 1.0 else Vector2.RIGHT
		var shoulder := Vector2(0.0, -32.0)
		draw_line(shoulder, shoulder + aim_dir * 14.0, Color(vi.r, vi.g, vi.b, 0.55 * a), 3.0)
		# ② 표적 브래킷(굵음 = 구형 문법 tell) — 실루엣을 감싼다.
		var bw: float = 22.0
		var top: float = -58.0
		var arm: float = 10.0
		for corner in [Vector2(-bw, top), Vector2(bw, top), Vector2(-bw, 0.0), Vector2(bw, 0.0)]:
			var c: Vector2 = corner
			var sx: float = -1.0 if c.x > 0.0 else 1.0
			var sy: float = 1.0 if c.y < -20.0 else -1.0
			draw_line(c, c + Vector2(sx * arm, 0.0), vi, 4.0)
			draw_line(c, c + Vector2(0.0, sy * arm), vi, 4.0)
		# ③ 스캔라인 스윕 + 깜빡이는 커서(1.6Hz 소면적 — 광과민성 기준 내).
		var scan: float = fmod(t, 1.4) / 1.4
		var sy2: float = lerpf(top + 4.0, -4.0, scan)
		draw_line(Vector2(-bw + 3.0, sy2), Vector2(bw - 3.0, sy2), Color(vi.r, vi.g, vi.b, 0.40 * a), 1.5)
		if fmod(t, 0.62) < 0.34:
			draw_line(Vector2(-8.0, 10.0), Vector2(8.0, 10.0), vi, 3.0)
		# ④ VEIL 소거 — 시안 취소선(내 VEIL이 그은 줄).
		if erasing and _erase_cyan:
			var k: float = clampf(_erase_t / 0.22, 0.0, 1.0)
			var x0: float = -bw - 6.0
			var x1: float = lerpf(x0, bw + 6.0, k)
			draw_line(Vector2(x0, top * 0.5), Vector2(x1, top * 0.5), Color(0.45, 0.90, 1.0, 0.9), 2.5)
