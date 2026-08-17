class_name ElectricArc
extends Node2D

# 변전소 시그니처 해저드 · 바닥 통전 구간(map_identity_rework §5 확산, 2026-08-17).
# 두 절연 포스트 사이 바닥 전선이 주기적으로 통전한다. 사이클: 대기 → 예고(포스트 스파크
# 점등 + 낮은 지직 라인) → 방전(지그재그 아크, 구간 안 지상 피해). SteamVent와 동형 문법
# (타이밍 보고 지나가기)이되 축이 수평이라 "발판 위로 피한다"가 회피가 된다.
# 시설 유닛(기계)은 절연 설계라 무피해 · 환경 내성 캐논(방수와 동일 결).
# 광과민: 점멸 없음 · 방전은 일정 밝기 유지 + 완만한 웨이브.
#
# 사용: MapData "arc_zones" = [{x1, x2, phase?, dmg?}]. Stage가 ground_y에 배치.

const IDLE_DUR: float = 1.9
const TELE_DUR: float = 0.8
const BURST_DUR: float = 0.9
const PERIOD: float = IDLE_DUR + TELE_DUR + BURST_DUR
const BAND_H: float = 50.0    # 방전 시 지면 위 위험 대역

var half: float = 140.0       # 구간 반폭 · position = 구간 중앙(지면)
var damage: int = 1
var phase: float = 0.0

var _t: float = 0.0
var _hit_this_burst: bool = false

func setup(x1: float, x2: float, ground_y: float, ph: float = 0.0, dmg: int = 1) -> void:
	position = Vector2((x1 + x2) * 0.5, ground_y)
	half = absf(x2 - x1) * 0.5
	phase = ph
	damage = dmg
	_t = ph * PERIOD
	z_index = 1
	add_to_group("electric_arc")

func _cycle_t() -> float:
	return fmod(_t, PERIOD)

func _physics_process(delta: float) -> void:
	_t += delta
	var ct: float = _cycle_t()
	var bursting: bool = ct >= IDLE_DUR + TELE_DUR
	if not bursting:
		_hit_this_burst = false
	elif not _hit_this_burst:
		_check_hit()
	queue_redraw()

func _check_hit() -> void:
	var p: Node = get_tree().get_first_node_in_group("player")
	if p == null or not (p is Node2D) or bool(p.get("clear_protect")):
		return
	var rel: Vector2 = (p as Node2D).global_position - global_position
	if absf(rel.x) <= half and rel.y > -BAND_H and rel.y <= 8.0:
		if p.has_method("take_hit"):
			p.call("take_hit", damage)
			_hit_this_burst = true
			SfxPlayer.play_at("spike_hit", (p as Node2D).global_position)

func _draw() -> void:
	var ct: float = _cycle_t()
	# 절연 포스트 · 양끝 상시(위치가 항상 보임 · 증기 노즐 마커와 동형).
	for sx in [-half, half]:
		draw_rect(Rect2(Vector2(float(sx) - 4.0, -26.0), Vector2(8.0, 26.0)), Color(0.20, 0.19, 0.15))
		draw_rect(Rect2(Vector2(float(sx) - 6.0, -30.0), Vector2(12.0, 5.0)), Color(0.32, 0.30, 0.22))
	# 바닥 전선 · 상시 어두운 케이블 라인.
	draw_rect(Rect2(Vector2(-half, -3.0), Vector2(half * 2.0, 3.0)), Color(0.16, 0.15, 0.11))
	if ct < IDLE_DUR:
		return
	var warn_col := Color(1.0, 0.78, 0.30)
	if ct < IDLE_DUR + TELE_DUR:
		# 예고 · 포스트 스파크 점 + 케이블이 달아오른다(램프 · 점멸 아님).
		var k: float = (ct - IDLE_DUR) / TELE_DUR
		for sx in [-half, half]:
			draw_circle(Vector2(float(sx), -30.0), 3.0 + 2.0 * k, Color(warn_col.r, warn_col.g, warn_col.b, 0.4 + 0.5 * k))
		draw_rect(Rect2(Vector2(-half, -4.0), Vector2(half * 2.0, 4.0)), Color(warn_col.r, warn_col.g, warn_col.b, 0.15 + 0.35 * k))
		return
	# 방전 · 지그재그 아크(연속 웨이브 · 일정 밝기) + 위험 대역 글로우.
	var bt: float = (ct - IDLE_DUR - TELE_DUR) / BURST_DUR
	var amp: float = sin(bt * PI)   # 0→1→0 진폭 엔벨로프(완만)
	draw_rect(Rect2(Vector2(-half, -BAND_H), Vector2(half * 2.0, BAND_H)), Color(1.0, 0.85, 0.45, 0.10 * amp))
	var seg: int = int(half / 14.0)
	var pts := PackedVector2Array()
	for i in seg + 1:
		var k2: float = float(i) / float(maxi(1, seg))
		var xx: float = -half + half * 2.0 * k2
		var yy: float = -14.0 - (sin(k2 * 9.0 + _t * 11.0) * 7.0 + sin(k2 * 17.0 - _t * 8.0) * 4.0) * amp
		pts.append(Vector2(xx, yy))
	if pts.size() >= 2:
		draw_polyline(pts, Color(1.0, 0.9, 0.55, 0.85), 3.0, true)
		draw_polyline(pts, Color(1.0, 1.0, 0.9, 0.9), 1.2, true)
	for sx in [-half, half]:
		draw_circle(Vector2(float(sx), -30.0), 4.5, Color(1.0, 0.9, 0.55, 0.9))
