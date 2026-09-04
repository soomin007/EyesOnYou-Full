class_name FalseVeil
extends CharacterBody2D

# 14-1 P3 본체 · 거짓 VEIL의 눈 (final_boss_rework §9 B안 "3장 구조" · 2026-09-04 재작성).
# 정체성 "렌더를 쥔 자"는 적 복제가 아니라 **무대를 다시 그리는 것**으로 표현한다.
# '가짜' 어휘 전면 폐지(가짜 눈·가짜 탄·가짜 병사·짝 규칙·억제 미사일 삭제 · 2026-09-03 사용자 확정).
# 시각 = "인간적인 눈 + 구형 렌더 tell"(곡선·부드러운 깜빡임·시선 추적 · 그로테스크 배제)은 유지.
#
# 3장 = HP 몫 30/40/30(창당 상한 폐지 · 길이 보장은 구조로):
#  1장 "겨눔"(~30%): 눈 하나. 짧은 잠복(PHASED) → 응시 예고(TELE) → 모습 드러냄(SOLID · 3연탄 ·
#      피격 가능) 반복. 창 문법 학습 구간.
#  2장 "추격"(~40%): 눈이 먼 자리(FLEE)로 도망가 무대를 다시 그린다(Stage가 redraw_requested를 받아
#      그려진 벽·거짓 발판 배치). 요원이 사거리에 들어오면 타격 창(TELE→SOLID)이 열리고, 닫히면
#      다음 자리로 워프(WARP)하며 다시 그린다. 자리에서 12s 안 열리면 더 가까운 자리로 옮긴다.
#  3장 "대면"(~30%): 잠복 폐지 · 상시 SOLID + 짧은 워프 무적만. 5연 부채꼴 볼리 결투.
# 사이클 신호: volley_started(1장 잠복 진입·3장 홀수 워프)에 Stage가 무표시 위협을 투입한다.
# 광과민성 기준(known_issues) 준수 · 점멸 없음, 깜빡임은 완만한 눈꺼풀 모션.

signal defeated
signal volley_started
# 장 전환(1→2 · 2→3) · Stage가 무대 변형 + 자막 + 연출을 단다(명명 연출 = 룰 변화 원칙).
signal chapter_changed(chapter: int)
# 2장 · 새 자리에 앉으며 무대를 다시 그려 달라. perch = 이번 자리, prev = 직전 자리.
signal redraw_requested(perch: Vector2, prev: Vector2)
# 2장 · 타격 창이 열렸다(요원이 사거리에 들어옴) · Stage 사운드/자막용.
signal window_opened

enum State { PHASED, TELE, SOLID, FLEE, WARP, DYING }

const MAX_HP: int = 6   # 기본값 · Stage가 레벨 스케일로 덮어쓴다(max_hp/hp)
# 장별 HP 몫 · 1장 30% / 2장 40% / 3장 30%.
const CH1_SHARE: float = 0.30
const CH2_SHARE: float = 0.40
# 1장 리듬 · 잠복 3.2(A안 5.2에서 단축 · 창당 상한이 없어져 창 수가 줄었으니 대기도 줄인다).
const CH1_PHASED_DUR: float = 3.2
const CH1_TELE_DUR: float = 0.7
const CH1_SOLID_DUR: float = 3.4
# 2장 리듬 · 타격 창은 짧고(2.8) 예고도 짧다(0.5) · 창은 "닿았다"의 보상.
const CH2_TELE_DUR: float = 0.5
const CH2_SOLID_DUR: float = 2.8
const CH2_REACH_DX: float = 400.0     # 사거리 = 타격 창 개방 조건(가로)
const CH2_REACH_DY: float = 250.0     # 같은 층 또는 한 층 차이
const CH2_FLEE_TIMEOUT: float = 12.0  # 이 시간 안에 창이 안 열리면 더 가까운 자리로
const CH2_PERCH_MIN_DX: float = 700.0 # 도망 자리 = 요원에게서 최소 이만큼
# 3장 리듬 · 볼리 2.3s마다 5연 · 4.4s마다 워프(0.55s 무적).
const CH3_VOLLEY_INTERVAL: float = 2.3
const CH3_WARP_INTERVAL: float = 4.4
const WARP_DUR: float = 0.45
const DRIFT_SPEED: float = 60.0
# 닿는 자리(1장·3장 실체화 후보 · A안 계산식 계승 · known_issues "이동 속도 × 창 길이 ≥ 거리").
const NEAR_MIN_DX: float = 60.0     # 요원 몸 위에 겹쳐 뜨지 않게(눈 반경 34 + 몸 반폭 14)
const NEAR_MAX_DX: float = 520.0    # 한 창(3.4s) 안에 닿는 거리
const NEAR_Y_BAND: float = 40.0     # 같은 높이(수평 사격으로 바로 맞는 대역)
const NEAR_Y_REACH: float = 220.0   # 점프·한 층 이동으로 닿는 높이

var max_hp: int = MAX_HP
var hp: int = MAX_HP
var state: State = State.PHASED
var chapter: int = 1
# 개시 응시 유예(초 · Stage가 add_child 전에 시드) · 발화가 흐르는 동안 공격 없음(_ready 참조).
var intro_hold: float = 0.0
# 결정타 출처 기록(Stage가 격파 시 읽음 · 다회차 기억).
var last_hit_from_dir: int = 0
# 다회차 기억(§7) · 2장 도망 자리 순서 회전 시드(Stage가 rival_kills로 준다 · "네가 외운 자리에는 없다").
var memory_shift: int = 0
var _t2: int = 0                        # 2장 진입 HP(1장 몫 소진점)
var _t3: int = 0                        # 3장 진입 HP(2장 몫 소진점)
var _state_t: float = 0.0
var _t: float = 0.0
var _gaze: Vector2 = Vector2.ZERO       # 동공 오프셋(플레이어 추적, 지연 = 긴 응시)
var _lid: float = 0.0                   # 0=뜸 1=감음
var _blink_t: float = 0.0
var _hit_flash_t: float = 0.0
var _die_t: float = 0.0
var _ripple_t: float = 0.0              # 그림 상태에서 탄 통과 파문("지금은 그림이다"의 시각 언어)
var _ripple_cd: float = 0.0
var _anchors: Array = []                # 실체화 후보 자리(각 데크·지면 가슴 높이)
var _anchor_idx: int = 0
var _prev_idx: int = -1                 # 직전에 실체화한 자리(다음 창 제외)
var _perch_idx: int = -1                # 2장 현재 도망 자리
var _perch_count: int = 0               # 2장 자리 이동 횟수(순서 회전용)
var _warp_from: Vector2 = Vector2.ZERO
var _warp_t: float = 0.0                # 워프 파문 연출 잔여
var _warp_after: String = ""            # 워프 착지 후 상태 · "flee" | "duel"
var _warp_prev: Vector2 = Vector2.ZERO  # 워프 직전 자리(redraw_requested prev)
var _volley_t: float = 0.0              # 3장 볼리 타이머
var _warp_cd: float = 0.0               # 3장 워프 타이머
var _warp_n: int = 0                    # 3장 워프 누적(홀수마다 무표시 위협 신호)

func setup(anchors: Array) -> void:
	_anchors = anchors

func _ready() -> void:
	# 그림 상태 = 콜리전 자체를 끈다 → 탄이 몸을 **통과**("실체 없음"이 총으로도 읽힘. 박히는데 무반응
	# 이라는 반려 2026-08-12). SOLID에서만 레이어 4(적) 켜져 탄이 박힌다.
	collision_layer = 0
	collision_mask = 0    # 물리 충돌 없음(부유)
	# 수류탄 폭발 경로(Grenade가 그룹 스캔) · "enemy" 그룹 밖 보스체용 그룹.
	add_to_group("boss_hittable")
	var col := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 34.0
	col.shape = shape
	add_child(col)
	z_index = 2
	_t2 = maxi(1, int(round(float(max_hp) * (1.0 - CH1_SHARE))))
	_t3 = maxi(1, int(round(float(max_hp) * (1.0 - CH1_SHARE - CH2_SHARE))))
	if _t3 >= _t2:
		_t3 = maxi(1, _t2 - 1)
	# 개시 응시 유예(2026-08-23 · 컷씬 개정) · 등장 직후엔 응시만. 잠복 진행도 유예만큼 늦게 시작
	# (_state_t 음수 시드). 유예 타이머는 자식 Timer(본체와 함께 사라짐 · pause 동안 정지 = 컷씬이
	# 떠 있는 동안은 유예가 흐르지 않는다). 첫 볼리 신호(무표시 위협 투입)만 유예 끝에 나간다.
	if intro_hold > 0.0:
		state = State.PHASED
		_state_t = -intro_hold
		_pick_near_anchor()
		var t := Timer.new()
		t.one_shot = true
		t.wait_time = maxf(0.05, intro_hold)
		t.timeout.connect(_intro_hold_end)
		t.timeout.connect(t.queue_free)
		add_child(t)
		t.start()
	else:
		_enter_phased()

func _intro_hold_end() -> void:
	if state != State.PHASED:
		return
	emit_signal("volley_started")

func is_hittable() -> bool:
	return state == State.SOLID

# ─── 1장 · 잠복 → 응시 → 모습 드러냄 ───

func _enter_phased() -> void:
	state = State.PHASED
	_state_t = 0.0
	collision_layer = 0
	_pick_near_anchor()
	emit_signal("volley_started")

# 닿는 자리 하나 · 플레이어 기준 같은 높이 대역(NEAR_Y_BAND)이 1순위, 그다음 한 층 차이(NEAR_Y_REACH),
# 그래도 모자라면 거리순. 직전 자리는 제외. 잠복 시작 때 잠정 선택(부유 목적지)하고, 예고 진입 순간
# 플레이어의 *그때* 위치로 다시 고른다(잠복 동안 옮겨 가면 "닿는 자리"가 달라진다 · 스모크 실측).
func _pick_near_anchor() -> void:
	if _anchors.is_empty():
		return
	var p := _find_player()
	if p == null:
		_anchor_idx = (_anchor_idx + 1) % _anchors.size()
		return
	var ref: Vector2 = p.global_position + Vector2(0.0, -30.0)
	var tier1: Array = []
	var tier2: Array = []
	var rest: Array = []
	for i in _anchors.size():
		if i == _prev_idx:
			continue
		var a: Vector2 = _anchors[i]
		var dx: float = absf(a.x - ref.x)
		var dy: float = absf(a.y - ref.y)
		if dx < NEAR_MIN_DX:
			continue
		if dy <= NEAR_Y_BAND and dx <= NEAR_MAX_DX:
			tier1.append(i)
		elif dy <= NEAR_Y_REACH and dx <= NEAR_MAX_DX:
			tier2.append(i)
		else:
			rest.append(i)
	var by_dist := func(ia: int, ib: int) -> bool:
		return (_anchors[ia] as Vector2).distance_to(ref) < (_anchors[ib] as Vector2).distance_to(ref)
	tier1.sort_custom(by_dist)
	tier2.sort_custom(by_dist)
	rest.sort_custom(by_dist)
	var pool: Array = tier1 + tier2 + rest
	if pool.is_empty():
		_anchor_idx = (_anchor_idx + 1) % _anchors.size()
		return
	# 가까운 둘 중 무작위(같은 자리 반복 회피 + 예측 불가).
	var n: int = mini(2, pool.size())
	_anchor_idx = int(pool[randi() % n])

# ─── 2장 · 도망 자리 ───

# 도망 자리 · 요원에게서 CH2_PERCH_MIN_DX 이상 떨어진 후보를 먼 순으로 모아 회차·이동 횟수로 회전
# (다회차 기억 §7 · "네가 외운 자리에는 없다"). 현재 자리는 제외. closer=true면 요원과 300~700px
# 사이의 후보(12s 무개방 구제 · 자리를 좁혀 창을 만들어 준다).
func _pick_perch(closer: bool = false) -> int:
	if _anchors.is_empty():
		return 0
	var p := _find_player()
	var ref: Vector2 = global_position if p == null else p.global_position + Vector2(0.0, -30.0)
	var pool: Array = []
	for i in _anchors.size():
		if i == _perch_idx:
			continue
		var dx: float = absf((_anchors[i] as Vector2).x - ref.x)
		if closer:
			if dx >= 300.0 and dx < CH2_PERCH_MIN_DX:
				pool.append(i)
		elif dx >= CH2_PERCH_MIN_DX:
			pool.append(i)
	if pool.is_empty():
		for i in _anchors.size():
			if i != _perch_idx:
				pool.append(i)
	var by_far := func(ia: int, ib: int) -> bool:
		return (_anchors[ia] as Vector2).distance_to(ref) > (_anchors[ib] as Vector2).distance_to(ref)
	pool.sort_custom(by_far)
	if closer:
		pool.reverse()
	# 상위 4곳 안에서 회전 · 매번 최원거리만 고르면 좌우 왕복 두 자리로 굳는다.
	var top: int = mini(4, pool.size())
	return int(pool[(memory_shift + _perch_count) % top])

func _begin_warp(to: Vector2, after: String) -> void:
	_warp_prev = global_position
	_warp_from = global_position
	_warp_t = 0.4
	global_position = to
	state = State.WARP
	_state_t = 0.0
	collision_layer = 0
	_warp_after = after
	_lid = 1.0

func _land_warp() -> void:
	match _warp_after:
		"flee":
			state = State.FLEE
			_state_t = 0.0
			collision_layer = 0
			emit_signal("redraw_requested", global_position, _warp_prev)
		"duel":
			state = State.SOLID
			_state_t = 0.0
			collision_layer = 4
			_warp_n += 1
			if _warp_n % 2 == 1:
				emit_signal("volley_started")
		_:
			state = State.FLEE
			_state_t = 0.0

func _player_in_reach() -> bool:
	var p := _find_player()
	if p == null:
		return false
	var ref: Vector2 = p.global_position + Vector2(0.0, -30.0)
	return absf(ref.x - global_position.x) <= CH2_REACH_DX and absf(ref.y - global_position.y) <= CH2_REACH_DY

# ─── 장 전환 ───

func _enter_chapter(ch: int) -> void:
	if ch <= chapter:
		return
	chapter = ch
	_hit_flash_t = 0.35
	emit_signal("chapter_changed", chapter)
	if chapter == 2:
		_perch_count = 0
		_perch_idx = _pick_perch()
		_begin_warp(_anchors[_perch_idx] if not _anchors.is_empty() else global_position, "flee")
	else:
		# 3장 · 닿는 자리로 워프해 상시 실체(잠복 폐지).
		_prev_idx = -1
		_pick_near_anchor()
		_volley_t = 0.0
		_warp_cd = 0.0
		_warp_n = 0
		_begin_warp(_anchors[_anchor_idx] if not _anchors.is_empty() else global_position, "duel")

# 하니스 전용 · 장을 강제 진입(HP를 그 장의 시작점으로 맞춘다). 실플레이 경로는 take_damage뿐.
func debug_force_chapter(ch: int) -> void:
	if ch == 2:
		hp = _t2
		_enter_chapter(2)
	elif ch == 3:
		hp = _t3
		_enter_chapter(3)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	_state_t += delta
	_hit_flash_t = maxf(0.0, _hit_flash_t - delta)
	_ripple_t = maxf(0.0, _ripple_t - delta)
	_ripple_cd = maxf(0.0, _ripple_cd - delta)
	_warp_t = maxf(0.0, _warp_t - delta)
	# 그림 상태에서 탄이 몸을 지나가면 파문 · "박히지 않고 통과한다"를 그 자리에서 보여준다.
	if state != State.SOLID and state != State.DYING and _ripple_cd <= 0.0:
		var btree := get_tree()
		if btree != null:
			for b in btree.get_nodes_in_group("player_bullet"):
				if b is Node2D and global_position.distance_to((b as Node2D).global_position) < 46.0:
					_ripple_t = 0.35
					_ripple_cd = 0.3
					break
	# 시선 추적 · 지연 lerp(반 박자 긴 응시) · 예고·실체 창에선 즉시 고정.
	var p := _find_player()
	if p != null:
		var want: Vector2 = (p.global_position - global_position).normalized() * 10.0
		var rate: float = 8.0 if (state == State.TELE or state == State.SOLID) else 2.0
		_gaze = _gaze.lerp(want, minf(1.0, delta * rate))
	match state:
		State.PHASED:
			_drift(delta)
			_update_blink(delta)
			if _state_t >= CH1_PHASED_DUR:
				state = State.TELE
				_state_t = 0.0
				# 예고 진입 · 플레이어의 지금 위치로 자리를 다시 고르고 그 자리로 스냅.
				# 워프 파문(이전 자리 소멸 링)으로 "옮겨 갔다"가 읽힌다.
				_pick_near_anchor()
				_prev_idx = _anchor_idx
				if not _anchors.is_empty():
					var dest: Vector2 = _anchors[_anchor_idx]
					if global_position.distance_to(dest) > 4.0:
						_warp_from = global_position
						_warp_t = 0.4
						global_position = dest
		State.TELE:
			_lid = maxf(0.0, _lid - delta * 6.0)   # 크게 뜬다 · 응시 예고
			var tele_dur: float = CH2_TELE_DUR if chapter == 2 else CH1_TELE_DUR
			if _state_t >= tele_dur:
				state = State.SOLID
				_state_t = 0.0
				collision_layer = 4   # 모습을 드러냄 · 이제 탄이 박힌다
				_fire_volley(3)
		State.SOLID:
			_lid = 0.0
			if chapter == 1:
				if _state_t >= CH1_SOLID_DUR:
					_enter_phased()
			elif chapter == 2:
				if _state_t >= CH2_SOLID_DUR:
					# 창 닫힘 · 다음 자리로 도망가며 다시 그린다.
					_perch_count += 1
					_perch_idx = _pick_perch()
					_begin_warp(_anchors[_perch_idx] if not _anchors.is_empty() else global_position, "flee")
			else:
				# 3장 결투 · 상시 실체 + 주기 볼리 + 주기 워프(짧은 무적).
				_volley_t += delta
				_warp_cd += delta
				if _volley_t >= CH3_VOLLEY_INTERVAL:
					_volley_t = 0.0
					_fire_volley(5)
				if _warp_cd >= CH3_WARP_INTERVAL:
					_warp_cd = 0.0
					_prev_idx = _anchor_idx
					_pick_near_anchor()
					_begin_warp(_anchors[_anchor_idx] if not _anchors.is_empty() else global_position, "duel")
		State.FLEE:
			_update_blink(delta)
			if _player_in_reach():
				state = State.TELE
				_state_t = 0.0
				emit_signal("window_opened")
			elif _state_t >= CH2_FLEE_TIMEOUT:
				# 무개방 구제 · 더 가까운 자리로 옮긴다(자리를 옮기는 것 자체가 다시 그리기).
				_perch_count += 1
				_perch_idx = _pick_perch(true)
				_begin_warp(_anchors[_perch_idx] if not _anchors.is_empty() else global_position, "flee")
		State.WARP:
			_lid = maxf(0.0, 1.0 - _state_t / WARP_DUR)
			var wd: float = WARP_DUR if chapter < 3 else 0.55
			if _state_t >= wd:
				_land_warp()
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
	# 완만한 깜빡임 · 3.6s 주기, 0.28s 동안 감았다 뜬다(점멸 아님).
	_blink_t += delta
	var cycle: float = fmod(_blink_t, 3.6)
	if cycle < 0.14:
		_lid = cycle / 0.14
	elif cycle < 0.28:
		_lid = 1.0 - (cycle - 0.14) / 0.14
	else:
		_lid = 0.0

# 모습을 드러내는 순간의 조준 볼리 · "볼 수 있는 창 = 위험한 창"의 리스크 교환. 1·2장 3연, 3장 5연 부채꼴.
func _fire_volley(count: int) -> void:
	var p := _find_player()
	if p == null:
		return
	SfxPlayer.play_at("enemy_patrol_fire", global_position)
	var base_dir: Vector2 = (p.global_position + Vector2(0, -24.0) - global_position).normalized()
	var spreads: Array = [-0.22, 0.0, 0.22]
	if count >= 5:
		spreads = [-0.36, -0.18, 0.0, 0.18, 0.36]
	for spread in spreads:
		var b := EnemyBullet.new()
		b.damage = 1
		b.velocity = base_dir.rotated(float(spread)) * EnemyBullet.BASE_SPEED * 0.9
		b.global_position = global_position + base_dir * 30.0
		get_parent().add_child(b)

func take_damage(amount: int, from_dir: int = 0) -> void:
	if state == State.DYING:
		return
	# 결정타 출처 기록(다회차 기억) · 총알 ±1 / 폭발(수류탄) 0. Enemy.take_damage와 같은 규약.
	last_hit_from_dir = from_dir
	if state != State.SOLID:
		# 그림 상태엔 실체가 없다 · 탄이 흘러나감(공정: 모습을 드러내는 창이 명확히 보임).
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -6.0)
		return
	# 장별 HP 몫 · 이번 장의 몫을 넘는 피해는 버린다(다음 장은 그 장의 시작점에서 시작).
	var floor_hp: int = 0
	if chapter == 1:
		floor_hp = _t2
	elif chapter == 2:
		floor_hp = _t3
	hp = maxi(floor_hp, hp - amount)
	_hit_flash_t = 0.25
	SfxPlayer.play_at("bullet_impact_enemy", global_position)
	SfxPlayer.play_at("boss_hurt", global_position, -2.0)
	if chapter == 1 and hp <= _t2:
		_enter_chapter(2)
	elif chapter == 2 and hp <= _t3:
		_enter_chapter(3)
	elif hp <= 0:
		state = State.DYING
		_die_t = 0.0
		collision_layer = 0
		emit_signal("defeated")

func _find_player() -> Node2D:
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("player")
	if nodes.size() == 0:
		return null
	return nodes[0] as Node2D

# ─── 렌더 · 유기적 눈(그로테스크 배제: 곡선·부드러운 발광·정갈한 도상) ───
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
	# 그림도(ghost) · 1이면 "구형 렌더로 그려진 그림"(스캔라인 짜임), 0이면 실체.
	var ghost: float = 0.0
	match state:
		State.PHASED:
			a = 0.42
			ghost = 1.0
		State.TELE:
			var tele_dur: float = CH2_TELE_DUR if chapter == 2 else CH1_TELE_DUR
			var k: float = clampf(_state_t / tele_dur, 0.0, 1.0)
			a = lerpf(0.42 if chapter == 1 else 0.75, 1.0, k)
			ghost = 1.0 - k
		State.SOLID:
			a = 1.0
		State.FLEE:
			# 도망 자리의 눈 · 실체보다 옅고 짜임이 남는다("아직 안 박힌다"가 멀리서도 읽힘).
			a = 0.75
			ghost = 0.55
		State.WARP:
			a = 0.55
			ghost = 0.8
		State.DYING:
			a = maxf(0.0, 1.0 - maxf(0.0, _die_t - 1.1) / 0.8)
	var open_amt: float = 1.0 - _lid
	if open_amt <= 0.02 and state != State.DYING:
		open_amt = 0.02
	var w: float = 46.0
	var h: float = 26.0 * open_amt
	# 뒤 글로우 · 부드러운 바이올렛 이중 타원.
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
		# 홍채/동공 · 시선(지연 추적) 오프셋. SOLID/TELE에선 동공 수축(응시).
		# 눈꺼풀과 함께 세로로 눌린다(transform y-스케일) · 감았는데 눈동자가 보이던 버그 수정
		# (사용자 2026-08-12): 개폐량 비율로 홍채·동공·하이라이트 전체를 압축.
		var iris_p: Vector2 = _gaze.limit_length(10.0)
		var pupil_r: float = 7.0
		if state == State.TELE:
			var tele_dur2: float = CH2_TELE_DUR if chapter == 2 else CH1_TELE_DUR
			pupil_r = lerpf(7.0, 4.2, clampf(_state_t / tele_dur2, 0.0, 1.0))
		elif state == State.SOLID:
			pupil_r = 4.2
		var squash: float = clampf(h / 26.0, 0.02, 1.0)
		draw_set_transform(iris_p, 0.0, Vector2(1.0, squash))
		draw_circle(Vector2.ZERO, 15.0, Color(0.58, 0.34, 0.88, 0.9 * a))
		draw_circle(Vector2.ZERO, 15.0 * 0.72, Color(0.42, 0.24, 0.66, 0.95 * a))
		draw_circle(Vector2.ZERO, pupil_r, Color(0.05, 0.03, 0.09, a))
		draw_circle(Vector2(-3.5, -3.5), 2.2, Color(1.0, 1.0, 1.0, 0.8 * a))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# 그림 상태 = 스캔라인 짜임 · "지금은 그림"이 시각 언어로 읽힌다. 모습을 드러내며(TELE→SOLID)
		# 짜임이 걷히고 몸이 꽉 찬다. 텍스트 라벨 없이 상태 전달("실체 없음" 라벨 작위적 반려 2026-08-13).
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
	# 실체(피격 가능) 링 · SOLID에서만 완만히 맥동. 3장은 상시라 링도 상시.
	if state == State.SOLID:
		var ring_a: float = 0.35 + 0.15 * sin(_t * 3.0)
		draw_arc(Vector2.ZERO, 52.0, 0.0, TAU, 40, Color(0.92, 0.80, 1.0, ring_a), 2.0, true)
	# 2장 도망 자리 · 사거리 표시 없음(공간 항법은 요원의 판단) · 대신 눈 아래 얇은 받침선으로
	# "여기 앉아 있다"를 알린다.
	if state == State.FLEE:
		draw_line(Vector2(-30.0, 30.0), Vector2(30.0, 30.0), Color(0.72, 0.42, 1.0, 0.35), 2.0)
	# 피격 플래시 · 확장 링(짧고 국소적).
	if _hit_flash_t > 0.0:
		var k: float = 1.0 - _hit_flash_t / 0.25
		draw_arc(Vector2.ZERO, 40.0 + 30.0 * k, 0.0, TAU, 36, Color(1.0, 1.0, 1.0, 0.7 * (1.0 - k)), 2.5, true)
	# 실체화 스냅 · SOLID 진입 순간 밝은 링이 퍼진다("지금부터 박힌다").
	if state == State.SOLID and _state_t < 0.35:
		var sk: float = _state_t / 0.35
		draw_arc(Vector2.ZERO, 40.0 + 26.0 * sk, 0.0, TAU, 40, Color(0.95, 0.85, 1.0, 0.8 * (1.0 - sk)), 3.0, true)
	# 탄 통과 파문 · 그림 상태에서 탄이 몸을 지나간 흔적(박히지 않았음을 그 자리에서 보여줌).
	if _ripple_t > 0.0:
		var rk: float = 1.0 - _ripple_t / 0.35
		draw_arc(Vector2.ZERO, 30.0 + 42.0 * rk, 0.0, TAU, 36, Color(0.72, 0.42, 1.0, 0.38 * (1.0 - rk)), 2.0, true)
