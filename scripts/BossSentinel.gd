class_name BossSentinel
extends CharacterBody2D

# 핵심부(lab) ARENA 보스. 명세: docs/design/world_layout.md §2.10
# 3페이즈 구조 — HP 12 → 8(P2 전환) → 4(P3 전환) → 0(자폭 카운트다운).
# 적 그룹("enemy")에 추가돼서 ARENA enemy_clear 카운트에 자연스럽게 포함된다.
# Stage가 killed 시그널을 받아 클리어 처리.

signal killed(at_position: Vector2)
signal phase_changed(new_phase: int)
signal self_destruct_started
signal self_destruct_disarmed
signal vent_started

const HP_MAX: int = 28     # 보스전 확대(2026-08-19): 24→28 · 실측 20.4s가 클라이맥스로 짧았다
const HP_PHASE2: int = 19  # 이 값 이하 들어오면 P2
const HP_PHASE3: int = 10  # 이 값 이하 들어오면 P3
const HP_SELF_DESTRUCT: int = 6  # 이 값 이하 시 자폭 카운트다운 시작 (버퍼 — 잔탄에 즉사 방지, 자폭 시퀀스 보장)
const HP_SELF_DESTRUCT_STORY: int = 2  # 스토리 보스(HP 8)는 더 낮게 — 충분히 싸운 뒤 자폭
# 스토리 모드 — P2/P3 스킵, 자폭 트리거까지 짧게.
const HP_MAX_STORY: int = 8
const PHASE_FREEZE_DURATION: float = 1.2  # 페이즈 전환 시 정지 + 무적 시간

# 과부하 배기(vent) — 창당 피해 상한(FalseVeil max_hp/6 문법 이식 · 2026-08-19 보스전 확대).
# 어떤 화력이든 배기 ~7회를 상대해야 자폭 임계에 닿는다 = 시간 하한 보장(known_issues:
# "수치 상향만으론 평소와 같음" — HP가 아니라 창이 길이를 만든다). 배기 중 무적 + 증기 방출
# + 증원 1기 호출(무방비를 잡몹이 메운다). 스토리 모드는 미적용(짧게 유지).
# 창당 상한 분모 8.0→5.5(2026-08-20 사용자 "공격 두 번이면 충전, 버려지는 시간이 많다"):
# 28HP 기준 창 7회→5회로 배기 빈도 자체를 줄인다.
const VENT_DIVISOR: float = 5.5
const VENT_DURATION: float = 3.0
# 강제 배출(2026-08-20 재해석) — 배기 중 피격 1발당 배기 시간 단축. 배기가 "기다리는 무적"이
# 아니라 "쏘면 빨리 끝나는 창"이 된다. 고화력 빌드일수록 배기가 짧아져 잦음이 상쇄된다.
# 계산: 기본 연사(1발/0.42s) 사격 시 3s 배기 ≈ 1.8s에 종료 · 오연사 만렙 ≈ 0.7s.
const VENT_HIT_SHAVE: float = 0.3
const VENT_SUMMON_CAP: int = 4       # 배기 증원 포함 동시 소환수 상한
# 위장 자폭(1회) — 페이크 보스 서사(§7 "이긴 순간을 이긴 것 같지 않게")의 전투 내 실연.
# 첫 자폭은 진짜처럼 터지지만 코어가 재점화한다. 두 번째 자폭이 진짜(기존 흐름).
const REIGNITE_HP_RATIO: float = 0.18
const REIGNITE_SPEED_MUL: float = 1.15

const SELF_DESTRUCT_TIME: float = 3.6
const SELF_DESTRUCT_INNER: float = 280.0   # 이 안: full 데미지
const SELF_DESTRUCT_OUTER: float = 700.0   # 이 너머: 무뎀 (이전 1200은 ARENA에서 사실상 회피 불가)
const SELF_DESTRUCT_DAMAGE: int = 3
const SELF_DESTRUCT_DAMAGE_MIN: int = 0  # outer 너머는 완전 회피
const SELF_DESTRUCT_CHASE_SPEED: float = 50.0  # 자폭 중 느린 추적
const SELF_DESTRUCT_FALL_ACCEL: float = 90.0   # 자폭 중 추락 가속
const SPARK_INTERVAL: float = 0.12  # 파지직 파티클 간격

const TOUCH_DAMAGE: int = 1
const TOUCH_COOLDOWN: float = 1.0

# 페이즈별 이동/공격 파라미터
const SPEED_P1: float = 77.0   # 일반 drone 110 × 0.7
const SPEED_P2: float = 165.0  # × 1.5
const SPEED_P3: float = 220.0
const BOMB_INTERVAL_P1: float = 1.7  # 피드백: 보스 폭탄 빈도 완화 (전 페이즈 소폭 증가)
const BOMB_INTERVAL_P2: float = 1.2
const BOMB_INTERVAL_P3: float = 0.9  # difficulty_analysis.md 권고(0.8~0.9)와 정합
const BOMB_TELEGRAPH: float = 0.5
const MISSILE_INTERVAL_P2: float = 3.5
const MISSILE_INTERVAL_P3: float = 2.5
const MISSILE_TELEGRAPH: float = 0.3
const MISSILE_SPEED: float = 380.0
const HOVER_Y: float = 280.0  # 호버 라인 (lab ground 820 기준 위쪽)
const HOVER_RANGE_X: Vector2 = Vector2(160.0, 1760.0)  # 좌/우 한계 (lab 1920 기준)
const TRACK_DEAD_ZONE: float = 80.0  # P2/P3 추적 시 dead zone

# 페이즈 전환 시 좌/우에서 소환되는 잔당 — 보스 본체에 묶이지 않은 압박.
# P2는 drone 2(천장 폭격), P3는 patrol 2(지면 추격)로 페이즈 차별화.
const SUMMON_OFFSET_X: float = 760.0
const SUMMON_DRONE_HP: int = 1
const SUMMON_PATROL_HP: int = 2

var hp: int = HP_MAX
var max_hp: int = HP_MAX          # HP 게이지 분모 — 성장 스케일(apply_hp_bonus)·스토리 축소 반영
var p2_threshold: int = HP_PHASE2
var p3_threshold: int = HP_PHASE3
# 인트로 홀드 — Stage 보스 인트로 컷씬(BGM 빌드업 구간) 동안 AI 정지. Stage가 켜고 끈다.
var intro_hold: bool = false
var phase: int = 1
# 스토리 모드 — _ready에서 GameState 보고 결정. true면 P2/P3 전환·잔당 소환 모두 생략.
var story_simplified: bool = false
var dir: int = 1  # 1=우, -1=좌
var dead: bool = false
var visual: Node2D
var touch_cd: float = 0.0
var bomb_cd: float = 0.8
var missile_cd: float = 3.0
var bomb_telegraph_t: float = 0.0   # >0: 텔레그래프 진행 중
var pending_bomb_x: float = 0.0
var missile_telegraph_t: float = 0.0
var pending_missile_dir: int = 0
var self_destruct_active: bool = false
var self_destruct_t: float = 0.0
var phase_freeze_t: float = 0.0  # 페이즈 전환 시 잠깐 정지 (시각적 강조)
var summoned_minions: Array = []  # 페이즈 소환 잔당 — 보스 처치 시 함께 정리.
var danger_ring_inner: Line2D = null  # 자폭 inner 빨간 외곽선
var danger_ring_outer: Line2D = null  # 자폭 outer 노랑 외곽선
var self_destruct_fall_v: float = 0.0  # 자폭 중 추락 속도 누적 (gravity-like)
var spark_t: float = 0.0  # 파지직 spawn 타이머
var _window_dmg: int = 0            # 배기 창 누적 피해
var vent_t: float = 0.0             # >0: 과부하 배기 중(무적)
var _fake_destruct_done: bool = false   # 위장 자폭 소진 여부
var _speed_mul: float = 1.0         # 재기동 후 이동 배속
var _vent_summon_kind: int = 2      # 배기 증원 타입 교대(드론↔순찰)
var _debris_nodes: Array = []       # P3 낙하 잔해(§6-3) — 사망 시 정리
# 과열 가독(2026-08-20 사용자 "김 나는 이펙트가 뭔지 모르겠다 · 뜬금없이 무적"): 창이 찰수록
# 몸체 주변이 달아오르고(예고 tell), 배기 중엔 라벨이 상태를 글자로 말한다.
var _heat_glow: Node2D = null
var _vent_label: Label = null

# 과열 글로우 — 창 누적(_window_dmg/cap)에 비례하는 주황 발광. modulate 틴트는 피격
# 플래시·페이즈 틴트가 덮어쓰므로(known_issues) 별도 자식 노드로 그린다.
class _HeatGlow extends Node2D:
	var heat: float = 0.0
	func _draw() -> void:
		if heat <= 0.02:
			return
		var a: float = clampf(heat, 0.0, 1.0)
		draw_circle(Vector2.ZERO, 58.0, Color(1.0, 0.42, 0.14, 0.14 * a))
		draw_circle(Vector2.ZERO, 40.0, Color(1.0, 0.55, 0.20, 0.30 * a))

func _set_heat(v: float) -> void:
	if _heat_glow == null:
		return
	(_heat_glow as _HeatGlow).heat = clampf(v, 0.0, 1.0)
	_heat_glow.queue_redraw()

# 텔레그래프 시각 노드
var bomb_dot: ColorRect = null
var wing_l: Polygon2D = null
var wing_r: Polygon2D = null

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	collision_layer = 4
	collision_mask = 1
	story_simplified = GameState.story_mode
	if story_simplified:
		max_hp = HP_MAX_STORY
		hp = HP_MAX_STORY
	# 콜리전 — 피격 면적 확대(피드백: 보스가 잘 안 맞음). 시각 2.5배와 같은 비율(56×40→70×50).
	# 상단 발판 위로 올라가지 않도록 mask=1만.
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70.0, 50.0)
	col.shape = shape
	add_child(col)
	# Visual — 일반 drone 스프라이트 2.5배 스케일 (피격 범위와 함께 확대)
	visual = CharacterArt.build_drone(self)
	visual.scale = Vector2(2.5, 2.5)
	# 텔레그래프용 빨간 점 (폭탄 발사 직전)
	bomb_dot = ColorRect.new()
	bomb_dot.color = Color(1.0, 0.20, 0.20, 0.0)
	bomb_dot.position = Vector2(-3.0, 18.0)
	bomb_dot.size = Vector2(6.0, 6.0)
	add_child(bomb_dot)
	# 날개(좌/우) 깜빡임 — P2/P3 미사일 발사 텔레그래프
	wing_l = Polygon2D.new()
	wing_l.color = Color(1.0, 0.20, 0.20, 0.0)
	wing_l.polygon = PackedVector2Array([
		Vector2(-32, -2), Vector2(-20, -2), Vector2(-20, 2), Vector2(-32, 2),
	])
	add_child(wing_l)
	wing_r = Polygon2D.new()
	wing_r.color = Color(1.0, 0.20, 0.20, 0.0)
	wing_r.polygon = PackedVector2Array([
		Vector2(20, -2), Vector2(32, -2), Vector2(32, 2), Vector2(20, 2),
	])
	add_child(wing_r)
	# 과열 글로우(몸체 뒤) + 배기 상태 라벨(몸체 위) — 배기 무적의 "왜"를 화면이 말하게.
	_heat_glow = _HeatGlow.new()
	_heat_glow.z_index = -1
	add_child(_heat_glow)
	_vent_label = Label.new()
	_vent_label.text = "과열 · 열 배출 중"
	_vent_label.add_theme_font_size_override("font_size", 13)
	_vent_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
	_vent_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_vent_label.add_theme_constant_override("outline_size", 4)
	_vent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vent_label.position = Vector2(-70.0, -92.0)
	_vent_label.size = Vector2(140.0, 18.0)
	_vent_label.visible = false
	add_child(_vent_label)

func _physics_process(delta: float) -> void:
	if dead:
		return
	# 인트로 컷씬 동안 완전 정지 — 공격/이동/접촉 판정 없음(플레이어가 대사를 읽는 시간).
	if intro_hold:
		velocity = Vector2.ZERO
		return
	touch_cd = max(0.0, touch_cd - delta)
	# 자폭 카운트다운 진행 — 일반 AI 대신 천천히 따라오며 추락 + 파지직.
	if self_destruct_active:
		self_destruct_t += delta
		if self_destruct_t >= SELF_DESTRUCT_TIME:
			_detonate()
			return
		_self_destruct_motion(delta)
		_emit_sparks(delta)
		return
	# 페이즈 전환 정지
	if phase_freeze_t > 0.0:
		phase_freeze_t -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		return
	# 과부하 배기 — 제자리 감속 + 증기 방출. 공격 정지(무방비는 증원이 메운다).
	if vent_t > 0.0:
		vent_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 420.0 * delta)
		move_and_slide()
		_emit_vent_steam(delta)
		# 배기가 진행될수록 달아오름이 식는다 — "열을 빼는 중"이 색으로 읽히게.
		_set_heat(vent_t / VENT_DURATION)
		if vent_t <= 0.0:
			_window_dmg = 0
			_set_heat(0.0)
			if _vent_label != null:
				_vent_label.visible = false
		return
	_move(delta)
	_attacks(delta)
	_check_touch_player()

# 자폭 중 보스 거동 — HOVER 라인 유지 대신 천천히 추락하며 플레이어 쪽으로 느슨한 추적.
func _self_destruct_motion(delta: float) -> void:
	var p: Node2D = _find_player()
	if p != null:
		var dx: float = p.global_position.x - global_position.x
		velocity.x = sign(dx) * SELF_DESTRUCT_CHASE_SPEED
		dir = int(sign(dx)) if abs(dx) > 1.0 else dir
	else:
		velocity.x = 0.0
	# 추락 — 가속도 누적 (지면에 닿을 때까지). 시각적으로 "통제 잃음".
	self_destruct_fall_v += SELF_DESTRUCT_FALL_ACCEL * delta
	velocity.y = self_destruct_fall_v
	move_and_slide()
	# 살짝 진동 (파지직 흔들림)
	if visual != null:
		visual.position = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

# 파지직(spark) — 0.12초 간격으로 보스 주변에 작은 노란/주황 라인 spawn.
# 0.25초 동안 fade-out 후 자동 정리.
func _emit_sparks(delta: float) -> void:
	spark_t -= delta
	if spark_t > 0.0:
		return
	spark_t = SPARK_INTERVAL
	var n: int = 3
	for i in n:
		var spark := Line2D.new()
		var ang: float = randf() * TAU
		var len: float = randf_range(14.0, 26.0)
		var jx: float = randf_range(-18.0, 18.0)
		var jy: float = randf_range(-12.0, 12.0)
		spark.points = PackedVector2Array([
			Vector2(jx, jy),
			Vector2(jx + cos(ang) * len * 0.5, jy + sin(ang) * len * 0.5),
			Vector2(jx + cos(ang + 0.4) * len, jy + sin(ang + 0.4) * len),
		])
		spark.width = 1.6
		spark.default_color = Color(1.0, 0.95, 0.45) if (i % 2 == 0) else Color(1.0, 0.55, 0.20)
		spark.z_index = 7
		add_child(spark)
		var tw: Tween = spark.create_tween()
		tw.tween_property(spark, "modulate:a", 0.0, 0.25)
		tw.tween_callback(spark.queue_free)

func _current_speed() -> float:
	var base: float = SPEED_P1
	match phase:
		2: base = SPEED_P2
		3: base = SPEED_P3
	return base * _speed_mul

func _move(_delta: float) -> void:
	var p: Node2D = _find_player()
	# Y는 HOVER_Y에 고정 (drone-like 호버), X는 페이즈별 행동
	if phase == 1:
		# 가로 왕복
		velocity.x = float(dir) * _current_speed()
		if global_position.x < HOVER_RANGE_X.x:
			dir = 1
		elif global_position.x > HOVER_RANGE_X.y:
			dir = -1
	else:
		# P2/P3 — 플레이어 추적 (느슨/적극)
		if p == null:
			velocity.x = 0.0
		else:
			var dx: float = p.global_position.x - global_position.x
			if abs(dx) < TRACK_DEAD_ZONE:
				velocity.x = 0.0
			else:
				velocity.x = sign(dx) * _current_speed()
				dir = int(sign(dx))
	# Y 회복 (HOVER_Y 라인으로)
	var dy: float = HOVER_Y - global_position.y
	velocity.y = clamp(dy * 4.0, -120.0, 120.0)
	move_and_slide()

func _attacks(delta: float) -> void:
	# 폭탄 — 모든 페이즈 공통 (간격만 다름)
	if bomb_telegraph_t > 0.0:
		bomb_telegraph_t -= delta
		# 점멸
		bomb_dot.color.a = 0.6 + 0.4 * sin(bomb_telegraph_t * 30.0)
		if bomb_telegraph_t <= 0.0:
			_drop_bomb()
			bomb_dot.color.a = 0.0
			bomb_cd = _bomb_interval()
	else:
		bomb_cd -= delta
		if bomb_cd <= 0.0:
			bomb_telegraph_t = BOMB_TELEGRAPH
			pending_bomb_x = global_position.x
	# 미사일 — P2/P3
	if phase >= 2:
		if missile_telegraph_t > 0.0:
			missile_telegraph_t -= delta
			var pulse: float = 0.5 + 0.5 * sin(missile_telegraph_t * 40.0)
			wing_l.color.a = pulse
			wing_r.color.a = pulse
			if missile_telegraph_t <= 0.0:
				_fire_missiles()
				wing_l.color.a = 0.0
				wing_r.color.a = 0.0
				missile_cd = (MISSILE_INTERVAL_P3 if phase == 3 else MISSILE_INTERVAL_P2)
		else:
			missile_cd -= delta
			if missile_cd <= 0.0:
				missile_telegraph_t = MISSILE_TELEGRAPH

func _bomb_interval() -> float:
	match phase:
		2: return BOMB_INTERVAL_P2
		3: return BOMB_INTERVAL_P3
	return BOMB_INTERVAL_P1

func _drop_bomb() -> void:
	SfxPlayer.play_at("bomb_throw", global_position)
	var bomb := Bomb.new()
	bomb.global_position = global_position + Vector2(0, 20.0)
	bomb.velocity = Vector2(0, 60.0)
	get_parent().add_child(bomb)

func _fire_missiles() -> void:
	# 좌/우 두 발 — 수평 이동, 플레이어 방향 노리지 않고 양방향으로 압박
	SfxPlayer.play_at("boss_missile_launch", global_position)
	_spawn_missile(global_position + Vector2(-30.0, -2.0), -1)
	_spawn_missile(global_position + Vector2(30.0, -2.0), 1)

func _spawn_missile(pos: Vector2, side: int) -> void:
	var m := Area2D.new()
	m.set_script(load("res://scripts/BossMissile.gd"))
	m.global_position = pos
	m.set("velocity", Vector2(MISSILE_SPEED * float(side), 0.0))
	get_parent().add_child(m)

func _check_touch_player() -> void:
	if touch_cd > 0.0:
		return
	var p: Node2D = _find_player()
	if p == null:
		return
	if global_position.distance_to(p.global_position) < 50.0:
		if p.has_method("take_hit"):
			p.take_hit(TOUCH_DAMAGE)
			touch_cd = TOUCH_COOLDOWN

func _find_player() -> Node2D:
	for n in get_tree().get_nodes_in_group("player"):
		if n is Node2D:
			return n as Node2D
	return null

# 플레이어 성장 스케일(2026-08-10) — 15스테이지 확장으로 s8 시점 화력이 원 설계(9스테이지)보다 높아
# 보스가 너무 빨리 녹는다는 피드백. 공격 계열 티어에 비례한 HP 가산 + 페이즈 임계도 같은 비율(2/3·1/3)
# 유지. 자폭 버퍼(HP_SELF_DESTRUCT)는 절대값 유지 — 연출 보장 목적이라 스케일 불필요.
func apply_hp_bonus(bonus: int) -> void:
	if bonus <= 0 or story_simplified:
		return
	max_hp = HP_MAX + bonus
	hp = max_hp
	p2_threshold = HP_PHASE2 + int(round(float(bonus) * 2.0 / 3.0))
	p3_threshold = HP_PHASE3 + int(round(float(bonus) / 3.0))

func take_damage(amount: int, _from_dir: int = 0) -> void:
	if dead:
		return
	# 페이즈 전환 동안은 무적 — 플레이어가 페이즈 연출을 인지할 시간 보장.
	if phase_freeze_t > 0.0:
		return
	# 자폭 카운트다운 중에는 무적 — 이미 날아오던 총알/연사에 즉사시키지 않고 자폭 시퀀스를
	# 끝까지 보여준다. (이전엔 자폭 진입 직후 잔탄에 맞아 카운트다운이 안 보이고 바로 처치되던
	# 문제 — 사용자 보고. 처치는 카운트다운 종료 → _detonate → _die로만 일어남.)
	if self_destruct_active:
		return
	# 과부하 배기 중 — HP는 안 깎이지만 맞을 때마다 배출이 빨라진다(강제 배출). 사격을 멈출
	# 이유가 없어져 배기가 대기 시간이 아니라 연속 사격 창이 된다. 바닥은 0.05로 클램프 —
	# 여기서 0으로 만들면 _physics_process의 배기 종료 정리(창 리셋·라벨 소등)를 건너뛰어
	# "창 가득 + 배기 없음" 데드락이 된다(다음 물리 틱이 자연 종료하게 맡긴다).
	if vent_t > 0.0:
		vent_t = maxf(0.05, vent_t - VENT_HIT_SHAVE)
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -12.0)
		return
	# 창당 피해 상한 — 초과분은 흘려보낸다(고화력 즉사 차단 · 시간 하한).
	if not story_simplified:
		var cap: int = maxi(4, int(ceil(float(max_hp) / VENT_DIVISOR)))
		var allowed: int = cap - _window_dmg
		if allowed <= 0:
			# 가득 찬 창에 또 맞으면 즉시 배기 — 페이즈 freeze와 겹쳐 배기가 보류된 경우
			# 여기서라도 걸어 준다(안 걸면 "창 가득 + 배기 없음" = 영구 무적 데드락 · 하니스 실측).
			SfxPlayer.play_at("bullet_deflect_shield", global_position, -8.0)
			if phase_freeze_t <= 0.0:
				_enter_vent()
			return
		amount = mini(amount, allowed)
		_window_dmg += amount
		# 과열 예고 tell — 창이 찰수록 몸체가 달아오른다(배기의 "왜"를 미리 보여줌).
		_set_heat(float(_window_dmg) / float(cap))
	hp = max(0, hp - amount)
	_flash_hit()
	if hp > 0:
		SfxPlayer.play_at("boss_hurt", global_position)
	# 페이즈 전환 검사 — 자폭 진입 후에는 페이즈 재전환 안 함. 임계는 성장 스케일 반영 인스턴스 값.
	if not story_simplified:
		if phase < 2 and hp <= p2_threshold:
			_transition_to(2)
		elif phase < 3 and hp <= p3_threshold:
			_transition_to(3)
	# 자폭 트리거 — HP 임계 이하로 떨어지면 카운트다운 시작. 버퍼(HP_SELF_DESTRUCT)를 둬
	# 트리거와 동시에 hp가 0이 되어 즉사하는 걸 방지. 진입하면 위 무적으로 항상 끝까지 자폭한다.
	var sd_threshold: int = HP_SELF_DESTRUCT_STORY if story_simplified else HP_SELF_DESTRUCT
	if hp <= sd_threshold:
		_arm_self_destruct()
		return
	if hp <= 0:
		_die()
		return
	# 창 상한 도달 → 과부하 배기(무적 3s + 증기 + 증원 1기). 페이즈 freeze 중이면 그 뒤로.
	if not story_simplified and _window_dmg >= maxi(4, int(ceil(float(max_hp) / VENT_DIVISOR))) 			and phase_freeze_t <= 0.0:
		_enter_vent()

func _flash_hit() -> void:
	if visual == null:
		return
	visual.modulate = Color(1.4, 1.0, 1.0, 1.0)
	var tw := visual.create_tween()
	tw.tween_property(visual, "modulate", Color(1, 1, 1, 1), 0.18)

func _transition_to(new_phase: int) -> void:
	phase = new_phase
	phase_freeze_t = PHASE_FREEZE_DURATION
	SfxPlayer.play_at("boss_phase_change", global_position)
	# 텔레그래프 노드 리셋 — 전환 직후 잔존 점등이 어색.
	bomb_telegraph_t = 0.0
	missile_telegraph_t = 0.0
	if bomb_dot != null:
		bomb_dot.color.a = 0.0
	if wing_l != null:
		wing_l.color.a = 0.0
	if wing_r != null:
		wing_r.color.a = 0.0
	# 페이즈별 visual tint — 색으로 인지 보강
	if visual != null:
		match new_phase:
			2: visual.self_modulate = Color(1.2, 0.85, 0.65)  # 주황 tint
			3: visual.self_modulate = Color(1.4, 0.55, 0.55)  # 빨강 tint
			_: visual.self_modulate = Color(1, 1, 1)
	# deferred — take_damage(물리 콜백) 경로에서 동기 스폰하면 "flushing queries" 에러로
	# 콜리전 설정이 거부된다(2026-08-20 실플레이 로그 실측, known_issues).
	call_deferred("_summon_minions", new_phase)
	# P3 불안정 구간 — 낙하 잔해 2존(final_boss_rework §6-3 · 자폭 문법과 정합 · 가벼운 빈도).
	# lab ground 820 기준(HOVER 상수들과 같은 좌표계). 사망 시 _debris_nodes로 정리.
	if new_phase == 3 and not story_simplified and _debris_nodes.is_empty():
		for cfg0 in [{"x_min": 300.0, "x_max": 800.0, "interval": 7.0},
				{"x_min": 1150.0, "x_max": 1650.0, "interval": 8.0, "phase": 0.5}]:
			var fd := FallingDebris.new()
			get_parent().add_child(fd)
			fd.setup(cfg0, 820.0)
			_debris_nodes.append(fd)
	emit_signal("phase_changed", new_phase)

# 과부하 배기 진입 — 무적 3s + 증기 + 증원 1기(상한 안에서). 배기가 끝나면 창 리셋.
func _enter_vent() -> void:
	if vent_t > 0.0 or self_destruct_active or dead:
		return
	vent_t = VENT_DURATION
	SfxPlayer.play_at("hatch_open", global_position)
	# 가독 — 달아오름 최대 + 상태 라벨 점등(첫 배기 VEIL 해설은 Stage가 vent_started로).
	_set_heat(1.0)
	if _vent_label != null:
		_vent_label.visible = true
	emit_signal("vent_started")
	# 증원은 deferred — _enter_vent는 take_damage(물리 콜백)에서 불려 동기 스폰 시
	# "flushing queries" 에러로 콜리전 설정이 거부된다(2026-08-20 실측).
	call_deferred("_vent_summon")

# 배기 증원 1기 — 배기 중 무방비를 잡몹이 메운다. 타입은 드론↔순찰 교대, 상한 준수.
func _vent_summon() -> void:
	if dead or phase < 2:
		return
	var alive: int = 0
	for m in summoned_minions:
		if is_instance_valid(m) and not bool((m as Node).get("dead")):
			alive += 1
	if alive < VENT_SUMMON_CAP:
		var kind: int = _vent_summon_kind
		_vent_summon_kind = 0 if _vent_summon_kind == 2 else 2
		var y: float = HOVER_Y if kind == 2 else (global_position.y + 280.0)
		var side: float = -1.0 if randf() < 0.5 else 1.0
		var pos := Vector2(clampf(global_position.x + side * SUMMON_OFFSET_X, 140.0, 1780.0), y)
		var hp_for: int = SUMMON_DRONE_HP if kind == 2 else SUMMON_PATROL_HP
		var m2: CharacterBody2D = _spawn_minion(kind, pos, hp_for)
		if m2 != null:
			summoned_minions.append(m2)

# 배기 증기 — 몸체 좌우로 청백 증기 사각이 흩어진다(시각 tell · 피격 플래시(modulate)와
# 페이즈 틴트(self_modulate)를 건드리지 않는 별도 노드 — known_issues 틴트 충돌 규칙).
func _emit_vent_steam(delta: float) -> void:
	spark_t -= delta
	if spark_t > 0.0:
		return
	spark_t = 0.10
	for i in 2:
		var puff := ColorRect.new()
		puff.color = Color(0.75, 0.88, 0.95, 0.55)
		var sz: float = randf_range(6.0, 14.0)
		puff.size = Vector2(sz, sz)
		puff.position = Vector2(randf_range(-46.0, 46.0), randf_range(-16.0, 16.0))
		puff.z_index = 5
		add_child(puff)
		var tw := puff.create_tween()
		tw.set_parallel(true)
		tw.tween_property(puff, "position", puff.position + Vector2(randf_range(-40.0, 40.0), -70.0), 0.6)
		tw.tween_property(puff, "modulate:a", 0.0, 0.6)
		tw.chain().tween_callback(puff.queue_free)

# 위장 자폭 후 재기동 — 링 정리 + 소량 재점화 HP + 배속. Stage가 disarm 시그널로
# 배너를 걷고 재기동 자막을 낸다. freeze 무적 1.2s로 인지 시간 보장.
func _reignite() -> void:
	_fake_destruct_done = true
	self_destruct_active = false
	self_destruct_t = 0.0
	self_destruct_fall_v = 0.0
	_window_dmg = 0
	for ring in [danger_ring_inner, danger_ring_outer]:
		if ring != null and is_instance_valid(ring):
			ring.queue_free()
	danger_ring_inner = null
	danger_ring_outer = null
	hp = maxi(hp, int(ceil(float(max_hp) * REIGNITE_HP_RATIO)))
	_speed_mul = REIGNITE_SPEED_MUL
	phase = 3
	phase_freeze_t = PHASE_FREEZE_DURATION
	SfxPlayer.play_at("boss_self_destruct_disarm", global_position)
	if visual != null:
		visual.self_modulate = Color(1.4, 0.55, 0.55)
	emit_signal("self_destruct_disarmed")

# 페이즈 전환 시 좌/우 화면 가장자리 위쪽에서 잔당 2마리 spawn.
# P2 = drone 2 (천장 폭격으로 지상 압박), P3 = patrol 2 (지면 추격으로 회피 동선 좁힘).
# freeze 1.2s 동안 spawn되니까 플레이어가 인지할 시간 있음.
func _summon_minions(new_phase: int) -> void:
	# 0=patrol, 2=drone (Stage._spawn_enemy의 kind와 일치)
	var kind: int = 2 if new_phase == 2 else 0
	var hp_for: int = SUMMON_DRONE_HP if kind == 2 else SUMMON_PATROL_HP
	# drone은 호버 라인 부근, patrol은 지면 위로 spawn.
	var y: float = HOVER_Y if kind == 2 else (global_position.y + 280.0)
	# X는 ARENA(1920) 안쪽으로 클램프 — 보스가 한쪽에 치우친 채 전환되면 보스 기준 ±760이
	# 벽 밖으로 나가, patrol이 좌하단 구석에 낀 채 방치됐다(사용자 보고 2026-08-14).
	var positions: Array = [
		Vector2(clampf(global_position.x - SUMMON_OFFSET_X, 140.0, 1780.0), y),
		Vector2(clampf(global_position.x + SUMMON_OFFSET_X, 140.0, 1780.0), y),
	]
	for pos in positions:
		var m: CharacterBody2D = _spawn_minion(kind, pos, hp_for)
		if m != null:
			summoned_minions.append(m)

func _spawn_minion(kind: int, pos: Vector2, hp_value: int) -> CharacterBody2D:
	var parent: Node = get_parent()
	if parent == null:
		return null
	var e := CharacterBody2D.new()
	e.set_script(load("res://scripts/Enemy.gd"))
	e.collision_layer = 4
	e.collision_mask = 1
	e.set("enemy_type", kind)
	e.set("hp", hp_value)
	# patrol 소환수는 사냥 모드 — 감지 범위(260px) 밖에서 스폰되면 제자리 순찰만 하다
	# 구석에 머물러 "끼어 있다"로 읽힌다. P3 의도(지면 추격으로 동선 좁힘)와도 사냥이 맞다.
	if kind == 0:
		e.set("hunt", true)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	if kind == 2:
		shape.size = Vector2(42.0, 32.0)  # 일반 drone과 동일 (시각 1.3배는 Enemy.gd)
		col.position = Vector2(0, 0)
	else:
		shape.size = Vector2(28.0, 40.0)
		col.position = Vector2(0, -20.0)
	col.shape = shape
	e.add_child(col)
	parent.add_child(e)
	e.global_position = pos
	return e

func _arm_self_destruct() -> void:
	self_destruct_active = true
	self_destruct_t = 0.0
	SfxPlayer.play_at("boss_self_destruct_alarm", global_position)
	# 위험 영역 시각화 — inner(380, 풀뎀) 빨강, outer(1200, 1뎀) 노랑.
	# outer 너머가 안전 영역. ARENA 1920이라 벽 끝까지 도망가면 outer 너머 도달.
	danger_ring_inner = _make_danger_ring(SELF_DESTRUCT_INNER, Color(0.95, 0.25, 0.25, 0.85), 4.0)
	danger_ring_outer = _make_danger_ring(SELF_DESTRUCT_OUTER, Color(0.95, 0.78, 0.30, 0.65), 3.0)
	add_child(danger_ring_inner)
	add_child(danger_ring_outer)
	# 두 ring 모두 펄스 — 카운트다운 인지.
	# 주의: array literal로 묶어 for 돌리면 ring이 Variant로 추론돼
	# `var tw := ring.create_tween()`의 := 타입 추론이 파서를 막는다.
	_pulse_ring(danger_ring_inner)
	_pulse_ring(danger_ring_outer)
	emit_signal("self_destruct_started")

func _pulse_ring(ring: Line2D) -> void:
	var tw: Tween = ring.create_tween()
	tw.set_loops()
	tw.tween_property(ring, "modulate:a", 0.45, 0.4)
	tw.tween_property(ring, "modulate:a", 1.0, 0.4)

func _make_danger_ring(radius: float, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	var pts: PackedVector2Array = []
	var n: int = 64
	for i in n + 1:
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	line.points = pts
	line.default_color = color
	line.width = width
	line.z_index = 6
	return line

func _detonate() -> void:
	# 거리 감쇠: inner 안=full 3뎀, outer 너머=1뎀, 그 사이는 lerp.
	# ARENA 1920에서 끝까지 도망쳐도 거리 ≈1700이라 1뎀 회피 가능.
	for n in get_tree().get_nodes_in_group("player"):
		if not (n is Node2D):
			continue
		var p := n as Node2D
		var dist: float = p.global_position.distance_to(global_position)
		var dmg: int = SELF_DESTRUCT_DAMAGE
		if dist >= SELF_DESTRUCT_OUTER:
			dmg = SELF_DESTRUCT_DAMAGE_MIN
		elif dist > SELF_DESTRUCT_INNER:
			# inner~outer 사이에서 3 → 1로 선형 감쇠
			var t_lerp: float = (dist - SELF_DESTRUCT_INNER) / (SELF_DESTRUCT_OUTER - SELF_DESTRUCT_INNER)
			dmg = int(round(lerp(float(SELF_DESTRUCT_DAMAGE), float(SELF_DESTRUCT_DAMAGE_MIN), t_lerp)))
		if p.has_method("take_hit"):
			p.take_hit(dmg)
	# 거대한 폭발 시각 효과
	var blast := Polygon2D.new()
	blast.color = Color(1.0, 0.35, 0.20, 0.9)
	blast.z_index = 8
	var pts: Array = []
	for i in 32:
		var a: float = float(i) * TAU / 32.0
		pts.append(Vector2(cos(a) * 480.0, sin(a) * 480.0))
	blast.polygon = PackedVector2Array(pts)
	blast.global_position = global_position
	blast.scale = Vector2(0.1, 0.1)
	get_parent().add_child(blast)
	var tw := blast.create_tween()
	tw.set_parallel(true)
	tw.tween_property(blast, "scale", Vector2(1.0, 1.0), 0.5)
	tw.tween_property(blast, "modulate", Color(1, 1, 1, 0), 0.7)
	tw.chain().tween_callback(blast.queue_free)
	# 위장 자폭(1회) — 첫 폭발은 피해·시각까지 진짜와 동일하지만 코어가 재점화한다.
	# 페이크 보스 서사(§7)의 전투 내 실연 · 두 번째 자폭이 진짜(기존 흐름 그대로).
	if not _fake_destruct_done and not story_simplified:
		_reignite()
		return
	# 자폭으로 사망 처리
	_die()

# 자폭 진입 후에는 보스가 무적(take_damage 무시)이라, 처치는 카운트다운 종료 → _detonate → _die로만
# 일어난다. 즉 _die 도달 시 항상 자폭 폭발이 끝난 상태. (이전엔 카운트다운 중 처치로 disarm되는
# 경로가 있었으나, 잔탄에 자폭이 안 보이고 즉사하던 문제로 제거 — 사용자 보고.)
func _die() -> void:
	if dead:
		return
	dead = true
	SfxPlayer.play_at("boss_death", global_position)
	# 보스가 죽으면 소환된 잔당도 함께 정리 — ARENA에 잔존 적이 남아 클리어 흐름이 어색해지는 것 방지.
	for m in summoned_minions:
		if is_instance_valid(m):
			m.queue_free()
	summoned_minions.clear()
	for fd in _debris_nodes:
		if is_instance_valid(fd):
			(fd as Node).queue_free()
	_debris_nodes.clear()
	emit_signal("self_destruct_disarmed")
	emit_signal("killed", global_position)
	# 시각적 사라짐
	var tw := visual.create_tween() if visual != null else null
	if tw != null:
		tw.tween_property(visual, "modulate:a", 0.0, 0.4)
		tw.tween_callback(queue_free)
	else:
		queue_free()
