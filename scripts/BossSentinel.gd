class_name BossSentinel
extends CharacterBody2D

# 핵심부(lab) ARENA 보스. 명세: docs/design/world_layout.md §2.10
# 3페이즈 구조 · HP 12 → 8(P2 전환) → 4(P3 전환) → 0(자폭 카운트다운).
# 적 그룹("enemy")에 추가돼서 ARENA enemy_clear 카운트에 자연스럽게 포함된다.
# Stage가 killed 시그널을 받아 클리어 처리.

signal killed(at_position: Vector2)
signal phase_changed(new_phase: int)
signal self_destruct_started
signal self_destruct_disarmed
signal vent_started
signal overheat_stalled
signal sweep_telegraphed

# 전면 리워크(2026-08-25 사용자 C안, sentinel_rework.md §8): 무대 세로 확장(2200x1300 ·
# ARENA_FOLLOW) + P2+ 고도 추적·데크 스윕(상층 캠핑 해소) + 배기 리듬 완화. 5차 갤러리 지적
# "체력이 적어 과열 패턴만 잦고 귀찮다" · HP 36→52 · 창당 상한 분모 5.5→3.8로 배기를
# ~5회→~3회로 줄이고 창 하나를 길게. 목표 전투 시간 60~90s 유지(창 수가 아니라 이동·회피
# 부하가 시간을 만든다). 14-1은 이보다 길게(§7).
const HP_MAX: int = 52
const HP_PHASE2: int = 36  # 이 값 이하 들어오면 P2 (~69%)
const HP_PHASE3: int = 19  # 이 값 이하 들어오면 P3 (~37%)
const HP_SELF_DESTRUCT: int = 8  # 이 값 이하 시 자폭 카운트다운 시작 (버퍼 · 잔탄에 즉사 방지, 자폭 시퀀스 보장)
const HP_SELF_DESTRUCT_STORY: int = 2  # 스토리 보스(HP 8)는 더 낮게 · 충분히 싸운 뒤 자폭
# 스토리 모드 · P2/P3 스킵, 자폭 트리거까지 짧게.
const HP_MAX_STORY: int = 8
const PHASE_FREEZE_DURATION: float = 1.2  # 페이즈 전환 시 정지 + 무적 시간

# 과부하 배기(vent) · 창당 피해 상한(FalseVeil max_hp/6 문법 이식 · 2026-08-19 보스전 확대).
# 어떤 화력이든 배기 ~7회를 상대해야 자폭 임계에 닿는다 = 시간 하한 보장(known_issues:
# "수치 상향만으론 평소와 같음" · HP가 아니라 창이 길이를 만든다). 배기 중 무적 + 증기 방출
# + 증원 1기 호출(무방비를 잡몹이 메운다). 스토리 모드는 미적용(짧게 유지).
# 창당 상한 분모 8.0→5.5(2026-08-20)→3.8(2026-08-25 리워크 §8 "과열 패턴이 쓸데없이 잦다"):
# 52HP 기준 배기 ~3회 · 창 하나가 길어 사격 리듬이 덜 끊긴다. 배기 자체도 3.0→2.6s 단축.
const VENT_DIVISOR: float = 3.8
const VENT_DURATION: float = 2.6
# 강제 배출(2026-08-20 재해석) · 배기 중 피격 1발당 배기 시간 단축. 배기가 "기다리는 무적"이
# 아니라 "쏘면 빨리 끝나는 창"이 된다. 고화력 빌드일수록 배기가 짧아져 잦음이 상쇄된다.
# 계산: 기본 연사(1발/0.42s) 사격 시 3s 배기 ≈ 1.8s에 종료 · 오연사 만렙 ≈ 0.7s.
const VENT_HIT_SHAVE: float = 0.3
const VENT_SUMMON_CAP: int = 4       # 배기 증원 포함 동시 소환수 상한
# 위장 자폭(1회) · 페이크 보스 서사(§7 "이긴 순간을 이긴 것 같지 않게")의 전투 내 실연.
# 첫 자폭은 진짜처럼 터지지만 코어가 재점화한다. 두 번째 자폭이 진짜(기존 흐름).
const REIGNITE_HP_RATIO: float = 0.18
const REIGNITE_SPEED_MUL: float = 1.15

# 증기 과열 실속(2026-08-22 카운터플레이) · P2가 소환한 시설 설비를 플레이어도 되받아친다.
# 이 기체의 전투 리듬 자체가 열 관리(창 누적 → 달아오름 → 배기)다 · 증기 기둥(분출 중 열기둥
# 포함)에 걸리면 코어가 열을 못 이겨 잠깐 멎는다 = 실속. 실속 동안은 창당 상한 없이 직결 ·
# "잘하면 빨라지는" 경로(보스를 증기 위로 유인하는 조종 스킬이 전투 시간을 줄인다).
const STALL_DURATION: float = 2.4
const STALL_COOLDOWN: float = 9.0     # 연쇄 스턴 방지(분출 주기 3.2s × 분출구 2기)
const STALL_HALF_X: float = 60.0      # 기둥 x 겹침 판정 반폭(기둥 32 + 몸체 35)

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
# P1 호버 = 데크 2단(528)과 같은 높이 · 데크 2단에선 수평 사격, 데크 1단(668)·연결
# 플레이트(600)에선 점프샷이 닿는다. 400으로 두면 데크 2단 점프샷만 닿아 왕복(77px/s)
# 보스가 사거리 밖에 머무는 시간이 너무 길다(리워크 §8 검증 중 발견).
const HOVER_Y: float = 520.0
const HOVER_RANGE_X: Vector2 = Vector2(200.0, 2000.0)  # 좌/우 한계 (lab 2200 기준)
const TRACK_DEAD_ZONE: float = 80.0  # P2/P3 추적 시 dead zone
# P2+ 고도 추적(리워크 §8) · 플레이어 고도보다 TRACK_OFFSET_Y 위 밴드로 내려온다.
# 상층 캠핑이 영구 안전지대가 아니게 하는 축 · 낮게 유인하면 증기 실속 사거리에 든다.
# 완화(2026-08-25 7차 갤러리 "고도 추적 여전히 짜증"): 오프셋 260→340(더 위에 머묾) ·
# 하한 980→860(지면까지 쫓아 내려오지 않음) · 수직 추적 속도는 _move에서 150→110.
const HOVER_Y_MIN: float = 400.0
const HOVER_Y_MAX: float = 860.0
const TRACK_OFFSET_Y: float = 340.0
const GROUND_Y_LAB: float = 1220.0   # 자폭 추락 바닥(콜리전 대신 수동 클램프 · 비행체는 발판 관통)
# 데크 스윕(리워크 §8 신설) · P2+에서 주기적으로 플레이어 고도를 예고한 뒤 수평 관통 돌진.
# "어느 발판이든 스윕 한 번이면 비켜야 한다"의 앵커 패턴. 예고 0.8s + 경로 표시선(예고 원칙 준수).
const SWEEP_INTERVAL_P2: float = 7.5
const SWEEP_INTERVAL_P3: float = 5.2
const SWEEP_TELEGRAPH: float = 0.8
const SWEEP_SPEED: float = 640.0
const SWEEP_Y_MAX: float = 1140.0   # 지면(1220) 위 여유 · 지면 깔기 금지

# 페이즈 전환 시 좌/우에서 소환되는 잔당 · 보스 본체에 묶이지 않은 압박.
# P2는 drone 2(천장 폭격), P3는 patrol 2(지면 추격)로 페이즈 차별화.
const SUMMON_OFFSET_X: float = 760.0
const SUMMON_DRONE_HP: int = 1
const SUMMON_PATROL_HP: int = 2

var hp: int = HP_MAX
var max_hp: int = HP_MAX          # HP 게이지 분모 · 성장 스케일(apply_hp_bonus)·스토리 축소 반영
var p2_threshold: int = HP_PHASE2
var p3_threshold: int = HP_PHASE3
# 인트로 홀드 · Stage 보스 인트로 컷씬(BGM 빌드업 구간) 동안 AI 정지. Stage가 켜고 끈다.
var intro_hold: bool = false
var phase: int = 1
# 스토리 모드 · _ready에서 GameState 보고 결정. true면 P2/P3 전환·잔당 소환 모두 생략.
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
var summoned_minions: Array = []  # 페이즈 소환 잔당 · 보스 처치 시 함께 정리.
var danger_ring_inner: Line2D = null  # 자폭 inner 빨간 외곽선
var danger_ring_outer: Line2D = null  # 자폭 outer 노랑 외곽선
var self_destruct_fall_v: float = 0.0  # 자폭 중 추락 속도 누적 (gravity-like)
var spark_t: float = 0.0  # 파지직 spawn 타이머
var _window_dmg: int = 0            # 배기 창 누적 피해
var vent_t: float = 0.0             # >0: 과부하 배기 중(무적)
var stall_t: float = 0.0            # >0: 증기 과열 실속 중(상한 없이 직결)
var _stall_cd: float = 0.0
var _fake_destruct_done: bool = false   # 위장 자폭 소진 여부
var _speed_mul: float = 1.0         # 재기동 후 이동 배속
var _vent_summon_kind: int = 2      # 배기 증원 타입 교대(드론↔순찰)
var _debris_nodes: Array = []       # P3 낙하 잔해(§6-3) · 사망 시 정리
# 데크 스윕 상태(리워크 §8) · 0=없음 · 1=예고(고도 조준+날개 점멸+경로선) · 2=관통 돌진.
var _sweep_state: int = 0
var _sweep_t: float = 0.0
var _sweep_y: float = 0.0
var _sweep_dir: int = 1
var _sweep_cd: float = 5.0          # P2 진입 직후 첫 스윕까지 유예
var _sweep_line: Line2D = null
# 과열 가독(2026-08-20 사용자 "김 나는 이펙트가 뭔지 모르겠다 · 뜬금없이 무적"): 창이 찰수록
# 몸체 주변이 달아오르고(예고 tell), 배기 중엔 라벨이 상태를 글자로 말한다.
var _heat_glow: Node2D = null
var _vent_label: Label = null

# 과열 글로우 · 창 누적(_window_dmg/cap)에 비례하는 주황 발광. modulate 틴트는 피격
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
	# 리워크 §8 · 비행체는 발판을 관통한다(mask 0). 구 무대(발판 위 고정 호버)에선 mask 1이어도
	# 부딪힐 일이 없었지만, 고도 추적·스윕은 발판 밴드를 지나다녀 물리 충돌이 곧 낑김이다.
	# 자폭 추락의 착지는 GROUND_Y_LAB 수동 클램프가 대신한다.
	collision_mask = 0
	story_simplified = GameState.story_mode
	if story_simplified:
		max_hp = HP_MAX_STORY
		hp = HP_MAX_STORY
	# 콜리전 · 피격 면적 확대(피드백: 보스가 잘 안 맞음). 시각 2.5배와 같은 비율(56×40→70×50).
	# 상단 발판 위로 올라가지 않도록 mask=1만.
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(70.0, 50.0)
	col.shape = shape
	add_child(col)
	# Visual · 일반 drone 스프라이트 2.5배 스케일 (피격 범위와 함께 확대)
	visual = CharacterArt.build_drone(self)
	visual.scale = Vector2(2.5, 2.5)
	# 텔레그래프용 빨간 점 (폭탄 발사 직전)
	bomb_dot = ColorRect.new()
	bomb_dot.color = Color(1.0, 0.20, 0.20, 0.0)
	bomb_dot.position = Vector2(-3.0, 18.0)
	bomb_dot.size = Vector2(6.0, 6.0)
	add_child(bomb_dot)
	# 날개(좌/우) 깜빡임 · P2/P3 미사일 발사 텔레그래프
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
	# 과열 글로우(몸체 뒤) + 배기 상태 라벨(몸체 위) · 배기 무적의 "왜"를 화면이 말하게.
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
	# 인트로 컷씬 동안 완전 정지 · 공격/이동/접촉 판정 없음(플레이어가 대사를 읽는 시간).
	if intro_hold:
		velocity = Vector2.ZERO
		return
	touch_cd = max(0.0, touch_cd - delta)
	# 자폭 카운트다운 진행 · 일반 AI 대신 천천히 따라오며 추락 + 파지직.
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
	_stall_cd = maxf(0.0, _stall_cd - delta)
	# 증기 과열 실속 · 제어를 잃고 살짝 가라앉는다. 공격 정지 · 피해는 상한 없이 직결(take_damage).
	if stall_t > 0.0:
		stall_t -= delta
		velocity = velocity.move_toward(Vector2(0.0, 55.0), 360.0 * delta)
		move_and_slide()
		_emit_sparks(delta)
		_set_heat(1.0)
		if visual != null:
			visual.position = Vector2(randf_range(-2.5, 2.5), randf_range(-2.5, 2.5))
		if stall_t <= 0.0:
			_stall_cd = STALL_COOLDOWN
			_set_heat(0.0)
			if visual != null:
				visual.position = Vector2.ZERO
			if _vent_label != null:
				_vent_label.visible = false
				_vent_label.text = "과열 · 열 배출 중"
				_vent_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
		return
	# 과부하 배기 · 제자리 감속 + 증기 방출. 공격 정지(무방비는 증원이 메운다).
	if vent_t > 0.0:
		vent_t -= delta
		velocity = velocity.move_toward(Vector2.ZERO, 420.0 * delta)
		move_and_slide()
		_emit_vent_steam(delta)
		# 배기가 진행될수록 달아오름이 식는다 · "열을 빼는 중"이 색으로 읽히게.
		_set_heat(vent_t / VENT_DURATION)
		if vent_t <= 0.0:
			_window_dmg = 0
			_set_heat(0.0)
			if _vent_label != null:
				_vent_label.visible = false
		return
	# 데크 스윕 진행 중 · 일반 이동/공격 대신 스윕 상태기. 접촉 판정은 유지(관통이 곧 공격).
	if _sweep_state != 0:
		_sweep_process(delta)
		_check_touch_player()
		return
	_move(delta)
	_attacks(delta)
	_check_touch_player()
	_check_steam_overheat()
	# 데크 스윕 쿨다운(P2+ · 리워크 §8) · 배기/실속/전환이 아닌 평시에만 흐른다.
	if phase >= 2 and not story_simplified:
		_sweep_cd -= delta
		if _sweep_cd <= 0.0:
			_begin_sweep()

# 증기 기둥 겹침 판정 · 분출 중인 SteamVent(짙은 증기 + 열기둥) 위에 겹치면 실속.
# 플레이어가 분출구 근처로 유인해 타이밍을 맞추는 조종 플레이(자기도 증기에 맞을 리스크 교환).
func _check_steam_overheat() -> void:
	if _stall_cd > 0.0 or phase < 2 or story_simplified:
		return
	for v in get_tree().get_nodes_in_group("steam_vent"):
		if not (v is SteamVent):
			continue
		var sv := v as SteamVent
		if sv.plume_height <= 0.0 or not sv.is_bursting():
			continue
		if absf(global_position.x - sv.global_position.x) > STALL_HALF_X:
			continue
		var up: float = sv.global_position.y - global_position.y
		if up >= 0.0 and up <= sv.height + sv.plume_height:
			_enter_stall()
			return

func _enter_stall() -> void:
	if stall_t > 0.0 or vent_t > 0.0 or self_destruct_active or dead or phase_freeze_t > 0.0:
		return
	_cancel_sweep()
	stall_t = STALL_DURATION
	# 진행 중이던 텔레그래프 취소 · 실속 중 공격 없음.
	bomb_telegraph_t = 0.0
	missile_telegraph_t = 0.0
	if bomb_dot != null:
		bomb_dot.color.a = 0.0
	if wing_l != null:
		wing_l.color.a = 0.0
	if wing_r != null:
		wing_r.color.a = 0.0
	SfxPlayer.play_at("boss_hurt", global_position)
	SfxPlayer.play_at("hatch_open", global_position, -4.0)
	_set_heat(1.0)
	if _vent_label != null:
		_vent_label.text = "과열 · 제어 불능"
		_vent_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.35))
		_vent_label.visible = true
	emit_signal("overheat_stalled")

# 자폭 중 보스 거동 · HOVER 라인 유지 대신 천천히 추락하며 플레이어 쪽으로 느슨한 추적.
func _self_destruct_motion(delta: float) -> void:
	var p: Node2D = _find_player()
	if p != null:
		var dx: float = p.global_position.x - global_position.x
		velocity.x = sign(dx) * SELF_DESTRUCT_CHASE_SPEED
		dir = int(sign(dx)) if abs(dx) > 1.0 else dir
	else:
		velocity.x = 0.0
	# 추락 · 가속도 누적. 시각적으로 "통제 잃음". mask 0(발판 관통)이라 착지는 수동 클램프.
	self_destruct_fall_v += SELF_DESTRUCT_FALL_ACCEL * delta
	velocity.y = self_destruct_fall_v
	move_and_slide()
	if global_position.y >= GROUND_Y_LAB - 30.0:
		global_position.y = GROUND_Y_LAB - 30.0
		self_destruct_fall_v = 0.0
	# 살짝 진동 (파지직 흔들림)
	if visual != null:
		visual.position = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))

# 파지직(spark) · 0.12초 간격으로 보스 주변에 작은 노란/주황 라인 spawn.
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
	# X는 페이즈별 행동, Y는 P1 고정 호버 / P2+ 플레이어 고도 밴드 추적(리워크 §8).
	if phase == 1:
		# 가로 왕복
		velocity.x = float(dir) * _current_speed()
		if global_position.x < HOVER_RANGE_X.x:
			dir = 1
		elif global_position.x > HOVER_RANGE_X.y:
			dir = -1
	else:
		# P2/P3 · 플레이어 추적 (느슨/적극)
		if p == null:
			velocity.x = 0.0
		else:
			var dx: float = p.global_position.x - global_position.x
			if abs(dx) < TRACK_DEAD_ZONE:
				velocity.x = 0.0
			else:
				velocity.x = sign(dx) * _current_speed()
				dir = int(sign(dx))
	# Y · P1은 HOVER_Y 라인, P2+는 플레이어보다 TRACK_OFFSET_Y 위 밴드로. 상층 데크에 있으면
	# 눈앞까지 내려오고, 지면으로 유인하면 증기 실속 사거리에 든다("바닥 함정 무의미" 해소 축).
	var hover_target: float = HOVER_Y
	if phase >= 2 and p != null:
		hover_target = clampf(p.global_position.y - TRACK_OFFSET_Y, HOVER_Y_MIN, HOVER_Y_MAX)
	var dy: float = hover_target - global_position.y
	velocity.y = clamp(dy * 4.0, -110.0, 110.0)
	move_and_slide()

# ─── 데크 스윕(리워크 §8) · 예고(고도 조준 + 날개 주황 점멸 + 경로선) 후 수평 관통 돌진 ───

func _begin_sweep() -> void:
	var p: Node2D = _find_player()
	if p == null:
		_sweep_cd = 2.0
		return
	_sweep_state = 1
	_sweep_t = SWEEP_TELEGRAPH
	_sweep_y = clampf(p.global_position.y - 42.0, HOVER_Y_MIN, SWEEP_Y_MAX)
	var dx: float = p.global_position.x - global_position.x
	_sweep_dir = 1 if dx >= 0.0 else -1
	# 진행 중이던 공격 텔레그래프 취소 · 스윕 예고와 겹치면 신호가 안 읽힌다.
	bomb_telegraph_t = 0.0
	missile_telegraph_t = 0.0
	if bomb_dot != null:
		bomb_dot.color.a = 0.0
	# 경로 표시선 · 스윕 고도를 가로지르는 붉은 라인(예고 동안 점점 선명).
	var parent: Node = get_parent()
	if parent != null:
		_sweep_line = Line2D.new()
		_sweep_line.points = PackedVector2Array([
			Vector2(HOVER_RANGE_X.x - 120.0, _sweep_y), Vector2(HOVER_RANGE_X.y + 120.0, _sweep_y)])
		_sweep_line.width = 4.0
		_sweep_line.default_color = Color(1.0, 0.42, 0.30, 0.0)
		_sweep_line.z_index = 5
		parent.add_child(_sweep_line)
		var lt: Tween = _sweep_line.create_tween()
		lt.tween_property(_sweep_line, "default_color:a", 0.85, SWEEP_TELEGRAPH * 0.85)
	SfxPlayer.play_at("enemy_sniper_charge", global_position, -4.0)
	# 첫 예고 해설은 Stage가 이 시그널로(7차 갤러리 "예고가 뭔 의민지 모르겠음").
	emit_signal("sweep_telegraphed")

func _sweep_process(delta: float) -> void:
	if _sweep_state == 1:
		_sweep_t -= delta
		# 조준 고도로 이동하며 예고 · 날개 주황 점멸.
		var dy: float = _sweep_y - global_position.y
		velocity = Vector2(velocity.x * 0.82, clampf(dy * 6.0, -460.0, 460.0))
		move_and_slide()
		var pulse: float = 0.5 + 0.5 * sin(_sweep_t * 30.0)
		for w in [wing_l, wing_r]:
			if w != null:
				w.color = Color(1.0, 0.62, 0.20, pulse)
		if _sweep_t <= 0.0:
			_sweep_state = 2
			SfxPlayer.play_at("boss_missile_launch", global_position, -2.0)
		return
	# 관통 돌진 · 수평 고속 통과. 무대 경계 도달로 종료.
	velocity = Vector2(float(_sweep_dir) * SWEEP_SPEED, clampf((_sweep_y - global_position.y) * 8.0, -260.0, 260.0))
	move_and_slide()
	dir = _sweep_dir
	if (_sweep_dir > 0 and global_position.x >= HOVER_RANGE_X.y) \
			or (_sweep_dir < 0 and global_position.x <= HOVER_RANGE_X.x):
		_end_sweep()

func _end_sweep() -> void:
	_sweep_state = 0
	_sweep_cd = SWEEP_INTERVAL_P3 if phase >= 3 else SWEEP_INTERVAL_P2
	for w in [wing_l, wing_r]:
		if w != null:
			w.color = Color(1.0, 0.20, 0.20, 0.0)   # 미사일 텔레그래프의 원래 빨강으로 복원
	if _sweep_line != null and is_instance_valid(_sweep_line):
		var lt: Tween = _sweep_line.create_tween()
		lt.tween_property(_sweep_line, "default_color:a", 0.0, 0.3)
		lt.tween_callback(_sweep_line.queue_free)
	_sweep_line = null

# 배기/실속/자폭/페이즈 전환이 스윕을 끊을 때 · 예고선 잔존·스테일 고도로의 재개를 막는다.
func _cancel_sweep() -> void:
	if _sweep_state == 0:
		return
	_end_sweep()

func _attacks(delta: float) -> void:
	# 폭탄 · 모든 페이즈 공통 (간격만 다름)
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
	# 미사일 · P2/P3
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
	# 좌/우 두 발 · 수평 이동, 플레이어 방향 노리지 않고 양방향으로 압박
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

# 플레이어 성장 스케일(2026-08-10) · 15스테이지 확장으로 s8 시점 화력이 원 설계(9스테이지)보다 높아
# 보스가 너무 빨리 녹는다는 피드백. 공격 계열 티어에 비례한 HP 가산 + 페이즈 임계도 같은 비율(2/3·1/3)
# 유지. 자폭 버퍼(HP_SELF_DESTRUCT)는 절대값 유지 · 연출 보장 목적이라 스케일 불필요.
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
	# 페이즈 전환 동안은 무적 · 플레이어가 페이즈 연출을 인지할 시간 보장.
	if phase_freeze_t > 0.0:
		return
	# 자폭 카운트다운 중에는 무적 · 이미 날아오던 총알/연사에 즉사시키지 않고 자폭 시퀀스를
	# 끝까지 보여준다. (이전엔 자폭 진입 직후 잔탄에 맞아 카운트다운이 안 보이고 바로 처치되던
	# 문제 · 사용자 보고. 처치는 카운트다운 종료 → _detonate → _die로만 일어남.)
	if self_destruct_active:
		return
	# 과부하 배기 중 · HP는 안 깎이지만 맞을 때마다 배출이 빨라진다(강제 배출). 사격을 멈출
	# 이유가 없어져 배기가 대기 시간이 아니라 연속 사격 창이 된다. 바닥은 0.05로 클램프 ·
	# 여기서 0으로 만들면 _physics_process의 배기 종료 정리(창 리셋·라벨 소등)를 건너뛰어
	# "창 가득 + 배기 없음" 데드락이 된다(다음 물리 틱이 자연 종료하게 맡긴다).
	if vent_t > 0.0:
		vent_t = maxf(0.05, vent_t - VENT_HIT_SHAVE)
		SfxPlayer.play_at("bullet_deflect_shield", global_position, -12.0)
		return
	# 창당 피해 상한 · 초과분은 흘려보낸다(고화력 즉사 차단 · 시간 하한).
	# 증기 과열 실속 중엔 상한을 안 거친다(직결) · 유인 플레이의 보상 창. 창 누적에도 안 잡혀
	# 실속이 끝난 뒤의 배기 리듬은 그대로다.
	if not story_simplified and stall_t <= 0.0:
		var cap: int = maxi(4, int(ceil(float(max_hp) / VENT_DIVISOR)))
		var allowed: int = cap - _window_dmg
		if allowed <= 0:
			# 가득 찬 창에 또 맞으면 즉시 배기 · 페이즈 freeze와 겹쳐 배기가 보류된 경우
			# 여기서라도 걸어 준다(안 걸면 "창 가득 + 배기 없음" = 영구 무적 데드락 · 하니스 실측).
			SfxPlayer.play_at("bullet_deflect_shield", global_position, -8.0)
			if phase_freeze_t <= 0.0:
				_enter_vent()
			return
		amount = mini(amount, allowed)
		_window_dmg += amount
		# 과열 예고 tell · 창이 찰수록 몸체가 달아오른다(배기의 "왜"를 미리 보여줌).
		_set_heat(float(_window_dmg) / float(cap))
	hp = max(0, hp - amount)
	_flash_hit()
	if hp > 0:
		SfxPlayer.play_at("boss_hurt", global_position)
	# 페이즈 전환 검사 · 자폭 진입 후에는 페이즈 재전환 안 함. 임계는 성장 스케일 반영 인스턴스 값.
	if not story_simplified:
		if phase < 2 and hp <= p2_threshold:
			_transition_to(2)
		elif phase < 3 and hp <= p3_threshold:
			_transition_to(3)
	# 자폭 트리거 · HP 임계 이하로 떨어지면 카운트다운 시작. 버퍼(HP_SELF_DESTRUCT)를 둬
	# 트리거와 동시에 hp가 0이 되어 즉사하는 걸 방지. 진입하면 위 무적으로 항상 끝까지 자폭한다.
	var sd_threshold: int = HP_SELF_DESTRUCT_STORY if story_simplified else HP_SELF_DESTRUCT
	if hp <= sd_threshold:
		_arm_self_destruct()
		return
	if hp <= 0:
		_die()
		return
	# 창 상한 도달 → 과부하 배기(무적 3s + 증기 + 증원 1기). 페이즈 freeze 중이면 그 뒤로.
	if not story_simplified and stall_t <= 0.0 			and _window_dmg >= maxi(4, int(ceil(float(max_hp) / VENT_DIVISOR))) 			and phase_freeze_t <= 0.0:
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
	_cancel_sweep()
	SfxPlayer.play_at("boss_phase_change", global_position)
	# 텔레그래프 노드 리셋 · 전환 직후 잔존 점등이 어색.
	bomb_telegraph_t = 0.0
	missile_telegraph_t = 0.0
	if bomb_dot != null:
		bomb_dot.color.a = 0.0
	if wing_l != null:
		wing_l.color.a = 0.0
	if wing_r != null:
		wing_r.color.a = 0.0
	# 페이즈별 visual tint · 색으로 인지 보강
	if visual != null:
		match new_phase:
			2: visual.self_modulate = Color(1.2, 0.85, 0.65)  # 주황 tint
			3: visual.self_modulate = Color(1.4, 0.55, 0.55)  # 빨강 tint
			_: visual.self_modulate = Color(1, 1, 1)
	# deferred · take_damage(물리 콜백) 경로에서 동기 스폰하면 "flushing queries" 에러로
	# 콜리전 설정이 거부된다(2026-08-20 실플레이 로그 실측, known_issues).
	call_deferred("_summon_minions", new_phase)
	# P3 불안정 구간 · 낙하 잔해 2존(final_boss_rework §6-3 · 자폭 문법과 정합 · 가벼운 빈도).
	# 리워크 무대(2200x1300 · ground 1220) 기준. 사망 시 _debris_nodes로 정리.
	if new_phase == 3 and not story_simplified and _debris_nodes.is_empty():
		for cfg0 in [{"x_min": 350.0, "x_max": 900.0, "interval": 7.0},
				{"x_min": 1300.0, "x_max": 1850.0, "interval": 8.0, "phase": 0.5}]:
			var fd := FallingDebris.new()
			get_parent().add_child(fd)
			fd.setup(cfg0, GROUND_Y_LAB)
			_debris_nodes.append(fd)
	emit_signal("phase_changed", new_phase)

# 페이즈 재시작(final_boss_rework §9.4 · 2026-09-04) · 사망 후 도달했던 페이즈부터. HP를 그 페이즈의
# 진입 임계로 복원하고 전환 연출(freeze·플래시·자막) 없이 상태만 맞춘다. Stage._spawn_boss가
# apply_hp_bonus 뒤에 호출(임계가 성장 보너스를 반영한 뒤). 잔당·잔해는 전환과 같은 경로로 다시 깐다.
func restore_phase(target: int) -> void:
	if story_simplified or dead or target < 2:
		return
	target = mini(target, 3)
	phase = target
	hp = p3_threshold if target >= 3 else p2_threshold
	hp = maxi(hp, HP_SELF_DESTRUCT + 1)   # 자폭 임계 위(복원 직후 즉시 자폭 방지)
	if visual != null:
		visual.self_modulate = Color(1.4, 0.55, 0.55) if target >= 3 else Color(1.2, 0.85, 0.65)
	call_deferred("_summon_minions", target)
	if target >= 3 and _debris_nodes.is_empty():
		for cfg0 in [{"x_min": 350.0, "x_max": 900.0, "interval": 7.0},
				{"x_min": 1300.0, "x_max": 1850.0, "interval": 8.0, "phase": 0.5}]:
			var fd := FallingDebris.new()
			get_parent().add_child(fd)
			fd.setup(cfg0, GROUND_Y_LAB)
			_debris_nodes.append(fd)

# 과부하 배기 진입 · 무적 3s + 증기 + 증원 1기(상한 안에서). 배기가 끝나면 창 리셋.
func _enter_vent() -> void:
	if vent_t > 0.0 or self_destruct_active or dead:
		return
	_cancel_sweep()
	vent_t = VENT_DURATION
	SfxPlayer.play_at("hatch_open", global_position)
	# 가독 · 달아오름 최대 + 상태 라벨 점등(첫 배기 VEIL 해설은 Stage가 vent_started로).
	_set_heat(1.0)
	if _vent_label != null:
		_vent_label.visible = true
	emit_signal("vent_started")
	# 증원은 deferred · _enter_vent는 take_damage(물리 콜백)에서 불려 동기 스폰 시
	# "flushing queries" 에러로 콜리전 설정이 거부된다(2026-08-20 실측).
	call_deferred("_vent_summon")

# 배기 증원 1기 · 배기 중 무방비를 잡몹이 메운다. 타입은 드론↔순찰 교대, 상한 준수.
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
		# 순찰은 보스 아래(지면 위로 낙하 안착 · 상한 클램프), 드론은 P1 호버 라인.
		var y: float = HOVER_Y if kind == 2 else minf(global_position.y + 280.0, GROUND_Y_LAB - 80.0)
		var side: float = -1.0 if randf() < 0.5 else 1.0
		var pos := Vector2(clampf(global_position.x + side * SUMMON_OFFSET_X, 160.0, 2040.0), y)
		var hp_for: int = SUMMON_DRONE_HP if kind == 2 else SUMMON_PATROL_HP
		var m2: CharacterBody2D = _spawn_minion(kind, pos, hp_for)
		if m2 != null:
			summoned_minions.append(m2)

# 배기 증기 · 몸체 좌우로 청백 증기 사각이 흩어진다(시각 tell · 피격 플래시(modulate)와
# 페이즈 틴트(self_modulate)를 건드리지 않는 별도 노드 · known_issues 틴트 충돌 규칙).
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

# 위장 자폭 후 재기동 · 링 정리 + 소량 재점화 HP + 배속. Stage가 disarm 시그널로
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
	# drone은 호버 라인 부근, patrol은 보스 아래(지면 위 낙하 안착 · 상한 클램프)로 spawn.
	var y: float = HOVER_Y if kind == 2 else minf(global_position.y + 280.0, GROUND_Y_LAB - 80.0)
	# X는 ARENA(2200) 안쪽으로 클램프 · 보스가 한쪽에 치우친 채 전환되면 보스 기준 ±760이
	# 벽 밖으로 나가, patrol이 좌하단 구석에 낀 채 방치됐다(사용자 보고 2026-08-14).
	var positions: Array = [
		Vector2(clampf(global_position.x - SUMMON_OFFSET_X, 160.0, 2040.0), y),
		Vector2(clampf(global_position.x + SUMMON_OFFSET_X, 160.0, 2040.0), y),
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
	# patrol 소환수는 사냥 모드 · 감지 범위(260px) 밖에서 스폰되면 제자리 순찰만 하다
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
	e.reset_physics_interpolation()
	return e

func _arm_self_destruct() -> void:
	self_destruct_active = true
	self_destruct_t = 0.0
	_cancel_sweep()
	# 실속 잔여 정리 · 자폭 시퀀스 뒤(위장 자폭 재기동 포함)에 실속이 되살아나지 않게.
	stall_t = 0.0
	if _vent_label != null:
		_vent_label.visible = false
		_vent_label.text = "과열 · 열 배출 중"
		_vent_label.add_theme_color_override("font_color", Color(1.0, 0.72, 0.32))
	SfxPlayer.play_at("boss_self_destruct_alarm", global_position)
	# 위험 영역 시각화 · inner(380, 풀뎀) 빨강, outer(1200, 1뎀) 노랑.
	# outer 너머가 안전 영역. ARENA 1920이라 벽 끝까지 도망가면 outer 너머 도달.
	danger_ring_inner = _make_danger_ring(SELF_DESTRUCT_INNER, Color(0.95, 0.25, 0.25, 0.85), 4.0)
	danger_ring_outer = _make_danger_ring(SELF_DESTRUCT_OUTER, Color(0.95, 0.78, 0.30, 0.65), 3.0)
	add_child(danger_ring_inner)
	add_child(danger_ring_outer)
	# 두 ring 모두 펄스 · 카운트다운 인지.
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
	# 위장 자폭(1회) · 첫 폭발은 피해·시각까지 진짜와 동일하지만 코어가 재점화한다.
	# 페이크 보스 서사(§7)의 전투 내 실연 · 두 번째 자폭이 진짜(기존 흐름 그대로).
	if not _fake_destruct_done and not story_simplified:
		_reignite()
		return
	# 자폭으로 사망 처리
	_die()

# 자폭 진입 후에는 보스가 무적(take_damage 무시)이라, 처치는 카운트다운 종료 → _detonate → _die로만
# 일어난다. 즉 _die 도달 시 항상 자폭 폭발이 끝난 상태. (이전엔 카운트다운 중 처치로 disarm되는
# 경로가 있었으나, 잔탄에 자폭이 안 보이고 즉사하던 문제로 제거 · 사용자 보고.)
func _die() -> void:
	if dead:
		return
	dead = true
	SfxPlayer.play_at("boss_death", global_position)
	# 보스가 죽으면 소환된 잔당도 함께 정리 · ARENA에 잔존 적이 남아 클리어 흐름이 어색해지는 것 방지.
	for m in summoned_minions:
		if is_instance_valid(m):
			m.queue_free()
	summoned_minions.clear()
	for fd in _debris_nodes:
		if is_instance_valid(fd):
			(fd as Node).queue_free()
	_debris_nodes.clear()
	if _sweep_line != null and is_instance_valid(_sweep_line):
		_sweep_line.queue_free()
	_sweep_line = null
	emit_signal("self_destruct_disarmed")
	emit_signal("killed", global_position)
	# 시각적 사라짐
	var tw := visual.create_tween() if visual != null else null
	if tw != null:
		tw.tween_property(visual, "modulate:a", 0.0, 0.4)
		tw.tween_callback(queue_free)
	else:
		queue_free()
