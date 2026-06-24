class_name BulletTrap
extends Node2D

# 발사 포탑 — 표면에 장착되어 정해진 방향으로 빠른 총알을 쏜다. 파괴 불가, 회피해야 함.
# 모드:
#   "periodic"  : 텔레그래프(구경 충전) 후 주기 발사.
#   "triggered" : 평소 대기. 같은 trigger_id의 LaserTripwire가 발동하면 텔레그래프 후 버스트 발사.
# 총알은 EnemyBullet 재사용하되 속도를 높임(트랩은 더 위협적). SFX는 기존 enemy_patrol_fire.
# 하우징이 장착면(-direction)에 붙어 부유 안 함. ⚠ 표식 + Stage가 근접 시 VEIL "파괴 불가" 1회 안내.

const BULLET_SPEED: float = 460.0   # 적 일반탄(240)보다 빠름
# 조준선 길이 = 실제 총알 사거리(속도 × 수명)와 일치시킴. 트랩 총알은 EnemyBullet을 그대로 쓰되
# 속도만 460으로 올리고 수명(1.6s)은 그대로라, 실제론 460×1.6 = 736px 날아갔다(선은 460만 그려
# 끝 너머에서도 맞던 불일치). 이제 그려지는 위협 라인이 진짜 사거리를 정직하게 보여준다.
# 사용자 피드백 2026-06-13.
const LINE_LEN: float = BULLET_SPEED * EnemyBullet.BASE_LIFETIME
const COL_PORT: Color = Color(0.16, 0.12, 0.10, 1.0)
const COL_EDGE: Color = Color(0.58, 0.42, 0.32, 1.0)
const COL_HOT: Color = Color(1.0, 0.55, 0.28)

var direction: Vector2 = Vector2.DOWN
var mode: String = "periodic"
var interval: float = 1.6
var telegraph: float = 0.5
var damage: int = 1
var burst: int = 3
var trigger_id: String = ""
var _t: float = 0.0
var _fire_t: float = -1.0       # 충전 카운트다운(>=0이면 충전 중)
var _burst_left: int = 0
var _burst_t: float = 0.0

func setup(dir: Vector2, intv: float, phase: float, tel: float = 0.5, p_mode: String = "periodic", tid: String = "") -> void:
	direction = dir.normalized()
	interval = maxf(0.4, intv)
	telegraph = clampf(tel, 0.1, interval)
	_t = fposmod(phase, interval)
	mode = p_mode
	trigger_id = tid

func _ready() -> void:
	add_to_group("bullet_trap")
	z_index = 2

func _process(delta: float) -> void:
	if mode == "periodic":
		_t += delta
		if _t >= interval:
			_t -= interval
			_fire_one()
	else:
		_advance_burst(delta)
	queue_redraw()

# LaserTripwire가 호출 — 대기 중인 triggered 포탑을 발사시킴.
func trigger_fire() -> void:
	if mode != "triggered":
		return
	if _fire_t >= 0.0 or _burst_left > 0:
		return  # 이미 동작 중
	_fire_t = telegraph

func _advance_burst(delta: float) -> void:
	if _fire_t >= 0.0:
		_fire_t -= delta
		if _fire_t <= 0.0:
			_fire_t = -1.0
			_burst_left = burst
			_burst_t = 0.0
		return
	if _burst_left > 0:
		_burst_t -= delta
		if _burst_t <= 0.0:
			_fire_one()
			_burst_left -= 1
			_burst_t = 0.08

func _fire_one() -> void:
	var host: Node = get_parent()
	if host == null:
		return
	var b := EnemyBullet.new()
	b.velocity = direction * BULLET_SPEED
	b.damage = damage
	host.add_child(b)
	b.global_position = global_position + direction * 14.0
	SfxPlayer.play_at("enemy_patrol_fire", global_position)

# 충전/경고 강도 0~1.
func _glow() -> float:
	if mode == "triggered":
		if _fire_t >= 0.0:
			return clampf(1.0 - _fire_t / telegraph, 0.0, 1.0)
		return 1.0 if _burst_left > 0 else 0.0
	var remaining: float = interval - _t
	if remaining > telegraph:
		return 0.0
	return clampf(1.0 - remaining / telegraph, 0.0, 1.0)

func _draw() -> void:
	var g: float = _glow()
	var perp := Vector2(-direction.y, direction.x)
	# 조준 라인 — periodic은 점선(텔레그래프 시 밝아짐), triggered는 평소 흐릿하게 발사 방향만 암시.
	var base_a: float = 0.08 if mode == "triggered" else 0.10
	var line_col: Color = COL_HOT * Color(1, 1, 1, base_a + 0.55 * g)
	var seg: float = 16.0
	var n: int = int(LINE_LEN / seg)
	for i in range(0, n, 2):
		draw_line(direction * (float(i) * seg + 18.0), direction * (float(i + 1) * seg + 18.0), line_col, 2.0, true)
	# 장착 베이스(브래킷) — -direction 쪽 표면에 붙음.
	var bracket := PackedVector2Array([
		perp * 15.0 - direction * 16.0, -perp * 15.0 - direction * 16.0,
		-perp * 13.0 - direction * 9.0, perp * 13.0 - direction * 9.0])
	draw_colored_polygon(bracket, COL_PORT.darkened(0.2))
	# 포탑 하우징.
	var housing := PackedVector2Array([
		perp * 12.0 - direction * 9.0, -perp * 12.0 - direction * 9.0,
		-perp * 9.0 + direction * 6.0, perp * 9.0 + direction * 6.0])
	draw_colored_polygon(housing, COL_PORT)
	draw_polyline(_closed(housing), COL_EDGE, 1.5, true)
	# 구경 — 충전 글로우.
	draw_line(perp * 7.0 + direction * 4.0, -perp * 7.0 + direction * 4.0,
		COL_HOT * Color(1, 1, 1, 0.45 + 0.55 * g), 3.0, true)
	# ⚠ 경고 — 하우징 뒤(장착면).
	var wc: Vector2 = -direction * 22.0
	draw_polyline(_closed(PackedVector2Array([wc + Vector2(0, -5), wc + Vector2(-5, 4), wc + Vector2(5, 4)])),
		Color(1.0, 0.78, 0.2, 0.9), 1.5, true)
	draw_line(wc + Vector2(0, -2), wc + Vector2(0, 1.5), Color(1.0, 0.78, 0.2, 0.9), 1.5, true)

func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array(pts)
	if pts.size() > 0:
		out.append(pts[0])
	return out
