extends CharacterBody2D

signal killed(at_position: Vector2)

enum EnemyType { PATROL, SNIPER, DRONE, BOMBER, SHIELD }
enum PatrolState { ROAMING, FIRING, TELEGRAPH, CHARGING, RECOVERING }
enum BomberState { ROAMING, STALKING, ARMING }

@export var enemy_type: int = EnemyType.PATROL
# 좁은 발판에 spawn돼도 떨어지지 않도록 보수적으로 작게.
# 발판 가장자리 감지 raycast가 우선 — patrol_range는 보조 한계만.
@export var patrol_range: float = 90.0
@export var hp: int = 2
@export var harmless: bool = false

const GRAVITY: float = 1400.0
const TOUCH_DAMAGE: int = 1
const TOUCH_COOLDOWN: float = 0.6

# Patrol — 평소 순찰 + 중거리 사격 + 근접 시 텔레그래프 후 돌진
const PATROL_SPEED: float = 70.0
const PATROL_CHARGE_SPEED: float = 280.0
const PATROL_DETECT_X: float = 260.0
const PATROL_DETECT_Y: float = 70.0
const PATROL_TELEGRAPH: float = 0.45
const PATROL_CHARGE_DURATION: float = 0.6
const PATROL_RECOVERY: float = 1.0
# 사격 — DETECT 범위 안 + CHARGE 범위 밖일 때 멈춰서 발사. 근접하면 돌진으로 전환.
# 사용자 피드백: 돌진이 메인이라 거의 항상 돌진으로 가도록 — DETECT 260의 92% 지점.
# 사격 윈도우는 240~260px 좁게 남겨두어 가끔 한두 발만 쏘게.
const PATROL_CHARGE_RANGE: float = 240.0
const PATROL_FIRE_INTERVAL: float = 1.5
const PATROL_FIRE_AIM_TIME: float = 0.7  # 2026-06-06 사용자 피드백 — 1.0은 너무 느슨. 0.7로 살짝 조여 인식/반응을 빠르게 (Sniper와 동일). 여전히 텔레그래프 인지 + 회피 윈도우는 남김.
# 사격은 비슷한 높이의 표적에만 — 높이 차가 이보다 크면 사격 안 함(2026-06-14). 감시탑 입구처럼
# 플레이어가 아래서 좁은 발판으로 등반 중일 때 위 정찰병이 *내려쏘는* 불합리(점프 최고점에서만 겨우
# 반격 가능한데 한두 대 맞기 쉬움)를 해소. 근접 돌진은 그대로라 같은 높이로 붙으면 여전히 위협.
const PATROL_FIRE_MAX_DY: float = 48.0
const PATROL_BULLET_DAMAGE: int = 1

# Bomber — 천천히 접근 + 근접 시 자폭
const BOMBER_SPEED: float = 50.0
const BOMBER_DETECT_X: float = 360.0
const BOMBER_DETECT_Y: float = 90.0
const BOMBER_ARM_RANGE: float = 90.0   # 이 거리에 들어오면 카운트다운 시작
const BOMBER_ARM_TIME: float = 0.7     # 카운트다운 길이
const BOMBER_BLAST_RADIUS: float = 70.0
const BOMBER_BLAST_DAMAGE: int = 1

# Shield — 정면 피격 무효, 측면/후면만 통하는 보병
const SHIELD_SPEED: float = 55.0
const SHIELD_DETECT_X: float = 180.0
const SHIELD_DETECT_Y: float = 60.0
const SHIELD_MELEE_RANGE: float = 42.0
const SHIELD_TOUCH_DAMAGE: int = 1
const SHIELD_TOUCH_COOLDOWN: float = 0.8

# Sniper — 시야가 트여 있을 때만 발사
const SNIPER_FIRE_INTERVAL: float = 2.6
const SNIPER_AIM_TIME: float = 0.7
# 저격수다운 사거리 — 플레이어 총알 사거리(495px)보다 충분히 길게.
# 플레이어가 사거리 안에 들어오면 LoS 체크 후 발사. 엄폐가 보일 만큼 길어야 진짜 저격수.
const SNIPER_RANGE: float = 820.0
# 측면 단독 둥지(회피 전용) 저격수 — 등반/회피 맵(watchtower/rooftops/cooling)에서 아래를 너무 쉽게
# 쏴 등반이 막힌다는 피드백. 둥지 저격수만 사거리·조준·발사를 완화해 "한 둥지씩, 텔레그래프 보고 피하며"
# 오르게 한다. 전투 맵(subway/datacenter) 저격수는 avoid_only 미부착이라 그대로(영향 없음).
# 모래주머니/ㄴ자 발판으로는 하향 사격을 못 막는다(탄이 발판 밑으로 빠짐) → 압박 수치로 조정.
const NEST_SNIPER_RANGE: float = 700.0
const NEST_SNIPER_AIM_TIME: float = 1.7    # 텔레그래프(붉은 조준선)=조준→발사 시간. 길게 잡아 등반 중 피할 여유.
const NEST_SNIPER_INTERVAL_MUL: float = 1.5  # 발사 간격 1.5배(2.6→3.9s) — 등반 중 피탄 횟수↓

# Drone — 머리 위 호버 후 폭탄 투하
const DRONE_SPEED: float = 110.0
# hover 거리 — 플레이어 머리 위 220px. 기존 -180은 플레이어가 플랫폼 바로
# 아래에 있을 때 드론이 그 플랫폼에 시각적으로 붙어 보였음.
const DRONE_HOVER_OFFSET_Y: float = -220.0
const DRONE_BOMB_INTERVAL: float = 2.5
const DRONE_BOMB_X_BAND: float = 90.0
const DRONE_BOMB_Y_MIN: float = 80.0
const DRONE_BOMB_Y_MAX: float = 240.0

# 도감 — 화면 안에 들어와야 트리거되도록 거리/높이 제한
const ENCOUNTER_X_LIMIT: float = 480.0
const ENCOUNTER_Y_LIMIT: float = 280.0

var origin_x: float = 0.0
var dir: int = 1
var touch_cd: float = 0.0
var dead: bool = false

# 가장자리 감지 — 발 앞쪽에 ground/platform이 없으면 떨어지지 않게 dir 반전.
# 수직 맵에서 적이 작은 발판에서 떨어져 바닥에 모이는 문제 방지.
# 일반 ROAMING은 36px 앞을 보고, 빠른 상태(CHARGING/STALKING)는 더 멀리(80px) 봐야 안전.
const EDGE_LOOKAHEAD_X: float = 36.0
const EDGE_LOOKAHEAD_X_FAST: float = 80.0
const EDGE_LOOKAHEAD_Y: float = 80.0
const EDGE_FLIP_COOLDOWN: float = 0.15
var edge_flip_cd: float = 0.0

func _has_ground_ahead(check_dir: int, lookahead: float = EDGE_LOOKAHEAD_X) -> bool:
	# 발 앞 lookahead 위치에서 아래 EDGE_LOOKAHEAD_Y 안에 ground/platform이 있는가.
	# 발판 위에 있을 때만 의미 있음 — 공중에선 호출하지 말 것.
	var space := get_world_2d().direct_space_state
	var origin: Vector2 = global_position + Vector2(float(check_dir) * lookahead, -6.0)
	var target: Vector2 = origin + Vector2(0.0, EDGE_LOOKAHEAD_Y)
	var query := PhysicsRayQueryParameters2D.create(origin, target)
	query.collision_mask = 1  # ground + platform 레이어
	query.exclude = [self]
	var hit: Dictionary = space.intersect_ray(query)
	return not hit.is_empty()

var patrol_state: int = PatrolState.ROAMING
var patrol_state_timer: float = 0.0
# FIRING phase 구분 — true면 조준 중(timer가면 발사), false면 쿨다운 중(timer가면 다시 조준 시작).
var patrol_fire_armed: bool = false

var fire_timer: float = 0.0
var aim_line: Line2D
var aim_los_clear: bool = false

var drone_bomb_cd: float = 0.0

# 드론 호버 positional loop SFX — listener는 Player.AudioListener2D.
# 사용자 피드백(2026-05-16 #2): 거리 변화가 잘 안 느껴지고, 가까이 와도 별로 안 커짐.
# 원인: base가 너무 낮아 가까이서도 muted, attenuation 곡선이 완만(1.6)해 falloff 미묘.
# 조정: base 좀 올리고(가까이 잘 들리게), attenuation 가파르게(거리 변화 뚜렷), max_dist 키움(멀리서부터 미세하게 들림).
const DRONE_HOVER_VOLUME_DB: float = -10.0       # 거리 0 기준 base
const DRONE_HOVER_MAX_DIST: float = 1100.0       # 이 너머는 무음 — 화면 폭 1280의 86%
const DRONE_HOVER_ATTENUATION: float = 2.0       # 클수록 가파른 falloff — 가까이 vs 멀리 차이 극적
var hover_audio: AudioStreamPlayer2D = null

var bomber_state: int = BomberState.ROAMING
var bomber_state_timer: float = 0.0

# 방패병 정면 회전 지연 — 한 번 돈 뒤 일정 시간 다시 못 돌게.
# 대시 쿨다운(0.7s)보다 충분히 길어야 측면/후면 잡고 돌아갈 시간이 생김.
# 사용자 후속 피드백: 좀 더 늘려달라 → 2.0 → 2.8.
const SHIELD_DIR_LOCK_DURATION: float = 2.8
var shield_dir_lock_timer: float = 0.0

var encountered: bool = false
var visual: Node2D

func _ready() -> void:
	add_to_group("enemy")
	origin_x = global_position.x
	match enemy_type:
		EnemyType.PATROL:
			hp = 2
			visual = CharacterArt.build_patrol(self)
			# 사용자: patrol 크기 키우기 — 콜리전과 함께 시각도 1.3배.
			if visual != null:
				visual.scale = Vector2(1.3, 1.3)
		EnemyType.SNIPER:
			hp = 1
			visual = CharacterArt.build_sniper(self)
		EnemyType.DRONE:
			hp = 1
			visual = CharacterArt.build_drone(self)
			# 사용자: drone 크기 키우기 — 콜리전과 함께 시각도 1.3배 (피드백: 드론이 잘 안 맞음).
			if visual != null:
				visual.scale = Vector2(1.3, 1.3)
			_setup_drone_hover_audio()
		EnemyType.BOMBER:
			hp = 1
			visual = CharacterArt.build_bomber(self)
		EnemyType.SHIELD:
			hp = 3
			visual = CharacterArt.build_shield(self)
			# 사용자: shield 크기 키우기 — 콜리전과 함께 시각도 1.4배.
			if visual != null:
				visual.scale = Vector2(1.4, 1.4)
	fire_timer = _sniper_interval()
	drone_bomb_cd = 1.2  # 스폰 직후 즉시 폭격 방지
	# 지면형 적은 spawn pos가 발판 살짝 위/아래여도 발판 top에 정확히 붙도록 snap.
	# (drone은 공중 상시라 snap 안 함. 첫 frame 뒤로 미루기 위해 call_deferred)
	if enemy_type != EnemyType.DRONE:
		call_deferred("_snap_to_floor")

func _snap_to_floor() -> void:
	if not is_inside_tree():
		return
	var space := get_world_2d().direct_space_state
	var origin: Vector2 = global_position + Vector2(0.0, -20.0)
	var target: Vector2 = global_position + Vector2(0.0, 240.0)
	var query := PhysicsRayQueryParameters2D.create(origin, target)
	query.collision_mask = 1
	query.exclude = [self]
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		var ground_y: float = float(hit.position.y)
		# 발 위치(global_position.y)가 ground top 바로 위 1px 안에 들어오게.
		global_position.y = ground_y - 1.0
		origin_x = global_position.x

# Risk 3 루트에서는 적이 더 빨리 반응한다.
# 수치는 보수적으로 잡았으니 플레이테스트 후 조정 필요 (상의 항목).
# VEIL 시야 마킹용 — 이 적이 지금 공격을 텔레그래프 중인가(조준/돌진 준비/폭탄 무장).
# VeilSight가 이 값으로 마커를 경고색으로 펄스시킨다("VEIL이 위험을 미리 짚어준다").
func veil_is_telegraphing() -> bool:
	if dead:
		return false
	if aim_line != null:  # sniper/patrol 원거리 조준 중
		return true
	match enemy_type:
		EnemyType.PATROL:
			return patrol_state == PatrolState.TELEGRAPH or patrol_state == PatrolState.CHARGING
		EnemyType.BOMBER:
			return bomber_state == BomberState.ARMING
	return false

func _telegraph_time() -> float:
	return PATROL_TELEGRAPH * (0.6 if GameState.is_high_risk() else 1.0)

func _patrol_fire_interval() -> float:
	# Sniper와 동일한 0.7 보정 — Risk 3에서 사격이 더 잦음.
	return PATROL_FIRE_INTERVAL * (0.7 if GameState.is_high_risk() else 1.0)

func _sniper_interval() -> float:
	var base: float = SNIPER_FIRE_INTERVAL * (0.7 if GameState.is_high_risk() else 1.0)
	if _is_nest_sniper():
		base *= NEST_SNIPER_INTERVAL_MUL
	return base

# 측면 단독 둥지(회피 전용) 저격수 식별 — Stage가 spawn 직후 avoid_only 메타를 붙인다.
func _is_nest_sniper() -> bool:
	return has_meta("avoid_only")

# 둥지 저격수는 사거리·조준 텔레그래프를 완화 — 한 둥지씩 상대하며 텔레그래프 보고 피해 오르게.
func _eff_sniper_range() -> float:
	return NEST_SNIPER_RANGE if _is_nest_sniper() else SNIPER_RANGE

func _eff_sniper_aim_time() -> float:
	return NEST_SNIPER_AIM_TIME if _is_nest_sniper() else SNIPER_AIM_TIME

func _drone_bomb_interval() -> float:
	return DRONE_BOMB_INTERVAL * (0.7 if GameState.is_high_risk() else 1.0)

func _enemy_id() -> String:
	match enemy_type:
		EnemyType.PATROL: return "patrol"
		EnemyType.SNIPER: return "sniper"
		EnemyType.DRONE: return "drone"
		EnemyType.BOMBER: return "bomber"
		EnemyType.SHIELD: return "shield"
	return ""

func _flip_visual(facing_left: bool) -> void:
	if visual != null:
		visual.scale.x = -1.0 if facing_left else 1.0

func _physics_process(delta: float) -> void:
	if dead or not is_inside_tree():
		return
	if touch_cd > 0.0:
		touch_cd -= delta
	_check_first_encounter()
	match enemy_type:
		EnemyType.PATROL:
			_tick_patrol(delta)
		EnemyType.SNIPER:
			_tick_sniper(delta)
		EnemyType.DRONE:
			_tick_drone(delta)
		EnemyType.BOMBER:
			_tick_bomber(delta)
		EnemyType.SHIELD:
			_tick_shield(delta)
	# bomber는 자체 폭발만 — 평상시 근접 데미지 없음
	if enemy_type == EnemyType.BOMBER:
		return
	_check_touch_player()

# ─── 도감 첫 조우 ───────────────────────────────────────────

func _check_first_encounter() -> void:
	if encountered or harmless:
		return
	if BestiaryOverlay.is_active():
		return
	var p := _find_player()
	if p == null:
		return
	var dx: float = abs(p.global_position.x - global_position.x)
	var dy: float = abs(p.global_position.y - global_position.y)
	if dx > ENCOUNTER_X_LIMIT or dy > ENCOUNTER_Y_LIMIT:
		return
	var stage_node := get_tree().get_first_node_in_group("stage")
	if stage_node == null:
		return
	encountered = true
	var id: String = _enemy_id()
	if not GameState.mark_enemy_seen(id):
		return  # 이미 본 적이라 카드 안 띄움
	BestiaryOverlay.show_card(stage_node, id)

# ─── Patrol ─────────────────────────────────────────────────

func _tick_patrol(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, 1100.0)
	else:
		velocity.y = 0.0

	var p := _find_player()

	match patrol_state:
		PatrolState.ROAMING:
			velocity.x = float(dir) * PATROL_SPEED
			if global_position.x > origin_x + patrol_range:
				dir = -1
			elif global_position.x < origin_x - patrol_range:
				dir = 1
			if is_on_wall():
				dir = -dir
			# 발판 가장자리 감지 — 떨어지지 않게 진행 방향에 ground 없으면 반전
			if edge_flip_cd > 0.0:
				edge_flip_cd -= delta
			elif is_on_floor() and not _has_ground_ahead(dir):
				dir = -dir
				edge_flip_cd = EDGE_FLIP_COOLDOWN
				velocity.x = float(dir) * PATROL_SPEED
			if not harmless and p != null and _player_in_charge_range(p):
				dir = 1 if p.global_position.x > global_position.x else -1
				velocity.x = 0.0
				# 근접이면 돌진, 비슷한 높이의 중거리면 사격. 높이 차가 크면(등반 중) 사격하지 않고 순찰 유지.
				var dist_p: float = global_position.distance_to(p.global_position)
				if dist_p <= PATROL_CHARGE_RANGE:
					patrol_state = PatrolState.TELEGRAPH
					patrol_state_timer = _telegraph_time()
				elif absf(p.global_position.y - global_position.y) <= PATROL_FIRE_MAX_DY:
					patrol_state = PatrolState.FIRING
					patrol_fire_armed = true
					patrol_state_timer = PATROL_FIRE_AIM_TIME
		PatrolState.FIRING:
			velocity.x = 0.0
			# 플레이어 방향 추적은 조준/쿨다운 둘 다에서 유지.
			if p != null:
				dir = 1 if p.global_position.x > global_position.x else -1
			patrol_state_timer -= delta
			# 조준 phase 시각 효과 — 텔레그래프(빨강)와 구분되는 노란 점멸.
			if patrol_fire_armed and visual != null:
				if int(patrol_state_timer * 10.0) % 2 == 0:
					visual.modulate = Color(1.4, 1.4, 0.85)
				else:
					visual.modulate = Color(1, 1, 1)
			if patrol_state_timer <= 0.0:
				if visual != null:
					visual.modulate = Color(1, 1, 1)
				if patrol_fire_armed:
					# 발사 순간
					if p != null and not harmless:
						_patrol_fire(p)
					patrol_fire_armed = false
					patrol_state_timer = _patrol_fire_interval()
				else:
					# 쿨다운 끝 — 상황에 따라 다음 행동 결정.
					if p == null or not _player_in_charge_range(p):
						patrol_state = PatrolState.ROAMING
					elif global_position.distance_to(p.global_position) <= PATROL_CHARGE_RANGE:
						patrol_state = PatrolState.TELEGRAPH
						patrol_state_timer = _telegraph_time()
					else:
						patrol_fire_armed = true
						patrol_state_timer = PATROL_FIRE_AIM_TIME
		PatrolState.TELEGRAPH:
			velocity.x = 0.0
			patrol_state_timer -= delta
			# 머리/몸 빨갛게 깜빡 — 돌진 예고
			if visual != null:
				if int(patrol_state_timer * 10.0) % 2 == 0:
					visual.modulate = Color(1.6, 0.55, 0.55)
				else:
					visual.modulate = Color(1, 1, 1)
			if patrol_state_timer <= 0.0:
				if visual != null:
					visual.modulate = Color(1, 1, 1)
				patrol_state = PatrolState.CHARGING
				patrol_state_timer = PATROL_CHARGE_DURATION
		PatrolState.CHARGING:
			velocity.x = float(dir) * PATROL_CHARGE_SPEED
			patrol_state_timer -= delta
			# 가장자리 도달 시 즉시 RECOVERING — 빠른 속도라 lookahead 80px
			var charge_edge_fall: bool = is_on_floor() and not _has_ground_ahead(dir, EDGE_LOOKAHEAD_X_FAST)
			if is_on_wall() or charge_edge_fall or patrol_state_timer <= 0.0:
				patrol_state = PatrolState.RECOVERING
				patrol_state_timer = PATROL_RECOVERY
				velocity.x = 0.0
		PatrolState.RECOVERING:
			velocity.x = 0.0
			patrol_state_timer -= delta
			if patrol_state_timer <= 0.0:
				origin_x = global_position.x  # 돌진 후 새 위치 기준으로 순찰
				patrol_state = PatrolState.ROAMING

	_flip_visual(dir < 0)
	move_and_slide()

func _player_in_charge_range(p: Node2D) -> bool:
	var dx: float = abs(p.global_position.x - global_position.x)
	var dy: float = abs(p.global_position.y - global_position.y)
	return dx <= PATROL_DETECT_X and dy <= PATROL_DETECT_Y

func _patrol_fire(p: Node2D) -> void:
	SfxPlayer.play_at("enemy_patrol_fire", global_position)
	var b := EnemyBullet.new()
	b.damage = PATROL_BULLET_DAMAGE
	# 2026-06-05 사용자 피드백 — 발사가 수평이 아니라 살짝 비스듬해서 옆으로 날아옴.
	# Patrol은 sniper가 아니므로 정밀 조준 안 함. 그냥 자기 dir 방향으로 수평 발사.
	# 플레이어가 위/아래에 있으면 점프/숙임으로 회피 가능 — 정찰병 정체성에 맞음.
	var muzzle_y: float = -18.0
	b.velocity = Vector2(float(dir), 0.0) * EnemyBullet.BASE_SPEED
	b.global_position = global_position + Vector2(float(dir) * 8.0, muzzle_y)
	get_parent().add_child(b)

# ─── Sniper ─────────────────────────────────────────────────

func _tick_sniper(delta: float) -> void:
	velocity.x = 0.0
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, 1100.0)
	else:
		velocity.y = 0.0
	move_and_slide()
	var p := _find_player()
	if p == null:
		_clear_aim()
		return
	var dist: float = global_position.distance_to(p.global_position)
	if dist > _eff_sniper_range():
		_clear_aim()
		fire_timer = _sniper_interval()
		return

	fire_timer -= delta
	if fire_timer < _eff_sniper_aim_time():
		aim_los_clear = _has_line_of_sight(p)
		if aim_los_clear:
			if aim_line == null:
				_start_aim()
			_update_aim()
		else:
			# 시야 끊김 → 발사 취소, 조준 다시 처음부터
			_clear_aim()
			fire_timer = _sniper_interval()

	if fire_timer <= 0.0:
		fire_timer = _sniper_interval()
		if aim_los_clear:
			_fire_at_player()
		_clear_aim()
	queue_redraw()  # 사거리 링(_draw) 갱신 — 플레이어 접근/조준 상태 반영

func _has_line_of_sight(p: Node2D) -> bool:
	var space := get_world_2d().direct_space_state
	var from: Vector2 = global_position + Vector2(0, -20)
	var to: Vector2 = p.global_position + Vector2(0, -28)
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	query.exclude = [get_rid()]
	var result: Dictionary = space.intersect_ray(query)
	return result.is_empty()

func _start_aim() -> void:
	aim_line = Line2D.new()
	aim_line.width = 1.0
	aim_line.default_color = Color(1.0, 0.30, 0.30, 0.55)
	aim_line.z_index = 1
	get_parent().add_child(aim_line)
	SfxPlayer.play_at("enemy_sniper_charge", global_position)

func _update_aim() -> void:
	if aim_line == null:
		return
	var p := _find_player()
	if p == null:
		return
	aim_line.clear_points()
	aim_line.add_point(global_position + Vector2(0, -20))
	aim_line.add_point(p.global_position + Vector2(0, -28))

func _clear_aim() -> void:
	if aim_line != null:
		aim_line.queue_free()
		aim_line = null

# ─── Drone ──────────────────────────────────────────────────

func _tick_drone(delta: float) -> void:
	if drone_bomb_cd > 0.0:
		drone_bomb_cd -= delta
	var player := _find_player()
	if player == null:
		return
	var dx: float = abs(player.global_position.x - global_position.x)
	var dy_above: float = player.global_position.y - global_position.y  # 양수면 드론이 위
	var hover_ok: bool = dx <= DRONE_BOMB_X_BAND and dy_above >= DRONE_BOMB_Y_MIN and dy_above <= DRONE_BOMB_Y_MAX
	# 호버 SFX는 AudioStreamPlayer2D loop라 매 tick 별도 트리거 불필요.
	# 슬라이더 볼륨만 동기화.
	_sync_hover_audio_volume()
	if hover_ok and drone_bomb_cd <= 0.0 and not harmless:
		velocity = Vector2.ZERO
		_drop_bomb()
		drone_bomb_cd = _drone_bomb_interval()
	else:
		var target: Vector2 = player.global_position + Vector2(0, DRONE_HOVER_OFFSET_Y)
		var to: Vector2 = target - global_position
		if to.length() > 6.0:
			velocity = to.normalized() * DRONE_SPEED
			_flip_visual((player.global_position.x - global_position.x) < 0.0)
		else:
			velocity = Vector2.ZERO
	move_and_slide()

func _drop_bomb() -> void:
	SfxPlayer.play_at("enemy_drone_drop", global_position)
	var b := Bomb.new()
	b.global_position = global_position + Vector2(0, 8)
	get_parent().add_child(b)

# 드론 spawn 시 한 번만 호출 — AudioStreamPlayer2D를 자식으로 부착하고 loop 재생 시작.
# 노드가 free될 때 자식 audio도 함께 정리되므로 별도 cleanup 불필요.
func _setup_drone_hover_audio() -> void:
	var path: String = "res://assets/sfx/enemy_drone_hover.mp3"
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream == null:
		return
	# SfxPlayer는 단발 SFX라 loop=false로 강제하지만, 호버는 loop가 정체성.
	# duplicate() 안 하면 다른 드론들과 stream 인스턴스 공유 — Godot에서는 same stream이
	# 동시 재생되어도 문제 없지만 loop 플래그 변경이 공유될 수 있어 안전하게 복제.
	stream = stream.duplicate()
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	hover_audio = AudioStreamPlayer2D.new()
	hover_audio.stream = stream
	hover_audio.bus = "Master"
	hover_audio.max_distance = DRONE_HOVER_MAX_DIST
	hover_audio.attenuation = DRONE_HOVER_ATTENUATION
	hover_audio.autoplay = true
	add_child(hover_audio)
	_sync_hover_audio_volume()

func _sync_hover_audio_volume() -> void:
	if hover_audio == null:
		return
	# 슬라이더 0이면 -80dB로 완전 무음. 그 외엔 DRONE_HOVER_VOLUME_DB + linear_to_db(slider).
	var v: float = clampf(GameState.sfx_volume, 0.0, 1.0)
	if v <= 0.001:
		hover_audio.volume_db = -80.0
	else:
		hover_audio.volume_db = DRONE_HOVER_VOLUME_DB + linear_to_db(v)

# ─── Bomber ─────────────────────────────────────────────────
# 평소엔 천천히 좌우 순찰. 플레이어가 감지 범위에 들어오면 추적.
# 근거리(BOMBER_ARM_RANGE)에 닿으면 점멸하며 자폭 카운트다운 시작 — 끝나면 폭발.
# HP 1로 사격 한 번에 처치 가능 (멀리서 잡는 게 정답).

func _tick_bomber(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, 1100.0)
	else:
		velocity.y = 0.0

	var p := _find_player()

	match bomber_state:
		BomberState.ROAMING:
			velocity.x = float(dir) * BOMBER_SPEED
			if global_position.x > origin_x + patrol_range:
				dir = -1
			elif global_position.x < origin_x - patrol_range:
				dir = 1
			if is_on_wall():
				dir = -dir
			# 발판 가장자리 감지
			if edge_flip_cd > 0.0:
				edge_flip_cd -= delta
			elif is_on_floor() and not _has_ground_ahead(dir):
				dir = -dir
				edge_flip_cd = EDGE_FLIP_COOLDOWN
				velocity.x = float(dir) * BOMBER_SPEED
			if not harmless and p != null and _bomber_in_detect_range(p):
				bomber_state = BomberState.STALKING
		BomberState.STALKING:
			if p == null:
				bomber_state = BomberState.ROAMING
			else:
				dir = 1 if p.global_position.x > global_position.x else -1
				velocity.x = float(dir) * BOMBER_SPEED * 1.4
				if is_on_wall():
					velocity.x = 0.0
				# 가장자리 — STALKING 빠름 → fast lookahead
				if is_on_floor() and not _has_ground_ahead(dir, EDGE_LOOKAHEAD_X_FAST):
					velocity.x = 0.0
				var d2: float = global_position.distance_to(p.global_position)
				if d2 <= BOMBER_ARM_RANGE:
					bomber_state = BomberState.ARMING
					bomber_state_timer = BOMBER_ARM_TIME
					velocity.x = 0.0
					SfxPlayer.play_at("enemy_bomber_beep", global_position)
				elif not _bomber_in_detect_range(p):
					bomber_state = BomberState.ROAMING
		BomberState.ARMING:
			velocity.x = 0.0
			bomber_state_timer -= delta
			# 깜빡임 — 시간이 줄수록 빨라짐
			if visual != null:
				var freq: float = lerp(6.0, 18.0, 1.0 - bomber_state_timer / BOMBER_ARM_TIME)
				if int(bomber_state_timer * freq) % 2 == 0:
					visual.modulate = Color(1.8, 0.45, 0.45)
				else:
					visual.modulate = Color(1, 1, 1)
			if bomber_state_timer <= 0.0:
				_bomber_explode()
				return

	_flip_visual(dir < 0)
	move_and_slide()

func _bomber_in_detect_range(p: Node2D) -> bool:
	var dx: float = abs(p.global_position.x - global_position.x)
	var dy: float = abs(p.global_position.y - global_position.y)
	return dx <= BOMBER_DETECT_X and dy <= BOMBER_DETECT_Y

func _bomber_explode() -> void:
	if dead:
		return
	SfxPlayer.play_at("enemy_bomber_explode", global_position)
	# 폭발 데미지 — 반경 안의 플레이어에게
	var p := _find_player()
	if p != null and global_position.distance_to(p.global_position) <= BOMBER_BLAST_RADIUS:
		if p.has_method("take_hit"):
			p.take_hit(BOMBER_BLAST_DAMAGE)
	# 시각 효과
	var blast := Polygon2D.new()
	blast.color = Color(1.0, 0.55, 0.30, 0.85)
	blast.z_index = 3
	var pts: Array = []
	for i in 24:
		var a: float = float(i) * TAU / 24.0
		pts.append(Vector2(cos(a) * BOMBER_BLAST_RADIUS, sin(a) * BOMBER_BLAST_RADIUS))
	blast.polygon = PackedVector2Array(pts)
	blast.global_position = global_position
	blast.scale = Vector2(0.2, 0.2)
	get_parent().add_child(blast)
	var tw := blast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2(1.0, 1.0), 0.25)
	tw.tween_property(blast, "modulate", Color(1, 1, 1, 0), 0.45)
	tw.chain().tween_callback(blast.queue_free)
	_die()

# ─── Shield ─────────────────────────────────────────────────
# 정면(facing dir)에서 오는 사격은 방패가 막는다. 측면/후면에서만 데미지 통함.
# 근접 시 짧은 휘두르기 — 정면 일정 거리 안의 플레이어에게 1뎀.
# HP 3 — 단단하지만 측면 잡으면 빠르게 처치 가능.

func _tick_shield(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, 1100.0)
	else:
		velocity.y = 0.0

	if shield_dir_lock_timer > 0.0:
		shield_dir_lock_timer -= delta

	var p := _find_player()

	# 방패병 정체성 = 정면으로 막기. 플레이어 방향으로 정면을 맞추되, 회전에 지연을 둠.
	# 한 번 돈 뒤 SHIELD_DIR_LOCK_DURATION 동안 잠금 → 측면/후면 사격 윈도우 확보.
	if not harmless and p != null:
		var desired_dir: int = 1 if p.global_position.x > global_position.x else -1
		if desired_dir != dir and shield_dir_lock_timer <= 0.0:
			dir = desired_dir
			shield_dir_lock_timer = SHIELD_DIR_LOCK_DURATION

	# 근접 시에만 추격 이동. 그 외에는 좁은 범위 patrol.
	if not harmless and p != null and _shield_player_nearby(p):
		var d2: float = global_position.distance_to(p.global_position)
		if d2 > SHIELD_MELEE_RANGE * 0.8:
			velocity.x = float(dir) * SHIELD_SPEED
		else:
			velocity.x = 0.0
	else:
		# 평소 순찰. dir은 player 방향으로 잠겨 있으니, patrol_range를 벗어나면 제자리에 멈춤.
		var px: float = global_position.x
		if (dir > 0 and px > origin_x + patrol_range) or (dir < 0 and px < origin_x - patrol_range):
			velocity.x = 0.0
		else:
			velocity.x = float(dir) * SHIELD_SPEED * 0.8
		if is_on_wall():
			velocity.x = 0.0
	# 가장자리 — 추격이든 순찰이든 떨어지지 않게 정지 (방패병은 정면 잠김이라 dir 반전 어색).
	if is_on_floor() and not _has_ground_ahead(dir):
		velocity.x = 0.0

	_flip_visual(dir < 0)
	move_and_slide()

func _shield_player_nearby(p: Node2D) -> bool:
	var dx: float = abs(p.global_position.x - global_position.x)
	var dy: float = abs(p.global_position.y - global_position.y)
	return dx <= SHIELD_DETECT_X and dy <= SHIELD_DETECT_Y

func _shield_blocks(from_dir: int) -> bool:
	# bullet의 진행 방향이 enemy의 정면을 향하면(부호 반대) 방패가 막음.
	# 예: enemy.dir=-1(왼쪽 향함), bullet.dir=+1(오른쪽으로 날아옴) → head-on → 막음.
	# enemy.dir=-1, bullet.dir=-1(같은 방향, 즉 뒤에서 옴) → 통과.
	return from_dir * dir < 0

# ─── 공통 ───────────────────────────────────────────────────

func _find_player() -> Node2D:
	# 트리에서 빠진(씬 전환 중) 노드의 콜백/틱이 player를 조회하면 get_tree()가 null →
	# "get_nodes_in_group on null" 크래시. player 조회의 단일 길목이라 여기서 가드.
	var tree := get_tree()
	if tree == null:
		return null
	var nodes := tree.get_nodes_in_group("player")
	if nodes.size() == 0:
		return null
	return nodes[0] as Node2D

func _fire_at_player() -> void:
	if harmless:
		return
	var player := _find_player()
	if player == null:
		return
	var dist: float = global_position.distance_to(player.global_position)
	if dist > _eff_sniper_range():
		return
	SfxPlayer.play_at("enemy_sniper_fire", global_position)
	var tracer := Line2D.new()
	tracer.width = 2.5
	tracer.default_color = Color(1.0, 0.55, 0.30, 1.0)
	tracer.z_index = 2
	tracer.add_point(global_position + Vector2(0, -20))
	tracer.add_point(player.global_position + Vector2(0, -28))
	get_parent().add_child(tracer)
	var tw := tracer.create_tween()
	tw.tween_property(tracer, "default_color", Color(1.0, 0.55, 0.30, 0.0), 0.30)
	tw.tween_callback(tracer.queue_free)
	if player.has_method("take_hit"):
		player.take_hit(1)

# 저격수 사거리 시각화 — 히트스캔이라 '사거리 안 + 시야 트임'이면 무조건 맞는다. 그 위협 반경을
# 점선 링으로 보여줘 플레이어가 "이 원 밖이면 안전 / 안이면 엄폐·이동"을 읽게 한다. 사거리 근처에
# 들어와야 떠오르고(평소엔 숨김), 안으로 들수록·조준 중일수록 진해진다. 사용자 피드백 2026-06-13.
func _draw() -> void:
	if enemy_type != EnemyType.SNIPER or dead or harmless:
		return
	var p := _find_player()
	if p == null:
		return
	var rng: float = _eff_sniper_range()
	var dist: float = global_position.distance_to(p.global_position)
	# 링 경계 = 실제 교전(인식) 사거리와 정확히 일치 — 링 안이면 사선만 트이면 맞고, 밖이면 안전.
	# (이전 1.15배는 표시 범위가 실제 교전보다 넓어 "보이는데 안 쏨"이 됐다. 사용자 피드백 2026-06-13.)
	if dist > rng:
		return
	var prox: float = clampf(1.0 - (dist - rng * 0.5) / (rng * 0.65), 0.0, 1.0)
	var aiming: bool = aim_line != null
	var a: float = (0.09 + 0.15 * prox) * (1.7 if aiming else 1.0)
	a = clampf(a, 0.0, 0.42)
	var col: Color = Color(1.0, 0.40, 0.34, a)
	var c: Vector2 = Vector2(0, -20)  # 발사 원점과 맞춤
	var segs: int = 72
	for i in range(0, segs, 2):  # 한 칸 건너뛰어 점선
		var a0: float = float(i) / float(segs) * TAU
		var a1: float = float(i + 1) / float(segs) * TAU
		draw_arc(c, rng, a0, a1, 5, col, 1.5, true)

func _exit_tree() -> void:
	_clear_aim()

func _check_touch_player() -> void:
	if harmless:
		return
	if touch_cd > 0.0:
		return
	var player := _find_player()
	if player == null:
		return
	# Shield는 정면(dir 쪽) 근접거리 안에 있을 때만 데미지 — 등 뒤로 돌면 안전
	if enemy_type == EnemyType.SHIELD:
		var rel_x: float = player.global_position.x - global_position.x
		var dy: float = abs(player.global_position.y - global_position.y)
		var same_side: bool = (rel_x > 0.0 and dir > 0) or (rel_x < 0.0 and dir < 0)
		if same_side and abs(rel_x) <= SHIELD_MELEE_RANGE and dy <= 42.0:
			if player.has_method("take_hit"):
				player.take_hit(SHIELD_TOUCH_DAMAGE)
				touch_cd = SHIELD_TOUCH_COOLDOWN
		return
	if global_position.distance_to(player.global_position) < 36.0:
		if player.has_method("take_hit"):
			player.take_hit(TOUCH_DAMAGE)
			touch_cd = TOUCH_COOLDOWN

func take_damage(amount: int, from_dir: int = 0) -> void:
	if dead:
		return
	# 방패병 — 정면(enemy.dir이 가리키는 쪽)으로 날아오는 사격은 막힘.
	# 즉 bullet의 진행 방향(from_dir)과 enemy의 dir이 반대 부호일 때 head-on이라 막음.
	if enemy_type == EnemyType.SHIELD and from_dir != 0 and _shield_blocks(from_dir):
		_show_block_spark(from_dir)
		SfxPlayer.play_at("bullet_deflect_shield", global_position)
		return
	# from_dir != 0이면 bullet 명중. 폭발/스킬(from_dir == 0)은 자체 SFX 별도.
	if from_dir != 0:
		SfxPlayer.play_at("bullet_impact_enemy", global_position)
	hp -= amount
	modulate = Color(1.6, 1.6, 1.6)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1), 0.15)
	if hp <= 0:
		_die()
	else:
		SfxPlayer.play_at("enemy_hurt", global_position)

func _show_block_spark(from_dir: int) -> void:
	# 방패 막힘 — 노란 짧은 라인이 방패 면(enemy.dir 쪽 외곽)에서 튀는 효과
	var spark := Line2D.new()
	spark.width = 2.0
	spark.default_color = Color(1.0, 0.85, 0.30, 0.9)
	spark.z_index = 4
	var face_x: float = global_position.x + (1.0 if dir > 0 else -1.0) * 16.0
	var y0: float = global_position.y - 26.0
	# 스파크는 방패 면 바깥쪽으로 튀는 모양. bullet이 들어온 방향의 반대로 흩어지게.
	var splash: float = -8.0 * float(from_dir)
	spark.add_point(Vector2(face_x, y0 - 4.0))
	spark.add_point(Vector2(face_x + splash, y0))
	spark.add_point(Vector2(face_x, y0 + 4.0))
	get_parent().add_child(spark)
	var tw := spark.create_tween()
	tw.tween_property(spark, "default_color", Color(1.0, 0.85, 0.30, 0.0), 0.18)
	tw.tween_callback(spark.queue_free)

func _die() -> void:
	dead = true
	# Bomber는 _bomber_explode가 폭발 SFX를 먼저 재생하므로 여기서 enemy_death는 생략 — 음향 중복 방지.
	if enemy_type != EnemyType.BOMBER:
		SfxPlayer.play_at("enemy_death", global_position)
	emit_signal("killed", global_position)
	queue_free()
