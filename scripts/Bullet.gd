class_name Bullet
extends Area2D

# 플레이어 사격으로 발생하는 총알. Player._try_attack에서 spawn.
# 적(layer 4) / 벽(layer 1)과 충돌. piercing 스킬 보유 시 적을 관통.

const BASE_SPEED: float = 900.0
const BASE_LIFETIME: float = 0.55

var dir: int = 1
var damage: int = 1
var pierce: bool = false
# fire_boost 티어 — 총알 외형(크기·색·잔상)으로 사격 성장 가시화. Player._spawn_bullet에서 전달.
var style_tier: int = 0
var speed_mult: float = 1.0
var lifetime_mult: float = 1.0
var lifetime: float = BASE_LIFETIME
var hit_enemies: Array = []
# 부채꼴 발사용 — 0이면 수평. radian, dir 기준 위/아래로 벌림.
var angle: float = 0.0
# 추적 — 가장 가까운 적 방향으로 휨. multishot T3=약한 추적(기본값), glide T3=강한 유도(값 상향).
var tracking: bool = false
const TRACKING_BLEND: float = 0.03  # 매 프레임 현재 방향과 타깃 방향을 lerp하는 비율
const TRACKING_MAX_ANGLE: float = 0.21  # ~12도. 이전 25도는 보스전 밸런스 붕괴로 축소.
var tracking_blend: float = TRACKING_BLEND
var tracking_max_angle: float = TRACKING_MAX_ANGLE

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1 | 4  # 벽 + 적
	body_entered.connect(_on_body_entered)
	z_index = 2
	lifetime = BASE_LIFETIME * lifetime_mult

	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(14.0, 6.0)
	col.shape = shape
	add_child(col)

	# ── 외형: fire_boost 티어 + 관통 여부로 탄/잔상 모양 변화 (스킬 성장 가시화) ──
	# T0 노랑 → T1 더 크고 밝은 주황 → T2 긴 잔상 → 관통(T3/활강) 길쭉한 트레이서.
	var col_body: Color = Color(1.0, 0.95, 0.55, 1.0)
	var col_trail: Color = Color(1.0, 0.92, 0.45, 0.55)
	var body_w: float = 10.0
	var body_h: float = 4.0
	var trail_w: float = 20.0
	var trail_h: float = 2.0
	if style_tier >= 1:                       # 사격 강화 — 더 크고 밝은 주황 탄
		col_body = Color(1.0, 0.72, 0.32, 1.0)
		col_trail = Color(1.0, 0.62, 0.28, 0.6)
		body_w = 12.0
		body_h = 5.0
	if style_tier >= 2:                       # 속사 — 긴 잔상
		trail_w = 32.0
		col_trail.a = 0.7
	if pierce:                                # 관통(사격강화 T3) — 길쭉한 트레이서
		body_w = 18.0
		body_h = 3.0
		trail_w = max(trail_w, 34.0)
	if tracking and tracking_blend >= 0.1:    # 유도(활강 T3) — 시안 틴트 + 길쭉(약한 추적과 구분)
		col_body = Color(0.55, 0.95, 1.0, 1.0)
		col_trail = Color(0.5, 0.88, 1.0, 0.7)
		body_w = max(body_w, 16.0)
		trail_w = max(trail_w, 30.0)

	var trail := ColorRect.new()
	trail.color = col_trail
	trail.size = Vector2(trail_w, trail_h)
	if dir > 0:
		trail.position = Vector2(-trail_w, -trail_h * 0.5)
	else:
		trail.position = Vector2(0.0, -trail_h * 0.5)
	add_child(trail)

	var bullet := ColorRect.new()
	bullet.color = col_body
	bullet.size = Vector2(body_w, body_h)
	bullet.position = Vector2(-body_w * 0.5, -body_h * 0.5)
	add_child(bullet)

func _process(delta: float) -> void:
	# 진행 벡터 — 수평 베이스(dir) + 각도(angle) 적용. 시각적 회전은 생략(스프라이트가
	# 작아 어색하지 않음).
	if tracking:
		_apply_tracking(delta)
	var vx: float = cos(angle) * float(dir)
	var vy: float = sin(angle)
	position.x += BASE_SPEED * speed_mult * vx * delta
	position.y += BASE_SPEED * speed_mult * vy * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()

func _apply_tracking(_delta: float) -> void:
	# 가장 가까운 적을 찾아 진행 방향을 살짝 그쪽으로 기울인다.
	# bullet의 진행은 (cos(angle)*dir, sin(angle)). 진행이 dir 부호를 따라가니까
	# x 축 부호 자체는 보존하고 y 성분(angle)만 천천히 조정한다.
	var nearest: Node2D = _find_nearest_enemy()
	if nearest == null:
		return
	var dx: float = nearest.global_position.x - global_position.x
	# 적이 진행 방향 반대편이면 추적 안 함 (이미 지나친 적).
	if dx * float(dir) <= 0.0:
		return
	var dy: float = (nearest.global_position.y - 28.0) - global_position.y  # 적 가슴 높이
	# 새 angle 계산: 진행 방향(+dir 쪽)에서 dy/dx 비율로 기울기.
	var target_angle: float = atan2(dy, abs(dx))
	target_angle = clamp(target_angle, -tracking_max_angle, tracking_max_angle)
	angle = lerp(angle, target_angle, tracking_blend)

func _find_nearest_enemy() -> Node2D:
	var nearest: Node2D = null
	var min_d: float = 99999.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not (e is Node2D):
			continue
		if e in hit_enemies:
			continue
		var d: float = global_position.distance_to((e as Node2D).global_position)
		if d < min_d:
			min_d = d
			nearest = e as Node2D
	return nearest

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("enemy"):
		if body in hit_enemies:
			return
		hit_enemies.append(body)
		# 명중/디플렉트 SFX는 Enemy.take_damage 안에서 방패 막힘 분기를 보고 결정.
		if body.has_method("take_damage"):
			# bullet의 진행 방향(dir)을 전달 — 방패 판정에 사용. 위치(global_position.x)는
			# 충돌 시점에 enemy 안쪽으로 이미 들어가 있어 부호가 어긋날 수 있음.
			body.take_damage(damage, dir)
		if not pierce:
			queue_free()
	elif body is StaticBody2D:
		# 벽/플랫폼 충돌 — 사라짐. 맵 경계벽·바닥·플랫폼은 "수직 벽"이 아니라 impact SFX 생략.
		# (boundary_wall: 외곽 가드, ground: 메인 지면, platform: 발판류)
		var skip_sfx: bool = body.is_in_group("boundary_wall") \
			or body.is_in_group("ground") or body.is_in_group("platform")
		if not skip_sfx:
			SfxPlayer.play_at("bullet_impact_wall", global_position)
		queue_free()
