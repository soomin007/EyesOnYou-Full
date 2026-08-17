class_name Searchlight
extends Node2D

# 감시탑 시그니처 해저드 · 탐조등(map_identity_rework §5 "감시탑 = 탐조등 노출", 2026-08-17).
# 빛 원뿔이 탑 내부를 천천히 훑는다. 빛 자체는 피해가 없고, 잡힌 채 0.45s를 넘기면 경보:
# 등이 붉게 물들고 경비 증원이 붙는다(잠입 문법 · 스캐너 빔의 "즉시 피해"와 다른 리듬).
# 회피 = 팬 타이밍 읽기 / 발판 아래 그림자(LoS 차단 = 세이프). 광과민 준수: 팬은 연속
# 이동, 경보는 점멸 없이 색 전환 유지.
#
# 사용: MapData "searchlights" = [{x, y, from_deg, to_deg, period?, len?}]. 각도는 도 단위
# (0=오른쪽, 90=아래). Stage가 alerted를 받아 증원을 처리한다(막1 = 인간 경비만 계약).

signal alerted(player_pos: Vector2)

const HALF_ANGLE: float = 0.15
const EXPOSE_NEED: float = 0.45
const ALERT_DUR: float = 2.4
const COOLDOWN: float = 8.0

var from_ang: float = PI - 0.4
var to_ang: float = PI + 0.4
var period: float = 7.0
var length: float = 950.0
var pole_h: float = 0.0   # >0이면 하우징 아래 지주를 그린다(지상 경계등 · 외곽 순찰로)

var _t: float = 0.0
var _exposure: float = 0.0
var _alert_t: float = 0.0
var _cd: float = 0.0
# 차폐 팬 · 각도 샘플마다 레이캐스트로 벽/발판에 잘린 실제 도달 거리(사용자 2026-08-17
# "가려진 곳 뒤편으로는 안 보이게" · 판정은 원래 LoS였고 그림만 통짜 원뿔이던 불일치 해소).
const FAN_RAYS: int = 36
var _fan_r: PackedFloat32Array = PackedFloat32Array()

func setup(cfg: Dictionary) -> void:
	position = Vector2(float(cfg.get("x", 0.0)), float(cfg.get("y", 0.0)))
	from_ang = deg_to_rad(float(cfg.get("from_deg", 160.0)))
	to_ang = deg_to_rad(float(cfg.get("to_deg", 200.0)))
	period = float(cfg.get("period", 7.0))
	length = float(cfg.get("len", 950.0))
	pole_h = float(cfg.get("pole_h", 0.0))
	z_index = -2   # 배우 뒤 · 배경 위(빛은 공간에 깔린다)
	add_to_group("searchlight")

func _current_angle() -> float:
	# 사인 핑퐁 · 양 끝에서 자연 감속(타이밍 읽기 쉬움).
	var k: float = 0.5 - 0.5 * cos(TAU * fmod(_t / period, 1.0))
	return lerpf(from_ang, to_ang, k)

func _physics_process(delta: float) -> void:
	if not is_inside_tree():
		return
	_t += delta
	_alert_t = maxf(0.0, _alert_t - delta)
	_cd = maxf(0.0, _cd - delta)
	var p: Node = get_tree().get_first_node_in_group("player")
	var caught: bool = false
	if p is Node2D and not bool(p.get("clear_protect")):
		var rel: Vector2 = (p as Node2D).global_position + Vector2(0.0, -24.0) - global_position
		if rel.length() < length and absf(angle_difference(rel.angle(), _current_angle())) < HALF_ANGLE:
			# 발판/바닥이 사이에 있으면 그림자 = 세이프(원웨이 발판도 레이엔 걸린다).
			var world := get_world_2d()
			if world != null:
				var query := PhysicsRayQueryParameters2D.create(global_position,
					(p as Node2D).global_position + Vector2(0.0, -24.0), 1)
				caught = world.direct_space_state.intersect_ray(query).is_empty()
	if caught:
		_exposure += delta
		if _exposure >= EXPOSE_NEED and _cd <= 0.0:
			_alert_t = ALERT_DUR
			_cd = COOLDOWN
			_exposure = 0.0
			if p is Node2D:
				emit_signal("alerted", (p as Node2D).global_position)
	else:
		_exposure = maxf(0.0, _exposure - delta * 2.0)
	_update_fan()
	queue_redraw()

# 각도 샘플별 도달 거리 갱신 · 빛이 실제로 닿는 곳까지만 그려진다(물리 차폐).
func _update_fan() -> void:
	var world := get_world_2d()
	if world == null:
		return
	var space := world.direct_space_state
	var ang: float = _current_angle()
	_fan_r.resize(FAN_RAYS + 1)
	for i in FAN_RAYS + 1:
		var a: float = lerpf(ang - HALF_ANGLE, ang + HALF_ANGLE, float(i) / float(FAN_RAYS))
		var to: Vector2 = global_position + Vector2.from_angle(a) * length
		var hit: Dictionary = space.intersect_ray(PhysicsRayQueryParameters2D.create(global_position, to, 1))
		_fan_r[i] = length if hit.is_empty() else (Vector2(hit.get("position", to)) - global_position).length()

func _draw() -> void:
	var ang: float = _current_angle()
	var alerted_now: bool = _alert_t > 0.0
	var base_a: float = 0.14 + 0.10 * clampf(_exposure / EXPOSE_NEED, 0.0, 1.0)
	var col := Color(0.95, 0.38, 0.30) if alerted_now else Color(0.95, 0.90, 0.68)
	# 차폐 팬 · 레이별 도달 지점까지만 채운다. 알파는 거리 감쇠(멀수록 옅게) ·
	# 가까운 벽에 맞으면 밝은 채로 뚝 끊겨 "빛이 벽에 막혔다"가 그림으로 읽힌다.
	if _fan_r.size() == FAN_RAYS + 1:
		var pts := PackedVector2Array([Vector2.ZERO])
		var cols := PackedColorArray([Color(col.r, col.g, col.b, base_a + 0.10)])
		for i in FAN_RAYS + 1:
			var a: float = lerpf(ang - HALF_ANGLE, ang + HALF_ANGLE, float(i) / float(FAN_RAYS))
			var r: float = _fan_r[i]
			pts.append(Vector2.from_angle(a) * r)
			cols.append(Color(col.r, col.g, col.b, base_a * (1.0 - r / length)))
		draw_polygon(pts, cols)
	# 지주(지상 경계등) · 하우징 아래로 지면까지.
	if pole_h > 0.0:
		draw_rect(Rect2(Vector2(-4.0, 8.0), Vector2(8.0, pole_h)), Color(0.14, 0.15, 0.18))
		draw_rect(Rect2(Vector2(-4.0, 8.0), Vector2(2.0, pole_h)), Color(0.24, 0.26, 0.32))
	# 하우징 · 마운트 + 렌즈(경보 시 붉게 유지 · 점멸 없음).
	draw_rect(Rect2(Vector2(-10.0, -10.0), Vector2(20.0, 20.0)), Color(0.10, 0.11, 0.15))
	draw_circle(Vector2.ZERO, 6.0, Color(col.r, col.g, col.b, 0.9))
