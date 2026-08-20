extends CharacterBody2D

signal killed(at_position: Vector2)

enum EnemyType { PATROL, SNIPER, DRONE, BOMBER, SHIELD, JAMMER, CALLER }
enum PatrolState { ROAMING, FIRING, TELEGRAPH, CHARGING, RECOVERING }
enum BomberState { ROAMING, STALKING, ARMING }

@export var enemy_type: int = EnemyType.PATROL
# 좁은 발판에 spawn돼도 떨어지지 않도록 보수적으로 작게.
# 발판 가장자리 감지 raycast가 우선 — patrol_range는 보조 한계만.
@export var patrol_range: float = 90.0
@export var hp: int = 2
@export var harmless: bool = false
# §4 거짓 렌더(rival_veil_concept) — >=0이면 이 EnemyType처럼 위장 렌더한다. 참 종류·hp·행동 = enemy_type.
# Stage 스폰(deceits)이 set. 근접/텔레그래프 시 리빌(지직거림 tell → 참 모습). 신뢰가 리빌을 앞당김.
@export var disguise_as: int = -1
# §4 거짓 렌더 — 시선 거짓(딴 데 보는 척 기습). true면 patrol이 각성을 숨기고 정지·플레이어 반대로
# 응시하다(안전해 보임) 근접(FEIGN_AMBUSH_RANGE) 시 홱 돌아 기습(압축 텔레그래프→돌진). Stage(feigns)가 set.
@export var feign_ambush: bool = false
# 엘리트(라이벌의 군대, elite_enemies_plan.md) — Stage._spawn_enemy가 add_child 전에 켠다.
# HP·템포 강화 + 바이올렛 고정 계급장(_EliteCrest). 텔레그래프 시간은 불변(§0.2 인지 계약).
@export var elite: bool = false
# 환경 처치 표식 — 열차 같은 해저드가 치명타를 넣는 순간에만 켠다(치명이 아니면 즉시 해제).
# 켜진 채 죽으면 XP·점수가 나오지 않는다: 해저드에 밀어 넣는 전술의 대가는 "그 적의 보상 포기"
# (경보 진압 경비 무보상과 동형 · 2026-08-19 사용자 "열차가 다 치우고 경험치 방울만 남는다").
var env_killed: bool = false

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
const FEIGN_AMBUSH_RANGE: float = 170.0   # §4 시선 거짓 — 이 거리 안으로 접근하면 각성(홱 돌아 기습)
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

# Jammer — 라이벌 VEIL의 '손'(rival_veil_concept §5 1단). 고정형 방출 장치: 순찰/사격 없이
# 자기 반경 안의 (재머 아닌) VEIL 마커를 소등한다(VeilSight가 이 반경을 읽어 마커를 끈다).
# 파괴하면 시야가 돌아온다 = "우선 표적". 능동 공격 없음, 접촉 데미지만(고정이라 회피 쉬움).
const JAMMER_RADIUS: float = 340.0   # VeilSight 마커 소등 반경 (재밍 필드 = 이 반경의 바이올렛 링)
const JAMMER_HP: int = 3

# Caller(호출병) — 직접 공격이 없는 증원 통신병(2026-08-20 사용자 제안 "호출기"). 살려두면
# 주기적으로 안테나를 세워 증원을 부른다. 실제 스폰은 Stage.request_caller_summon 경유 —
# 텔레그래프 후 타이머 스폰(물리 콜백 동기 스폰 금지 규약과 동형). 플레이어가 다가오면 반대로
# 물러나 추격을 강제하고, 접촉 데미지가 없다(무공격 정체성). 불려 온 증원은 처치 보상이 없다
# (무한 파밍 차단 · 경보 진압 경비 무보상과 동형).
const CALLER_HP: int = 2
const CALLER_FLEE_SPEED: float = 95.0
const CALLER_FLEE_RANGE: float = 400.0    # 이 안으로 접근하면 반대쪽으로 물러남
const CALLER_AGGRO_RANGE: float = 760.0   # 플레이어가 이 안에 있어야 호출 사이클 진행(화면 밖 무한 소환 방지)
const CALLER_SUMMON_INTERVAL: float = 6.5
const CALLER_FIRST_DELAY: float = 2.2     # 첫 호출까지 여유 — "우선 표적" 판단 시간
const CALLER_CHARGE_TIME: float = 1.1     # 호출 예고(안테나 신호 링) — 이 동안 끊으면 이번 호출 무산
const CALLER_LIVE_CAP: int = 4            # 이 호출병이 부른 생존 증원 상한

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

# ─── 엘리트 수치(elite_enemies_plan.md §2) — HP는 _ready에서 오버라이드 ───
const ELITE_PATROL_SPEED: float = 85.0
const ELITE_PATROL_CHARGE_SPEED: float = 330.0
const ELITE_PATROL_RECOVERY: float = 0.6
const ELITE_PATROL_BURST_GAP: float = 0.15       # 2연 버스트 간격 — 수평탄이라 점프 하나로 함께 회피
const ELITE_SNIPER_AIM: float = 0.55
const ELITE_SNIPER_INTERVAL: float = 1.9          # risk3 0.7배 곱해도 1.33s — 회피 가능선
const ELITE_DRONE_SPEED: float = 125.0
const ELITE_DRONE_BOMB_INTERVAL: float = 2.8      # 2연 투하 보상으로 사이클은 완만
const ELITE_DRONE_SECOND_DROP_GAP: float = 0.25
const ELITE_DRONE_SECOND_DROP_SPREAD: float = 40.0  # 2발째 좌우 분산 — "그 자리 탈출"이 답
const ELITE_BOMBER_STALK_MULT: float = 1.8
const ELITE_BOMBER_DETECT_X: float = 420.0
const ELITE_BOMBER_BLAST_RADIUS: float = 85.0
const ELITE_SHIELD_LOCK: float = 2.2              # 대시 쿨(0.7)의 3배 유지 — 측면 창 보존
const ELITE_VIOLET: Color = Color(0.72, 0.42, 1.0)  # 라이벌 바이올렛 축(간섭 플래시와 동일)

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

# 사냥 모드 — 진행 방향 벽(부서지는 엄폐 등)에 막히면 반전 대신 짧은 도약으로 타넘는다.
# 지면+벽 접촉일 때만 발동, 도약 중(공중)엔 재발동 없음.
func _try_hunt_hop() -> void:
	if is_on_floor() and is_on_wall():
		velocity.y = HUNT_HOP_VELOCITY

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

# §4 거짓 렌더 — 위장이 벗겨지는 근접 반경(바로 옆). 주 리빌은 교전(피격/막힘)이고, 이건 안 쏘고
# 붙었을 때의 폴백. 넓으면 지직거림 tell을 보기도 전에 벗겨져 무의미해진다(피드백). 신뢰 warm이면 +40.
const DISGUISE_REVEAL_RANGE: float = 70.0

var encountered: bool = false
var visual: Node2D
var _disguised: bool = false   # §4 거짓 렌더로 위장 중인가
var _glitch: Node2D = null     # 지직거림 tell 노드(위장/거짓 렌더 공용)
var _feigning: bool = false    # §4 시선 거짓 — 각성을 숨긴 채 딴 데 보는 척 중인가
# 이스터에그 — 황금 희귀 개체(shiny). Stage._spawn_enemy가 낮은 확률로 켠다. 처치 시 보너스 XP.
# 색은 visual/self modulate가 텔레그래프·피격 플래시로 흰색 리셋되므로, 독립된 오라 자식으로 표현.
var shiny: bool = false

# 농성(웨이브) 맵 사냥 모드 — Stage가 waves_hunt 맵의 지상 적(patrol/bomber/shield)에 켠다.
# 감지 범위 밖에서도 플레이어 쪽으로 전진하고, 진행 방향 벽(부서지는 엄폐 등)은 반전 대신
# 짧은 도약으로 타넘는다. (저지선: 좌우 스폰 적이 감지 260px 밖 + 엄폐 솔리드에 막혀
# 스폰 지점만 순찰하던 버그의 해법, 2026-08-11 피드백.)
var hunt: bool = false
const HUNT_HOP_VELOCITY: float = -520.0   # 엄폐 최고 92px < 도약 ~123px

# 혼성 진형 호위(2026-08-20 사용자 "진형을 갖춰서 오면 위협적") — 웨이브 스폰 직후 Stage가
# 방패병 근처 정찰병에 리더를 배정한다. 호위 정찰병은 방패 뒤(플레이어 반대쪽)를 따라붙어
# "방패가 막고 사수가 쏘는" 대형이 된다. 리더가 죽으면 평소 행동으로 복귀.
var escort_leader: Node2D = null
const ESCORT_GAP: float = 80.0            # 리더 뒤 유지 거리

# 호출병 상태 — charging 중엔 정지(취약 창), 사이클은 플레이어 인지 범위 안에서만 흐른다.
var caller_cycle_t: float = 0.0
var caller_charging: bool = false
var caller_charge_t: float = 0.0
var caller_calls: int = 0                 # 호출 회차(Stage가 증원 구성 교대에 사용)
var _caller_summons: Array = []           # 살아 있는 증원 참조(상한 판정용)
var _caller_beacon: Node2D = null

# 지속 기본 틴트 — 텔레그래프/조준 점멸이 리셋할 목표색(기본 흰색). shiny는 금빛으로 바꿔
# 몸통 자체가 항상 황금이게 한다(known_issues 함정의 ⓑ 해법: 리셋 목표를 틴트 값으로).
var _base_tint: Color = Color(1, 1, 1)

# 황금 오라 — modulate와 무관한 별도 발광(피격/텔레그래프 색 변화에 안 덮임).
class _ShinyAura extends Node2D:
	var t: float = 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
		var a: float = lerp(0.22, 0.44, pulse)
		# 발광 이중 원 + 맥동 링 — "더 황금스럽게" 피드백(2026-08-11)으로 기존보다 넓고 밝게.
		draw_circle(Vector2.ZERO, 34.0, Color(1.0, 0.80, 0.26, a * 0.4))
		draw_circle(Vector2.ZERO, 18.0, Color(1.0, 0.90, 0.48, a))
		draw_arc(Vector2.ZERO, 30.0 + 3.0 * pulse, 0.0, TAU, 40, Color(1.0, 0.88, 0.40, a * 0.8), 1.5, true)
		# 회전 반짝이 4점 — 납작한 궤도(원근감)를 도는 작은 마름모.
		for i in 4:
			var ang: float = t * 1.6 + TAU * float(i) / 4.0
			var c: Vector2 = Vector2(cos(ang), sin(ang) * 0.55) * 30.0
			var s: float = 2.6 + 1.4 * sin(t * 5.0 + float(i) * 1.7)
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0),
			]), Color(1.0, 0.95, 0.62, 0.85))

# 황금 글린트 — 몸통 위 가산 혼합(ADD) 금빛 워시 + 주기적 사선 스윕. modulate는 곱셈이라
# 붉은 유니폼이 금색이 될 수 없다(빨강×금=주황) — 가산이라야 어떤 바탕색 위에서도 노랗게 뜬다.
class _ShinyGlint extends Node2D:
	var t: float = 0.0
	# 몸통 워시 영역 — 지면형(발 원점) 기본. 드론 등 중심 원점 개체는 스폰 측에서 교체.
	var body_rect: Rect2 = Rect2(-13.0, -46.0, 26.0, 44.0)
	func _ready() -> void:
		var m := CanvasItemMaterial.new()
		m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		material = m
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var pulse: float = 0.5 + 0.5 * sin(t * 3.0)
		var a: float = lerp(0.14, 0.26, pulse)
		draw_rect(body_rect, Color(0.95, 0.72, 0.18, a), true)
		# 사선 글린트 스윕 — 금속 광택처럼 1.6s마다 몸통을 훑는 밝은 금띠.
		var ph: float = fmod(t, 1.6) / 1.6
		if ph < 0.35:
			var k: float = ph / 0.35
			var x: float = lerp(body_rect.position.x - 3.0, body_rect.end.x + 3.0, k)
			var ga: float = 0.55 * (1.0 - absf(k - 0.5) * 2.0)
			draw_line(Vector2(x - 6.0, body_rect.position.y - 2.0), Vector2(x + 6.0, body_rect.end.y + 2.0), Color(1.0, 0.95, 0.55, ga), 3.0)

# 호출병 안테나 표시 — 평상시 느린 점멸등, 호출 예고 중엔 안테나 끝에서 퍼지는 신호 링.
# 링이 보이는 동안 처치하면 이번 호출이 무산된다(끊는 손맛). 점멸은 느리게(광과민 기준 준수).
class _CallerBeacon extends Node2D:
	var charge_frac: float = -1.0   # -1 = 예고 아님, 0~1 = 예고 진행도(소유자가 매 틱 갱신)
	var t: float = 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var tip := Vector2(0.0, -56.0)
		var idle_a: float = 0.45 + 0.25 * sin(t * 2.6)
		draw_circle(tip, 2.8, Color(1.0, 0.64, 0.22, idle_a))
		if charge_frac < 0.0:
			return
		for i in 3:
			var k: float = fmod(charge_frac * 1.4 + float(i) / 3.0, 1.0)
			draw_arc(tip, 7.0 + 30.0 * k, 0.0, TAU, 26, Color(1.0, 0.60, 0.20, 0.5 * (1.0 - k)), 2.0, true)

# 재밍 필드 — 마커가 소등되는 구역을 라이벌 바이올렛 링으로 그린다.
# 작가성(known_issues): "마커가 그냥 사라진다"가 아니라 "여기가 가로막혔다"로 읽히게, 반경을 눈에 보이게.
# 중심 = 재머 발밑(local 0,0) — VeilSight 소등 판정도 global_position(발) 기준이라 시각/판정 일치.
class _JamField extends Node2D:
	var radius: float = 340.0
	var owner_ref: Node = null
	var t: float = 0.0
	func _process(delta: float) -> void:
		t += delta
		if owner_ref != null and owner_ref.get("dead"):
			visible = false
			return
		queue_redraw()
	func _draw() -> void:
		var vi: Color = Color(0.80, 0.34, 0.98)          # 라이벌 바이올렛 — VEIL 시안(0.42,0.86,1.0)의 대비
		var pulse: float = 0.5 + 0.5 * sin(t * 2.2)
		var edge_a: float = lerp(0.12, 0.24, pulse)
		# 옅은 채움 — "이 안은 가려졌다"
		draw_circle(Vector2.ZERO, radius, Color(vi.r, vi.g, vi.b, 0.045))
		# 경계 링 — 회전 위상의 점선 스캔(교란되는 느낌)
		var segs: int = 96
		for i in range(0, segs, 2):
			var a0: float = float(i) / float(segs) * TAU + t * 0.4
			var a1: float = float(i + 1) / float(segs) * TAU + t * 0.4
			draw_arc(Vector2.ZERO, radius, a0, a1, 4, Color(vi.r, vi.g, vi.b, edge_a), 2.0, true)
		# 안쪽 보조 링
		draw_arc(Vector2.ZERO, radius * 0.6, 0.0, TAU, 48, Color(vi.r, vi.g, vi.b, edge_a * 0.5), 1.2, true)

# 지직거림 tell — 거짓 렌더가 있는 곳에 뜨는 붉은 글리치(§4.1: 모든 거짓엔 tell이 있어야 한다).
# 근접·신뢰가 높을수록 또렷(신뢰가 지각을 산다). 대부분 시간엔 거의 안 보이게(남발 금지 §4.1).
# 위장 적/거짓 함정 공용 프리미티브 — 소유자 몸통(-44..0, ±16)에 겹쳐 그린다.
class _GlitchTell extends Node2D:
	var owner_ref: Node = null
	var t: float = 0.0
	func _process(delta: float) -> void:
		t += delta
		queue_redraw()
	func _draw() -> void:
		var beat: float = fmod(t, 1.4)
		if beat > 0.5:
			return   # 주기적으로 번쩍(0.5s/1.4s — 조금 더 자주·길게)
		var vis: float = 1.0 - (beat / 0.5)
		# 원거리에서도 "저 적은 뭔가 이상하다"가 읽히게 — 범위 넓고 최소 강도 높게(피드백: 너무 좁았음).
		var mul: float = 0.7
		if owner_ref != null and owner_ref.has_method("_find_player"):
			var pl: Node = owner_ref.call("_find_player")
			if pl != null and is_instance_valid(pl):
				var d: float = (owner_ref as Node2D).global_position.distance_to((pl as Node2D).global_position)
				mul = clamp(1.0 - d / 850.0, 0.55, 1.0)
				if GameState.veil_register_band() == "warm":
					mul = min(1.0, mul + 0.25)
		var a: float = vis * mul
		if a < 0.04:
			return
		var red := Color(1.0, 0.18, 0.30, a)
		# 전신 붉은 오프셋 고스트(크로매틱) — 작은 스캔라인보다 훨씬 멀리서 읽힌다. 크기·강도 상향(피드백).
		var ox: float = sin(t * 40.0) * 4.0
		draw_rect(Rect2(-21.0 + ox, -54.0, 42.0, 56.0), Color(red.r, red.g, red.b, a * 0.42), true)
		# 붉은 외곽선(실루엣)
		draw_rect(Rect2(-22.0, -55.0, 44.0, 57.0), Color(red.r, red.g, red.b, a), false, 2.5)
		# 스캔라인 지직거림
		for i in range(5):
			var yy: float = -52.0 + float((int(t * 90.0) + i * 12) % 52)
			draw_line(Vector2(-21, yy), Vector2(21, yy), Color(red.r, red.g, red.b, a), 2.0)

# 엘리트 계급장 — 항상 켜진 고정 기하(머리 위 셰브론 2단 + 발밑 링). 깜빡이지 않는다:
# "지직이면 거짓(_GlitchTell), 고정 기호면 정예"의 시각 문법(elite_enemies_plan.md §3).
# modulate 함정 회피 — 텔레그래프/피격 플래시가 visual을 리셋해도 독립 자식이라 불변.
class _EliteCrest extends Node2D:
	func _draw() -> void:
		var vi: Color = Color(0.72, 0.42, 1.0, 0.95)
		for i in 2:
			var y: float = -64.0 - float(i) * 9.0
			draw_polyline(PackedVector2Array([
				Vector2(-9.0, y), Vector2(0.0, y - 7.0), Vector2(9.0, y),
			]), vi, 2.5, true)
		draw_arc(Vector2.ZERO, 20.0, 0.0, TAU, 40, Color(vi.r, vi.g, vi.b, 0.55), 1.6, true)

# 엘리트 몸체 트림 — "계급장만으론 원거리 구분이 약하다"(사용자 2026-08-12) 보강. 몸통 윤곽에
# 바이올렛 액센트(어깨 L자 + 측면 라인 + 밑줄). 고정 발광(지직임 없음) = "고정 기호면 정예" 문법
# 유지 → 거짓 렌더(_GlitchTell 지직임)와 혼동 없음. modulate 무관 독립 자식(플래시 리셋 함정 회피).
# 치수는 콜리전 박스 기준(타입별 _ready에서 세팅) — 시각 스케일과 대체로 일치.
class _EliteTrim extends Node2D:
	var half_w: float = 18.0
	var top_y: float = -52.0
	var bot_y: float = 0.0
	func _draw() -> void:
		var vi := Color(0.72, 0.42, 1.0, 0.9)
		var arm: float = 7.0
		for side_raw in [-1.0, 1.0]:
			var side: float = side_raw
			var x: float = side * half_w
			# 어깨 L자(상단 모서리)
			draw_line(Vector2(x, top_y), Vector2(x - side * arm, top_y), vi, 2.0)
			draw_line(Vector2(x, top_y), Vector2(x, top_y + arm), vi, 2.0)
			# 측면 세로 라인(중단)
			var mid0: float = lerpf(top_y, bot_y, 0.42)
			var mid1: float = lerpf(top_y, bot_y, 0.78)
			draw_line(Vector2(x, mid0), Vector2(x, mid1), Color(vi.r, vi.g, vi.b, 0.55), 2.0)
		# 밑줄(발밑) — 지면 그림자 자리의 정예 표식
		draw_line(Vector2(-half_w * 0.8, bot_y + 2.0), Vector2(half_w * 0.8, bot_y + 2.0), Color(vi.r, vi.g, vi.b, 0.45), 2.0)

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
		EnemyType.JAMMER:
			hp = JAMMER_HP
			visual = CharacterArt.build_jammer(self)
			# VeilSight가 마커 소등 대상 재머를 값싸게 찾도록 전용 그룹에도 등록.
			add_to_group("jammer")
			var field := _JamField.new()
			field.radius = JAMMER_RADIUS
			field.owner_ref = self
			field.z_index = -2   # 캐릭터 아트 뒤
			add_child(field)
		EnemyType.CALLER:
			hp = CALLER_HP
			visual = CharacterArt.build_caller(self)
			caller_cycle_t = CALLER_FIRST_DELAY
			var beacon := _CallerBeacon.new()
			beacon.z_index = 3
			add_child(beacon)
			_caller_beacon = beacon
	# 막 진행 강화(라이벌 침식, 2026-08-18 사용자 "적을 강화해") — 막4/5 일반 유닛 내구 상향.
	# 엘리트 램프와 같은 경계(막4+) = "막3까지는 데모 느낌" 제약 준수. 폭탄병 1 유지(원거리 1샷
	# 정답 보존, 엘리트와 동형) · 재머 제외(라이벌의 "손"은 별개 문법). 엘리트는 아래 오버라이드가
	# 절대값으로 덮어 계급 우위 유지(막5 일반 patrol 4 < 엘리트 6).
	var act_now: int = GameState.act_for_stage(GameState.current_stage)
	if act_now >= 3:
		match enemy_type:
			EnemyType.PATROL, EnemyType.SHIELD:
				hp += 1 if act_now == 3 else 2
			EnemyType.SNIPER, EnemyType.DRONE:
				if act_now >= 4:
					hp += 1
	# §4 거짓 렌더 — 위장 렌더: 참 종류의 hp/행동은 위에서 정해졌고, 시각만 위장 종류로 교체 + 지직거림 tell.
	if disguise_as >= 0 and disguise_as != enemy_type:
		_disguised = true
		if visual != null:
			visual.free()   # _ready 안이라 즉시 free 안전(1프레임 이중 스프라이트 방지)
		visual = _build_visual_for(disguise_as)
		var g := _GlitchTell.new()
		g.owner_ref = self
		g.z_index = 3
		add_child(g)
		_glitch = g
	# §4 거짓 렌더 — 시선 거짓(딴 데 보는 척 기습). patrol 전용, 위장(_disguised)과 배타(한 적이 종류와
	# 각성을 동시에 속이면 과함 §4.1). 각성을 숨긴 채 정지·응시하다 근접 시 홱 기습. 지직거림 tell 공유.
	if feign_ambush and enemy_type == EnemyType.PATROL and not _disguised:
		_feigning = true
		var fg := _GlitchTell.new()
		fg.owner_ref = self
		fg.z_index = 3
		add_child(fg)
		_glitch = fg
	# 엘리트(라이벌의 군대) — HP 오버라이드(§2, bomber는 1 유지 = 원거리 1샷 정답 보존) + 계급장.
	# 위장/시선 거짓과는 스폰 단계에서 배타(Stage 가드) — 계급장이 위장을 깨는 모순 방지.
	if elite:
		# HP 상향(2026-08-11: "엘리트가 강한 느낌이 안 든다" — 금방 죽어 강화 패턴을 못 보여줌.
		# bomber는 1 유지 = 원거리 1샷 정답 보존).
		match enemy_type:
			EnemyType.PATROL: hp = 6
			EnemyType.SNIPER: hp = 3
			EnemyType.DRONE: hp = 3
			EnemyType.SHIELD: hp = 7
		var crest := _EliteCrest.new()
		crest.z_index = 3
		add_child(crest)
		# 몸체 트림 — 콜리전 박스 치수에 맞춤(Stage._spawn_enemy의 타입별 shape.size와 동기).
		var trim := _EliteTrim.new()
		trim.z_index = 3
		match enemy_type:
			EnemyType.PATROL:
				trim.half_w = 20.0
				trim.top_y = -56.0
			EnemyType.SHIELD:
				trim.half_w = 24.0
				trim.top_y = -60.0
			EnemyType.DRONE:
				trim.half_w = 26.0
				trim.top_y = -18.0
				trim.bot_y = 18.0
			_:
				trim.half_w = 16.0
				trim.top_y = -42.0
		add_child(trim)
	fire_timer = _sniper_interval()
	drone_bomb_cd = 1.2  # 스폰 직후 즉시 폭격 방지
	if shiny:
		# 드론은 콜리전·시각이 몸 중심(0,0) 기준이라 지면형 발 기준 오프셋을 쓰면 오라가 위로
		# 어긋난다(2026-08-11 사용자 보고) — 공중형은 중심 정렬.
		var is_air: bool = enemy_type == EnemyType.DRONE
		var aura := _ShinyAura.new()
		aura.position = Vector2.ZERO if is_air else Vector2(0.0, -22.0)
		aura.z_index = -1                    # 캐릭터 아트 뒤
		add_child(aura)
		# 몸통 금빛 — 점멸/조준 리셋 목표를 이 틴트로 바꿔 유지("오라만으론 황금이 약하다", 2026-08-11).
		_base_tint = Color(1.5, 1.24, 0.55)
		if visual != null:
			visual.modulate = _base_tint
		# 가산 글린트 — 붉은 유니폼 위에서도 금빛이 뜨게(곱셈 틴트의 한계 보완).
		var glint := _ShinyGlint.new()
		glint.z_index = 2
		glint.body_rect = Rect2(-17.0, -17.0, 34.0, 34.0) if is_air else Rect2(-13.0, -46.0, 26.0, 44.0)
		add_child(glint)
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
		EnemyType.CALLER:
			return caller_charging   # 호출 예고 중 = "지금 끊어야 하는" 순간
	return false

func _telegraph_time() -> float:
	return PATROL_TELEGRAPH * (0.6 if GameState.is_high_risk() else 1.0)

func _patrol_fire_interval() -> float:
	return PATROL_FIRE_INTERVAL * _pressure_interval_mul()

func _sniper_interval() -> float:
	var interval: float = ELITE_SNIPER_INTERVAL if elite else SNIPER_FIRE_INTERVAL
	var base: float = interval * _pressure_interval_mul()
	if _is_nest_sniper():
		base *= NEST_SNIPER_INTERVAL_MUL
	return base

# 사격 빈도 압박 배수 — risk3(0.7)과 막 진행(막4 0.85 / 막5 0.75)을 곱하지 않고 min으로 결합
# (기준 2 곱연산 차단은 적 쪽도 동일 · ELITE_SNIPER_INTERVAL "회피 가능선" 주석의 0.7 하한 보존).
# 예고(텔레그래프) 시간은 안 건드린다 — 빈도만 조이고 공정성은 유지(elite_enemies_plan §0.2와 동형).
func _pressure_interval_mul() -> float:
	var risk_mul: float = 0.7 if GameState.is_high_risk() else 1.0
	var act_now: int = GameState.act_for_stage(GameState.current_stage)
	var act_mul: float = 1.0
	if act_now >= 4:
		act_mul = 0.75
	elif act_now == 3:
		act_mul = 0.85
	return minf(risk_mul, act_mul)

# 측면 단독 둥지(회피 전용) 저격수 식별 — Stage가 spawn 직후 avoid_only 메타를 붙인다.
func _is_nest_sniper() -> bool:
	return has_meta("avoid_only")

# 둥지 저격수는 사거리·조준 텔레그래프를 완화 — 한 둥지씩 상대하며 텔레그래프 보고 피해 오르게.
func _eff_sniper_range() -> float:
	return NEST_SNIPER_RANGE if _is_nest_sniper() else SNIPER_RANGE

func _eff_sniper_aim_time() -> float:
	if _is_nest_sniper():
		return NEST_SNIPER_AIM_TIME
	return ELITE_SNIPER_AIM if elite else SNIPER_AIM_TIME

func _drone_bomb_interval() -> float:
	var interval: float = ELITE_DRONE_BOMB_INTERVAL if elite else DRONE_BOMB_INTERVAL
	return interval * _pressure_interval_mul()

# ─── 엘리트 유효치(elite_enemies_plan.md §2) — 텔레그래프 "시간"은 어디에도 안 건드림(§0.2) ───
func _eff_patrol_speed() -> float:
	return ELITE_PATROL_SPEED if elite else PATROL_SPEED

func _eff_patrol_charge_speed() -> float:
	return ELITE_PATROL_CHARGE_SPEED if elite else PATROL_CHARGE_SPEED

func _eff_patrol_recovery() -> float:
	return ELITE_PATROL_RECOVERY if elite else PATROL_RECOVERY

func _eff_drone_speed() -> float:
	return ELITE_DRONE_SPEED if elite else DRONE_SPEED

func _eff_bomber_stalk_mult() -> float:
	return ELITE_BOMBER_STALK_MULT if elite else 1.4

func _eff_bomber_detect_x() -> float:
	return ELITE_BOMBER_DETECT_X if elite else BOMBER_DETECT_X

func _eff_bomber_blast_radius() -> float:
	return ELITE_BOMBER_BLAST_RADIUS if elite else BOMBER_BLAST_RADIUS

func _eff_shield_lock() -> float:
	return ELITE_SHIELD_LOCK if elite else SHIELD_DIR_LOCK_DURATION

func _enemy_id() -> String:
	match enemy_type:
		EnemyType.PATROL: return "patrol"
		EnemyType.SNIPER: return "sniper"
		EnemyType.DRONE: return "drone"
		EnemyType.BOMBER: return "bomber"
		EnemyType.SHIELD: return "shield"
		EnemyType.JAMMER: return "jammer"
		EnemyType.CALLER: return "caller"
	return ""

# VeilSight가 마커 소등 반경을 읽는다 (const는 get()으로 못 꺼내므로 메서드로 노출).
func jam_radius() -> float:
	return JAMMER_RADIUS

# ─── 호출병(caller) ───────────────────────────────────────────

# 살아 있는 증원 수 — 죽었거나 해제된 참조는 여기서 정리(is_instance_valid가 항상 맨 앞).
func _caller_live_summons() -> int:
	var pruned: Array = []
	for s in _caller_summons:
		if is_instance_valid(s) and not bool(s.get("dead")):
			pruned.append(s)
	_caller_summons = pruned
	return pruned.size()

# Stage._caller_do_spawn이 스폰 직후 호출 — 상한 판정 대상 등록.
func register_summon(e: Node) -> void:
	_caller_summons.append(e)

func _tick_caller(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, 1100.0)
	else:
		velocity.y = 0.0
	var p := _find_player()
	velocity.x = 0.0
	if p != null:
		# 이동 — 가까워지면 반대쪽으로 물러난다(무기 없는 통신병). 가장자리/벽에선 멈춰 선다.
		# 예고 중엔 정지(취약 창 — 끊을 기회).
		if not caller_charging:
			var dx: float = p.global_position.x - global_position.x
			if absf(dx) < CALLER_FLEE_RANGE:
				var flee_dir: int = -1 if dx > 0.0 else 1
				if not is_on_wall() and (not is_on_floor() or _has_ground_ahead(flee_dir)):
					dir = flee_dir
					velocity.x = float(flee_dir) * CALLER_FLEE_SPEED
		# 시선은 항상 플레이어 쪽(물러나며 돌아봄).
		_flip_visual(p.global_position.x < global_position.x)
		# 호출 사이클 — 플레이어가 인지 범위 안에 있을 때만 진행.
		if not harmless and absf(p.global_position.x - global_position.x) <= CALLER_AGGRO_RANGE:
			if caller_charging:
				caller_charge_t -= delta
				if caller_charge_t <= 0.0:
					caller_charging = false
					caller_cycle_t = CALLER_SUMMON_INTERVAL
					_caller_request_summon()
			else:
				caller_cycle_t -= delta
				if caller_cycle_t <= 0.0 and _caller_live_summons() < CALLER_LIVE_CAP:
					caller_charging = true
					caller_charge_t = CALLER_CHARGE_TIME
					SfxPlayer.play_at("enemy_sniper_charge", global_position)
	if _caller_beacon != null:
		_caller_beacon.set("charge_frac",
			(1.0 - caller_charge_t / CALLER_CHARGE_TIME) if caller_charging else -1.0)
	move_and_slide()

func _caller_request_summon() -> void:
	var sn := get_tree().get_first_node_in_group("stage")
	if sn != null and sn.has_method("request_caller_summon"):
		sn.call("request_caller_summon", self)

func _flip_visual(facing_left: bool) -> void:
	if visual != null:
		visual.scale.x = -1.0 if facing_left else 1.0

# 지정 종류의 시각을 만든다 — 위장 렌더/리빌 복원 공용. hp·행동은 항상 enemy_type(참)이 결정.
func _build_visual_for(kind: int) -> Node2D:
	var v: Node2D = null
	match kind:
		EnemyType.PATROL:
			v = CharacterArt.build_patrol(self)
			if v != null:
				v.scale = Vector2(1.3, 1.3)
		EnemyType.SNIPER:
			v = CharacterArt.build_sniper(self)
		EnemyType.DRONE:
			v = CharacterArt.build_drone(self)
			if v != null:
				v.scale = Vector2(1.3, 1.3)
		EnemyType.BOMBER:
			v = CharacterArt.build_bomber(self)
		EnemyType.SHIELD:
			v = CharacterArt.build_shield(self)
			if v != null:
				v.scale = Vector2(1.4, 1.4)
		EnemyType.JAMMER:
			v = CharacterArt.build_jammer(self)
		EnemyType.CALLER:
			v = CharacterArt.build_caller(self)
	return v

# §4 거짓 렌더 — 위장이 벗겨지는 조건: (a) 참 종류가 텔레그래프 시작(behavior가 거짓을 배신) 또는
# (b) 플레이어가 리빌 반경 안(신뢰 warm이면 확대). 둘 다 tell 이후라 fair.
func _update_disguise() -> void:
	if not _disguised:
		return
	var reveal: bool = veil_is_telegraphing()
	if not reveal:
		var p := _find_player()
		if p != null:
			var extra: float = 40.0 if GameState.veil_register_band() == "warm" else 0.0
			if global_position.distance_to(p.global_position) < DISGUISE_REVEAL_RANGE + extra:
				reveal = true
	if reveal:
		_reveal_disguise()

func _reveal_disguise() -> void:
	if not _disguised:
		return
	_disguised = false
	if visual != null:
		visual.free()
	visual = _build_visual_for(enemy_type)   # 참 종류로 복원
	# 언마스크 — 짧은 바이올렛 글리치 플래시 + 신호음
	modulate = Color(1.8, 1.4, 1.9)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1), 0.2)
	SfxPlayer.play_at("bestiary_first_seen", global_position)
	if _glitch != null:
		_glitch.queue_free()
		_glitch = null

# §4 시선 거짓 — 각성: 딴 데 보는 척을 풀고 홱 돌아 기습(압축 텔레그래프→돌진). tell 제거 + 언마스크.
func _spring_feign_ambush(p: Node2D) -> void:
	if not _feigning:
		return
	_feigning = false
	dir = 1 if p.global_position.x > global_position.x else -1   # 홱 돌아 플레이어 향함
	velocity.x = 0.0
	_reveal_feign()
	patrol_state = PatrolState.TELEGRAPH
	patrol_state_timer = _telegraph_time() * 0.5   # 압축 텔레그래프(기습 — 일반 돌진보다 짧게)

func _reveal_feign() -> void:
	modulate = Color(1.8, 1.4, 1.9)
	create_tween().tween_property(self, "modulate", Color(1, 1, 1), 0.2)
	SfxPlayer.play_at("bestiary_first_seen", global_position)
	if _glitch != null:
		_glitch.queue_free()
		_glitch = null

func _physics_process(delta: float) -> void:
	if dead or not is_inside_tree():
		return
	if touch_cd > 0.0:
		touch_cd -= delta
	_check_first_encounter()
	if _disguised:
		_update_disguise()
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
		EnemyType.CALLER:
			_tick_caller(delta)
	# bomber는 자체 폭발만 — 평상시 근접 데미지 없음. 호출병은 무공격 정체성이라 접촉도 없음.
	if enemy_type == EnemyType.BOMBER or enemy_type == EnemyType.CALLER:
		return
	_check_touch_player()

# ─── 도감 첫 조우 ───────────────────────────────────────────

func _check_first_encounter() -> void:
	if _disguised:
		return   # 위장 중엔 도감 스포일 방지 — 리빌 후 참 종류로 등록
	if encountered or harmless:
		return
	# 14-1 페이즈 목표(재머 시각 재사용, rival_node)는 도감 조우 제외 — 보스 연출 중 도감
	# 팝업이 pause를 걸면 가짜 클리어 타이머 체인이 동결돼 P3가 영영 안 온다(하니스 재현
	# 2026-08-14). 재머 카드는 일반 맵 재머에서 등록된다.
	if has_meta("rival_node"):
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
	# 특별 개체 조우 — VEIL 한마디(각 런당 1회, 2026-08-11 사용자 제안). 황금=희귀 반응 /
	# 엘리트="다른 신호" 복선(라이벌의 군대 §6). 어투 = 간결한 전술 보고체(사용자 지시 2026-08-11:
	# 해요체 남발이 "유치원 교사" 같다 — AI 전술 요원의 짧은 보고로). 문구는 dialogue_review §8 검토 대상.
	if shiny and not GameState.shiny_line_shown:
		GameState.shiny_line_shown = true
		stage_node.call("_show_veil_subtitle", "미확인 개체 포착. 데이터베이스에 없는 사양입니다. 회수 가치가 높습니다.", 4.0)
	elif elite and not GameState.elite_line_shown:
		GameState.elite_line_shown = true
		stage_node.call("_show_veil_subtitle", "저 계급장은 시설 편제에 없습니다. 외부 신호 수신 중. 교전에 주의하십시오.", 4.2)
	var id: String = _enemy_id()
	if GameState.mark_enemy_seen(id):
		# 기반 타입 카드 우선 — 같은 조우에서 elite 카드까지 겹치면 과함(다음 조우로 미룸).
		BestiaryOverlay.show_card(stage_node, id)
		return
	if elite and GameState.mark_enemy_seen("elite"):
		BestiaryOverlay.show_card(stage_node, "elite")

# ─── Patrol ─────────────────────────────────────────────────

func _tick_patrol(delta: float) -> void:
	if not is_on_floor():
		velocity.y = min(velocity.y + GRAVITY * delta, 1100.0)
	else:
		velocity.y = 0.0

	var p := _find_player()

	# §4 시선 거짓 — 딴 데 보는 척: 각성을 숨긴 채 정지하고 플레이어 반대로 응시(안전해 보임).
	# 근접(FEIGN_AMBUSH_RANGE)하면 홱 돌아 기습. 지직거림 tell이 항상 켜져 있어 fair(주의하면 알아챔).
	if _feigning:
		velocity.x = 0.0
		if p != null:
			_flip_visual(p.global_position.x > global_position.x)   # 플레이어 반대(딴 데 봄)
			if global_position.distance_to(p.global_position) <= FEIGN_AMBUSH_RANGE:
				_spring_feign_ambush(p)
		move_and_slide()
		return

	# 호위 리더 유효성 — 해제/사망 리더는 해제(is_instance_valid가 항상 맨 앞, known_issues).
	if escort_leader != null and (not is_instance_valid(escort_leader) or bool(escort_leader.get("dead"))):
		escort_leader = null

	match patrol_state:
		PatrolState.ROAMING:
			if escort_leader != null and p != null and not harmless:
				# 혼성 진형 호위 — 방패 리더 뒤(플레이어 반대쪽) ESCORT_GAP 지점을 따라붙는다.
				# 방패가 전면 탄을 막는 동안 뒤에서 사격(사격/돌진 전환은 아래 공통 분기 그대로 —
				# 플레이어가 파고들면 대형을 깨고 나오는 것도 정상 행동).
				var lead_x: float = escort_leader.global_position.x
				var behind_x: float = lead_x - (1.0 if p.global_position.x > lead_x else -1.0) * ESCORT_GAP
				var ddx: float = behind_x - global_position.x
				if absf(ddx) > 12.0:
					dir = 1 if ddx > 0.0 else -1
					velocity.x = float(dir) * _eff_patrol_speed() * 1.15
					if is_on_floor() and not _has_ground_ahead(dir):
						velocity.x = 0.0
					else:
						_try_hunt_hop()
				else:
					velocity.x = 0.0
					dir = 1 if p.global_position.x > global_position.x else -1
			elif hunt and p != null and not harmless:
				# 사냥 모드 — 순찰 범위/벽 반전 무시, 플레이어 쪽으로 전진. 벽(엄폐)은 타넘기.
				# 가장자리 검사도 생략(농성 맵은 평지 + 엄폐 꼭대기 통과라 낙하가 안전).
				dir = 1 if p.global_position.x > global_position.x else -1
				velocity.x = float(dir) * _eff_patrol_speed()
				_try_hunt_hop()
			else:
				velocity.x = float(dir) * _eff_patrol_speed()
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
					velocity.x = float(dir) * _eff_patrol_speed()
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
					visual.modulate = _base_tint
			if patrol_state_timer <= 0.0:
				if visual != null:
					visual.modulate = _base_tint
				if patrol_fire_armed:
					# 발사 순간 — 엘리트는 2연 버스트(수평탄이라 점프 하나로 함께 회피 가능, §2).
					if p != null and not harmless:
						_patrol_fire(p)
						if elite:
							_schedule_elite_second_shot()
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
					visual.modulate = _base_tint
			if patrol_state_timer <= 0.0:
				if visual != null:
					visual.modulate = _base_tint
				patrol_state = PatrolState.CHARGING
				patrol_state_timer = PATROL_CHARGE_DURATION
		PatrolState.CHARGING:
			velocity.x = float(dir) * _eff_patrol_charge_speed()
			patrol_state_timer -= delta
			# 가장자리 도달 시 즉시 RECOVERING — 빠른 속도라 lookahead 80px
			var charge_edge_fall: bool = is_on_floor() and not _has_ground_ahead(dir, EDGE_LOOKAHEAD_X_FAST)
			if is_on_wall() or charge_edge_fall or patrol_state_timer <= 0.0:
				patrol_state = PatrolState.RECOVERING
				patrol_state_timer = _eff_patrol_recovery()
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

# 엘리트 patrol 2연 버스트의 2발째 — 짧은 지연 뒤 생존/트리 확인 후 발사(콜백 안전 가드, known_issues).
func _schedule_elite_second_shot() -> void:
	get_tree().create_timer(ELITE_PATROL_BURST_GAP).timeout.connect(func() -> void:
		if not is_instance_valid(self) or dead or not is_inside_tree():
			return
		var p2 := _find_player()
		if p2 != null and not harmless:
			_patrol_fire(p2)
	)

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
			# 발사 임박도(0=조준 시작, 1=발사 직전) — 조준선이 굵고 밝아진다.
			var aim_prog: float = clampf(1.0 - fire_timer / _eff_sniper_aim_time(), 0.0, 1.0)
			_update_aim(aim_prog)
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
	aim_line.width = 1.5
	aim_line.default_color = Color(1.0, 0.30, 0.30, 0.45)
	aim_line.begin_cap_mode = Line2D.LINE_CAP_ROUND  # 총구·표적 끝을 점처럼 — "겨눠진" 느낌
	aim_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	aim_line.z_index = 1
	get_parent().add_child(aim_line)
	SfxPlayer.play_at("enemy_sniper_charge", global_position)

# prog: 0=조준 시작, 1=발사 직전. 임박할수록 굵고 밝게 → "곧 쏜다, 위험"을 또렷이(피드백).
func _update_aim(prog: float) -> void:
	if aim_line == null:
		return
	var p := _find_player()
	if p == null:
		return
	aim_line.clear_points()
	aim_line.add_point(global_position + Vector2(0, -20))
	aim_line.add_point(p.global_position + Vector2(0, -28))
	aim_line.width = lerpf(1.5, 4.5, prog)
	aim_line.default_color = Color(1.0, 0.32 + 0.18 * prog, 0.30, lerpf(0.40, 0.95, prog))

func _clear_aim() -> void:
	if aim_line != null:
		aim_line.queue_free()
		aim_line = null

# ─── Drone ──────────────────────────────────────────────────

# 드론 산개/각 잡기(2026-08-11) — 전 드론이 플레이어 머리 바로 위 한 점에 정직하게 뭉쳐,
# 발판을 지붕 삼아 그 밑에서 수류탄으로 농사짓는 전략이 지배적이던 문제.
# ⓐ 평시(쿨다운)엔 개체별 측면 오프셋에서 대기 — 뭉침·광역 몰살 방지.
# ⓑ 폭탄이 준비되고 시야(LoS)가 열려 있을 때만 머리 위로 파고들어 투하 — "파고들면 온다"가 읽힘.
# ⓒ 플레이어가 지붕 아래면(LoS 차단) 투하 낭비 대신 측면 대기 — 지붕은 유효 엄폐로 유지하되
#    드론이 한 점에 떠 주는 공짜 표적은 없앤다. (스토리 모드는 드론 스폰 자체가 스킵이라 무관.)
var _hover_side: float = 1.0 if randf() < 0.5 else -1.0   # 개체별 대기 측면
var _hover_gap: float = randf_range(100.0, 170.0)          # 개체별 대기 거리

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
	var los_clear: bool = _drone_sees_player(player)
	if hover_ok and drone_bomb_cd <= 0.0 and not harmless and los_clear:
		velocity = Vector2.ZERO
		_drop_bomb()
		# 엘리트 — 2연 투하(2발째 좌우 분산): "그 자리 탈출"이 답이 되게(§2).
		if elite:
			get_tree().create_timer(ELITE_DRONE_SECOND_DROP_GAP).timeout.connect(func() -> void:
				if not is_instance_valid(self) or dead or not is_inside_tree():
					return
				_drop_bomb(randf_range(-ELITE_DRONE_SECOND_DROP_SPREAD, ELITE_DRONE_SECOND_DROP_SPREAD))
			)
		drone_bomb_cd = _drone_bomb_interval()
	else:
		# 목표 — 투하 준비 + 시야 열림: 머리 위 / 그 외: 개체별 측면 오프셋 대기.
		var target: Vector2
		if drone_bomb_cd <= 0.0 and los_clear and not harmless:
			target = player.global_position + Vector2(0, DRONE_HOVER_OFFSET_Y)
		else:
			target = player.global_position + Vector2(_hover_side * _hover_gap, DRONE_HOVER_OFFSET_Y)
		var to: Vector2 = target - global_position
		if to.length() > 6.0:
			velocity = to.normalized() * _eff_drone_speed()
			_flip_visual((player.global_position.x - global_position.x) < 0.0)
		else:
			velocity = Vector2.ZERO
	move_and_slide()

# 드론→플레이어 시야 — 사이에 지형(layer 1: 바닥/발판)이 있으면 폭탄이 지붕에 낭비된다.
func _drone_sees_player(p: Node2D) -> bool:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(global_position, p.global_position + Vector2(0.0, -20.0), 1)
	query.exclude = [self]
	var hit: Dictionary = space.intersect_ray(query)
	return hit.is_empty()

func _drop_bomb(offset_x: float = 0.0) -> void:
	SfxPlayer.play_at("enemy_drone_drop", global_position)
	var b := Bomb.new()
	b.global_position = global_position + Vector2(offset_x, 8)
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
			if hunt and p != null and not harmless:
				# 사냥 모드 — 감지 밖에서도 플레이어 쪽으로 전진(농성 맵 "밀려온다" 압박). 벽은 타넘기.
				dir = 1 if p.global_position.x > global_position.x else -1
				velocity.x = float(dir) * BOMBER_SPEED
				_try_hunt_hop()
			else:
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
				velocity.x = float(dir) * BOMBER_SPEED * _eff_bomber_stalk_mult()
				if is_on_wall():
					if hunt:
						_try_hunt_hop()   # 사냥 모드 — 엄폐에 막혀 멈추지 않고 타넘는다
					else:
						velocity.x = 0.0
				# 가장자리 — STALKING 빠름 → fast lookahead. 사냥 모드는 낙하 안전(평지 농성 맵)이라 생략
				# (엄폐 꼭대기에서 아래 지면이 lookahead 밖이라 동결되는 것 방지).
				if not hunt and is_on_floor() and not _has_ground_ahead(dir, EDGE_LOOKAHEAD_X_FAST):
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
					visual.modulate = _base_tint
			if bomber_state_timer <= 0.0:
				_bomber_explode()
				return

	_flip_visual(dir < 0)
	move_and_slide()

func _bomber_in_detect_range(p: Node2D) -> bool:
	var dx: float = abs(p.global_position.x - global_position.x)
	var dy: float = abs(p.global_position.y - global_position.y)
	return dx <= _eff_bomber_detect_x() and dy <= BOMBER_DETECT_Y

func _bomber_explode() -> void:
	if dead:
		return
	SfxPlayer.play_at("enemy_bomber_explode", global_position)
	# 폭발 데미지 — 반경 안의 플레이어에게 (반경은 엘리트 유효치)
	var br: float = _eff_bomber_blast_radius()
	var p := _find_player()
	if p != null and global_position.distance_to(p.global_position) <= br:
		if p.has_method("take_hit"):
			p.take_hit(BOMBER_BLAST_DAMAGE)
	# 시각 효과
	var blast := Polygon2D.new()
	blast.color = Color(1.0, 0.55, 0.30, 0.85)
	blast.z_index = 3
	var pts: Array = []
	for i in 24:
		var a: float = float(i) * TAU / 24.0
		pts.append(Vector2(cos(a) * br, sin(a) * br))
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
			shield_dir_lock_timer = _eff_shield_lock()

	# 근접 시에만 추격 이동. 그 외에는 좁은 범위 patrol.
	if not harmless and p != null and _shield_player_nearby(p):
		var d2: float = global_position.distance_to(p.global_position)
		if d2 > SHIELD_MELEE_RANGE * 0.8:
			velocity.x = float(dir) * SHIELD_SPEED
		else:
			velocity.x = 0.0
	else:
		# 평소 순찰. dir은 player 방향으로 잠겨 있으니, patrol_range를 벗어나면 제자리에 멈춤.
		# 사냥 모드는 범위 무시하고 전진(정면 잠금 회전 로직은 위 공유), 벽(엄폐)은 타넘기.
		var px: float = global_position.x
		if hunt and p != null and not harmless:
			velocity.x = float(dir) * SHIELD_SPEED * 0.8
			_try_hunt_hop()
		elif (dir > 0 and px > origin_x + patrol_range) or (dir < 0 and px < origin_x - patrol_range):
			velocity.x = 0.0
		else:
			velocity.x = float(dir) * SHIELD_SPEED * 0.8
		if is_on_wall() and not hunt:
			velocity.x = 0.0
	# 가장자리 — 추격이든 순찰이든 떨어지지 않게 정지 (방패병은 정면 잠김이라 dir 반전 어색).
	# 사냥 모드는 생략 — 평지 농성 맵 + 엄폐 꼭대기 통과 시 동결 방지.
	if not hunt and is_on_floor() and not _has_ground_ahead(dir):
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
	# 14-1 P2 제어 노드 — 교대 실드(meta fs_dir = 실드가 향한 쪽). 막힌 쪽에서 온 탄은 무효,
	# 주기적으로 편이 바뀐다(Stage가 플립). 폭발(from_dir 0)은 관통 = 수류탄이 정답 카드.
	if has_meta("fs_dir") and from_dir != 0 and from_dir * int(get_meta("fs_dir")) < 0:
		_show_block_spark(from_dir)
		SfxPlayer.play_at("bullet_deflect_shield", global_position)
		return
	# 방패병 — 정면(enemy.dir이 가리키는 쪽)으로 날아오는 사격은 막힘.
	# 즉 bullet의 진행 방향(from_dir)과 enemy의 dir이 반대 부호일 때 head-on이라 막음.
	if enemy_type == EnemyType.SHIELD and from_dir != 0 and _shield_blocks(from_dir):
		if _disguised:
			_reveal_disguise()   # 정찰병인 줄 알고 쏜 정면 사격이 튕김 = 정체 노출(§4 교전 리빌)
		_show_block_spark(from_dir)
		SfxPlayer.play_at("bullet_deflect_shield", global_position)
		return
	# 엘리트 방패병 — 폭발 면역(§2, 사용자 제안: 만능이 된 수류탄을 라이벌이 학습해 카운터).
	# from_dir == 0 = 폭발/스킬류(수류탄. Bullet은 항상 dir을 넘긴다). 측면 사격 정답은 그대로.
	# tell = 방패 전체 바이올렛 번쩍 + deflect SFX — "안 통한다"가 즉시 읽히게.
	if elite and enemy_type == EnemyType.SHIELD and from_dir == 0:
		_show_explosion_immune_flash()
		SfxPlayer.play_at("bullet_deflect_shield", global_position)
		# 상황 멘트(런당 1회) — "저 방패병은 폭발 면역" 류의 맥락 안내(2026-08-11 사용자 제안).
		# 어투 = 간결한 전술 보고체(해요체 "흘려요"가 유치하다는 지적으로 재작성).
		if not GameState.shield_immune_line_shown:
			GameState.shield_immune_line_shown = true
			var sn := get_tree().get_first_node_in_group("stage")
			if sn != null:
				sn.call("_show_veil_subtitle", "폭발 피해 무효 확인. 저 방패병은 측면과 후방 사격만 유효합니다.", 3.8)
		return
	# 교전(피격) = 위장이 벗겨지는 주 시점 — 지직거림 tell을 못 봤어도 여기서 정체가 드러난다.
	if _disguised:
		_reveal_disguise()
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

# 엘리트 방패병 폭발 무효 tell — 몸 전체 바이올렛 번쩍 + 확산 링 + "무효" 라벨.
# (플래시만으론 폭발 이펙트에 묻혀 안 읽힌다는 피드백 2026-08-11로 강화.)
func _show_explosion_immune_flash() -> void:
	var f := Polygon2D.new()
	f.color = Color(ELITE_VIOLET.r, ELITE_VIOLET.g, ELITE_VIOLET.b, 0.8)
	f.polygon = PackedVector2Array([
		Vector2(-20.0, -58.0), Vector2(20.0, -58.0), Vector2(20.0, 2.0), Vector2(-20.0, 2.0),
	])
	f.z_index = 4
	add_child(f)
	var tw := f.create_tween()
	tw.tween_property(f, "color:a", 0.0, 0.35)
	tw.tween_callback(f.queue_free)
	# 확산 링 — 폭발 연기 위에서도 "무효 판정"이 도드라지게.
	var ring := _ImmuneRing.new()
	ring.position = Vector2(0.0, -28.0)
	ring.z_index = 5
	add_child(ring)
	# "무효" 라벨 — 위로 떠오르며 사라짐.
	var lbl := Label.new()
	lbl.text = "무효"
	lbl.add_theme_font_size_override("font_size", 16)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.55, 1.0))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	lbl.add_theme_constant_override("outline_size", 4)
	lbl.position = Vector2(-18.0, -92.0)
	lbl.z_index = 5
	add_child(lbl)
	var ltw := lbl.create_tween()
	ltw.tween_property(lbl, "position:y", -116.0, 0.6)
	ltw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.6)
	ltw.tween_callback(lbl.queue_free)

# 폭발 무효 확산 링 — 바이올렛 원이 커지며 사라짐. 스스로 소멸.
class _ImmuneRing extends Node2D:
	var t: float = 0.0
	func _process(delta: float) -> void:
		t += delta
		if t >= 0.45:
			queue_free()
			return
		queue_redraw()
	func _draw() -> void:
		var k: float = t / 0.45
		var r: float = lerp(20.0, 66.0, k)
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(0.72, 0.42, 1.0, 0.85 * (1.0 - k)), 3.0, true)

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
