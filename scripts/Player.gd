class_name Player
extends CharacterBody2D

signal damaged
signal died
signal revived

const SPEED: float = 240.0
const JUMP_VELOCITY: float = -540.0
const GRAVITY: float = 1400.0
const MAX_FALL_SPEED: float = 1100.0
const GLIDE_FALL_SPEED: float = 130.0  # glide(공중 글라이드) 시 점프 키 홀드 중 최대 낙하 속도
const ATTACK_COOLDOWN: float = 0.30
const DASH_SPEED: float = 720.0
const DASH_DURATION: float = 0.18
const DASH_COOLDOWN: float = 0.7
const INVULN_AFTER_HIT: float = 0.8
const SKILL_COOLDOWN: float = 3.5  # explosive 재사용 대기 (너프: 3.0→3.5, "만능" 억제)
const DROP_THROUGH_DURATION: float = 0.25  # 플랫폼 통과 예외 유지 시간

# 점프 입력 관용(플랫포머 표준). coyote = 가장자리에서 막 떨어진 직후에도 지상 점프 허용,
# jump buffer = 착지 직전 누른 점프 입력을 기억해 착지 순간 발동. 둘 다 "분명 점프했는데
# 안 올라가짐"(2차 피드백 다수) 해소용 — 원인은 docs/design/known_issues.md 참조.
const COYOTE_TIME: float = 0.10
const JUMP_BUFFER_TIME: float = 0.10

# 충전형 방패(barrier) — SkillTreeData.barrier 라인.
# T1: 10초 충전 후 1회 피격 무효 / T2: 6초 충전 / T3: 무효 직후 0.6s 무적.
const BARRIER_CHARGE_T1: float = 10.0
const BARRIER_CHARGE_T2: float = 6.0
const BARRIER_INVULN_T3: float = 0.6

# 비상 부활(shield) — SkillTreeData.shield 라인. T1 1회 부활 / T2 부활 HP 2 / T3 재충전.
# (이름은 barrier "에너지 방어막"과 헷갈리지 않게 "부활"로 통일.)
const SHIELD_RECHARGE_TIME: float = 30.0  # T3 — 부활 소진 후 이 시간 뒤 재무장

const ATTACK_MUZZLE_X: float = 13.0
const ATTACK_MUZZLE_Y: float = -31.0  # 총구 높이 — 5두신 비례 재조정 후 새 손목 위치
const EXPLOSION_RADIUS: float = 180.0
# 너프: 3→2. 방패병(HP3)을 한 방에 못 죽이게 해 "모든 적 올킬 만능"을 깬다. 단 방패 무시 AoE라
# 정면 못 뚫는 방패병에 여전히 유효(2뎀×2) + patrol·sniper·drone·bomber는 한 방 유지 → 군집/방패 상성 보존.
const EXPLOSION_DAMAGE: int = 2
# 1회 폭발이 타격하는 최대 적 수 — 뭉친 적을 한 방에 몰살하는 문제(사용자: 감시탑 발판에서 전멸)
# 방지. 가장 가까운 적부터 이 수만큼만. 군집 처리는 되되 "올킬"은 막는다.
const MAX_EXPLOSION_HITS: int = 3

var facing: int = 1
var attack_cd: float = 0.0
# fire_boost T2 "사격 시 잠깐 가속" — 사격 직후 _SPRINT_DURATION 동안 이동 속도 ×_SPRINT_MULT.
const _SPRINT_DURATION: float = 0.5
const _SPRINT_MULT: float = 1.4
var sprint_t: float = 0.0
# hp T3 "피격 슬로모" — 피격 시 짧게 Engine.time_scale 감소.
const _HIT_SLOWMO_DURATION: float = 0.35
const _HIT_SLOWMO_SCALE: float = 0.4
var slowmo_active: bool = false
var jumps_used: int = 0
var _coyote_t: float = 0.0       # 바닥을 떠난 뒤 지상 점프가 아직 유효한 잔여 시간
var _jump_buffer_t: float = 0.0  # 착지 직전 누른 점프 입력을 기억하는 잔여 시간
# 환경 레버 — Area2D body_entered 시 LeverInteractable이 직접 세팅한다.
# attack 입력이 사격 대신 레버 당기기로 흡수된다.
var nearby_lever: Node = null
var dash_timer: float = 0.0
var dash_cd: float = 0.0
var skill_cd: float = 0.0
var invuln: float = 0.0

var visual: Node2D
var torso: Node2D = null      # CharacterArt가 만든 Torso 컨테이너 — idle bob에 사용
var arm_front: Node2D = null  # 앞팔/총 — 사격 시 반동 회전, 이동 시 흔들림
var leg_l: Node2D = null      # 왼다리 — 가랑이 origin. walk swing.
var leg_r: Node2D = null      # 오른다리
var anim_t: float = 0.0       # 시각 애니메이션 누적 시간(sin bob 위상)
var muzzle_flash: ColorRect

# explosive T3 — 2회 충전. 사용 시 charges -1, cd 끝나면 +1 누적.
var skill_charges: int = 1
var skill_max_charges: int = 1

# barrier 상태
var barrier_ready: bool = false
var barrier_charge_t: float = 0.0
var barrier_indicator: Node2D = null

# shield(비상 부활) T3 재충전 상태 — 부활 소진 후 recharge_t 동안 비무장, 0 도달 시 재무장.
# (T1/T2는 GameState.skills에서 erase되어 1회용이라 이 상태를 안 씀.)
var shield_spent: bool = false
var shield_recharge_t: float = 0.0

func _ready() -> void:
	add_to_group("player")
	z_index = 2
	# 명시 AudioListener2D — default listener는 active Camera2D인데, ARENA(보스전)에선
	# 카메라가 월드 중앙 고정이라 거리 감쇠가 플레이어 기준이 아니게 됨. listener를
	# 플레이어에 묶으면 카메라 모드와 무관하게 positional audio가 플레이어 위치 기준.
	var listener := AudioListener2D.new()
	add_child(listener)
	listener.make_current()
	visual = CharacterArt.build_player(self)
	torso = visual.get_node_or_null("Torso")
	if torso != null:
		arm_front = torso.get_node_or_null("ArmFront")
		leg_l = torso.get_node_or_null("LegL")
		leg_r = torso.get_node_or_null("LegR")
	_refresh_skill_charges()
	# 스킬 부착물(파우치·윙 등) — 초기 1회 + 스킬 변경 시 갱신(성장 가시화).
	CharacterArt.attach_player_skill_parts(torso, GameState.skills)
	if not GameState.skills_changed.is_connected(_on_skills_changed):
		GameState.skills_changed.connect(_on_skills_changed)
	muzzle_flash = ColorRect.new()
	muzzle_flash.name = "MuzzleFlash"
	muzzle_flash.color = Color(1.0, 0.92, 0.45, 1.0)
	muzzle_flash.size = Vector2(12.0, 8.0)
	muzzle_flash.position = Vector2(ATTACK_MUZZLE_X, ATTACK_MUZZLE_Y - 4.0)
	muzzle_flash.visible = false
	add_child(muzzle_flash)
	# barrier indicator — 머리 위 점, 충전 완료 시 푸른빛 펄스. 사용자
	# 사용자: 동심원이 허벅지에 작게 그려짐 → 캐릭터 전체(28x56)를 감싸는
	# 세로 긴 타원으로. 본체 가운데 y=-28 부근 + 상하 반경 32, 좌우 반경 22.
	barrier_indicator = Node2D.new()
	barrier_indicator.name = "BarrierAura"
	barrier_indicator.position = Vector2(0.0, -28.0)
	barrier_indicator.modulate.a = 0.0
	add_child(barrier_indicator)
	var aura_outer := Polygon2D.new()
	aura_outer.color = Color(0.55, 0.85, 1.0, 0.16)
	aura_outer.polygon = _make_ellipse_polygon(28.0, 38.0)
	barrier_indicator.add_child(aura_outer)
	var aura_mid := Polygon2D.new()
	aura_mid.color = Color(0.65, 0.92, 1.0, 0.24)
	aura_mid.polygon = _make_ellipse_polygon(22.0, 32.0)
	barrier_indicator.add_child(aura_mid)
	var aura_inner := Polygon2D.new()
	aura_inner.color = Color(0.85, 0.97, 1.0, 0.34)
	aura_inner.polygon = _make_ellipse_polygon(16.0, 26.0)
	barrier_indicator.add_child(aura_inner)

func _make_ellipse_polygon(rx: float, ry: float, n: int = 36) -> PackedVector2Array:
	var pts: PackedVector2Array = []
	for i in n + 1:
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a) * rx, sin(a) * ry))
	return pts

var _was_on_floor: bool = true
const _STEP_INTERVAL: float = 0.32
var _step_t: float = 0.0

func _physics_process(delta: float) -> void:
	_tick_timers(delta)
	_handle_input(delta)
	_apply_gravity(delta)
	move_and_slide()
	var on_floor_now: bool = is_on_floor()
	# 착지 SFX — 공중에서 지면으로 전이된 순간 한 번. 짧은 hop은 step과 비슷해서
	# 발이 떴던 시간이 있을 때만(=jumps_used > 0 또는 _was_on_floor false) 의미.
	if on_floor_now and not _was_on_floor:
		SfxPlayer.play("player_land")
	_was_on_floor = on_floor_now
	if on_floor_now:
		jumps_used = 0
		_coyote_t = COYOTE_TIME
	else:
		_coyote_t = maxf(_coyote_t - delta, 0.0)
	# 발걸음 SFX — 지면에서 충분한 속도로 이동 중일 때만 일정 간격으로.
	if on_floor_now and absf(velocity.x) > 30.0:
		_step_t += delta
		if _step_t >= _STEP_INTERVAL:
			_step_t = 0.0
			SfxPlayer.play("player_step")
	else:
		_step_t = _STEP_INTERVAL  # 다시 걷기 시작하면 즉시 첫 step 트리거되도록.
	anim_t += delta
	_update_visual()

func _tick_timers(delta: float) -> void:
	if attack_cd > 0.0:
		attack_cd -= delta
	if sprint_t > 0.0:
		sprint_t -= delta
	if dash_timer > 0.0:
		dash_timer -= delta
	if dash_cd > 0.0:
		dash_cd -= delta
	if skill_cd > 0.0:
		skill_cd -= delta
		# 쿨다운 종료 — charges 미만이면 +1 (T3 2회 충전).
		if skill_cd <= 0.0 and skill_charges < skill_max_charges:
			skill_charges += 1
			if skill_charges < skill_max_charges:
				skill_cd = get_skill_cd_max()  # 다음 충전 시작
	if invuln > 0.0:
		invuln -= delta
	if muzzle_flash != null and muzzle_flash.visible:
		muzzle_flash.modulate.a = max(0.0, muzzle_flash.modulate.a - delta * 7.0)
		if muzzle_flash.modulate.a <= 0.05:
			muzzle_flash.visible = false
			muzzle_flash.modulate.a = 1.0
	# shield T3 재충전 — 소진 상태에서 시간 경과 후 재무장(보호 복귀를 플래시로 알림).
	if shield_spent:
		shield_recharge_t -= delta
		if shield_recharge_t <= 0.0:
			shield_spent = false
			_show_shield_flash()
	_tick_barrier(delta)

func _tick_barrier(delta: float) -> void:
	# barrier 라인 미보유 시 indicator 숨김.
	if not GameState.has_skill("barrier"):
		if barrier_indicator != null:
			barrier_indicator.visible = false
		return
	if barrier_indicator != null:
		barrier_indicator.visible = true
	if barrier_ready:
		# 충전 완료 — 사용자 피드백: 충전 중 색 정도로 연하게. 펄스 폭도 작게.
		if barrier_indicator != null:
			var pulse: float = 0.40 + 0.10 * sin(Time.get_ticks_msec() * 0.004)
			barrier_indicator.modulate.a = pulse
			var s: float = 1.0 + 0.06 * sin(Time.get_ticks_msec() * 0.005)
			barrier_indicator.scale = Vector2(s, s)
		return
	# 충전 진행 — 사용자 피드백: 충전 중에는 안 보임.
	var charge_max: float = BARRIER_CHARGE_T2 if GameState.get_skill_tier("barrier") >= 2 else BARRIER_CHARGE_T1
	barrier_charge_t += delta
	if barrier_indicator != null:
		barrier_indicator.modulate.a = 0.0
		barrier_indicator.scale = Vector2(1.0, 1.0)
	if barrier_charge_t >= charge_max:
		barrier_ready = true
		barrier_charge_t = 0.0
		# 충전 완료 시 짧은 펄스 + 작은 후광
		if barrier_indicator != null:
			var tw := barrier_indicator.create_tween()
			barrier_indicator.scale = Vector2(2.6, 2.6)
			tw.tween_property(barrier_indicator, "scale", Vector2(1.0, 1.0), 0.25)

func _handle_input(delta: float) -> void:
	var dir: float = Input.get_axis("move_left", "move_right")
	if dir != 0.0:
		facing = 1 if dir > 0.0 else -1

	if dash_timer > 0.0:
		# dash_boost T2 = 대시 거리 +30% → 속도 *1.3 (지속시간은 그대로라 거리 늘어남)
		var dash_speed_mult: float = 1.3 if GameState.get_skill_tier("dash_boost") >= 2 else 1.0
		velocity.x = float(facing) * DASH_SPEED * dash_speed_mult
	else:
		# fire_boost T2 — 사격 직후 0.5s 동안 이동 속도 ×1.4 ("사격 시 잠깐 가속" desc 구현).
		var move_mult: float = _SPRINT_MULT if sprint_t > 0.0 else 1.0
		velocity.x = dir * SPEED * move_mult

	# 점프 입력은 버퍼에 기억해 두고 매 프레임 소비를 시도(jump buffer). 착지 직전 입력도
	# 착지 순간 발동하고, coyote 윈도우 안이면 가장자리 이탈 직후에도 지상 점프가 나간다.
	if Input.is_action_just_pressed("jump"):
		_jump_buffer_t = JUMP_BUFFER_TIME
	if _jump_buffer_t > 0.0:
		_jump_buffer_t = maxf(_jump_buffer_t - delta, 0.0)
		if _try_jump():
			_jump_buffer_t = 0.0
	# 전투 입력 제한 (??? 맵에서) — 이동/점프만 허용
	if not GameState.restrict_combat_input:
		# 레버 영역 내에서는 attack 입력이 사격 대신 레버 당기기에만 쓰임 (꾹 누름 사격도 차단).
		if nearby_lever != null and is_instance_valid(nearby_lever):
			if Input.is_action_just_pressed("attack") and nearby_lever.has_method("try_pull"):
				nearby_lever.try_pull()
		# 공격 — 꾹 누르면 쿨다운마다 자동 연발. _try_attack이 cd 체크해 자체 무시.
		elif Input.is_action_pressed("attack"):
			_try_attack()
		if Input.is_action_just_pressed("dash"):
			_try_dash()
		if Input.is_action_just_pressed("skill"):
			_try_skill()
	if Input.is_action_just_pressed("move_down"):
		_try_drop_through()

func _try_drop_through() -> void:
	if not is_on_floor():
		return
	# 직전 move_and_slide의 충돌 결과에서 발 밑이 one-way 플랫폼인지 검사
	for i in get_slide_collision_count():
		var c := get_slide_collision(i)
		var collider: Object = c.get_collider()
		if collider is Node and (collider as Node).is_in_group("platform"):
			add_collision_exception_with(collider)
			# process_always=true — paused 상태(LevelUp 등) 중에도 timer 진행되어
			# collision_exception이 dangling 안 되도록 (이전엔 paused 중 fire 안 돼 다음 씬으로 carry 위험).
			get_tree().create_timer(DROP_THROUGH_DURATION, true).timeout.connect(
				func() -> void:
					if is_instance_valid(self) and is_instance_valid(collider):
						remove_collision_exception_with(collider)
			)
			position.y += 2.0
			velocity.y = max(velocity.y, 80.0)
			return

# 점프를 시도하고 실제로 발동했으면 true(버퍼 소비 판정용).
func _try_jump() -> bool:
	var max_jumps: int = 1
	if GameState.has_skill("double_jump"):
		max_jumps += 1
	# 글라이드 T2 — 공중 점프 1회 추가(최대 3단; 높은 곳·숨은 보상 도달). 재설계(2026-06-13):
	# T1은 활강만, 삼단점프는 T2로 분리(T1에 활강+삼단점프 둘 다라 글라이드 가치가 과했음).
	if GameState.get_skill_tier("glide") >= 2:
		max_jumps += 1
	# 지상 점프 — 바닥이거나, 가장자리에서 막 떨어진 직후(coyote, 아직 공중 점프 미사용).
	if is_on_floor() or (_coyote_t > 0.0 and jumps_used == 0):
		velocity.y = JUMP_VELOCITY
		jumps_used = 1
		_coyote_t = 0.0
		SfxPlayer.play("player_jump")
		return true
	elif jumps_used < max_jumps:
		velocity.y = JUMP_VELOCITY * 0.92
		jumps_used += 1
		# 사용자: 더블점프 전용 사운드는 어색해서 일반 점프 사운드 재사용.
		SfxPlayer.play("player_jump")
		return true
	return false

# 현재 티어가 반영된 실제 max 쿨다운 (HUD 게이지 표시용).
func get_attack_cd_max() -> float:
	return ATTACK_COOLDOWN * (0.70 if GameState.get_skill_tier("fire_boost") >= 2 else 1.0)

func get_dash_cd_max() -> float:
	return DASH_COOLDOWN * (0.8 if GameState.get_skill_tier("dash_boost") >= 1 else 1.0)

func get_skill_cd_max() -> float:
	var ex_tier: int = GameState.get_skill_tier("explosive")
	if ex_tier >= 2:
		return 3.0  # 너프: 2.5→3.0 (T2/T3도 남발 억제)
	return SKILL_COOLDOWN

func _try_attack() -> void:
	if attack_cd > 0.0:
		return
	# fire_boost T2 "속사": 사격 쿨다운 -30%(연사 속도↑) + 사격 후 0.5s 이동 가속(_handle_input에서 적용).
	var fb_tier: int = GameState.get_skill_tier("fire_boost")
	var cd_mult: float = 0.70 if fb_tier >= 2 else 1.0
	attack_cd = ATTACK_COOLDOWN * cd_mult
	if fb_tier >= 2:
		sprint_t = _SPRINT_DURATION
	_show_muzzle_flash()
	SfxPlayer.play("bullet_fire")
	# multishot T1=3발, T2/T3=5발.
	var ms_tier: int = GameState.get_skill_tier("multishot")
	var shots: int = 1
	if ms_tier == 1:
		shots = 3
	elif ms_tier >= 2:
		shots = 5
	for i in shots:
		_spawn_bullet(i, shots)

func _spawn_bullet(idx: int, total: int) -> void:
	var b := Bullet.new()
	b.dir = facing
	# fire_boost: T1=데미지 +1(→2 고정), T2=연사 속도(데미지 추가 없음), T3=관통. 베이스 1.
	# 추가 데미지는 방패병(HP3) 외엔 효용 낮아(대부분 적 HP 1~2) T2를 연사로 전환(피드백 2026-06-12).
	# 방패병은 폭발물이 상성 카운터라 데미지 스택이 불필요.
	var fb_tier: int = GameState.get_skill_tier("fire_boost")
	b.damage = 2 if fb_tier >= 1 else 1  # T0=1, T1+=2 고정
	b.pierce = fb_tier >= 3
	b.style_tier = fb_tier               # 총알 외형 분기용 (성장 가시화)
	# multishot T3 — 약한 추적
	b.tracking = GameState.get_skill_tier("multishot") >= 3
	# glide T3 — 활강 중(공중 낙하) 사격이 적을 강하게 유도 + 데미지. 재설계(2026-06-15):
	# '관통'은 사격강화 T3 전담으로 넘기고 활강 T3는 '유도(homing)'를 정체성으로 분리(중복 제거).
	# → 두 라인 모두 보유 시 활강 중엔 관통(fire_boost) + 유도(glide) 시너지가 자연히 겹친다.
	var gl_tier: int = GameState.get_skill_tier("glide")
	if gl_tier >= 3 and not is_on_floor() and velocity.y > 0.0:
		b.damage += 1
		b.tracking = true
		b.tracking_blend = 0.12      # 약한 추적(0.03)보다 강하게 — "완전 유도" 체감
		b.tracking_max_angle = 0.42  # ~24도
	# 부채꼴 — 가운데를 0으로 양 끝으로 10°씩 벌림.
	# T1(3발): -10°/0/+10°. T2(5발): -20/-10/0/+10/+20.
	if total > 1:
		var step: float = deg_to_rad(10.0)
		var center: float = float(total - 1) * 0.5
		b.angle = (float(idx) - center) * step
	var muzzle_x: float = ATTACK_MUZZLE_X * float(facing)
	var muzzle_y: float = ATTACK_MUZZLE_Y
	b.global_position = global_position + Vector2(muzzle_x, muzzle_y)
	get_parent().add_child(b)

func _show_muzzle_flash() -> void:
	if muzzle_flash == null:
		return
	var mx: float = ATTACK_MUZZLE_X if facing > 0 else -(ATTACK_MUZZLE_X + 12.0)
	muzzle_flash.position = Vector2(mx, ATTACK_MUZZLE_Y - 4.0)
	muzzle_flash.modulate.a = 1.0
	muzzle_flash.visible = true

func _try_dash() -> void:
	if not GameState.has_skill("dash"):
		return
	if dash_cd > 0.0:
		return
	SfxPlayer.play("player_dash")
	# dash_boost: T1=쿨다운 -20%, T2=거리 +30%(_handle_input의 dash_timer 분기에서 적용),
	#            T3=대시 후 0.3s 무적 추가.
	var db_tier: int = GameState.get_skill_tier("dash_boost")
	var cd_mult: float = 0.8 if db_tier >= 1 else 1.0
	dash_timer = DASH_DURATION
	dash_cd = DASH_COOLDOWN * cd_mult
	var iframe: float = DASH_DURATION
	if db_tier >= 3:
		iframe += 0.3
	invuln = max(invuln, iframe)

func _try_skill() -> void:
	# explosive: T1=쿨다운 3.0s, T2=반경+30% 쿨다운 2.5s, T3=쿨다운 2.5s + 2회 충전.
	var ex_tier: int = GameState.get_skill_tier("explosive")
	if ex_tier == 0:
		return
	_refresh_skill_charges()  # 티어 변경(레벨업 직후) 반영
	if skill_charges <= 0:
		return
	skill_charges -= 1
	if skill_cd <= 0.0:
		skill_cd = get_skill_cd_max()
	SfxPlayer.play("skill_active_use")
	_spawn_explosion()

# T3에서 max 2 charges. 매 _ready/_try_skill 진입 시 호출해 티어 갱신을 반영.
func _refresh_skill_charges() -> void:
	var ex_tier: int = GameState.get_skill_tier("explosive")
	var new_max: int = 2 if ex_tier >= 3 else 1
	if new_max != skill_max_charges:
		skill_max_charges = new_max
		skill_charges = clampi(skill_charges, 0, skill_max_charges)
		# T3로 막 진입했으면 충전 1개 추가 보장(이전엔 1/1 상태)
		if new_max == 2 and skill_charges < new_max and skill_cd <= 0.0:
			skill_charges = new_max

# 스킬 티어 변경(레벨업) 시 — 충전 수와 캐릭터 부착물 외형을 함께 갱신.
func _on_skills_changed() -> void:
	_refresh_skill_charges()
	if torso != null:
		CharacterArt.attach_player_skill_parts(torso, GameState.skills)
		_play_skill_acquire_flash()

# 스킬 획득/티어업 순간을 눈에 띄게 — 캐릭터에 밝은 확산 링 + 본체 섬광.
# 레벨업은 일시정지 중 skills_changed가 오므로, 일반(pausable) tween이면 오버레이가
# 닫히고 게임이 재개되는 순간 자연히 재생된다(부착물 변화에 시선을 끈다).
func _play_skill_acquire_flash() -> void:
	var ring := Node2D.new()
	ring.name = "SkillAcquireFlash"
	ring.position = Vector2(0, -28)
	ring.z_index = 6
	add_child(ring)
	var line := Line2D.new()
	var pts: PackedVector2Array = []
	for i in 20:
		var ang: float = float(i) * TAU / 20.0
		pts.append(Vector2(cos(ang) * 22.0, sin(ang) * 30.0))
	line.points = pts
	line.closed = true
	line.width = 3.0
	line.default_color = Color(0.75, 0.95, 1.0, 0.95)
	line.antialiased = true
	ring.add_child(line)
	ring.scale = Vector2(0.45, 0.45)
	var tw := ring.create_tween()
	tw.set_parallel(true)
	tw.tween_property(ring, "scale", Vector2(1.7, 1.7), 0.45).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
	tw.tween_property(line, "default_color:a", 0.0, 0.45)
	tw.set_parallel(false)
	tw.tween_callback(ring.queue_free)
	# 본체 섬광 — torso.modulate는 다른 곳에서 안 건드려 충돌 없음(피격은 visual.modulate).
	if torso != null:
		var ft := torso.create_tween()
		ft.tween_property(torso, "modulate", Color(1.6, 1.6, 1.8), 0.08)
		ft.tween_property(torso, "modulate", Color(1, 1, 1), 0.34)

func _spawn_explosion() -> void:
	var center: Vector2 = global_position + Vector2(0, -28)
	# 폭발 임팩트 — skill_active_use(발동 클릭) 위에 bomb_explode를 레이어해서 폭발감 보강.
	SfxPlayer.play("bomb_explode")
	# explosive T2/T3 = 반경 +30%
	var radius: float = EXPLOSION_RADIUS
	if GameState.get_skill_tier("explosive") >= 2:
		radius *= 1.3
	# 데미지: 반경 안 적을 거리순으로 최대 MAX_EXPLOSION_HITS체만 (몰살 방지).
	var in_range: Array = []
	for n in get_tree().get_nodes_in_group("enemy"):
		if not (n is Node2D):
			continue
		var enemy := n as Node2D
		var d: float = enemy.global_position.distance_to(center)
		if d <= radius and enemy.has_method("take_damage"):
			in_range.append({"e": enemy, "d": d})
	in_range.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["d"]) < float(b["d"]))
	var hits: int = 0
	for item in in_range:
		if hits >= MAX_EXPLOSION_HITS:
			break
		var it: Dictionary = item
		var e: Node2D = it["e"]
		e.take_damage(EXPLOSION_DAMAGE)
		hits += 1
	# 시각: 확장하며 페이드되는 원
	var blast := Polygon2D.new()
	blast.color = Color(1.0, 0.55, 0.30, 0.85)
	blast.z_index = 3
	var pts: Array = []
	for i in 28:
		var a: float = float(i) * TAU / 28.0
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	blast.polygon = PackedVector2Array(pts)
	blast.global_position = center
	blast.scale = Vector2(0.2, 0.2)
	get_parent().add_child(blast)
	var tw := blast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2(1.0, 1.0), 0.30)
	tw.tween_property(blast, "modulate", Color(1, 1, 1, 0), 0.45)
	tw.chain().tween_callback(blast.queue_free)

func _apply_gravity(delta: float) -> void:
	if is_on_floor():
		return
	velocity.y = min(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)
	# 공중 활강 — T1부터 낙하 시 자동으로 천천히 떨어진다(점프 홀드 불필요 — 패시브).
	# 아래 방향키를 누르면 활강을 끄고 원래 속도로 빠르게 떨어진다(사용자 요청). 좌우 입력은 활강 가속.
	# T2=활강 중 사격 관통+데미지, T3=유도 — 효과는 _spawn_bullet. 공중 제압 라인(상성: 저격수·드론).
	var glide_tier: int = GameState.get_skill_tier("glide")
	if glide_tier >= 1 and velocity.y > 0.0 and not Input.is_action_pressed("move_down"):
		var fall_speed: float = GLIDE_FALL_SPEED
		# 좌우 이동 입력 시 낙하 속도 ↑ (활공 거리·속도 제어).
		if Input.get_axis("move_left", "move_right") != 0.0:
			fall_speed = GLIDE_FALL_SPEED * 1.6
		velocity.y = min(velocity.y, fall_speed)

func take_hit(amount: int) -> void:
	# 0뎀 타격은 피격이 아니다 — 보스 자폭 반경(700px) 밖처럼 거리 감쇠로 0뎀이 된 경우,
	# barrier 소모·hit 카운트가 일어나면 안 됨(사용자 보고: 노란 원 밖인데 방어막이 벗겨짐).
	if amount <= 0:
		return
	if invuln > 0.0:
		return
	# 실력 추적 — invuln을 통과한 실제 타격마다 1회 카운트(barrier 흡수·스토리 무피해 포함).
	# i-frame 동안의 연타는 1회로 묶여 "맞은 횟수"로 읽힘. VEIL 적응형 추천이 사용.
	GameState.register_hit()
	# barrier 충전 완료 상태면 1회 무효화 + 충전 리셋. T3는 후속 무적.
	if GameState.has_skill("barrier") and barrier_ready:
		barrier_ready = false
		barrier_charge_t = 0.0
		if barrier_indicator != null:
			barrier_indicator.modulate.a = 0.0
		_show_shield_flash()
		if GameState.get_skill_tier("barrier") >= 3:
			invuln = max(invuln, BARRIER_INVULN_T3)
		emit_signal("damaged")  # 화면 플래시·shake 트리거 (시각 피드백 유지)
		return
	GameState.damage_player(amount)
	SfxPlayer.play("player_hurt")
	# hp T2 = 피격 후 1s 무적 (기본 0.8보다 길게).
	# hp T3 = 추가로 짧은 슬로모션 (Engine.time_scale 감속).
	var hp_tier: int = GameState.get_skill_tier("hp")
	# max() — 신호 핸들러(예: 도전방 _challenge_fail)가 더 긴 invuln을 set한 케이스 보존.
	# 이전 코드는 직접 대입이라 핸들러가 emit 안에서 set한 5.0이 보존됐지만, 순서가 바뀌어도 안전하게.
	invuln = max(invuln, 1.0 if hp_tier >= 2 else INVULN_AFTER_HIT)
	if hp_tier >= 3:
		_trigger_hit_slowmo()
	emit_signal("damaged")
	# 비상 부활 — T1: HP 1로 부활, T2: HP 2로 부활. T3: 라인 유지 + 30s 후 재무장.
	# T1/T2는 발동 시 라인 erase(1회용), T3는 shield_spent로 비무장 두었다가 recharge로 재무장.
	var sh_tier: int = GameState.get_skill_tier("shield")
	if GameState.is_dead() and sh_tier >= 1 and not shield_spent:
		GameState.player_hp = 2 if sh_tier >= 2 else 1
		_show_shield_flash()
		emit_signal("revived")
		if sh_tier >= 3:
			# T3 재충전 — 라인을 소비하지 않고 비무장으로 두었다가 SHIELD_RECHARGE_TIME 후 재무장.
			shield_spent = true
			shield_recharge_t = SHIELD_RECHARGE_TIME
		else:
			GameState.skills.erase("shield")
		return
	if GameState.is_dead():
		SfxPlayer.play("player_death")
		emit_signal("died")

# hp T3 — 피격 시 짧은 슬로모. Engine.time_scale 0.4로 감속, 0.35s 후 1.0 복원.
# 실시간 타이머(ignore_time_scale=true)로 슬로모 안에서도 정확히 0.35s 후 해제.
# 이미 슬로모 중에 또 피격되면 무시 (중첩 방지).
func _trigger_hit_slowmo() -> void:
	if slowmo_active:
		return
	slowmo_active = true
	Engine.time_scale = _HIT_SLOWMO_SCALE
	var timer: SceneTreeTimer = get_tree().create_timer(_HIT_SLOWMO_DURATION, true, false, true)
	timer.timeout.connect(_end_hit_slowmo)

func _end_hit_slowmo() -> void:
	slowmo_active = false
	Engine.time_scale = 1.0

func _exit_tree() -> void:
	# scene 전환 도중 슬로모가 활성된 채 player가 free되면 다음 씬도 0.4 배속이 됨.
	# 안전판 — player가 트리에서 빠질 때 무조건 1.0 복원.
	if slowmo_active or not is_equal_approx(Engine.time_scale, 1.0):
		Engine.time_scale = 1.0
		slowmo_active = false

func _show_shield_flash() -> void:
	# 방어막 발동 — 강한 흰 플래시 + 확장하는 후광 (한 번에 인지되도록 강화).
	if visual != null:
		visual.modulate = Color(3.5, 3.5, 4.0)
		create_tween().tween_property(visual, "modulate", Color(1, 1, 1), 0.6)
	var halo := Polygon2D.new()
	halo.color = Color(1.0, 1.0, 1.2, 0.85)
	var pts: Array = []
	for i in 28:
		var a: float = float(i) * TAU / 28.0
		pts.append(Vector2(cos(a) * 28.0, sin(a) * 28.0))
	halo.polygon = PackedVector2Array(pts)
	halo.position = Vector2(0, -28)
	halo.z_index = 5
	add_child(halo)
	var tw := halo.create_tween()
	tw.set_parallel(true)
	tw.tween_property(halo, "scale", Vector2(3.4, 3.4), 0.55)
	tw.tween_property(halo, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(halo.queue_free)
	# 두 번째 후광 (살짝 늦게 따라옴 — 섬광 느낌)
	var halo2 := Polygon2D.new()
	halo2.color = Color(0.85, 0.95, 1.0, 0.5)
	halo2.polygon = PackedVector2Array(pts)
	halo2.position = Vector2(0, -28)
	halo2.z_index = 4
	add_child(halo2)
	var tw2 := halo2.create_tween()
	tw2.tween_interval(0.12)
	tw2.set_parallel(true)
	tw2.tween_property(halo2, "scale", Vector2(4.5, 4.5), 0.5)
	tw2.tween_property(halo2, "modulate:a", 0.0, 0.5)
	tw2.chain().tween_callback(halo2.queue_free)

func _update_visual() -> void:
	if visual == null:
		return
	if invuln > 0.0:
		visual.modulate.a = 0.4 if int(invuln * 20.0) % 2 == 0 else 1.0
	else:
		visual.modulate.a = 1.0
	visual.scale.x = -1.0 if facing < 0 else 1.0
	# 자세 — Torso의 작은 y bob + ArmFront 회전으로 정적 인상 완화.
	# scale.x로 좌우 반전돼도 child rotation은 시각적으로 자동 미러됨.
	if torso == null:
		return
	var moving: bool = absf(velocity.x) > 10.0
	var grounded: bool = is_on_floor()
	var bob: float = 0.0
	var lean: float = 0.0
	var arm_rot: float = 0.0
	if not grounded:
		bob = -1.0
		if velocity.y < 0.0:
			lean = 0.05
			arm_rot = -0.18
		else:
			lean = -0.03
			arm_rot = 0.10
	elif moving:
		bob = sin(anim_t * 14.0) * 1.4
		arm_rot = sin(anim_t * 14.0) * 0.10
	else:
		bob = sin(anim_t * 3.0) * 0.6
		arm_rot = sin(anim_t * 3.0) * 0.03
	# 사격 직후 반동 — attack_cd가 max에서 0으로 줄어드는 동안 팔이 위로 튀었다 내려옴.
	var max_cd: float = get_attack_cd_max()
	if attack_cd > 0.0 and max_cd > 0.0:
		var t: float = clamp(attack_cd / max_cd, 0.0, 1.0)
		arm_rot += -0.30 * t
	torso.position.y = bob
	torso.rotation = lean
	if arm_front != null:
		arm_front.rotation = arm_rot
	# 다리 — 가랑이 origin인 LegL/LegR을 회전시켜 보행/점프 자세.
	var leg_l_rot: float = 0.0
	var leg_r_rot: float = 0.0
	if grounded:
		if moving:
			var swing: float = sin(anim_t * 14.0) * 0.45
			leg_l_rot = -swing
			leg_r_rot = swing
	else:
		# 점프/낙하 — 한쪽 다리 앞 한쪽 뒤로 살짝(running jump 자세).
		# 양다리가 같은 방향이면 어색하니 비대칭으로.
		leg_l_rot = -0.22
		leg_r_rot = 0.10
	if leg_l != null:
		leg_l.rotation = leg_l_rot
	if leg_r != null:
		leg_r.rotation = leg_r_rot
